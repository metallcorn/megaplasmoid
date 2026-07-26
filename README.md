# MEGA plasmoid

A Plasma 6 widget that shows the state of your [MEGA](https://mega.nz) account on
top of [MEGAcmd](https://github.com/meganz/MEGAcmd): synchronisations, FUSE
mounts, running transfers, storage quota and the local FUSE cache.

There is no official MEGA widget for Plasma, and the official MEGAsync GUI shows
neither FUSE mounts nor the size of the cache they fill up. This widget does.

## Features

- **Hides itself when there is nothing to say.** The tray icon is `Passive` while
  everything is in sync, becomes `Active` during transfers and
  `NeedsAttention` on sync issues, low cloud space, an oversized FUSE cache, a
  dead server or a lost session.
- **Synchronisations** — status per sync, pause/resume, open the local folder.
- **FUSE mounts** — mount/unmount, open in the file manager.
- **Transfers** — direction, progress and state of every active transfer.
- **FUSE cache** — current size plus a *Clear cache* button that stops the
  server, empties the cache and starts the server again. The button is disabled
  while transfers are queued, because writes through a mount are deferred and
  clearing the cache would drop data that has not reached the cloud yet.
- **Notifications** — seven event types, each one switchable individually in
  *System Settings → Notifications → Applications → MEGA*.
- **Battery friendly** — see [Polling](#polling).

## Requirements

- Plasma 6 (developed on 6.7, `X-Plasma-API-Minimum-Version` is 6.0)
- MEGAcmd with `mega-exec` in `PATH` (developed against 2.5.2)
- A logged-in MEGAcmd session

The widget never asks for your password and never stores it. Log in once from a
terminal:

```sh
mega-cmd          # opens the MEGAcmd shell
login your@email  # asks for the password with hidden input
quit              # the background server stays logged in
```

`mega-login your@email` on its own does **not** work: outside the MEGAcmd shell
the command requires the password as an argument, which would leak it into `ps`
and the shell history.

## Install

### From a release package

```sh
kpackagetool6 --type Plasma/Applet --install megaplasmoid.plasmoid
```

Or: *right click on the panel → Add Widgets → Get New Widgets → Install Widget
From Local File*.

### From source

```sh
git clone https://github.com/metallcorn/megaplasmoid.git
cd megaplasmoid
make install        # installs into ~/.local/share/plasma/plasmoids/
```

Then restart the shell so Plasma re-reads the QML:

```sh
kquitapp6 plasmashell && kstart plasmashell
```

Add the widget to a panel or to the system tray. Note that with the default
settings it hides under the tray's expander arrow while everything is fine —
that is the intended behaviour, not a broken install.

### Makefile targets

| Target | What it does |
|---|---|
| `make mo` | compiles `po/*.po` into `contents/locale/…` |
| `make package` | builds `megaplasmoid.plasmoid` |
| `make install` | copies the package into `~/.local/share/plasma/plasmoids/` |
| `make uninstall` | removes it, plus the notification and locale files |
| `make clean` | removes build artifacts |

## Configuration

*Right click on the widget → Configure MEGA…*

| Setting | Default |
|---|---|
| Hide the tray icon when everything is fine | on |
| Low space warning threshold | 90 % |
| FUSE cache size warning threshold | 2048 MiB |
| Polling interval, panel open | 2 s |
| Polling interval, collapsed, on AC power | 30 s |
| Polling interval, collapsed, on battery | 180 s |

## Polling

MEGAcmd has no change notifications, so the widget polls. Three things keep that
cheap on a laptop:

- **Adaptive interval.** Frequent only while the panel is open; on battery the
  default is once every three minutes.
- **A serial queue.** Commands run strictly one at a time — one `mega-exec`
  process at any moment instead of the five to eight a naive implementation
  spawns per tick. Identical commands are de-duplicated, so the queue cannot
  grow without bound if it falls behind the timer.
- **A pause switch.** *Pause updates* in the widget's actions stops the timer
  completely: no processes, no wake-ups. Data then refreshes only via
  *Refresh now*.

## Notifications

Event definitions live in
`contents/notifyrc/plasma_applet_megacmd.notifyrc`. Plasma looks them up in
`~/.local/share/knotifications6/`, which a widget package cannot write to at
install time, so the widget copies the file there on first run. The same applies
to the translation catalog, which goes to `~/.local/share/locale/`. Both copies
are refreshed whenever the packaged version differs.

*FUSE cache grew large* and *Synchronisation finished* are defined but switched
off by default; enable them in System Settings if you want them.

## Translations

Source strings are English. Catalogs live in `po/`, and `po/build-mo.py`
compiles them — it is a small self-contained `.mo` writer, so neither `gettext`
nor any other build dependency is required (handy on Steam Deck, where the root
filesystem is read-only).

```sh
make mo
```

The script also reports strings that are missing from a catalog or no longer
present in the QML.

To add a language, copy `po/ru.po`, translate it and rebuild. The translation
domain is `plasma_applet_org.kde.plasma.megacmd`.

## Known limitations

- **No bandwidth figures.** MEGAcmd does not expose transfer quota at all, so
  the widget cannot show it. Showing a guess would be worse than showing
  nothing.
- **No history.** MEGAcmd reports a snapshot; there is no log of past
  synchronisations to build a "recent files" list from.
- **No log-in from the UI**, by design — see [Requirements](#requirements).
- **MEGA's FUSE support is in beta.** There is no streaming, so opening a file
  downloads it in full first, and the cache in `~/.megaCmd/fuse-cache` grows as
  you browse. Restarting the server does *not* empty it, despite what MEGA's own
  disclaimer suggests — hence the *Clear cache* button.
- **`Plasma5Support` is a compatibility module.** It is the only way to run a
  process from a plasmoid without shipping a compiled C++ plugin, and KDE will
  eventually drop it. All of it is confined to `contents/ui/Backend.qml`, so the
  day it disappears only that file needs rewriting.

## Layout notes

If you are writing a Plasma widget yourself, the metrics, component choices,
layout traps, notification and translation rules collected while building this
one are written up in **[docs/PLASMOID-UI-GUIDELINE.md](docs/PLASMOID-UI-GUIDELINE.md)**
(in Russian). Every claim there is backed by either a plasma-workspace source
file or a measurement.

Two of them cost real time to find and are worth repeating here:

- A widget for the system tray must **not** declare its own `header`. The tray
  draws the shared heading itself — back arrow, widget title, high-priority
  action buttons, the hamburger menu, the configure gear and the pin — and an
  applet's own header is appended as a *second* row below it. Action buttons
  belong in `Plasmoid.contextualActions` with
  `priority: PlasmaCore.Action.HighPriority`.
- A `ListView` inside a `ColumnLayout` needs `implicitHeight: contentHeight`,
  not just `Layout.preferredHeight`. Without it the layout treats the list as
  zero-height, reserves no space, and the sections below overlap — while the
  rows still paint, because `clip` is off.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).

MEGA and MEGAcmd are products of Mega Limited. This widget is an unofficial
third-party front-end and is not affiliated with or endorsed by Mega Limited.
