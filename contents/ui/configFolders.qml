/*
 * Страница настроек «Папки»: синхронизации, FUSE-маунты и правила исключения.
 *
 * Применение — по Apply/OK, как во всех диалогах KDE. Контракт диалога описан
 * в его исходнике (shells/org.kde.plasma.desktop/contents/configuration/
 * AppletConfiguration.qml):
 *
 *   settingValueChanged():  applyButton.enabled = ... || currentItem.unsavedChanges
 *   saveConfig():           if (currentItem.saveConfig) currentItem.saveConfig()
 *   closing():              при непустых изменениях спрашивает Apply/Discard/Cancel
 *
 * Поэтому страница объявляет property bool unsavedChanges и function
 * saveConfig(), а до нажатия копит изменения в pending и ничего не трогает на
 * сервере. Отказ от изменений диалог берёт на себя: страница пересоздаётся, и
 * очередь исчезает вместе с ней.
 *
 * Особенность: страница живёт в отдельном контексте и не видит Backend из
 * виджета, поэтому здесь свой экземпляр с paused: true — опрос по таймеру не
 * нужен, данные обновляются после операций и при открытии.
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

    RuleProfiles {
        id: profiles
        customJson: plasmoid ? plasmoid.configuration.ruleProfiles : "[]"
    }

    // ---- контракт диалога настроек ----

    property var pending: []
    property bool unsavedChanges: pending.length > 0

    function queue(op) {
        var list = pending.slice();
        list.push(op);
        pending = list;
    }

    function dropPending() {
        pending = [];
    }

    /*
     * Порядок выполнения — тот же, в каком пользователь набирал изменения.
     * Очередь Backend последовательная, поэтому команды не перемешаются между
     * собой и с опросом.
     */
    function saveConfig() {
        var ops = pending;
        pending = [];

        var profilesJson = plasmoid ? plasmoid.configuration.ruleProfiles : "[]";

        for (var i = 0; i < ops.length; ++i) {
            var op = ops[i];
            switch (op.kind) {
            case "addSync":
                backend.addSyncWithProfile(op.local, op.remote, op.filters);
                break;
            case "removeSync":
                backend.removeSync(op.id);
                break;
            case "rules":
                backend.applyProfile(op.target, op.filters);
                break;
            case "addMount":
                backend.addMount(op.local, op.remote, op.name, op.readOnly);
                break;
            case "removeMount":
                backend.removeMount(op.name);
                break;
            case "saveProfile":
                profiles.customJson = profilesJson;
                profilesJson = profiles.withSaved(op.name, op.filters);
                break;
            }
        }

        if (plasmoid && profilesJson !== plasmoid.configuration.ruleProfiles) {
            plasmoid.configuration.ruleProfiles = profilesJson;
            plasmoid.configuration.writeConfig();
        }
    }

    // ---- состояние страницы ----

    readonly property bool syncMode: modeGroup.currentIndex === 0

    // Открытый редактор правил. Цель "" означает набор для ещё не созданной
    // синхронизации: применять его некуда, он поедет вместе с созданием.
    property bool rulesOpen: false
    property string rulesTarget: ""
    property string rulesLocalRoot: ""
    property string rulesTitle: ""
    property var rulesFilters: []
    property bool rulesCloudHasFiles: false
    property int rulesPendingIndex: -1     // правим набор запланированной папки

    // Набор для новой синхронизации: по умолчанию профиль разработки, потому
    // что виджет ставят ради каталогов с работой, а не ради «Загрузок».
    property var draftFilters: profiles.byKey("developer")
                               ? profiles.byKey("developer").filters.slice() : []

    function openRulesForSync(sync) {
        rulesTarget = sync.localPath;
        rulesLocalRoot = sync.localPath;
        rulesTitle = i18n("Rules: %1", sync.localPath);
        rulesCloudHasFiles = true;
        rulesPendingIndex = -1;
        rulesFilters = [];
        backend.ruleCheckText = "";
        backend.loadRules(sync.localPath);
        rulesOpen = true;
    }

    function openRulesForDraft() {
        rulesTarget = "";
        rulesLocalRoot = localPath.text;
        rulesTitle = i18n("Rules for the new folder");
        rulesCloudHasFiles = false;
        rulesPendingIndex = -1;
        rulesFilters = draftFilters.slice();
        backend.ruleCheckText = "";
        rulesOpen = true;
    }

    function closeRules(filters) {
        if (rulesTarget.length > 0) {
            // Ставим в очередь, только если набор действительно изменился.
            if (JSON.stringify(filters.slice().sort())
                !== JSON.stringify(backend.rules.slice().sort()))
                queue({ kind: "rules", target: rulesTarget, filters: filters });
        } else {
            draftFilters = filters;
        }
        rulesOpen = false;
    }

    // Правила синхронизации подгружаются асинхронно: как пришли — кладём в
    // рабочую копию редактора.
    Connections {
        target: backend
        function onRulesChanged() {
            if (page.rulesOpen && page.rulesTarget.length > 0
                && page.rulesFilters.length === 0)
                page.rulesFilters = backend.rules.slice();
        }
        function onOperationDone(ok, message) {
            backend.refreshQuota();
            if (ok) {
                error.visible = false;
            } else {
                error.text = message.length > 0 ? message
                                                : i18n("The operation failed");
                error.visible = true;
            }
        }
    }

    Component.onCompleted: backend.refreshState()

    Dialogs.FolderDialog {
        id: folderDialog
        title: i18n("Choose a local folder")
        onAccepted: localPath.text = selectedFolder.toString().replace(/^file:\/\//, "")
    }

    // ---- редактор правил ----

    IgnoreRules {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        visible: page.rulesOpen
        backend: backend
        profiles: profiles
        filters: page.rulesFilters
        localRoot: page.rulesLocalRoot
        title: page.rulesTitle
        cloudHasFiles: page.rulesCloudHasFiles
        onCloseRequested: page.closeRules(filters)
        onSaveProfileRequested: function (name, f) {
            page.queue({ kind: "saveProfile", name: name, filters: f });
        }
    }

    // ---- основной вид ----

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing
        visible: !page.rulesOpen

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
            visible: page.pending.length > 0
            type: Kirigami.MessageType.Information
            text: i18np("One change is waiting for Apply.",
                        "%1 changes are waiting for Apply.", page.pending.length)

            actions: [
                Kirigami.Action {
                    icon.name: "edit-undo"
                    text: i18n("Discard changes")
                    onTriggered: page.dropPending()
                }
            ]
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: backend.cmdMissing || backend.serverDown || !backend.loggedIn
            type: Kirigami.MessageType.Warning
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
                currentIndex: -1

                // Список показывает и то, что есть, и то, что появится после
                // Apply: иначе непонятно, куда делась только что добавленная
                // папка.
                model: {
                    var rows = [];
                    var list = page.syncMode ? backend.syncs : backend.mounts;
                    for (var i = 0; i < list.length; ++i)
                        rows.push({ entry: list[i], planned: "" });
                    for (var j = 0; j < page.pending.length; ++j) {
                        var op = page.pending[j];
                        if (page.syncMode && op.kind === "addSync")
                            rows.push({ entry: { localPath: op.local,
                                                 remotePath: op.remote,
                                                 runState: "", status: "",
                                                 error: "NO", id: "" },
                                        planned: "add", opIndex: j });
                        if (!page.syncMode && op.kind === "addMount")
                            rows.push({ entry: { localPath: op.local,
                                                 remotePath: op.remote,
                                                 name: op.name,
                                                 enabled: false, persistent: true },
                                        planned: "add", opIndex: j });
                    }
                    return rows;
                }

                delegate: QQC2.ItemDelegate {
                    required property var modelData
                    required property int index

                    width: existing.width
                    highlighted: existing.currentIndex === index
                    onClicked: existing.currentIndex = index

                    readonly property var entry: modelData.entry
                    readonly property bool willBeAdded: modelData.planned === "add"
                    readonly property bool willBeRemoved: {
                        for (var i = 0; i < page.pending.length; ++i) {
                            var op = page.pending[i];
                            if (page.syncMode && op.kind === "removeSync"
                                && op.id === entry.id)
                                return true;
                            if (!page.syncMode && op.kind === "removeMount"
                                && op.name === entry.name)
                                return true;
                        }
                        return false;
                    }
                    readonly property bool rulesChangePlanned: {
                        for (var i = 0; i < page.pending.length; ++i)
                            if (page.pending[i].kind === "rules"
                                && page.pending[i].target === entry.localPath)
                                return true;
                        return false;
                    }

                    contentItem: RowLayout {
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: willBeAdded ? "list-add"
                                  : (willBeRemoved ? "list-remove"
                                  : (page.syncMode ? "folder-sync" : "folder-remote"))
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: Kirigami.Units.iconSizes.small
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            QQC2.Label {
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                                font.strikeout: willBeRemoved
                                text: entry.localPath + "  →  " + entry.remotePath
                            }

                            QQC2.Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font: Kirigami.Theme.smallFont
                                opacity: 0.7
                                text: {
                                    if (willBeAdded)
                                        return i18n("will be added on Apply");
                                    if (willBeRemoved)
                                        return i18n("will be removed on Apply");
                                    if (page.syncMode) {
                                        var s = entry.runState !== "Running"
                                              ? i18n("paused") : entry.status;
                                        return rulesChangePlanned
                                             ? s + " · " + i18n("rules will change on Apply")
                                             : s;
                                    }
                                    return (entry.enabled ? i18n("mounted")
                                                          : i18n("not mounted"))
                                         + (entry.persistent ? ""
                                                             : " · " + i18n("transient"));
                                }
                            }
                        }

                        QQC2.ToolButton {
                            visible: page.syncMode && !willBeAdded && !willBeRemoved
                            icon.name: "view-filter"
                            text: i18n("Rules…")
                            display: QQC2.AbstractButton.IconOnly
                            onClicked: page.openRulesForSync(entry)
                            QQC2.ToolTip.text: i18n("What is excluded from this synchronisation")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }

                        QQC2.ToolButton {
                            icon.name: willBeAdded || willBeRemoved ? "edit-undo"
                                                                    : "edit-delete"
                            text: willBeAdded || willBeRemoved ? i18n("Undo")
                                                               : i18n("Remove")
                            display: QQC2.AbstractButton.IconOnly
                            onClicked: {
                                if (willBeAdded || willBeRemoved) {
                                    var list = page.pending.filter(function (op) {
                                        if (willBeAdded)
                                            return !((op.kind === "addSync"
                                                      || op.kind === "addMount")
                                                     && op.local === entry.localPath);
                                        return !((op.kind === "removeSync"
                                                  && op.id === entry.id)
                                                 || (op.kind === "removeMount"
                                                     && op.name === entry.name));
                                    });
                                    page.pending = list;
                                } else if (page.syncMode) {
                                    page.queue({ kind: "removeSync", id: entry.id });
                                } else {
                                    page.queue({ kind: "removeMount", name: entry.name });
                                }
                            }
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

            QQC2.Label { text: i18n("Name:"); visible: !page.syncMode }

            QQC2.TextField {
                id: mountName
                Layout.fillWidth: true
                Layout.columnSpan: 2
                visible: !page.syncMode
                placeholderText: i18n("optional, defaults to the folder name")
            }

            // Профиль правил выбирается до создания: MEGAcmd копирует набор в
            // новую синхронизацию в момент создания, поэтому она сразу родится
            // правильной и мусор не успеет уехать.
            QQC2.Label { text: i18n("Rules:"); visible: page.syncMode }

            QQC2.ComboBox {
                id: profileBox
                Layout.fillWidth: true
                visible: page.syncMode
                textRole: "name"
                model: profiles.all
                currentIndex: {
                    var d = profiles.detect(page.draftFilters);
                    if (!d)
                        return -1;
                    for (var i = 0; i < profiles.all.length; ++i)
                        if (profiles.all[i].key === d.key)
                            return i;
                    return -1;
                }
                displayText: currentIndex >= 0 ? currentText : i18n("Custom set")
                onActivated: function (index) {
                    page.draftFilters = profiles.all[index].filters.slice();
                }
            }

            QQC2.Button {
                visible: page.syncMode
                icon.name: "view-filter"
                text: i18n("Edit…")
                onClicked: page.openRulesForDraft()
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
                text: i18n("Nothing is changed until you press Apply or OK.")
            }

            QQC2.Button {
                icon.name: "list-add"
                text: page.syncMode ? i18n("Add synchronisation") : i18n("Add mount")
                // Корень облака MEGAcmd как цель синхронизации отвергает, если
                // ниже уже есть хоть одна («Active sync below path»).
                enabled: backend.loggedIn && localPath.text.length > 0
                         && (!page.syncMode || remotePicker.path !== "/")
                onClicked: {
                    if (page.syncMode)
                        page.queue({ kind: "addSync", local: localPath.text,
                                     remote: remotePicker.path,
                                     filters: page.draftFilters.slice() });
                    else
                        page.queue({ kind: "addMount", local: localPath.text,
                                     remote: remotePicker.path,
                                     name: mountName.text,
                                     readOnly: readOnly.checked });
                    localPath.text = "";
                    mountName.text = "";
                }
                QQC2.ToolTip.text: page.syncMode && remotePicker.path === "/"
                                   ? i18n("Choose a cloud folder: the cloud root cannot be synchronised")
                                   : ""
                QQC2.ToolTip.visible: hovered && page.syncMode
                                      && remotePicker.path === "/"
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
    }
}
