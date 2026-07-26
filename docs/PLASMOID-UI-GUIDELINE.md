# Plasmoid UI Guideline

Практическое руководство по интерфейсу плазмоидов для Plasma 6. Не пересказ
официального HIG, а свод того, что подтверждено исходниками plasma-workspace и
замерами на живой системе.

Проверено на **Plasma 6.7.3, Qt 6, KDE neon 24.04**. Числовые значения —
результат замеров при масштабе 100 %; на других масштабах они меняются, поэтому
в коде должны стоять именованные константы, а не числа.

Помечено:
- **[источник]** — подтверждено кодом plasma-workspace или самого компонента;
- **[замер]** — получено измерением на живой системе;
- **[соглашение]** — общепринятая практика, обязательной не является.

---

## 1. Строение пакета

```
metadata.json                    KPlugin: Id, Name, Icon, Category, License, Version
contents/
  ui/main.qml                    корень: PlasmoidItem
  ui/<Component>.qml             свои компоненты, доступны по имени файла
  config/main.xml                ключи настроек (KConfigXT)
  config/config.qml              страницы диалога настроек
  ui/configGeneral.qml           форма страницы
  notifyrc/<домен>.notifyrc      типы уведомлений
  locale/<язык>/LC_MESSAGES/     каталоги переводов
```

`.plasmoid` — обычный zip с `metadata.json` и `contents/`. Ставится через
`kpackagetool6 --type Plasma/Applet --install`, либо *Add Widgets → Get New
Widgets → Install Widget From Local File*.

**Ловушка:** `kpackagetool6 -u <каталог>` на каталог, который сам является местом
установки, удаляет пакет перед переустановкой из него же и оставляет пустоту.
Исходники держать отдельно от места установки. **[замер]**

---

## 2. Представления и статус

```qml
PlasmoidItem {
    id: root
    compactRepresentation: /* иконка в панели или трее */
    fullRepresentation:    /* раскрытая панель */
    Plasmoid.icon: /* имя иконки из темы */
    toolTipMainText: /* заголовок подсказки */
    toolTipSubText:  /* строки состояния */
}
```

### Plasmoid.status

Значения `PlasmaCore.Types` **[замер]**:

| Значение | Число | Смысл в системном трее |
|---|---|---|
| `UnknownStatus` | 0 | — |
| `PassiveStatus` | 1 | значок скрыт под стрелочкой |
| `ActiveStatus` | 2 | значок показан в трее |
| `NeedsAttentionStatus` | 3 | значок показан и подсвечен |
| `RequiresAttentionStatus` | 4 | сильнее предыдущего |
| `AcceptingInputStatus` | 5 | виджет ждёт ввода |
| `HiddenStatus` | 6 | скрыт полностью |

Правила, которые стоит соблюдать:

- **Пассивен по умолчанию, если сказать нечего.** Виджет, постоянно висящий в
  трее без новостей, — шум.
- `NeedsAttention` только когда требуется действие пользователя. Не для «идёт
  работа» — для этого `Active`.
- **Если данные заведомо устаревшие (виджет на паузе, опрос выключен), тревогу
  поднимать нельзя.** Статус в этом состоянии не должен быть `NeedsAttention`.

---

## 3. Системный трей: кто рисует шапку

Это главный источник неродного вида, и он не очевиден.

Трей рисует общую шапку **сам** — `applets/systemtray/qml/ExpandedRepresentation.qml`
**[источник]**:

- стрелка «назад» (когда открыт аплет и есть скрытые элементы);
- `Kirigami.Heading level: 1` с текстом `plasmoid.title`;
- кнопки действий, у которых `priority === PlasmaCore.Action.HighPriority`;
- «гамбургер» `application-menu` с остальными действиями;
- шестерёнка настроек — из внутреннего действия `configure`;
- булавка `window-pin` («Keep Open»).

Если аплет объявит свой `header`, трей подклеит его **второй строкой** под своей:

```qml
height: trayHeading.height + bottomPadding + container.headingHeight
```

Отсюда двойной заголовок и высота, не совпадающая с батареей, сетью и звуком.

### Правило

**Аплет, предназначенный для трея, не объявляет свой `header`.** Кнопки идут в
действия:

