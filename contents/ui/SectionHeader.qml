/*
 * Заголовок секции: точная копия геометрии PlasmaExtras.ListSectionHeader
 * (тот же кегль — Kirigami.Heading level 5, та же прозрачность 0.75, тот же
 * верхний отступ largeSpacing + smallSpacing, та же линия во всю оставшуюся
 * ширину), но начертание обычное.
 *
 * Свой компонент нужен потому, что оригинал зашивает font.weight: Font.Bold
 * внутри Kirigami.Heading и переопределить его снаружи нельзя.
 *
 * Содержимое, объявленное внутри тега, попадает в строку справа от линии —
 * так же, как у оригинала (например значение рядом с названием секции).
 */
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

RowLayout {
    id: root

    property string text

    spacing: Kirigami.Units.largeSpacing
    Layout.topMargin: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing

    Kirigami.Heading {
        // Ширину НЕ привязываем к root.width: этот RowLayout сам является
        // элементом внешней раскладки, его ширина зависит от детей, и обратная
        // связь даёт «Detected recursive rearrange». В оригинале такая привязка
        // допустима только потому, что там строка лежит внутри ItemDelegate и
        // получает ширину извне. Сжатие длинного заголовка обеспечивают
        // minimumWidth 0 и elide.
        Layout.minimumWidth: 0
        Layout.alignment: Qt.AlignVCenter

        level: 5
        type: Kirigami.Heading.Primary
        font.weight: Font.Normal      // единственное отличие от оригинала
        opacity: 0.75
        text: root.text
        elide: Text.ElideRight

        Accessible.ignored: true
    }

    Kirigami.Separator {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter

        Accessible.ignored: true
    }
}
