/*
 * Выбор папки в облаке: обход по одному уровню.
 *
 * Рекурсивный `find --type=d` на большом аккаунте слишком дорог, поэтому
 * содержимое запрашивается только для текущего пути, а вложенность даёт
 * навигация. Показываются лишь папки: файл не может быть целью синхронизации
 * или маунта.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: picker

    required property var backend

    // Текущий путь в облаке; он же результат выбора.
    property string path: "/"
    property bool busy: false

    spacing: Kirigami.Units.smallSpacing

    function reload() {
        busy = true;
        backend.listRemoteDirs(path);
    }

    // Результат приходит сигналом, а не колбэком: хранение функций в property var
    // валило plasmashell, подробности в шапке Backend.qml.
    Connections {
        target: picker.backend

        function onRemoteDirsReady(path, dirs) {
            // Ответ мог прийти на прошлый путь, если пользователь успел перейти.
            if (path !== picker.path)
                return;
            model.clear();
            for (var i = 0; i < dirs.length; ++i) {
                // Корзина в выборе не нужна.
                if (dirs[i] === ".Trash-1000")
                    continue;
                model.append({ "name": dirs[i] });
            }
            picker.busy = false;
        }
    }

    function enter(name) {
        path = (path === "/") ? "/" + name : path + "/" + name;
        reload();
    }

    function up() {
        if (path === "/")
            return;
        var at = path.lastIndexOf("/");
        path = (at <= 0) ? "/" : path.substring(0, at);
        reload();
    }

    ListModel { id: model }

    Component.onCompleted: reload()

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.ToolButton {
            icon.name: "go-up"
            enabled: picker.path !== "/" && !picker.busy
            onClicked: picker.up()
            QQC2.ToolTip.text: i18n("Go up")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }

        QQC2.TextField {
            Layout.fillWidth: true
            text: picker.path
            // Путь можно ввести руками: у кого дерево большое, щёлкать долго.
            onEditingFinished: {
                if (text !== picker.path) {
                    picker.path = text.length > 0 ? text : "/";
                    picker.reload();
                }
            }
        }

        QQC2.BusyIndicator {
            running: picker.busy
            visible: running
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: Kirigami.Units.iconSizes.small
        }
    }

    QQC2.ScrollView {
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 9
        clip: true

        ListView {
            id: view
            model: model
            currentIndex: -1

            delegate: QQC2.ItemDelegate {
                required property string name
                required property int index

                width: view.width
                icon.name: "folder"
                text: name
                onDoubleClicked: picker.enter(name)
                onClicked: view.currentIndex = index

                QQC2.ToolTip.text: i18n("Double-click to open")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        visible: !picker.busy && model.count === 0
        text: i18n("No subfolders here")
        font: Kirigami.Theme.smallFont
        opacity: 0.7
    }
}