```qml
Plasmoid.contextualActions: [
    PlasmaCore.Action {
        text: i18n("Pause updates")
        icon.name: "media-playback-pause"
        priority: PlasmaCore.Action.HighPriority   // прямая кнопка в шапке трея
        checkable: true
        checked: root.paused
        onTriggered: root.togglePause()
    },
    PlasmaCore.Action {
        text: i18n("Open folder")                  // без priority → в «гамбургер»
        icon.name: "folder-open"
        onTriggered: root.openFolder()
    }
]
```

`footer` объявлять можно: трей подклеивает его к своей нижней панели
(`mergeFooters`, `container.footerHeight`) **[источник]**. Это штатное место для
кнопок действий.

### Размеры в трее

Попап трея держит минимум `Kirigami.Units.gridUnit * 24` на обе стороны
**[источник]**, контейнер аплета — `gridUnit * 12`. Следствия:

- в трее размер задаёт трей, все виджеты одинаковы;
- **запрашивать больше `gridUnit * 24` нельзя** — станете выше соседей, и
  переключение между виджетами перестанет быть бесшовным;
- запрашивать меньше можно: вне трея (на рабочем столе, в панели) виджет тогда
  сожмётся под содержимое.

---

## 4. Метрики

Значения при масштабе 100 % **[замер]**:

| Константа | Значение | Где применяется |
|---|---|---|
| `Kirigami.Units.smallSpacing` | 4 px | шаг между элементами внутри группы |
| `Kirigami.Units.mediumSpacing` | 6 px | промежуточный шаг |
| `Kirigami.Units.largeSpacing` | 8 px | **боковые отступы содержимого**, шаг между группами |
| `Kirigami.Units.gridUnit` | 18 px | сетка размеров: `gridUnit * N` для ширины и высоты панели |
| `iconSizes.small` | 16 px | значок в строке списка, компактное представление |
| `iconSizes.smallMedium` | 22 px | кнопки в шапке трея |
| `iconSizes.medium` | 32 px | заголовки |
| `iconSizes.large` | 48 px | пустые состояния |
| `shortDuration` | 141 мс | подсветка, мелкие переходы |
| `longDuration` | 283 мс | появление панелей |
| `toolTipDelay` | 700 мс | задержка подсказки |

**`gridUnit` в отступах — ошибка.** Он вдвое больше `largeSpacing`, и поля
получаются заметно шире нативных. `gridUnit` предназначен для габаритов, а не
для полей.

Эталонные значения из `applets/devicenotifier/qml/FullRepresentation.qml`
**[источник]**:

```qml
ListView {
    // No topMargin because ListSectionHeader brings its own
    bottomMargin: Kirigami.Units.largeSpacing
    leftMargin:   Kirigami.Units.largeSpacing
    rightMargin:  Kirigami.Units.largeSpacing
    spacing:      Kirigami.Units.smallSpacing
}
```

Пиксели в коде не писать никогда: сломается HiDPI и настройка масштаба.

---

## 5. Каталог компонентов

`org.kde.plasma.extras` **[замер: список файлов модуля]**:

| Компонент | Назначение |
|---|---|
| `Representation` | корень раскрытой панели, поддерживает `header` и `footer` |
| `PlasmoidHeading` | панель шапки или подвала; `position: ToolBar.Footer` для подвала |
| `BasicPlasmoidHeading` | облегчённый вариант |
| `ListSectionHeader` | заголовок секции списка (подпись + линия) |
| `ExpandableListItem` | строка списка: значок, заголовок, подзаголовок, кнопка действия, раскрытие |
| `ListItem` | простая строка |
| `DescriptiveLabel` | второстепенный текст |
| `Heading` | заголовок |
| `PlaceholderMessage` | пустое состояние: значок, текст, пояснение |
| `Highlight` | подсветка строки |
| `SearchField`, `PasswordField`, `ActionTextField` | поля ввода |
| `ModelContextMenu` | контекстное меню по модели |
| `ContextualHelpButton` | кнопка «что это» |
| `ShadowedLabel` | текст с тенью (для поверхностей с картинкой) |

