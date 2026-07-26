/*
 * Единственная точка, которая знает про MEGAcmd и про запуск процессов.
 * Всё остальное в виджете работает только со свойствами этого объекта.
 * Если Plasma когда-нибудь выпилит Plasma5Support — переписывать надо только здесь.
 */
import QtQuick
import org.kde.plasma.plasma5support as P5Support

Item {
    id: backend

    // ---- наблюдаемое состояние ----
    property bool cmdMissing: false      // mega-exec не найден
    property bool serverDown: false      // бинарь есть, но сервер не отвечает
    property bool loggedIn: false

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

    signal cacheCleared(bool ok, string message)

    // ---- запуск процессов ----
    /*
     * Команды выполняются строго по одной. Раньше цикл опроса выпускал их
     * параллельно, и на каждый тик поднималось 5–8 процессов сразу — заметный
     * всплеск для ноутбука и лишние подключения к mega-cmd-server.
     *
     * Побочная польза дедупликации: если очередь не поспевает за таймером,
     * повторная постановка той же команды просто игнорируется, и очередь
     * не растёт бесконечно.
     */
    P5Support.DataSource {
        id: exe
        engine: "executable"
        connectedSources: []

        property var queue: []          // ожидающие команды, FIFO
        property string active: ""      // выполняемая сейчас
        property var callbacks: ({})    // cmd -> колбэк (есть и у активной, и у ждущих)
        property var timeouts: ({})     // cmd -> сколько ждать, мс

        onNewData: function (source, data) {
            if (source !== active) {
                // Чужой источник (например остаток после срабатывания сторожа).
                disconnectSource(source);
                return;
            }
            var cb = callbacks[source];
            delete callbacks[source];
            delete timeouts[source];
            watchdog.stop();
            disconnectSource(source);
            active = "";
            if (cb)
                cb(String(data["stdout"] || ""), Number(data["exit code"]), String(data["stderr"] || ""));
            pump();
        }

        function run(cmd, cb, timeoutMs) {
            // Уже выполняется или уже стоит в очереди — второй раз не ставим.
            if (cmd === active || (cmd in callbacks))
                return;
            callbacks[cmd] = cb;
            timeouts[cmd] = timeoutMs > 0 ? timeoutMs : 15000;
            queue.push(cmd);
            pump();
        }

        function pump() {
            if (active !== "" || queue.length === 0)
                return;
            active = queue.shift();
            watchdog.interval = timeouts[active] || 15000;
            watchdog.restart();
            connectSource(active);
        }

        property string stalled: ""     // последняя команда, снятая по таймауту
    }

    /*
     * Сторож: при серийном исполнении одна зависшая команда заблокировала бы
     * весь виджет. По истечении таймаута бросаем её и идём дальше — колбэк
     * не вызывается, состояние просто не обновится до следующего цикла.
     * Объявлен снаружи DataSource: у того нет default property, дочерние
     * элементы внутрь не принимаются.
     */
    Timer {
        id: watchdog
        repeat: false
        onTriggered: {
            if (exe.active === "")
                return;
            var stuck = exe.active;
            delete exe.callbacks[stuck];
            delete exe.timeouts[stuck];
            exe.disconnectSource(stuck);
            exe.active = "";
            exe.stalled = stuck;
            exe.pump();
        }
    }

    // Диагностика: последняя команда, снятая по таймауту, и длина очереди.
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
     * ВАЖНО: команда для DataSource собирается через quote(), а не через
     * JSON.stringify. Проверено экспериментально: при двойных кавычках вокруг
     * скрипта аргументы теряются молча — команда выполняется, код возврата 0,
     * а переменные внутри пустые.
     */
    function sh(script, cb, timeoutMs) {
        exe.run("sh -c " + quote(script), cb, timeoutMs);
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

    // ---- опросы ----

    function refreshQuota() {
        // df дешевле, чем whoami -l: не ходит за историей платежей и сессиями.
        sh("mega-exec df", function (out, code) {
            if (code !== 0) {
                serverDown = true;
                return;
            }
            serverDown = false;
            if (looksNotLoggedIn(out)) {
                loggedIn = false;
                return;
            }
            loggedIn = true;
            var m = out.match(/USED STORAGE:\s+(\d+)\s+[\d.,]+%\s+of\s+(\d+)/);
            if (m) {
                usedBytes = parseFloat(m[1]);
                totalBytes = parseFloat(m[2]);
            }
        });
    }

    function refreshAccount() {
        // Самый дорогой вызов (сеть + сессии), поэтому дёргается редко.
        sh("mega-exec whoami -l", function (out, code) {
            if (code !== 0)
                return;
            var e = out.match(/Account e-mail:\s*(\S+)/);
            if (e)
                accountEmail = e[1];
            var p = out.match(/Pro level:\s*(\d+)/);
            proLevel = p ? parseInt(p[1]) : -1;
            var d = out.match(/Pro expiration date:\s*(.+)/);
            proExpires = d ? d[1].trim() : "";
        });
    }

    function refreshSyncs() {
        sh("mega-exec sync --col-separator='|' --path-display-size=4096 "
           + "--output-cols=ID,LOCALPATH,REMOTEPATH,RUN_STATE,STATUS,ERROR", function (out, code) {
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
        });
    }

    function refreshMounts() {
        // fuse-show не понимает --col-separator (в его справке флаг указан, но
        // на деле отвергается), поэтому режем по ширине колонок.
        sh("mega-exec fuse-show --disable-path-collapse", function (out, code) {
            if (code !== 0)
                return;
            mounts = parseFixedWidth(out, ["NAME", "LOCAL_PATH", "REMOTE_PATH", "PERSISTENT", "ENABLED"]).map(function (r) {
                return {
                    name: r["NAME"] || "",
                    localPath: r["LOCAL_PATH"] || "",
                    remotePath: r["REMOTE_PATH"] || "",
                    persistent: (r["PERSISTENT"] || "") === "YES",
                    enabled: (r["ENABLED"] || "") === "YES"
                };
            });
        });
    }

    function refreshTransfers() {
        sh("mega-exec transfers --col-separator='|' --path-display-size=4096", function (out, code) {
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
        });
    }

    function refreshIssues() {
        sh("mega-exec sync-issues --limit=0", function (out, code) {
            if (code !== 0)
                return;
            if (out.indexOf("no sync issues") !== -1) {
                issueCount = 0;
                return;
            }
            issueCount = parseSeparated(out, "|").length
                      || Math.max(0, String(out).split("\n").filter(function (l) {
                             return l.trim().length > 0;
                         }).length - 1);
        });
    }

    function refreshCache() {
        // Обход каталога — не самая дешёвая операция, зовём редко.
        sh("du -sb \"$HOME/.megaCmd/fuse-cache\" 2>/dev/null | cut -f1", function (out, code) {
            var n = parseFloat(String(out).trim());
            cacheBytes = isNaN(n) ? -1 : n;
        });
    }

    function refreshPower() {
        sh("cat /sys/class/power_supply/A*/online 2>/dev/null | head -1", function (out) {
            var v = String(out).trim();
            if (v.length > 0)
                onBattery = (v === "0");
        });
    }

    function checkAvailable() {
        sh("command -v mega-exec >/dev/null 2>&1 && echo yes || echo no", function (out) {
            cmdMissing = (String(out).trim() !== "yes");
        });
    }

    // ---- действия ----

    // Открыть локальный путь в файловом менеджере. Единственная точка вызова
    // xdg-open: подпись и значок для этого действия — в OpenFolderAction.qml.
    function openLocal(path) {
        if (!path)
            return;
        sh("xdg-open " + quote(path), function () {});
    }

    function pauseSync(id) {
        sh("mega-exec sync --pause " + quote(id), function () {
            refreshSyncs();
        });
    }

    function resumeSync(id) {
        sh("mega-exec sync --enable " + quote(id), function () {
            refreshSyncs();
        });
    }

    function setMountEnabled(name, on) {
        var verb = on ? "fuse-enable" : "fuse-disable";
        sh("mega-exec " + verb + " " + quote(name), function () {
            refreshMounts();
        });
    }

    /*
     * Очистка кэша. Опасная операция, поэтому обёрнута:
     *  - вызывающий обязан убедиться, что очередь передач пуста
     *    (иначе теряем отложенные выгрузки — запись через маунт асинхронная);
     *  - сервер гасится, кэш чистится, сервер поднимается обратно;
     *  - ветка с systemd нужна на этой машине, ветка без него — для Steam Deck,
     *    где юнита нет и сервер поднимается первым же вызовом mega-exec.
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
        sh(script, function (out, code, err) {
            busyClearing = false;
            var ok = (code === 0 && String(out).indexOf("OK") !== -1);
            cacheCleared(ok, ok ? "" : (String(err).trim() || i18n("Could not clear the cache")));
            refreshCache();
            refreshMounts();
            refreshSyncs();
        // Останов и запуск сервера плюс удаление кэша не укладываются в обычный
        // таймаут, поэтому даём этой команде отдельный запас.
        }, 180000);
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

    property date lastUpdate: new Date(0)

    readonly property int currentInterval: expanded
        ? expandedInterval
        : (transfers.length > 0 ? 5000 : (onBattery ? batteryInterval : acInterval))

    function refreshLight() {
        refreshQuota();
        refreshSyncs();
        refreshTransfers();
        refreshIssues();
        lastUpdate = new Date();
    }

    function refreshHeavy() {
        refreshAccount();
        refreshMounts();
        refreshCache();
        refreshPower();
    }

    /*
     * Два файла обязаны лежать вне пакета, потому что их ищут по стандартным
     * путям XDG, а пакет плазмоида ставит файлы только внутрь себя:
     *
     *   ~/.local/share/knotifications6/  — описание типов уведомлений,
     *       без него KNotification молчит, а в Параметрах системы не появляется
     *       раздел для их настройки;
     *   ~/.local/share/locale/<язык>/LC_MESSAGES/  — каталог переводов,
     *       домен plasma_applet_<id> формирует Plasma::Applet::translationDomain().
     *
     * Поэтому оба едут внутри пакета и копируются на место при запуске: на новой
     * машине (например на Steam Deck, куда пакет просто скопировали) всё
     * заработает само, без установочных скриптов и без gettext.
     */
    property string runtimeFilesState: ""

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
        sh(script, function (out) {
            runtimeFilesState = String(out).trim();
        });
    }

    // file:///путь → /путь, с раскодированием %XX.
    function urlToPath(url) {
        return decodeURIComponent(String(url).replace(/^file:\/\//, ""));
    }

    // Ручное обновление: работает и на паузе — это единственный способ
    // получить данные, когда автоопрос выключен.
    function refreshNow() {
        if (cmdMissing) {
            checkAvailable();
            return;
        }
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
            if (backend.cmdMissing) {
                backend.checkAvailable();
                return;
            }
            backend.refreshLight();
            // Тяжёлое — при раскрытии сразу, иначе примерно раз в 10 циклов.
            if (backend.expanded || backend.cycle % 10 === 0)
                backend.refreshHeavy();
            backend.cycle++;
        }
    }

    Component.onCompleted: {
        checkAvailable();
        if (!paused) {
            refreshPower();
            refreshHeavy();
        }
    }
}
