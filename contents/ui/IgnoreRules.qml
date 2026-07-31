/*
 * Редактор набора правил исключения.
 *
 * Работает с рабочей копией списка фильтров и ничего не применяет сам: набор
 * забирает вызывающая страница и ставит в очередь до нажатия Apply/OK. Так
 * страница «Папки» ведёт себя как остальные диалоги KDE.
 *
 * Модель показа: галочки — это вид на набор. Галочка отмечена тогда и только
 * тогда, когда в наборе есть все строки её группы; снятие удаляет ровно их.
 * Всё, что ни в одну группу не попало, показывается ниже дословно, включая
 * строки, которые виджет не разобрал, — их он не трогает никогда.
 *
 * Замерено на MEGAcmd 2.5.2:
 *  - добавление правила НЕ удаляет уже загруженное: копии остаются в облаке и
 *    перестают обновляться;
 *  - снятие правила приводит к конфликту локальной и облачной копий, и
 *    разрешить его из CLI нельзя — поэтому предупреждение висит на снятии;
 *  - фильтр обязан содержать двоеточие: у стоковых правил это «:~*», где цель
 *    и тип опущены.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: view

    property var backend
    property var profiles                // RuleProfiles
    property var filters: []             // рабочая копия набора
    property string localRoot: ""        // для «Проверить»; у профиля пусто
    property string title: ""

    // В облаке уже лежат файлы этой синхронизации: тогда снятие правила может
    // привести к столкновению копий. У новой папки и у профиля — нет.
    property bool cloudHasFiles: false

    signal closeRequested()
    signal saveProfileRequested(string name, var filters)

    spacing: Kirigami.Units.smallSpacing

    readonly property var presets: [
        {
            label: i18n("Python virtual environments"),
            hint: "venv, .venv, myenv",
            filters: ["-dn:venv", "-dn:.venv", "-dn:myenv"]
        },
        {
            label: i18n("Node.js modules"),
            hint: "node_modules",
            filters: ["-dn:node_modules"]
        },
        {
            label: i18n("Caches and IDE indexes"),
            hint: "__pycache__, .mypy_cache, .pytest_cache, .ruff_cache, .tox, .direnv, .cache, .idea, *.pyc",
            filters: ["-dn:__pycache__", "-dn:.mypy_cache", "-dn:.pytest_cache",
                      "-dn:.ruff_cache", "-dn:.tox", "-dn:.direnv", "-dn:.cache",
                      "-dn:.idea", "-fn:*.pyc"]
        },
        {
            label: i18n("Build artifacts"),
            hint: "dist, build, target",
            filters: ["-dn:dist", "-dn:build", "-dn:target"]
        },
        {
            label: i18n("Symbolic links"),
            hint: i18n("MEGA cannot sync them and reports each one as an issue"),
            filters: ["-sn:*"]
        },
        {
            // Набор самой MEGA держим отдельной группой не ради удобства
            // выключения, а чтобы семь строк вида «-:~*» не забивали собой
            // список своих правил: понять их без справки невозможно.
            label: i18n("Temporary and system files"),
            hint: i18n("MEGA's own defaults: editor backups (~*), unfinished downloads, *.tmp, Thumbs.db, desktop.ini"),
            filters: ["-:~*", "-:*~.*", "-:*.crdownload",
                      "-:*.sb-????????-??????", "-:*.tmp",
                      "-:Thumbs.db", "-:desktop.ini"]
        }
    ]

    readonly property string dotFilter: "-:.*"

    readonly property var knownFilters: {
        var all = [dotFilter];
        var p = presets || [];
        for (var i = 0; i < p.length; ++i)
            all = all.concat(p[i].filters);
        return all;
    }

    readonly property var customRules: (filters || []).filter(function (r) {
        return view.knownFilters.indexOf(r) === -1;
    })

    function hasAll(group) {
        for (var i = 0; i < group.length; ++i)
            if ((filters || []).indexOf(group[i]) === -1)
                return false;
        return true;
    }

    function addFilters(group) {
        var out = (filters || []).slice();
        for (var i = 0; i < group.length; ++i)
            if (out.indexOf(group[i]) === -1)
                out.push(group[i]);
        filters = out;
    }

    function removeFilters(group) {
        filters = (filters || []).filter(function (f) {
            return group.indexOf(f) === -1;
        });
        if (cloudHasFiles)
            removalWarning.visible = true;
    }

    function applyGroup(group, on) {
        if (on)
            addFilters(group);
        else
            removeFilters(group);
    }

    /*
     * Человеческое описание правила: запись
     * <CLASS><TARGET><TYPE><STRATEGY>:<PATTERN> компактна, но нечитаема — по
     * строке «-dn:venv» без справки не понять ничего. Неразобранное описываем
     * пустой строкой: тогда показывается только исходная запись, и виджет
     * ничего не выдумывает про правило, которого не понял.
     */
    function describe(filter) {
        var m = String(filter).match(/^([-+])([dfsa]?)([NnpP]?)([GgRr]?):(.*)$/);
        if (!m)
            return "";

        var action = m[1] === "+" ? i18n("Include") : i18n("Exclude");

        var what;
        switch (m[2] || "a") {
        case "d": what = i18n("directories"); break;
        case "f": what = i18n("files"); break;
        case "s": what = i18n("symbolic links"); break;
        default:  what = i18n("everything"); break;
        }

        var pattern = m[5];
        var isGlob = /[*?\[]/.test(pattern);
        var where;
        if (m[3] === "p" || m[3] === "P")
            where = i18n("at the path %1", pattern);
        else if (pattern === "*")
            where = i18n("anywhere in the folder");
        else if (m[3] === "N")
            where = isGlob ? i18n("matching %1, in the folder root only", pattern)
                           : i18n("named %1, in the folder root only", pattern);
        else
            where = isGlob ? i18n("matching %1, anywhere in the folder", pattern)
                           : i18n("named %1, anywhere in the folder", pattern);

        var text = i18nc("@info rule description: action, object, place",
                         "%1 %2 %3", action, what, where);
        if (m[4] === "R" || m[4] === "r")
            text += " " + i18n("(regular expression)");
        return text;
    }

    // ---- шапка ----
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.ToolButton {
            icon.name: "go-previous"
            text: i18n("Back")
            display: QQC2.AbstractButton.IconOnly
            onClicked: view.closeRequested()
        }

        QQC2.Label {
            Layout.fillWidth: true
            elide: Text.ElideMiddle
            text: view.title
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label { text: i18n("Profile:") }

        QQC2.ComboBox {
            id: profileBox
            Layout.fillWidth: true
            textRole: "name"
            model: view.profiles ? view.profiles.all : []

            // Показываем, какому профилю соответствует набор прямо сейчас.
            // Не совпал ни с одним — «Свой набор», и выбор ничего не менял бы.
            readonly property var detected: view.profiles
                                            ? view.profiles.detect(view.filters || [])
                                            : null

            displayText: detected ? detected.name : i18n("Custom set")

            onActivated: function (index) {
                var p = model[index];
                if (p)
                    view.filters = p.filters.slice();
            }
        }

        QQC2.Button {
            text: i18n("Save as profile…")
            icon.name: "document-save-as"
            onClicked: saveDialog.open()
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        text: profileBox.detected ? profileBox.detected.hint
                                  : i18n("The rules below do not match any profile.")
    }

    Kirigami.InlineMessage {
        id: removalWarning
        Layout.fillWidth: true
        visible: false
        type: Kirigami.MessageType.Warning
        text: i18n("Files that were excluded earlier are still in the cloud. Bringing them back into the synchronisation makes the local and cloud copies collide, and MEGAcmd cannot resolve such conflicts — delete the cloud copies first.")
    }

    QQC2.Dialog {
        id: saveDialog
        title: i18n("Save profile")
        modal: true
        anchors.centerIn: parent
        standardButtons: QQC2.Dialog.Save | QQC2.Dialog.Cancel
        onAccepted: {
            if (profileName.text.length > 0)
                view.saveProfileRequested(profileName.text, (view.filters || []).slice());
        }

        contentItem: ColumnLayout {
            QQC2.Label { text: i18n("Profile name:") }
            QQC2.TextField {
                id: profileName
                Layout.fillWidth: true
                placeholderText: i18n("e.g. My repositories")
            }
        }
    }

    QQC2.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        ColumnLayout {
            width: view.width - Kirigami.Units.gridUnit
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label { text: i18n("Do not synchronise:") }

            Repeater {
                model: view.presets

                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 0

                    QQC2.CheckBox {
                        text: modelData.label
                        checked: view.hasAll(modelData.filters)
                        onToggled: view.applyGroup(modelData.filters, checked)
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.gridUnit * 2
                        wrapMode: Text.WordWrap
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                        text: modelData.hint
                    }
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            QQC2.CheckBox {
                text: i18n("Synchronise hidden files (.git, .env, .claude)")
                checked: !view.hasAll([view.dotFilter])
                onToggled: view.applyGroup([view.dotFilter], !checked)
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit * 2
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                text: i18n("MEGAcmd excludes everything starting with a dot by default. For a folder with code that drops repository history, keys and editor settings.")
            }

            Kirigami.Separator { Layout.fillWidth: true }

            QQC2.Label { text: i18n("Own rules:") }

            Repeater {
                model: view.customRules

                delegate: RowLayout {
                    required property string modelData
                    Layout.fillWidth: true

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        QQC2.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            visible: text.length > 0
                            text: view.describe(modelData)
                        }

                        QQC2.Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.family: "monospace"
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            opacity: 0.7
                            text: modelData
                        }
                    }

                    QQC2.ToolButton {
                        icon.name: "edit-delete"
                        display: QQC2.AbstractButton.IconOnly
                        text: i18n("Remove")
                        onClicked: view.removeFilters([modelData])
                    }
                }
            }

            /*
             * Пустой список здесь — обычное состояние, а не потеря: правила,
             * попавшие под галочки, тут не повторяются. Без этой подписи
             * пустота читается как «мои правила исчезли».
             */
            QQC2.Label {
                Layout.fillWidth: true
                visible: view.customRules.length === 0
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                text: {
                    var total = (view.filters || []).length;
                    return total > 0
                        ? i18np("Nothing here yet: the single rule of this folder is covered by the checkboxes above.",
                                "Nothing here yet: all %1 rules of this folder are covered by the checkboxes above.",
                                total)
                        : i18n("No rules yet.");
                }
            }

            RowLayout {
                Layout.fillWidth: true

                QQC2.TextField {
                    id: customField
                    Layout.fillWidth: true
                    placeholderText: i18n("e.g. -dn:node_modules or -p:benchmark")
                }

                QQC2.Button {
                    text: i18n("Check")
                    enabled: customField.text.length > 0 && view.localRoot.length > 0
                    onClicked: view.backend.checkRule(view.localRoot, customField.text)
                }

                QQC2.Button {
                    icon.name: "list-add"
                    text: i18n("Add")
                    enabled: customField.text.length > 0
                             && view.describe(customField.text).length > 0
                    onClicked: {
                        view.addFilters([customField.text]);
                        customField.text = "";
                        if (view.backend)
                            view.backend.ruleCheckText = "";
                    }
                }
            }

            // Расшифровка того, что набирается, — до нажатия «Добавить».
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: customField.text.length > 0
                text: {
                    var d = view.describe(customField.text);
                    return d.length > 0 ? d
                                        : i18n("The filter format is not recognised.");
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: view.backend && view.backend.ruleCheckText.length > 0
                font: Kirigami.Theme.smallFont
                text: view.backend ? view.backend.ruleCheckText : ""
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                text: i18n("Format: <class><target><type><strategy>:<pattern> — for example -dn:venv excludes directories named venv anywhere in the tree. The colon is required: the plain form is :pattern. Only the rules in the synchronisation root are shown; MEGAcmd does not see .megaignore files in subfolders.")
            }
        }
    }
}
