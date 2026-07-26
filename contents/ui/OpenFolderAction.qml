/*
 * Одно действие «открыть локальную папку» на все места, где оно нужно:
 * строки синхронизаций, строки подключённых папок, контекстное меню виджета.
 *
 * Раньше это были три отдельные копии с разными подписями («Open local folder»
 * и «Open in file manager»), делавшие ровно одно и то же. Разные названия у
 * одинакового действия — это несогласованность интерфейса, поэтому теперь
 * подпись и значок живут в одном месте.
 */
import QtQuick
import QtQuick.Templates as T

T.Action {
    required property var backend
    required property string path

    icon.name: "folder-open"
    text: i18n("Open in file manager")
    enabled: path.length > 0

    onTriggered: backend.openLocal(path)
}