Из `org.kde.plasma.components`: `ScrollView`, `Label`, `Button`, `ToolButton`,
`ProgressBar`, `Switch`, `CheckBox`, `ToolTip`, `ScrollBar`.
Из `org.kde.kirigami`: `Units`, `Theme`, `Icon`, `Heading`, `Separator`,
`InlineMessage`, `FormLayout`.

### Что чем не заменять

| Задача | Правильно | Неправильно |
|---|---|---|
| Прокрутка в панели | `PlasmaComponents.ScrollView` | `QQC2.ScrollView` |
| Второстепенный текст | `PlasmaExtras.DescriptiveLabel` | `Label` + `smallFont` + `opacity` |
| Заголовок секции | `PlasmaExtras.ListSectionHeader` | жирный `Label` |
| Строка списка | `PlasmaExtras.ExpandableListItem` | самодельный `RowLayout` |
| Пустое состояние | `PlasmaExtras.PlaceholderMessage` | центрированный `Label` |

Ручная вёрстка выглядит чужеродно: у штатных компонентов зашиты высота строк,
отступы и кегль, которые на глаз не угадываются.

---

## 6. Типографика и цвета

- Заголовки — `Kirigami.Heading` с `level` от 1 (крупный) до 5 (мелкий) и
  `type: Kirigami.Heading.Primary | Secondary`.
- `ListSectionHeader` рисует подпись как `Heading level: 5`, `type: Primary`,
  `opacity: 0.75` и **принудительно `font.weight: Font.Bold`** — с комментарием
  в исходнике «for contrast with small text» **[источник]**. Снаружи это не
  переопределяется: `label` — алиас только к тексту.
- Если полужирный не нужен (например по требованию дизайна проекта), придётся
  сделать свой заголовок. Копия ListSectionHeader с `Font.Normal` — рабочий путь,
  но см. ловушку в §7.
- Цвета — только через `Kirigami.Theme`: `textColor`, `disabledTextColor`,
  `negativeTextColor`, `positiveTextColor`, `highlightColor`,
  `backgroundColor`. Захардкоженный цвет ломается при смене темы и в тёмном
  оформлении.
- Шрифты — `Kirigami.Theme.defaultFont`, `smallFont`. Размеры в пунктах не
  задавать.

---

## 7. Раскладка: проверенные ловушки

### 7.1. ListView внутри ColumnLayout

```qml
ListView {
    Layout.fillWidth: true
    implicitHeight: contentHeight            // обязательно
    Layout.preferredHeight: contentHeight
    interactive: false
    spacing: Kirigami.Units.smallSpacing
    currentIndex: -1                         // обязательно, если есть highlight
    highlight: PlasmaExtras.Highlight {}
    highlightMoveDuration: Kirigami.Units.shortDuration
}
```

- **Без `implicitHeight` раскладка считает список нулевой высоты** (замерено:
  `h=0` при видимых строках). Место под него не резервируется, нижние элементы
  наезжают друг на друга, а строки всё равно рисуются — `clip` по умолчанию
  выключен, делегаты выходят за границы. **[замер]**
- **`currentIndex` по умолчанию 0**, поэтому `highlight` виснет на первой строке
  постоянно. `-1` снимает подсветку; `ExpandableListItem` сам выставляет
  `currentIndex` при наведении. **[замер]**
- `ExpandableListItem` обращается внутри к `ListView.view` (навигация,
  раскрытие) **[источник]**, поэтому обязан жить в настоящем `ListView`, а не в
  `Repeater`.

### 7.2. Binding loop у ScrollView

`ScrollView` с `contentWidth: availableWidth` внутри `Representation` даёт
`Binding loop detected for property "implicitWidth"`: ширина панели считается от
контента, а контент — от ширины панели. Лечится явным `implicitWidth` у
`ScrollView`. **[замер]**

### 7.3. Recursive rearrange при копировании из ListSectionHeader

В оригинале у подписи стоит `Layout.maximumWidth: rowLayout.width`, и это законно
только потому, что строка лежит внутри `ItemDelegate` и получает ширину извне.
Если корнем своего компонента сделать сам `RowLayout` (элемент внешней
раскладки), получится `Qt Quick Layouts: Detected recursive rearrange`.
Правильно — `Layout.minimumWidth: 0` плюс `elide`. **[замер]**

### 7.4. Высота панели

