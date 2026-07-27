/*
 * Единственная точка, которая знает про MEGAcmd и про запуск процессов.
 * Всё остальное в виджете работает только со свойствами и сигналами этого
 * объекта. Если Plasma когда-нибудь выпилит Plasma5Support — переписывать надо
 * только здесь.
 *
 * ВАЖНО о том, почему результаты разбираются через теги, а не через колбэки.
 *
 * Первая версия хранила колбэк каждой команды в объекте внутри property var:
 *
 *     callbacks[cmd] = cb;        // добавление ключа
 *     delete callbacks[cmd];      // удаление ключа
 *
 * Это валило plasmashell с SIGSEGV в QV4::Object::insertMember (три дампа с
 * одинаковой подписью). Долгоживущий JS-объект внутри property var, у которого
 * ключи постоянно появляются и исчезают, да ещё и хранящий функции, портит
 * кучу JS-движка. Проявлялось «иногда»: при закрытии попапа и после разблокировки
 * экрана, то есть когда состояние менялось одновременно с приходом результатов.
 *
 * Поэтому здесь:
 *   - функции не хранятся вообще;
 *   - долгоживущих объектов с динамическими ключами нет;
 *   - в очереди лежат свежие объекты фиксированной формы {cmd, tag, timeout};
 *   - результат разбирается по тегу в handleResult(), а наружу уходит сигналом.
 */
import QtQuick
import org.kde.plasma.plasma5support as P5Support

