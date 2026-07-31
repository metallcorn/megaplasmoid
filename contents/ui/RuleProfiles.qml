/*
 * Профили правил исключения: именованные наборы фильтров .megaignore.
 *
 * Встроенные заданы здесь, свои хранятся в настройках виджета ключом
 * ruleProfiles (JSON) — это конфигурация виджета, а не состояние сервера,
 * поэтому им место именно там.
 *
 * Профиль применяется до создания синхронизации: MEGAcmd копирует набор
 * DEFAULT в новую синхронизацию в момент её создания (замерено), поэтому
 * достаточно записать выбранный профиль в DEFAULT и следом создать папку —
 * она родится уже с правилами, и мусор не успеет уехать.
 */
import QtQuick

QtObject {
    id: profiles

    // JSON из настроек виджета; пустая строка допустима.
    property string customJson: "[]"

    // Стоковый набор MEGAcmd. Его же ставит сам сервер новым синхронизациям.
    readonly property var megaDefaults: [
        "-:~*", "-:*~.*", "-:*.crdownload", "-:*.sb-????????-??????",
        "-:*.tmp", "-:Thumbs.db", "-:desktop.ini", "-:.*"
    ]

    // Мусор среды разработки. Отличие от стокового набора принципиальное:
    // здесь нет «-:.*», то есть .git, .env и .claude синхронизируются — ради
    // них каталог с кодом обычно и синхронизируют.
    readonly property var developer: [
        "-:~*", "-:*~.*", "-:*.crdownload", "-:*.sb-????????-??????",
        "-:*.tmp", "-:Thumbs.db", "-:desktop.ini",
        "-dn:venv", "-dn:.venv", "-dn:myenv",
        "-dn:node_modules",
        "-dn:__pycache__", "-dn:.mypy_cache", "-dn:.pytest_cache",
        "-dn:.ruff_cache", "-dn:.tox", "-dn:.direnv", "-dn:.cache",
        "-dn:.idea", "-fn:*.pyc",
        "-sn:*"
    ]

    // Временные файлы офисных пакетов: LibreOffice кладёт .~lock.*#, Word —
    // ~$имя. Они живут ровно пока открыт документ, и синхронизировать их
    // бессмысленно.
    readonly property var documents: [
        "-:~*", "-:*~.*", "-:*.crdownload", "-:*.sb-????????-??????",
        "-:*.tmp", "-:Thumbs.db", "-:desktop.ini",
        "-fn:.~lock.*", "-fn:~$*", "-sn:*"
    ]

    // Миниатюры и кэши просмотрщиков. Сами снимки, включая RAW и сайдкары
    // XMP, синхронизируются: они и есть содержимое такой папки.
    readonly property var media: [
        "-:~*", "-:*~.*", "-:*.crdownload", "-:*.sb-????????-??????",
        "-:*.tmp", "-:Thumbs.db", "-:desktop.ini",
        "-dn:.thumbnails", "-dn:.cache", "-dn:@eaDir", "-sn:*"
    ]

    // Символьные ссылки исключены во всех профилях, кроме «без правил»: MEGA
    // их не синхронизирует в принципе, а на каждую заводит проблему.
    readonly property var none: []

    readonly property var builtin: [
        { key: "mega",      name: i18n("MEGA defaults"),
          hint: i18n("What MEGAcmd sets up by itself. Hidden files, including .git and .env, are not synchronised."),
          filters: megaDefaults },
        { key: "developer", name: i18n("Development"),
          hint: i18n("Without virtual environments, modules, caches and symlinks. Repository history and keys are synchronised."),
          filters: developer },
        { key: "documents", name: i18n("Documents"),
          hint: i18n("Without office lock and temporary files."),
          filters: documents },
        { key: "media",     name: i18n("Photos and video"),
          hint: i18n("Without thumbnails and viewer caches."),
          filters: media },
        { key: "none",      name: i18n("No rules"),
          hint: i18n("Synchronise everything, including build artifacts and caches."),
          filters: none }
    ]

    readonly property var custom: {
        try {
            var parsed = JSON.parse(customJson && customJson.length > 0 ? customJson : "[]");
            if (!Array.isArray(parsed))
                return [];
            return parsed.filter(function (p) {
                return p && typeof p.name === "string" && Array.isArray(p.filters);
            }).map(function (p) {
                return { key: "custom:" + p.name, name: p.name,
                         hint: i18n("Your own profile"), filters: p.filters };
            });
        } catch (e) {
            // Битый JSON не должен ронять страницу настроек: своих профилей
            // просто не будет, встроенные останутся на месте.
            return [];
        }
    }

    readonly property var all: (builtin || []).concat(custom || [])

    function byKey(key) {
        var list = all || [];
        for (var i = 0; i < list.length; ++i)
            if (list[i].key === key)
                return list[i];
        return null;
    }

    // Совпадает ли набор правил с профилем. Порядок не важен: MEGAcmd хранит
    // фильтры отсортированными, а пришли они могли в любом.
    function matches(rules, profile) {
        var r = rules || [];
        if (!profile || !profile.filters || r.length !== profile.filters.length)
            return false;
        for (var i = 0; i < profile.filters.length; ++i)
            if (r.indexOf(profile.filters[i]) === -1)
                return false;
        return true;
    }

    // Какому профилю соответствует текущий набор; null — свой, ничей.
    function detect(rules) {
        var list = all || [];
        for (var i = 0; i < list.length; ++i)
            if (matches(rules, list[i]))
                return list[i];
        return null;
    }

    // Возвращает JSON со своими профилями, куда добавлен (или заменён) один.
    function withSaved(name, filters) {
        var list = [];
        try {
            var parsed = JSON.parse(customJson && customJson.length > 0 ? customJson : "[]");
            if (Array.isArray(parsed))
                list = parsed;
        } catch (e) {
            list = [];
        }
        var out = list.filter(function (p) { return !p || p.name !== name; });
        out.push({ name: name, filters: filters });
        return JSON.stringify(out);
    }

    function withoutSaved(name) {
        var list = [];
        try {
            var parsed = JSON.parse(customJson && customJson.length > 0 ? customJson : "[]");
            if (Array.isArray(parsed))
                list = parsed;
        } catch (e) {
            list = [];
        }
        return JSON.stringify(list.filter(function (p) { return !p || p.name !== name; }));
    }
}
