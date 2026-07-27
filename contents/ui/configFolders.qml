/*
 * Страница настроек «Папки»: добавление и удаление синхронизаций и FUSE-маунтов.
 *
 * Особенность: страница настроек живёт в отдельном контексте и не видит Backend
 * из виджета, поэтому здесь свой экземпляр. Он создаётся с paused: true — опрос
 * по таймеру не нужен, данные обновляются после каждой операции и при открытии.
 *
 * Правки здесь не относятся к настройкам виджета: они меняют состояние сервера
 * MEGAcmd и применяются немедленно, а не по нажатию «Применить». Поэтому у
 * страницы нет ни одного свойства cfg_*.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as Dialogs
import org.kde.kirigami as Kirigami

Item {
    id: page

    implicitWidth: Kirigami.Units.gridUnit * 32
    implicitHeight: Kirigami.Units.gridUnit * 30

    Backend {
        id: backend
        paused: true
        extraPath: plasmoid ? plasmoid.configuration.megacmdPath : ""
    }

    // Что настраиваем: синхронизацию или маунт. Формы почти совпадают,
    // отличаются составом полей.
    readonly property bool syncMode: modeGroup.currentIndex === 0

    Component.onCompleted: backend.refreshState()

    Connections {
        target: backend
        function onOperationDone(ok, message) {
            // Операция могла провалиться из-за отвалившейся сессии, поэтому
            // перепроверяем и факт входа, а не только списки.
            backend.refreshQuota();
            if (ok) {
                error.visible = false;
                localPath.text = "";
                mountName.text = "";
            } else {
                error.text = message.length > 0 ? message : i18n("The operation failed");
                error.visible = true;
            }
        }
    }

    Dialogs.FolderDialog {
        id: folderDialog
        title: i18n("Choose a local folder")
        onAccepted: localPath.text = selectedFolder.toString().replace(/^file:\/\//, "")
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        QQC2.TabBar {
            id: modeGroup
            Layout.fillWidth: true

            QQC2.TabButton { text: i18n("Synchronisations") }
            QQC2.TabButton { text: i18n("Mounted folders") }
        }

        Kirigami.InlineMessage {
            id: error
            Layout.fillWidth: true
            visible: false
            type: Kirigami.MessageType.Error
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: backend.cmdMissing || backend.serverDown || !backend.loggedIn
            type: Kirigami.MessageType.Warning
            // Диагностику из шелла показываем прямо здесь: иначе на чужой
            // машине не понять, почему mega-exec не найден или чем недоволен
            // сервер.
            text: {
                var head = backend.cmdMissing
                         ? i18n("mega-exec was not found in PATH.")
                         : (backend.serverDown
                            ? i18n("MEGAcmd server is not responding.")
                            : i18n("Not signed in. Run mega-cmd, then login, in a terminal."));
                var tail = backend.lastErrorText;
                if (backend.cmdMissing && backend.shellPath.length > 0)
                    tail = (tail.length > 0 ? tail + "\n" : "")
                         + i18n("PATH: %1", backend.shellPath);
                return tail.length > 0 ? head + "\n" + tail : head;
            }

            actions: [
                Kirigami.Action {
                    icon.name: "view-refresh"
                    text: i18n("Check again")
                    onTriggered: backend.refreshState()
                }
            ]
        }

        // ---- что уже настроено ----
        QQC2.Label {
            text: page.syncMode ? i18n("Configured synchronisations:")
                                : i18n("Configured mounts:")
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 7
            clip: true

            ListView {
                id: existing
                model: page.syncMode ? backend.syncs : backend.mounts
                currentIndex: -1

                delegate: QQC2.ItemDelegate {
                    required property var modelData
                    required property int index

                    width: existing.width
                    highlighted: existing.currentIndex === index
                    onClicked: existing.currentIndex = index

                    contentItem: RowLayout {
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: page.syncMode ? "folder-sync" : "folder-remote"
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: Kirigami.Units.iconSizes.small
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            QQC2.Label {
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                                text: page.syncMode
                                      ? modelData.localPath + "  →  " + modelData.remotePath
                                      : modelData.localPath + "  →  " + modelData.remotePath
                            }

                            QQC2.Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font: Kirigami.Theme.smallFont
                                opacity: 0.7
                                text: page.syncMode
                                      ? modelData.runState + " · " + modelData.status
                                      : (modelData.enabled ? i18n("mounted") : i18n("not mounted"))
                                            + (modelData.persistent ? "" : " · " + i18n("transient"))
                            }
                        }

                        QQC2.ToolButton {
                            icon.name: "edit-delete"
                            text: i18n("Remove")
                            display: QQC2.AbstractButton.IconOnly
                            onClicked: page.syncMode ? backend.removeSync(modelData.id)
                                                     : backend.removeMount(modelData.name)
                            QQC2.ToolTip.text: page.syncMode
                                               ? i18n("Stop synchronising (files are kept)")
                                               : i18n("Remove this mount")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                    }
                }
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            visible: existing.count === 0
            text: page.syncMode ? i18n("Nothing is being synchronised yet.")
                                : i18n("No folders are mounted yet.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // ---- добавление ----
        QQC2.Label {
            text: page.syncMode ? i18n("Add a synchronisation:") : i18n("Add a mount:")
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: Kirigami.Units.smallSpacing
            rowSpacing: Kirigami.Units.smallSpacing

            QQC2.Label { text: i18n("Local folder:") }

            QQC2.TextField {
                id: localPath
                Layout.fillWidth: true
                placeholderText: page.syncMode ? i18n("e.g. ~/Documents/MEGA")
                                               : i18n("e.g. ~/MEGA")
            }

            QQC2.Button {
                icon.name: "folder-open"
                text: i18n("Browse…")
                onClicked: folderDialog.open()
            }

            QQC2.Label { text: i18n("Name:") }

            QQC2.TextField {
                id: mountName
                Layout.fillWidth: true
                Layout.columnSpan: 2
                visible: !page.syncMode
                placeholderText: i18n("optional, defaults to the folder name")
            }

            // Заполнитель, чтобы сетка не разъезжалась в режиме синхронизаций
            Item {
                Layout.columnSpan: 2
                visible: page.syncMode
                implicitHeight: 0
            }

            QQC2.CheckBox {
                id: readOnly
                Layout.column: 1
                Layout.columnSpan: 2
                visible: !page.syncMode
                text: i18n("Read-only mount")
            }
        }

        QQC2.Label {
            visible: !page.syncMode
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("A writable mount also lets you copy files into the cloud. Note that MEGA has no streaming: opening a file downloads it in full, and the local cache grows as you browse.")
        }

        QQC2.Label { text: i18n("Cloud folder:") }

        RemoteFolderPicker {
            id: remotePicker
            Layout.fillWidth: true
            Layout.fillHeight: true
            backend: backend
        }

        RowLayout {
            Layout.fillWidth: true

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                text: i18n("Changes apply immediately, not on OK.")
            }

            QQC2.Button {
                icon.name: "list-add"
                text: page.syncMode ? i18n("Add synchronisation") : i18n("Add mount")
                enabled: backend.loggedIn && localPath.text.length > 0
                onClicked: {
                    var local = localPath.text;
                    if (page.syncMode)
                        backend.addSync(local, remotePicker.path);
                    else
                        backend.addMount(local, remotePicker.path,
                                         mountName.text, readOnly.checked);
                }
            }
        }
    }
}
