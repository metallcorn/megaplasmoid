/*
 * Уведомления через KNotification. Типы событий описаны в
 * contents/notifyrc/plasma_applet_megacmd.notifyrc — благодаря этому файлу они
 * появляются в Параметрах системы → Уведомления и отключаются там поштучно.
 * Свои настройки уведомлений виджет не заводит: это работа оболочки.
 */
import QtQuick
import org.kde.notification

QtObject {
    id: notifier

    // Должно совпадать с именем файла notifyrc, иначе KNotification не найдёт
    // описание события и уведомление молча не покажется.
    readonly property string component: "plasma_applet_megacmd"

    property Component _notification: Component {
        Notification {
            componentName: notifier.component
            autoDelete: true
        }
    }

    function send(eventId, title, text) {
        var n = _notification.createObject(notifier, {
            "eventId": eventId,
            "title": title,
            "text": text
        });
        if (n)
            n.sendEvent();
    }
}