```qml
Layout.minimumWidth:  Kirigami.Units.gridUnit * 18
Layout.minimumHeight: Kirigami.Units.gridUnit * 12
Layout.maximumWidth:  Kirigami.Units.gridUnit * 80
Layout.maximumHeight: Kirigami.Units.gridUnit * 40
Layout.preferredWidth: Kirigami.Units.gridUnit * 24
Layout.preferredHeight: Math.min(content.implicitHeight + отступы + footer.height,
                                 Kirigami.Units.gridUnit * 24)
```

Считать от содержимого, а не задавать жёстко: жёсткое значение оставляет пустоту
вне трея. Ограничение сверху не даёт стать выше соседей, переполнение уходит в
прокрутку. **В расчёт включать высоту `footer`**, иначе он отъедает область
содержимого и появляется лишняя полоса прокрутки. **[замер]**

---

## 8. Значки

- Только имена из темы (`folder-cloud`, `dialog-error`, `view-refresh`,
  `media-playback-pause`). Своих файлов в пакете не держать — тогда виджет
  следует теме и цветовой схеме.
- `Kirigami.Icon` для отображения, размеры из `Kirigami.Units.iconSizes`.
- Для панелей и трея предпочтительны symbolic-варианты (`go-previous-symbolic`),
  как в самом трее **[источник]**.
- Декоративным значкам ставить `Accessible.ignored: true` **[источник:
  ListSectionHeader, ExpandedRepresentation]**.

---

## 9. Диалог настроек

```
contents/config/main.xml       ключи и значения по умолчанию
contents/config/config.qml     ConfigModel + ConfigCategory
contents/ui/configGeneral.qml  Kirigami.FormLayout со свойствами cfg_<ключ>
```

Правила:

- **Имена `cfg_<ключ>` обязаны совпадать с `entry name` в `main.xml`.** При
  расхождении диалог открывается, но значения молча не сохраняются — ошибка
  ничем себя не проявляет. Проверять автоматически. **[замер]**
- `Kirigami.FormLayout`: подписи с двоеточием в левой колонке, группы через
  `Kirigami.FormData.isSection: true` с заголовком.
- **Единицы измерения — в подписи**, а не внутри `SpinBox` через
  `textFromValue`: дорисовка «с» и «ГБ» в поле ломает ввод с клавиатуры.
  `«Опрос от батареи, с:»` вместо `«180 с»` внутри поля. **[замер]**
- Пояснения — мелким шрифтом, привязанные к своей группе, с ограничением
  ширины (`Layout.maximumWidth: Kirigami.Units.gridUnit * 18`). **[соглашение]**
- Значения применять привязками (`Plasmoid.configuration.<ключ>`), тогда
  изменения действуют сразу, без перезапуска.

---

## 10. Уведомления

- Типы событий описываются в `contents/notifyrc/<componentName>.notifyrc`.
  **Имя файла обязано совпадать с `componentName`** объекта `Notification`,
  иначе KNotification молча ничего не покажет (в логе:
  `No event config could be found for event id …`). **[замер]**
- Домен для аплета: `plasma_applet_<pluginId>` **[источник:
  `Plasma::Applet::translationDomain()`]**.
- Файл обязан лежать в `<XDG data dir>/knotifications6/`. Пакет плазмоида писать
  туда при установке не может, поэтому файл везут внутри пакета и копируют при
  первом запуске.
- Благодаря `.notifyrc` события появляются в *Параметры системы → Уведомления*
  и отключаются поштучно. Своих настроек уведомлений в виджете не заводить.
- `Action=Popup` — показывать по умолчанию; **пустой `Action=`** — событие
  объявлено, но по умолчанию выключено (для информационных).
- Срабатывать **по фронту** состояния, иначе одна проблема сыпется каждый цикл
  опроса. Данные обычно приходят несколькими асинхронными вызовами, поэтому нужен
  дебаунс, а первый проход должен только запоминать состояние — при добавлении
  виджета не вываливать уведомления о том, что и так видно в панели.

---

## 11. Локализация

- Исходные строки в коде — **английские**. `i18n`, `i18nc` (с контекстом),
  `i18np` (множественное число).
