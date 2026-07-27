import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Раскладка по HIG: подписи с двоеточием в левой колонке, единицы измерения
// вынесены в подпись (а не внутрь поля, иначе ломается ввод с клавиатуры),
// смысловые группы разделены секциями с заголовками.
Kirigami.FormLayout {
    id: page

    property alias cfg_hideWhenIdle: hideWhenIdle.checked
    property alias cfg_megacmdPath: megacmdPath.text
    property alias cfg_lowSpacePercent: lowSpace.value
    property alias cfg_cacheLimitMb: cacheLimit.value
    property alias cfg_pollExpandedSec: pollExpanded.value
    property alias cfg_pollAcSec: pollAc.value
    property alias cfg_pollBatterySec: pollBattery.value

    // ---- поведение значка ----

    QQC2.CheckBox {
        id: hideWhenIdle
        Kirigami.FormData.label: i18n("Tray icon:")
        text: i18n("Hide when everything is fine")
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 18
        text: i18n("The icon appears on its own while data is transferring, and is highlighted on sync errors, low space or an oversized cache.")
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
    }

    // ---- расположение MEGAcmd ----

    Item {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("MEGAcmd location")
    }

    QQC2.TextField {
        id: megacmdPath
        Kirigami.FormData.label: i18n("Directory with mega-exec:")
        placeholderText: i18n("leave empty if it is in PATH")
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 18
        text: i18n("Plasma does not read ~/.bashrc, so its PATH is shorter than the one in a terminal. If MEGAcmd was installed without root — the usual case on Steam Deck — name its directory here. Run \"which mega-exec\" in a terminal to find it.")
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
    }

    // ---- пороги предупреждений ----

    Item {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("When to warn")
    }

    QQC2.SpinBox {
        id: lowSpace
        Kirigami.FormData.label: i18n("Cloud storage used above, %:")
        from: 50
        to: 99
    }

    QQC2.SpinBox {
        id: cacheLimit
        Kirigami.FormData.label: i18n("FUSE cache larger than, MiB:")
        from: 128
        to: 102400
        stepSize: 128
        editable: true
    }

    // ---- частота опроса ----

    Item {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Polling interval")
    }

    QQC2.SpinBox {
        id: pollExpanded
        Kirigami.FormData.label: i18n("Panel open, s:")
        from: 1
        to: 60
    }

    QQC2.SpinBox {
        id: pollAc
        Kirigami.FormData.label: i18n("Collapsed, on AC power, s:")
        from: 5
        to: 3600
        stepSize: 5
        editable: true
    }

    QQC2.SpinBox {
        id: pollBattery
        Kirigami.FormData.label: i18n("Collapsed, on battery, s:")
        from: 10
        to: 3600
        stepSize: 10
        editable: true
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 18
        text: i18n("The widget queries MEGAcmd on a timer only. The rarer the polling while collapsed, the less battery it uses.")
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
    }
}