Item {
    id: backend

    // ---- наблюдаемое состояние ----
    property bool cmdMissing: false      // mega-exec не найден
    property bool serverDown: false      // бинарь есть, но сервер не отвечает
    property bool loggedIn: false
    property string lastErrorText: ""    // диагностика от шелла или MEGAcmd

    property string accountEmail: ""
    property int proLevel: -1
    property string proExpires: ""

    property real usedBytes: 0
    property real totalBytes: 0
    readonly property real usedRatio: totalBytes > 0 ? usedBytes / totalBytes : 0

    property var syncs: []        // {id, localPath, remotePath, runState, status, error}
    property var mounts: []       // {name, localPath, remotePath, persistent, enabled}
    property var transfers: []    // {direction, tag, source, dest, progress, state}
    property int issueCount: 0

    property real cacheBytes: -1  // -1 = ещё не считали
    property bool onBattery: false
    property bool busyClearing: false
    property string homeDir: ""
    property string runtimeFilesState: ""

    /*
     * Каталог с mega-exec, если его нет в PATH оболочки.
     *
     * plasmashell не читает ~/.bashrc, поэтому PATH у него беднее, чем в
     * терминале. Если MEGAcmd поставлен без root (типичный случай на Steam
     * Deck, где корень только для чтения), команда работает в терминале и не
     * находится из виджета. Ниже к PATH добавляются обычные места установки,
     * а это свойство позволяет указать своё.
     */
    property string extraPath: ""
    property string shellPath: ""      // фактический PATH, для диагностики

    signal cacheCleared(bool ok, string message)
    signal operationDone(bool ok, string message)
    signal remoteDirsReady(string path, var dirs)

    // ---- запуск процессов ----
    /*
     * Команды выполняются строго по одной. Раньше цикл опроса выпускал их
     * параллельно, и на каждый тик поднималось 5–8 процессов сразу — заметный
     * всплеск для ноутбука и лишние подключения к mega-cmd-server.
     *
     * Дедупликация по тегу заодно работает тормозом: если очередь не поспевает
     * за таймером, повторная постановка той же операции игнорируется.
     */
    P5Support.DataSource {
        id: exe
        engine: "executable"
        connectedSources: []

        // Очередь свежих объектов {cmd, tag, timeout} и текущая операция.
        // Долгоживущих словарей здесь нет намеренно, см. шапку файла.
        property var queue: []
        property var current: null
        property string stalled: ""     // тег последней команды, снятой по таймауту

        onNewData: function (source, data) {
            if (!current || source !== current.cmd) {
                // Чужой источник, например остаток после срабатывания сторожа.
                disconnectSource(source);
                return;
            }
            /*
             * Движок executable умеет прислать неполный кадр сразу при
             * подключении — без поля "exit code". Такой кадр надо пропустить и
             * дождаться настоящего результата, иначе получим пустой вывод и код
             * NaN, то есть ложный отрицательный ответ. Виджет это переживал за
             * счёт следующего цикла опроса, а страница настроек работает с
             * paused и запрос не повторяет — она оставалась с неверным
             * вердиктом навсегда.
             */
            if (!data || data["exit code"] === undefined)
                return;

            var tag = current.tag;
            watchdog.stop();
            disconnectSource(source);
            current = null;

            backend.handleResult(tag,
                                 String(data["stdout"] || ""),
                                 Number(data["exit code"]),
                                 String(data["stderr"] || ""));
            pump();
        }

        function pending(tag) {
            if (current && current.tag === tag)
                return true;
            for (var i = 0; i < queue.length; ++i)
                if (queue[i].tag === tag)
                    return true;
            return false;
        }

        function run(cmd, tag, timeoutMs) {
            if (pending(tag))
                return;
            var q = queue;
            q.push({ "cmd": cmd, "tag": tag,
                     "timeout": timeoutMs > 0 ? timeoutMs : 15000 });
            queue = q;
            pump();
        }

        function pump() {
            if (current || queue.length === 0)
                return;
            var q = queue;
            var next = q.shift();
            queue = q;
            current = next;
            watchdog.interval = next.timeout;
            watchdog.restart();
            connectSource(next.cmd);
        }
    }

    /*
     * Сторож: при серийном исполнении одна зависшая команда заблокировала бы
     * весь виджет. По истечении таймаута бросаем её и идём дальше — результат
     * не разбирается, состояние просто не обновится до следующего цикла.
     * Объявлен снаружи DataSource: у того нет default property, дочерние
     * элементы внутрь не принимаются.
     */
    Timer {
        id: watchdog
        repeat: false
        onTriggered: {
            if (!exe.current)
                return;
            var stuck = exe.current;
            exe.disconnectSource(stuck.cmd);
            exe.current = null;
            exe.stalled = stuck.tag;
            exe.pump();
        }
    }

    // Диагностика.
    readonly property string stalled: exe.stalled
    readonly property int queueLength: exe.queue.length

    /*
     * Экранирование для шелла: значение оборачивается в одинарные кавычки,
     * внутренние кавычки закрываются по схеме '\''. Двойные кавычки здесь
     * непригодны — внутри них шелл раскрывает $ и `...`, то есть имя файла
     * вида a$b.txt превратилось бы в другое.
     */
    function quote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    /*
     * Обёртка: всё, что содержит пайпы и globы, обязано идти через sh -c.
     * ВАЖНО: команда собирается через quote(), а не через JSON.stringify.
     * Проверено экспериментально: при двойных кавычках вокруг скрипта аргументы
     * теряются молча — команда выполняется, код возврата 0, переменные пустые.
     */
    /*
     * К PATH добавляются каталоги, куда MEGAcmd попадает при установке без
     * root. Порядок важен: сначала указанный пользователем, потом обычные
     * места, и только затем системный PATH — свежая ручная установка должна
     * побеждать старую пакетную.
     */
    function pathPrefix() {
        var dirs = [];
        if (extraPath.length > 0)
            dirs.push(expandTilde(extraPath));
        dirs.push("$HOME/.local/bin", "$HOME/bin", "$HOME/megacmd",
                  "$HOME/Applications/megacmd", "/usr/local/bin");
        return 'PATH="' + dirs.join(":") + ':$PATH"; ';
    }

    function sh(script, tag, timeoutMs) {
        exe.run("sh -c " + quote(pathPrefix() + script), tag, timeoutMs);
    }

    // Домашний каталог нужен, чтобы раскрывать «~» в путях, введённых руками.
    // Через шелл его не раскрыть: quote() ставит одинарные кавычки, внутри
    // которых $HOME остаётся текстом — и это правильно, иначе имя файла с $
    // подставилось бы как переменная.
    function expandTilde(p) {
        var s = String(p);
        if (homeDir.length > 0 && (s === "~" || s.indexOf("~/") === 0))
            return homeDir + s.substring(1);
        return s;
    }

    // ---- разбор вывода ----

    // Таблицы с --col-separator: sync, transfers, sync-issues.
    // Разбираем по именам колонок из заголовка, а не по позициям, чтобы
    // смена версии MEGAcmd (новая колонка, другой порядок) нас не сломала.
    function parseSeparated(text, sep) {
        var lines = String(text).split("\n").filter(function (l) {
            return l.trim().length > 0 && l.indexOf(sep) !== -1;
        });
        if (lines.length < 2)
            return [];
        var header = lines[0].split(sep).map(function (h) {
            return h.trim();
        });
        var rows = [];
        for (var i = 1; i < lines.length; ++i) {
            var cells = lines[i].split(sep);
            var row = {};
            for (var j = 0; j < header.length; ++j)
                row[header[j]] = (cells[j] || "").trim();
            rows.push(row);
        }
        return rows;
    }

    // Таблицы без разделителя (fuse-show): колонки выровнены пробелами.
    // Берём смещения из заголовка и режем строки по ним — это переживает
    // и пробелы внутри путей, и изменение ширины колонок.
    function parseFixedWidth(text, columns) {
        var lines = String(text).split("\n").filter(function (l) {
            return l.trim().length > 0;
        });
        if (lines.length < 2)
            return [];
        var header = lines[0];
        var offsets = [];
        for (var c = 0; c < columns.length; ++c) {
            var at = header.indexOf(columns[c]);
            if (at < 0)
                return [];               // заголовок не тот, что ждём — лучше пусто, чем мусор
            offsets.push(at);
        }
        var rows = [];
        for (var i = 1; i < lines.length; ++i) {
            var line = lines[i];
            if (line.indexOf("Use \"") === 0)
                continue;                // подсказка в конце вывода fuse-show
            var row = {};
            for (var k = 0; k < columns.length; ++k) {
                var from = offsets[k];
                var to = (k + 1 < columns.length) ? offsets[k + 1] : line.length;
                row[columns[k]] = line.substring(from, to).trim();
            }
            rows.push(row);
        }
        return rows;
    }

    function looksNotLoggedIn(text) {
        return String(text).indexOf("Not logged in") !== -1;
    }

    function looksLikeError(text, code) {
        return code !== 0 || String(text).indexOf("ERR") !== -1;
    }

    // ---- разбор результатов по тегу ----

    function handleResult(tag, out, code, err) {
        // Отсутствие команды видно по коду 127 от шелла. Отдельная проверка
        // `command -v` не нужна: проверка и рабочий вызов не могут разойтись,
        // если решает один и тот же результат.
        if (code === 127) {
            cmdMissing = true;
            lastErrorText = String(err).trim();
            return;
        }
        if (tag.indexOf("mega") === 0 || tag === "quota")
            cmdMissing = false;

        if (tag === "quota") {
            if (code !== 0) {
                serverDown = true;
                lastErrorText = String(err).trim() || String(out).trim();
                return;
            }
            serverDown = false;
            lastErrorText = "";
            if (looksNotLoggedIn(out)) {
                loggedIn = false;
                return;
            }
            loggedIn = true;
            var q = out.match(/USED STORAGE:\s+(\d+)\s+[\d.,]+%\s+of\s+(\d+)/);
            if (q) {
                usedBytes = parseFloat(q[1]);
                totalBytes = parseFloat(q[2]);
            }
            return;
        }

        if (tag === "account") {
            if (code !== 0)
                return;
            var e = out.match(/Account e-mail:\s*(\S+)/);
            if (e)
                accountEmail = e[1];
            var p = out.match(/Pro level:\s*(\d+)/);
            proLevel = p ? parseInt(p[1]) : -1;
            var d = out.match(/Pro expiration date:\s*(.+)/);
            proExpires = d ? d[1].trim() : "";
            return;
        }

        if (tag === "syncs") {
            if (code !== 0)
                return;
            syncs = parseSeparated(out, "|").map(function (r) {
                return {
                    id: r["ID"] || "",
                    localPath: r["LOCALPATH"] || "",
                    remotePath: r["REMOTEPATH"] || "",
                    runState: r["RUN_STATE"] || "",
                    status: r["STATUS"] || "",
                    error: r["ERROR"] || "NO"
                };
            });
            return;
        }

        if (tag === "mounts") {
            if (code !== 0)
                return;
            mounts = parseFixedWidth(out, ["NAME", "LOCAL_PATH", "REMOTE_PATH",
                                           "PERSISTENT", "ENABLED"]).map(function (r) {
                return {
                    name: r["NAME"] || "",
                    localPath: r["LOCAL_PATH"] || "",
                    remotePath: r["REMOTE_PATH"] || "",
                    persistent: (r["PERSISTENT"] || "") === "YES",
                    enabled: (r["ENABLED"] || "") === "YES"
                };
            });
            return;
        }

        if (tag === "transfers") {
            if (code !== 0)
                return;
            transfers = parseSeparated(out, "|").map(function (r) {
                return {
                    direction: r["TYPE"] || "",
                    tag: r["TAG"] || "",
                    source: r["SOURCEPATH"] || "",
                    dest: r["DESTINYPATH"] || "",
                    progress: r["PROGRESS"] || "",
                    state: r["STATE"] || ""
                };
            });
            return;
        }

        if (tag === "issues") {
            if (code !== 0)
                return;
            if (out.indexOf("no sync issues") !== -1) {
                issueCount = 0;
                return;
            }
            var rows = parseSeparated(out, "|").length;
            issueCount = rows > 0 ? rows
                       : Math.max(0, String(out).split("\n").filter(function (l) {
                             return l.trim().length > 0;
                         }).length - 1);
            return;
        }

        if (tag === "cache") {
            var n = parseFloat(String(out).trim());
            cacheBytes = isNaN(n) ? -1 : n;
            return;
        }

        if (tag === "power") {
            var v = String(out).trim();
            if (v.length > 0)
                onBattery = (v === "0");
            return;
        }

        if (tag === "path") {
            shellPath = String(out).trim();
            return;
        }

        if (tag === "home") {
            homeDir = String(out).trim();
            return;
        }

        if (tag === "runtime") {
            runtimeFilesState = String(out).trim();
            return;
        }

        if (tag === "clear") {
            busyClearing = false;
            var ok = (code === 0 && String(out).indexOf("OK") !== -1);
            cacheCleared(ok, ok ? "" : (String(err).trim()
                                        || i18n("Could not clear the cache")));
            refreshCache();
            refreshMounts();
            refreshSyncs();
            return;
        }

        if (tag.indexOf("op:") === 0) {
            var text = String(out).trim();
            var good = !looksLikeError(text, code);
            operationDone(good, good ? "" : text);
            refreshSyncs();
            refreshMounts();
            return;
        }

        if (tag.indexOf("ls:") === 0) {
            var path = tag.substring(3);
            if (code !== 0) {
                remoteDirsReady(path, []);
                return;
            }
            // Тип узла — первый символ колонки FLAGS: d означает папку.
            // Разбор по образцу даты, а не по номерам полей: в именах бывают
            // пробелы, а у подпути перед таблицей печатается лишняя строка.
            var re = /^(\S+)\s+\S+\s+\S+\s+\d{1,2}\w{3}\d{4}\s+\d{2}:\d{2}:\d{2}\s+(.+)$/;
            var dirs = [];
            var lines = String(out).split("\n");
            for (var i = 0; i < lines.length; ++i) {
                var m = lines[i].replace(/\s+$/, "").match(re);
                if (m && m[1].charAt(0) === "d")
                    dirs.push(m[2]);
            }
            remoteDirsReady(path, dirs);
            return;
        }
    }

    // ---- опросы ----

    // df дешевле, чем whoami -l: не ходит за историей платежей и сессиями.
    function refreshQuota()     { sh("mega-exec df", "quota"); }
    function refreshAccount()   { sh("mega-exec whoami -l", "account", 30000); }

    function refreshSyncs() {
        sh("mega-exec sync --col-separator='|' --path-display-size=4096 "
           + "--output-cols=ID,LOCALPATH,REMOTEPATH,RUN_STATE,STATUS,ERROR", "syncs");
    }

    // fuse-show не понимает --col-separator (в его справке флаг указан, но на
    // деле отвергается), поэтому режем по ширине колонок.
    function refreshMounts() {
        sh("mega-exec fuse-show --disable-path-collapse", "mounts");
    }

    function refreshTransfers() {
        sh("mega-exec transfers --col-separator='|' --path-display-size=4096", "transfers");
    }

    function refreshIssues()    { sh("mega-exec sync-issues --limit=0", "issues"); }

    // Обход каталога — не самая дешёвая операция, зовём редко.
    function refreshCache() {
        sh('du -sb "$HOME/.megaCmd/fuse-cache" 2>/dev/null | cut -f1', "cache", 60000);
    }

    function refreshPower() {
        sh("cat /sys/class/power_supply/A*/online 2>/dev/null | head -1", "power");
    }

    function fetchHomeDir() {
        if (homeDir.length === 0)
            sh('printf %s "$HOME"', "home");
        sh('printf %s "$PATH"', "path");
    }

    // ---- управление синхронизациями и маунтами ----

    property int opSeq: 0

    // Тег операции уникален: иначе дедупликация проглотила бы вторую операцию,
    // отданную сразу после первой.
    function nextOpTag() {
        opSeq = opSeq + 1;
        return "op:" + opSeq;
    }

    function addSync(localPath, remotePath) {
        sh("mega-exec sync " + quote(expandTilde(localPath)) + " "
           + quote(remotePath) + " 2>&1", nextOpTag(), 60000);
    }

    function removeSync(id) {
        sh("mega-exec sync --delete " + quote(id) + " 2>&1", nextOpTag(), 60000);
    }

    // По умолчанию маунт writable и persistent (переживает перезапуск) — так же,
    // как у самой команды fuse-add.
    function addMount(localPath, remotePath, name, readOnly) {
        var cmd = "mega-exec fuse-add";
        if (name && name.length > 0)
            cmd += " --name=" + quote(name);
        if (readOnly)
            cmd += " --read-only";
        cmd += " " + quote(expandTilde(localPath)) + " " + quote(remotePath) + " 2>&1";
        sh(cmd, nextOpTag(), 60000);
    }

    function removeMount(nameOrPath) {
        sh("mega-exec fuse-remove " + quote(nameOrPath) + " 2>&1", nextOpTag(), 60000);
    }

    function setMountEnabled(name, on) {
        sh("mega-exec " + (on ? "fuse-enable" : "fuse-disable") + " "
           + quote(name) + " 2>&1", nextOpTag(), 60000);
    }

    function pauseSync(id)  { sh("mega-exec sync --pause " + quote(id) + " 2>&1", nextOpTag(), 60000); }
    function resumeSync(id) { sh("mega-exec sync --enable " + quote(id) + " 2>&1", nextOpTag(), 60000); }

    /*
     * Список подпапок удалённого пути — для выбора папки в облаке. Результат
     * приходит сигналом remoteDirsReady: колбэки здесь не хранятся принципиально,
     * см. шапку файла.
     *
     * `find --type=d` рекурсивен и на большом аккаунте (у автора 4313 папки)
     * слишком дорог, поэтому обход идёт по одному уровню через `ls -l`.
     */
    function listRemoteDirs(remotePath) {
        sh("mega-exec ls -l " + quote(remotePath) + " 2>&1", "ls:" + remotePath, 60000);
    }

    // Открыть локальный путь в файловом менеджере. Единственная точка вызова
    // xdg-open: подпись и значок для этого действия — в OpenFolderAction.qml.
    function openLocal(path) {
        if (!path)
            return;
        sh("xdg-open " + quote(expandTilde(path)), "open:" + path, 30000);
    }

    /*
     * Очистка кэша. Опасная операция, поэтому обёрнута:
     *  - вызывающий обязан убедиться, что очередь передач пуста (иначе теряем
     *    отложенные выгрузки — запись через маунт асинхронная);
     *  - сервер гасится, кэш чистится, сервер поднимается обратно;
     *  - ветка с systemd нужна на обычной системе, ветка без него — там, где
     *    юнита нет и сервер поднимается первым же вызовом mega-exec.
     */
    function clearCache() {
        if (busyClearing)
            return;
        busyClearing = true;
        var script =
            'set -e; '
          + 'C="$HOME/.megaCmd/fuse-cache"; '
          + 'if systemctl --user is-active --quiet megacmd 2>/dev/null; then '
          + '  systemctl --user stop megacmd; '
          + '  rm -rf "$C"/*; '
          + '  systemctl --user start megacmd; '
          + 'else '
          + '  mega-exec quit >/dev/null 2>&1 || true; '
          + '  n=0; while pgrep -x mega-cmd-server >/dev/null 2>&1 && [ $n -lt 60 ]; do sleep 0.5; n=$((n+1)); done; '
          + '  rm -rf "$C"/*; '
          + '  mega-exec version >/dev/null 2>&1 || true; '
          + 'fi; '
          + 'echo OK';
        // Останов и запуск сервера плюс удаление кэша не укладываются в обычный
        // таймаут, поэтому даём этой команде отдельный запас.
        sh(script, "clear", 180000);
    }

    /*
     * Два файла обязаны лежать вне пакета, потому что их ищут по стандартным
     * путям XDG, а пакет плазмоида ставит файлы только внутрь себя:
     *
     *   ~/.local/share/knotifications6/  — описание типов уведомлений, без него
     *       KNotification молчит, а в Параметрах системы не появляется раздел;
     *   ~/.local/share/locale/<язык>/LC_MESSAGES/  — каталог переводов.
     *
     * Поэтому оба едут внутри пакета и копируются на место при запуске: на новой
     * машине всё заработает само, без установочных скриптов и без gettext.
     */
    function installRuntimeFiles(notifyrcUrl, moUrl) {
        var notifyrc = urlToPath(notifyrcUrl);
        var mo = urlToPath(moUrl);
        var script =
            'S=' + quote(notifyrc) + '; M=' + quote(mo) + '; '
          + 'N="$HOME/.local/share/knotifications6"; '
          + 'L="$HOME/.local/share/locale/ru/LC_MESSAGES"; '
          + 'r=""; '
          + 'if [ -f "$S" ]; then mkdir -p "$N" && '
          + '  { cmp -s "$S" "$N/plasma_applet_megacmd.notifyrc" || cp "$S" "$N/"; } '
          + '  && r="notifyrc:ok"; else r="notifyrc:nosrc"; fi; '
          + 'if [ -f "$M" ]; then mkdir -p "$L" && '
          + '  { cmp -s "$M" "$L/plasma_applet_org.kde.plasma.megacmd.mo" || cp "$M" "$L/"; } '
          + '  && r="$r locale:ok"; else r="$r locale:nosrc"; fi; '
          + 'echo "$r"';
        sh(script, "runtime", 30000);
    }

    // file:///путь → /путь, с раскодированием %XX.
    function urlToPath(url) {
        return decodeURIComponent(String(url).replace(/^file:\/\//, ""));
    }

    // ---- цикл опроса ----
    // Ключ к экономии батареи: когда панель свёрнута и ничего не происходит,
    // опрос идёт раз в несколько минут, а тяжёлые вызовы пропускаются вовсе.

    property int cycle: 0
    property bool expanded: false
    property bool paused: false        // пауза: ни одного вызова без явной команды
    property int expandedInterval: 2000
    property int acInterval: 30000
    property int batteryInterval: 180000

    readonly property int currentInterval: expanded
        ? expandedInterval
        : (transfers.length > 0 ? 5000 : (onBattery ? batteryInterval : acInterval))

    function refreshLight() {
        refreshQuota();
        refreshSyncs();
        refreshTransfers();
        refreshIssues();
    }

    function refreshHeavy() {
        refreshAccount();
        refreshMounts();
        refreshCache();
        refreshPower();
    }

    // Состояние для страницы настроек: доступность сервера, факт входа и списки.
    // refreshQuota() здесь обязателен: только он выставляет loggedIn. Без него
    // страница с paused-бэкендом навсегда считала, что вход не выполнен.
    function refreshState() {
        refreshQuota();
        refreshSyncs();
        refreshMounts();
    }

    // Ручное обновление: работает и на паузе — это единственный способ получить
    // данные, когда автоопрос выключен.
    function refreshNow() {
        refreshLight();
        refreshHeavy();
    }

    Timer {
        id: poll
        interval: backend.currentInterval
        repeat: true
        // На паузе таймер остановлен полностью: ни одного процесса, ни одного
        // пробуждения — расход на виджет строго нулевой.
        running: !backend.paused
        triggeredOnStart: true
        onTriggered: {
            backend.refreshLight();
            // Тяжёлое — при раскрытии сразу, иначе примерно раз в 10 циклов.
            if (backend.expanded || backend.cycle % 10 === 0)
                backend.refreshHeavy();
            backend.cycle = backend.cycle + 1;
        }
    }

    Component.onCompleted: {
        fetchHomeDir();
        if (!paused) {
            refreshPower();
            refreshHeavy();
        }
    }
}
