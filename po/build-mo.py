#!/usr/bin/env python3
"""
Компилирует po/<язык>.po в contents/locale/<язык>/LC_MESSAGES/<домен>.mo.

Написано вручную потому, что msgfmt из gettext может отсутствовать (в этой
системе его нет, а на Steam Deck ставить пакеты некуда). Формат .mo простой и
стабильный, так что своя реализация надёжнее внешней зависимости.

Заодно сверяет каталог с исходниками: строки, которых нет в QML, и строки QML
без перевода печатаются как предупреждения.
"""
import os
import re
import struct
import sys

DOMAIN = "plasma_applet_org.kde.plasma.megacmd"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def parse_po(path):
    """Читает .po и возвращает список записей (msgctxt, msgid, msgid_plural, [msgstr])."""
    entries = []
    cur = {"ctxt": None, "id": None, "plural": None, "strs": {}}
    field = None

    def flush():
        if cur["id"] is not None:
            entries.append(dict(cur))
        cur.update({"ctxt": None, "id": None, "plural": None, "strs": {}})

    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#"):
                if not line:
                    flush()
                    field = None
                continue
            m = re.match(r'^(msgctxt|msgid_plural|msgid|msgstr(?:\[(\d+)\])?)\s+"(.*)"$', line)
            if m:
                key, idx, text = m.group(1), m.group(2), m.group(3)
                text = unescape(text)
                if key == "msgctxt":
                    flush() if cur["id"] is not None else None
                    cur["ctxt"] = text
                    field = ("ctxt", None)
                elif key == "msgid":
                    if cur["id"] is not None:
                        ctxt = cur["ctxt"]
                        flush()
                        cur["ctxt"] = None
                    cur["id"] = text
                    field = ("id", None)
                elif key == "msgid_plural":
                    cur["plural"] = text
                    field = ("plural", None)
                else:
                    n = int(idx) if idx is not None else 0
                    cur["strs"][n] = text
                    field = ("str", n)
                continue
            m = re.match(r'^"(.*)"$', line)
            if m and field:
                text = unescape(m.group(1))
                kind, n = field
                if kind == "ctxt":
                    cur["ctxt"] += text
                elif kind == "id":
                    cur["id"] += text
                elif kind == "plural":
                    cur["plural"] += text
                else:
                    cur["strs"][n] += text
    flush()
    return entries


def unescape(s):
    return (s.replace("\\n", "\n").replace("\\t", "\t")
             .replace('\\"', '"').replace("\\\\", "\\"))


def build_mo(entries):
    """Собирает бинарный .mo. Формат: magic, счётчики, две таблицы смещений."""
    items = []
    for e in entries:
        if e["id"] is None:
            continue
        key = e["id"]
        if e["ctxt"] is not None:
            key = e["ctxt"] + "\x04" + key          # контекст отделяется EOT
        if e["plural"] is not None:
            key = key + "\x00" + e["plural"]
            parts = [e["strs"].get(i, "") for i in sorted(e["strs"])]
            val = "\x00".join(parts)
        else:
            val = e["strs"].get(0, "")
        if e["id"] == "" or val:                    # заголовок каталога тоже нужен
            items.append((key.encode("utf-8"), val.encode("utf-8")))

    items.sort(key=lambda kv: kv[0])
    n = len(items)
    keystart = 7 * 4 + 16 * n
    offsets, kdata, vdata = [], b"", b""
    for k, v in items:
        offsets.append((len(kdata), len(k), len(vdata), len(v)))
        kdata += k + b"\x00"
        vdata += v + b"\x00"
    valuestart = keystart + len(kdata)

    ktable, vtable = b"", b""
    for ko, kl, vo, vl in offsets:
        ktable += struct.pack("<II", kl, keystart + ko)
        vtable += struct.pack("<II", vl, valuestart + vo)

    return (struct.pack("<Iiiiiii", 0x950412DE, 0, n, 7 * 4, 7 * 4 + 8 * n, 0, 0)
            + ktable + vtable + kdata + vdata)


def qml_strings():
    """Строки из QML — для сверки полноты каталога."""
    found = set()
    for sub in ("contents/ui", "contents/config"):
        d = os.path.join(ROOT, sub)
        if not os.path.isdir(d):
            continue
        for name in os.listdir(d):
            if not name.endswith(".qml"):
                continue
            src = open(os.path.join(d, name), encoding="utf-8").read()
            for m in re.finditer(r'\bi18n(c|p|cp)?\s*\(', src):
                kind = m.group(1) or ""
                i, depth, buf = m.end(), 1, ""
                while i < len(src) and depth > 0:
                    c = src[i]
                    if c == "(":
                        depth += 1
                    elif c == ")":
                        depth -= 1
                    if depth > 0:
                        buf += c
                    i += 1
                args = re.findall(r'"((?:[^"\\]|\\.)*)"', buf)
                if not args:
                    continue
                # У i18nc и i18ncp первый аргумент — контекст, строка идёт
                # вторым. Без этой развилки i18ncp регистрировал бы как msgid
                # свой контекст, а настоящая строка не искалась бы вовсе, и
                # проверка полноты каталога молчала бы об этом.
                if kind in ("c", "cp") and len(args) > 1:
                    found.add((unescape(args[0]), unescape(args[1])))
                else:
                    found.add((None, unescape(args[0])))
    return found


def main():
    po_dir = os.path.join(ROOT, "po")
    langs = [f[:-3] for f in os.listdir(po_dir) if f.endswith(".po")]
    if not langs:
        print("нет .po файлов", file=sys.stderr)
        return 1

    in_qml = qml_strings()
    for lang in sorted(langs):
        entries = parse_po(os.path.join(po_dir, lang + ".po"))
        translated = {(e["ctxt"], e["id"]) for e in entries if e["id"]}

        # Сортировка по строке: msgctxt бывает None, и он несравним со str.
        def order(item):
            return (item[1], item[0] or "")

        missing = sorted(in_qml - translated, key=order)
        extra = sorted(translated - in_qml, key=order)

        def fmt(item):
            ctxt, msgid = item
            return (("[%s] " % ctxt) if ctxt else "") + msgid[:64]

        if missing:
            print("ВНИМАНИЕ %s: без перевода (%d):" % (lang, len(missing)))
            for item in missing:
                print("   -", fmt(item))
        if extra:
            print("ВНИМАНИЕ %s: лишние, нет в QML (%d):" % (lang, len(extra)))
            for item in extra:
                print("   +", fmt(item))

        out_dir = os.path.join(ROOT, "contents", "locale", lang, "LC_MESSAGES")
        os.makedirs(out_dir, exist_ok=True)
        out = os.path.join(out_dir, DOMAIN + ".mo")
        data = build_mo(entries)
        with open(out, "wb") as fh:
            fh.write(data)
        print("%s: %d строк → %s (%d байт)"
              % (lang, len(entries), os.path.relpath(out, ROOT), len(data)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