- Каталоги: `<XDG data dir>/locale/<язык>/LC_MESSAGES/plasma_applet_<pluginId>.mo`
  — схема подтверждена 55 системными каталогами в
  `/usr/share/locale/ru/LC_MESSAGES/plasma_applet_*.mo` **[замер]**.
- **Сверять каталог с исходниками по паре (msgctxt, msgid)**, а не по одному
  msgid: контекст входит в ключ поиска, поэтому одинаковый текст с разными
  контекстами — разные записи, и расхождение контекста тихо ломает перевод.
  **[замер]**
- **Перевод нельзя проверить вне Plasma**: домен подключает оболочка при загрузке
  аплета, в отдельном процессе `qml6` строки остаются английскими
  (`kf.i18n: Domain is not set`). **[замер]**
- `msgfmt` может отсутствовать. Формат `.mo` простой, свой компилятор снимает
  зависимость от gettext.

---

## 12. Доступность и ввод

- Кнопкам без подписи (`display: IconOnly`) обязателен `ToolTip` с текстом
  действия **[источник: ExpandedRepresentation]**.
- Декоративным элементам — `Accessible.ignored: true`.
- Смысловым — `Accessible.description`, где текст кнопки не объясняет действие
  **[источник: devicenotifier, «Click to safely remove all devices»]**.
- В трее клавиатурную навигацию между шапкой и содержимым выстраивает трей
  (`KeyNavigation.up`, `.down`, `.backtab`) **[источник]**; внутри своего
  содержимого связи задавать самому.

---

## 13. Согласованность

- Одинаковое действие — **один компонент и одна подпись**. Две кнопки с разными
  названиями, делающие одно и то же, — дефект интерфейса.
- Отличать подписи можно только там, где отличается контекст: в общем
  контекстном меню виджета уместно «Открыть папку MEGA», а в строке списка —
  «Открыть в файловом менеджере», потому что в строке и так видно, о чём речь.
- Опасным операциям — предохранитель в UI, а не предупреждение в тексте: кнопка
  должна быть недоступна, когда операция небезопасна.

---

## 14. Как проверять, не обманывая себя

### Вывод QML не виден без переменной окружения

```sh
QT_FORCE_STDERR_LOGGING=1 qml6 файл.qml
```

Без неё лог **пуст даже при фатальных ошибках** — пустота выглядит как успех.
**[замер]**

### Стенд

```qml
// _harness.qml — временный, не в пакете
import QtQuick
import QtQuick.Window
import QtQuick.Layouts

Window {
    visible: true
    width:  Math.round(rep.Layout.preferredWidth)
    height: Math.round(rep.Layout.preferredHeight)

    Backend { id: be }
    FullRepresentation { id: rep; anchors.fill: parent; backend: be }

    Timer { interval: 15000; running: true; onTriggered: Qt.quit() }
}
```

- Модели наполнять данными, иначе делегаты не создаются и их ошибки не всплывут.
- Стенд должен сам вызывать `Qt.quit()`: `SIGTERM` от `timeout` теряет буферы
  вывода. **[замер]**
- Код выхода 2 и «Did not load any objects» — не загрузилось. Код 124 (таймаут)
  означает лишь, что объекты созданы и живут; **работоспособности он не
  доказывает**.
- Искать в логе: `Binding loop`, `recursive rearrange`, `TypeError`,
  `Cannot assign`, `is not a`.

### Чего стенд показать не может

- **Цвета и оформление.** Без темы оболочки компоненты Plasma рисуются
  дефолтными цветами: `ItemDelegate` выглядит голубым, кнопки — тёмной
  заливкой, что легко принять за обрезанный элемент. **[замер]**
- **Переводы** (см. §11).
- **Поведение в трее**: шапку, булавку, шестерёнку и единый размер даёт только
  настоящий трей.

`plasmawindowed <id>` запускает аплет в окне, но ошибки загрузки показывает в
GUI-диалоге, а не в stdout, и его код выхода ничего не доказывает. **[замер]**

### Геометрию мерить

Судить о раскладке по числам, а не по картинке:

```qml
console.warn("implicitH=" + Math.round(content.implicitHeight)
             + " h=" + Math.round(content.height));
for (var i = 0; i < content.children.length; ++i) {
    var c = content.children[i];
    if (c.visible)
        console.warn("  y=" + Math.round(c.y) + " h=" + Math.round(c.height)
                     + " implH=" + Math.round(c.implicitHeight));
}
```

