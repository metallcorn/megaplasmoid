import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Backend {
        id: backend
        expanded: root.expanded
        paused: Plasmoid.configuration.paused
        expandedInterval: Plasmoid.configuration.pollExpandedSec * 1000
        acInterval: Plasmoid.configuration.pollAcSec * 1000
        batteryInterval: Plasmoid.configuration.pollBatterySec * 1000
    }

    Notifications {
        id: notifier
    }

    readonly property var be: backend

    // ---- признаки, по которым решаем, показываться ли вообще ----
    readonly property bool lowSpace: backend.totalBytes > 0
        && backend.usedRatio * 100 >= Plasmoid.configuration.lowSpacePercent
    readonly property bool cacheBloated: backend.cacheBytes > 0
        && backend.cacheBytes > Plasmoid.configuration.cacheLimitMb * 1024 * 1024
    readonly property bool anySyncPaused: backend.syncs.some(function (s) {
        return s.runState === "Suspended" || s.runState === "Disabled";
    })
    readonly property bool anySyncError: backend.syncs.some(function (s) {
        return s.error !== "NO" && s.error !== "";
    })
    readonly property bool busy: backend.transfers.length > 0

    readonly property bool needsAttention: backend.cmdMissing
        || backend.serverDown
        || !backend.loggedIn
        || backend.issueCount > 0
        || anySyncError
        || lowSpace
        || cacheBloated

    /*
     * Ради этого всё и затевалось: по умолчанию виджет прячется под стрелочку
     * в трее и не мозолит глаза. Всплывает сам, когда идёт передача, и
     * подсвечивается, когда что-то действительно не так.
     */
    Plasmoid.status: {
        // На паузе виджет не претендует на внимание: данные заведомо
        // могут быть устаревшими, поднимать тревогу по ним нельзя.
        if (backend.paused)
            return Plasmoid.configuration.hideWhenIdle
                ? PlasmaCore.Types.PassiveStatus
                : PlasmaCore.Types.ActiveStatus;
        if (needsAttention)
            return PlasmaCore.Types.NeedsAttentionStatus;
        if (busy || anySyncPaused)
            return PlasmaCore.Types.ActiveStatus;
        return Plasmoid.configuration.hideWhenIdle
            ? PlasmaCore.Types.PassiveStatus
            : PlasmaCore.Types.ActiveStatus;
    }

    readonly property string stateIcon: {
        if (backend.paused)
            return "media-playback-pause";
        if (backend.cmdMissing || backend.serverDown || !backend.loggedIn)
            return "cloud-offline";
        if (needsAttention)
            return "dialog-warning";
        if (busy)
            return "cloud-upload";
        return "folder-cloud";
    }

    readonly property string stateText: {
        if (backend.paused)
            return i18n("Updates paused");
        if (backend.cmdMissing)
            return i18n("MEGAcmd is not installed");
        if (backend.serverDown)
            return i18n("MEGAcmd server is not responding");
        if (!backend.loggedIn)
            return i18n("Not signed in");
        if (backend.issueCount > 0)
            return i18np("%1 sync issue", "%1 sync issues", backend.issueCount);
        if (anySyncError)
            return i18n("Sync error");
        if (lowSpace)
            return i18n("Cloud storage almost full");
        if (cacheBloated)
            return i18n("FUSE cache grew large");
        if (busy)
            return i18np("%1 transfer in progress", "%1 transfers in progress", backend.transfers.length);
        if (anySyncPaused)
            return i18n("Synchronisation paused");
        return i18n("Everything is in sync");
    }

    Plasmoid.icon: stateIcon
    toolTipMainText: i18n("MEGA")
    toolTipSubText: {
        var lines = [stateText];
        if (backend.totalBytes > 0)
            lines.push(i18nc("@info used of total storage", "%1 of %2",
                             formatSize(backend.usedBytes),
                             formatSize(backend.totalBytes)));
        return lines.join("\n");
    }

    function formatSize(bytes) {
        if (!bytes || bytes <= 0)
            return "0 B";
        var units = ["B", "KiB", "MiB", "GiB", "TiB"];
        var i = 0;
        var v = bytes;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return (i === 0 ? v.toFixed(0) : v.toFixed(1)) + " " + units[i];
    }

    function togglePause() {
        Plasmoid.configuration.paused = !Plasmoid.configuration.paused;
        Plasmoid.configuration.writeConfig();
        // При снятии паузы сразу подтягиваем свежие данные, чтобы панель
        // не показывала состояние на момент остановки.
        if (!Plasmoid.configuration.paused)
            backend.refreshNow();
    }

    /*
     * Кнопки живут здесь, а не в собственной шапке.
     *
     * Системный трей сам выкладывает действия с priority=HighPriority прямыми
     * кнопками в своей шапке, а остальные складывает в «гамбургер»
     * (application-menu). Так кнопки виджета выглядят и располагаются точно так
     * же, как у батареи, сети и звука, а шестерёнку настроек и булавку трей
     * добавляет сам.
     */
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            id: pauseAction
            text: backend.paused ? i18n("Resume updates") : i18n("Pause updates")
            icon.name: backend.paused ? "media-playback-start" : "media-playback-pause"
            priority: PlasmaCore.Action.HighPriority
            checkable: true
            checked: backend.paused
            onTriggered: root.togglePause()
        },
        PlasmaCore.Action {
            text: i18n("Refresh now")
            icon.name: "view-refresh"
            priority: PlasmaCore.Action.HighPriority
            onTriggered: backend.refreshNow()
        },
        PlasmaCore.Action {
            text: i18n("Open MEGA folder")
            icon.name: "folder-open"
            enabled: backend.mounts.length > 0
            onTriggered: {
                if (backend.mounts.length > 0)
                    backend.sh("xdg-open " + backend.quote(backend.mounts[0].localPath), function () {});
            }
        }
    ]

    compactRepresentation: MouseArea {
        id: compact

        property bool wasExpanded: false

        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small

        onPressed: wasExpanded = root.expanded
        onClicked: root.expanded = !wasExpanded

        Kirigami.Icon {
            anchors.fill: parent
            source: root.stateIcon
            active: compact.containsMouse
        }

        // Индикатор количества проблем — маленький бейдж поверх иконки.
        Rectangle {
            visible: backend.issueCount > 0
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Math.round(parent.width * 0.5)
            height: width
            radius: width / 2
            color: Kirigami.Theme.negativeTextColor

            PlasmaComponents.Label {
                anchors.centerIn: parent
                text: backend.issueCount > 9 ? "9+" : backend.issueCount
                font.pixelSize: Math.round(parent.height * 0.7)
                color: Kirigami.Theme.backgroundColor
            }
        }
    }

    fullRepresentation: FullRepresentation {
        backend: root.be
    }

    /*
     * Уведомления срабатывают по фронту: только в момент перехода состояния,
     * иначе одна и та же проблема сыпалась бы каждый цикл опроса.
     */
    QtObject {
        id: prev
        property bool primed: false      // до первой загрузки данных молчим
        property bool issues: false
        property bool syncError: false
        property bool lowSpace: false
        property bool cacheBloated: false
        property bool serverDown: false
        property bool loggedOut: false
        property bool wasBusy: false
    }

    // Данные приходят несколькими асинхронными вызовами, поэтому проверяем не
    // сразу, а когда поток изменений утихнет — иначе поймаем полузаполненное
    // состояние.
    Timer {
        id: settle
        interval: 1500
        onTriggered: root.evaluateNotifications()
    }

    Connections {
        target: backend
        function onSyncsChanged() { settle.restart(); }
        function onIssueCountChanged() { settle.restart(); }
        function onUsedBytesChanged() { settle.restart(); }
        function onCacheBytesChanged() { settle.restart(); }
        function onServerDownChanged() { settle.restart(); }
        function onLoggedInChanged() { settle.restart(); }
        function onTransfersChanged() { settle.restart(); }
    }

    function evaluateNotifications() {
        var hasIssues = backend.issueCount > 0;
        var loggedOut = !backend.cmdMissing && !backend.serverDown && !backend.loggedIn;

        // Первый проход только запоминает состояние: при добавлении виджета или
        // перезапуске оболочки не нужно вываливать уведомления о том, что и так
        // уже видно в панели.
        if (!prev.primed) {
            prev.primed = true;
        } else {
            if (hasIssues && !prev.issues)
                notifier.send("syncIssue", i18n("MEGA: sync issue"),
                              i18np("%1 issue detected, synchronisation is stalled",
                                    "%1 issues detected, synchronisation is stalled",
                                    backend.issueCount));

            if (anySyncError && !prev.syncError)
                notifier.send("syncError", i18n("MEGA: sync error"),
                              i18n("One of the synchronisations reported an error"));

            if (lowSpace && !prev.lowSpace)
                notifier.send("lowSpace", i18n("MEGA: running out of space"),
                              i18n("%1% of cloud storage is used",
                                   Math.round(backend.usedRatio * 100)));

            if (backend.serverDown && !prev.serverDown)
                notifier.send("serverDown", i18n("MEGA: server unavailable"),
                              i18n("Cannot reach mega-cmd-server"));

            if (loggedOut && !prev.loggedOut)
                notifier.send("notLoggedIn", i18n("MEGA: signed out"),
                              i18n("The MEGAcmd session is no longer valid, syncing has stopped"));

            if (cacheBloated && !prev.cacheBloated)
                notifier.send("cacheBloated", i18n("MEGA: FUSE cache grew large"),
                              i18n("The cache takes up %1 and can be cleared from the widget",
                                   formatSize(backend.cacheBytes)));

            // Завершение: были передачи, теперь их нет и всё синхронизировано.
            if (prev.wasBusy && !busy && !hasIssues && !anySyncError)
                notifier.send("syncFinished", i18n("MEGA: synchronisation finished"),
                              i18n("All transfers have completed"));
        }

        prev.issues = hasIssues;
        prev.syncError = anySyncError;
        prev.lowSpace = lowSpace;
        prev.cacheBloated = cacheBloated;
        prev.serverDown = backend.serverDown;
        prev.loggedOut = loggedOut;
        prev.wasBusy = busy;
    }

    Component.onCompleted: {
        // Кладём на место описание типов уведомлений и каталог переводов:
        // пакет плазмоида не может ставить файлы вне своего каталога.
        backend.installRuntimeFiles(
            Qt.resolvedUrl("../notifyrc/plasma_applet_megacmd.notifyrc"),
            Qt.resolvedUrl("../locale/ru/LC_MESSAGES/plasma_applet_org.kde.plasma.megacmd.mo"));
    }
}
