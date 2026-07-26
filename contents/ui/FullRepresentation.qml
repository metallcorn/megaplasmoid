import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

/*
 * Метрики сняты с системного виджета — эталон
 * applets/devicenotifier/qml/FullRepresentation.qml из plasma-workspace:
 *
 *   PlasmaComponents.ScrollView (не QQC2), горизонтальная полоса отключена;
 *   боковые отступы — Kirigami.Units.largeSpacing (8 px), НЕ gridUnit (18 px);
 *   шаг между элементами — smallSpacing (4 px);
 *   второстепенный текст — PlasmaExtras.DescriptiveLabel;
 *   кнопка действия — в footer, трей подклеит его к своей нижней панели.
 *
 * Полужирного текста здесь нет вовсе. Вместо PlasmaExtras.ListSectionHeader
 * используется свой SectionHeader.qml: оригинал зашивает font.weight: Font.Bold
 * внутри Kirigami.Heading, и снаружи это не переопределяется. Геометрия,
 * кегль и линия у копии те же — отличается только начертание.
 *
 * Своего header тут нет намеренно: трей рисует шапку сам, а header аплета
 * добавляет ВТОРОЙ строкой под своей.
 */
PlasmaExtras.Representation {
    id: rep

    required property var backend

    readonly property int contentMargin: Kirigami.Units.largeSpacing

    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    Layout.minimumHeight: Kirigami.Units.gridUnit * 12
    Layout.maximumWidth: Kirigami.Units.gridUnit * 80
    Layout.maximumHeight: Kirigami.Units.gridUnit * 40
    Layout.preferredWidth: Kirigami.Units.gridUnit * 24
    // Высота по содержимому (плюс footer), но не выше уровня попапа трея:
    // иначе вне трея под короткой сводкой висит пустота, а в трее виджет
    // выбивается из общего ряда.
    Layout.preferredHeight: Math.min(content.implicitHeight + rep.contentMargin
                                     + (footerHeading.visible ? footerHeading.height : 0),
                                     Kirigami.Units.gridUnit * 24)

    collapseMarginsHint: true

    function formatSize(bytes) {
        if (!bytes || bytes <= 0)
            return "0 B";
        var units = ["B", "KiB", "MiB", "GiB", "TiB"];
        var i = 0, v = bytes;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return (i === 0 ? v.toFixed(0) : v.toFixed(1)) + " " + units[i];
    }

    contentItem: PlasmaComponents.ScrollView {
        id: scroll

        PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff
        contentWidth: availableWidth
        // Ширина задана явно: иначе implicitWidth панели считается от контента,
        // а контент — от ширины панели, и получается binding loop.
        implicitWidth: Kirigami.Units.gridUnit * 24

        ColumnLayout {
            id: content
            width: scroll.availableWidth
            spacing: Kirigami.Units.smallSpacing

            // ---- недоступность ----
            PlasmaExtras.PlaceholderMessage {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.gridUnit * 2
                Layout.leftMargin: Kirigami.Units.gridUnit * 2
                Layout.rightMargin: Kirigami.Units.gridUnit * 2
                visible: rep.backend.cmdMissing || rep.backend.serverDown || !rep.backend.loggedIn
                iconName: "cloud-offline"
                text: rep.backend.cmdMissing
                      ? i18n("MEGAcmd is not installed")
                      : (rep.backend.serverDown ? i18n("MEGAcmd server is not responding")
                                                : i18n("Not signed in"))
                explanation: rep.backend.cmdMissing
                      ? i18n("Install the megacmd package to use this widget.")
                      : (rep.backend.serverDown
                         ? i18n("Start mega-cmd-server or check the megacmd service.")
                         : i18n("Sign in with mega-cmd → login. This widget never asks for or stores your password."))
            }

            // ---- пауза ----
            Kirigami.InlineMessage {
                Layout.fillWidth: true
                Layout.leftMargin: rep.contentMargin
                Layout.rightMargin: rep.contentMargin
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: rep.backend.paused
                type: Kirigami.MessageType.Information
                text: i18n("Automatic updates are off. Data refreshes only on request.")
            }

            // ---- аккаунт ----
            SectionHeader {
                Layout.fillWidth: true
                Layout.leftMargin: rep.contentMargin
                Layout.rightMargin: rep.contentMargin
                visible: rep.backend.loggedIn && rep.backend.accountEmail.length > 0
                text: i18n("Account")
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: rep.contentMargin
                Layout.rightMargin: rep.contentMargin
                spacing: 0
                visible: rep.backend.loggedIn && rep.backend.accountEmail.length > 0

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: rep.backend.accountEmail
                    elide: Text.ElideRight
                }

                PlasmaExtras.DescriptiveLabel {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: {
                        if (rep.backend.proLevel > 0)
                            return rep.backend.proExpires.length > 0
                                 ? i18n("Pro %1 · until %2", rep.backend.proLevel, rep.backend.proExpires)
                                 : i18n("Pro %1", rep.backend.proLevel);
                        if (rep.backend.proLevel === 0)
                            return i18n("Free plan");
                        return "";
                    }
                    elide: Text.ElideRight
                }
            }

            SectionHeader {
                Layout.fillWidth: true
                Layout.leftMargin: rep.contentMargin
                Layout.rightMargin: rep.contentMargin
                visible: rep.backend.loggedIn && rep.backend.totalBytes > 0
                text: i18n("Storage")

                PlasmaExtras.DescriptiveLabel {
                    Layout.alignment: Qt.AlignVCenter
                    text: i18nc("@info used of total storage", "%1 of %2",
                                rep.formatSize(rep.backend.usedBytes),
                                rep.formatSize(rep.backend.totalBytes))
                }
            }

            PlasmaComponents.ProgressBar {
                Layout.fillWidth: true
                Layout.leftMargin: rep.contentMargin
                Layout.rightMargin: rep.contentMargin
                visible: rep.backend.loggedIn && rep.backend.totalBytes > 0
                from: 0
                to: 1
                value: rep.backend.usedRatio
            }

            // ---- синхронизации ----
            SectionHeader {
                Layout.fillWidth: true
                Layout.leftMargin: rep.contentMargin
                Layout.rightMargin: rep.contentMargin
                visible: rep.backend.loggedIn
                text: i18n("Synchronisation")
            }

            PlasmaExtras.DescriptiveLabel {
                Layout.fillWidth: true
                Layout.leftMargin: rep.contentMargin
                Layout.rightMargin: rep.contentMargin
                visible: rep.backend.loggedIn && rep.backend.syncs.length === 0
                text: i18n("No synchronisations")
            }

            // ExpandableListItem обращается к ListView.view, поэтому обязан жить
            // внутри настоящего ListView, а не в Repeater. implicitHeight
            // обязателен: без него раскладка считает список нулевой высоты
            // (contentHeight приходит позже) и не резервирует под него место.
            ListView {
                Layout.fillWidth: true
                Layout.leftMargin: rep.contentMargin
                Layout.rightMargin: rep.contentMargin
                implicitHeight: contentHeight
                Layout.preferredHeight: contentHeight
                visible: rep.backend.loggedIn && count > 0
                interactive: false
                spacing: Kirigami.Units.smallSpacing
                model: rep.backend.syncs

                // -1: иначе подсветка постоянно висит на первой строке.
                // ExpandableListItem сам ставит currentIndex при наведении.
                currentIndex: -1
                highlight: PlasmaExtras.Highlight {}
                highlightMoveDuration: Kirigami.Units.shortDuration
                highlightResizeDuration: Kirigami.Units.shortDuration

                delegate: PlasmaExtras.ExpandableListItem {
                    required property var modelData
                    required property int index

                    icon: modelData.error !== "NO" ? "dialog-error"
                        : (modelData.status === "Synced" ? "dialog-ok" : "view-refresh")
                    title: modelData.remotePath
                    subtitle: modelData.localPath + " · " + modelData.status
                    subtitleCanWrap: false
                    isBusy: modelData.status !== "Synced" && modelData.error === "NO"

                    defaultActionButtonAction: T.Action {
                        icon.name: modelData.runState === "Running" ? "media-playback-pause"
                                                                   : "media-playback-start"
                        text: modelData.runState === "Running" ? i18n("Pause") : i18n("Resume")
                        onTriggered: modelData.runState === "Running"
                                     ? rep.backend.pauseSync(modelData.id)
                                     : rep.backend.resumeSync(modelData.id)
                    }

                    contextualActions: [
                        T.Action {
                            icon.name: "folder-open"
                            text: i18n("Open local folder")
                            onTriggered: rep.backend.sh("xdg-open " + rep.backend.quote(modelData.localPath),
                                                        function () {})
                        }
                    ]
                }
            }

            // ---- подключённые папки ----
            SectionHeader {
                Layout.fillWidth: true
                Layout.leftMargin: rep.contentMargin
                Layout.rightMargin: rep.contentMargin
                visible: rep.backend.loggedIn && rep.backend.mounts.length > 0
                text: i18n("Mounted folders")
            }

            ListView {
                Layout.fillWidth: true
                Layout.leftMargin: rep.contentMargin
                Layout.rightMargin: rep.contentMargin
                implicitHeight: contentHeight
                Layout.preferredHeight: contentHeight
                visible: rep.backend.loggedIn && count > 0
                interactive: false
                spacing: Kirigami.Units.smallSpacing
                model: rep.backend.mounts

                currentIndex: -1
                highlight: PlasmaExtras.Highlight {}
                highlightMoveDuration: Kirigami.Units.shortDuration
                highlightResizeDuration: Kirigami.Units.shortDuration

                delegate: PlasmaExtras.ExpandableListItem {
                    required property var modelData
                    required property int index

                    icon: modelData.enabled ? "folder-remote" : "folder-locked"
                    title: modelData.name
                    subtitle: modelData.localPath
                    subtitleCanWrap: false

                    defaultActionButtonAction: T.Action {
                        icon.name: modelData.enabled ? "media-playback-stop" : "media-playback-start"
                        text: modelData.enabled ? i18n("Unmount") : i18n("Mount")
                        onTriggered: rep.backend.setMountEnabled(modelData.name, !modelData.enabled)
                    }

                    contextualActions: [
                        T.Action {
                            icon.name: "folder-open"
                            text: i18n("Open in file manager")
                            enabled: modelData.enabled
                            onTriggered: rep.backend.sh("xdg-open " + rep.backend.quote(modelData.localPath),
                                                        function () {})
                        }
                    ]
                }
            }

            // ---- передачи: появляются только когда они есть ----
            SectionHeader {
                Layout.fillWidth: true
                Layout.leftMargin: rep.contentMargin
                Layout.rightMargin: rep.contentMargin
                visible: rep.backend.transfers.length > 0
                text: i18n("Transfers")
            }

            ListView {
                Layout.fillWidth: true
                Layout.leftMargin: rep.contentMargin
                Layout.rightMargin: rep.contentMargin
                Layout.bottomMargin: rep.contentMargin
                implicitHeight: contentHeight
                Layout.preferredHeight: contentHeight
                visible: count > 0
                interactive: false
                spacing: Kirigami.Units.smallSpacing
                model: rep.backend.transfers

                currentIndex: -1

                delegate: PlasmaExtras.ExpandableListItem {
                    required property var modelData
                    required property int index

                    icon: modelData.direction.indexOf("⇓") !== -1 ? "go-down" : "go-up"
                    title: modelData.source
                    subtitle: modelData.progress + " · " + modelData.state
                    subtitleCanWrap: false
                    isBusy: modelData.state === "ACTIVE"
                    defaultActionButtonVisible: false
                }
            }
        }
    }

    /*
     * Нижняя панель: размер кэша слева, кнопка очистки справа — так сведения
     * о кэше не требуют отдельной секции, а кнопка оказывается там, где
     * системные виджеты держат действия.
     */
    footer: PlasmaExtras.PlasmoidHeading {
        id: footerHeading
        position: PlasmaComponents.ToolBar.Footer
        visible: rep.backend.loggedIn && rep.backend.cacheBytes >= 0

        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing

            PlasmaExtras.DescriptiveLabel {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: rep.backend.transfers.length > 0
                      ? i18n("Transfer in progress")
                      : i18nc("@info size of the local FUSE cache", "FUSE cache: %1",
                              rep.formatSize(rep.backend.cacheBytes))
            }

            PlasmaComponents.Button {
                icon.name: "edit-clear-history"
                text: rep.backend.busyClearing ? i18n("Clearing…") : i18n("Clear cache")
                // Предохранитель: запись через маунт отложенная, в кэше могут
                // лежать ещё не выгруженные файлы — чистить нельзя.
                enabled: !rep.backend.busyClearing && rep.backend.transfers.length === 0
                onClicked: rep.backend.clearCache()
            }
        }
    }
}