### После правки QML

```sh
kquitapp6 plasmashell && kstart plasmashell
```

Plasma кэширует QML. Передобавлять виджет в панель не нужно: пока `Id` в
`metadata.json` не менялся, существующий экземпляр подхватит новые файлы.

---

## 15. Экономия батареи

Актуально для виджетов, опрашивающих внешний источник (у большинства нет
уведомлений об изменениях).

- **Адаптивный интервал:** часто — только когда панель раскрыта
  (`root.expanded`); свёрнут и от сети — реже; от батареи — совсем редко.
- **Разделять дорогие и дешёвые запросы:** тяжёлые вызывать раз в N циклов.
- **Очередь вместо параллельного запуска.** Наивная реализация поднимает по
  процессу на каждый запрос: замерено 5–8 одновременно против 1 при серийной
  очереди. Дедупликация одинаковых команд не даёт очереди расти, если она не
  поспевает за таймером. **[замер]**
- **Таймаут на команду.** При серийном исполнении одна зависшая команда
  блокирует весь виджет. Оговорка: `disconnectSource` не убивает процесс,
  зависшая команда остаётся сиротой.
- **Пауза.** Переключатель, полностью останавливающий таймер: ни процессов, ни
  пробуждений. Обновление тогда только по кнопке.
- Питание определять по `/sys/class/power_supply/A*/online` либо через UPower.

---

## 16. Чек-лист перед сдачей

Раскладка и вид:

- [ ] нет своего `header`, если виджет для трея
- [ ] боковые отступы — `largeSpacing`, не `gridUnit`
- [ ] в коде нет пиксельных констант и захардкоженных цветов
- [ ] у каждого `ListView` в `ColumnLayout` есть `implicitHeight: contentHeight`
- [ ] у списков с `highlight` стоит `currentIndex: -1`
- [ ] высота панели считается от содержимого, с учётом `footer`, с ограничением
      сверху `gridUnit * 24`
- [ ] в логе нет `Binding loop` и `recursive rearrange`

Функциональность:

- [ ] `Plasmoid.status` пассивен, когда сказать нечего
- [ ] опасные операции блокируются, а не предупреждают текстом
- [ ] одинаковые действия имеют одинаковые подписи
- [ ] кнопкам без подписи заданы подсказки

Инфраструктура:

- [ ] ключи `main.xml` совпадают с алиасами `cfg_*`
- [ ] исходные строки английские, каталог полон с учётом контекстов
- [ ] `.notifyrc` назван по `componentName`, события срабатывают по фронту
- [ ] проверено в **реальной оболочке**, а не только в стенде
- [ ] то, что не проверено, названо прямо

---

## Источники

Файлы plasma-workspace, на которые опирается этот документ:

| Файл | Что даёт |
|---|---|
| `applets/systemtray/qml/ExpandedRepresentation.qml` | устройство шапки трея, приоритеты действий, минимальные размеры попапа |
| `applets/systemtray/qml/PlasmoidPopupsContainer.qml` | склейка header и footer аплета с шапкой трея |
| `applets/devicenotifier/qml/FullRepresentation.qml` | эталонные метрики содержимого панели |
| `src/plasma/applet.cpp` (libplasma) | формула домена переводов |
| `org/kde/plasma/extras/ListSectionHeader.qml` | внутреннее устройство заголовка секции |
| `org/kde/plasma/extras/ExpandableListItem.qml` | API строки списка, зависимость от `ListView.view` |

Выкачивание:

```sh
# файл
curl -s "https://invent.kde.org/plasma/plasma-workspace/-/raw/master/applets/systemtray/qml/ExpandedRepresentation.qml"

# список файлов каталога
curl -s "https://invent.kde.org/api/v4/projects/plasma%2Fplasma-workspace/repository/tree?path=applets%2Fdevicenotifier%2Fqml&per_page=100"
```

Установленные компоненты лежат в
`/usr/lib/<арх>/qt6/qml/org/kde/plasma/extras/` и читаются напрямую — это самый
быстрый способ узнать настоящий API, документация отстаёт.
