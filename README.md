# MEGA plasmoid

A Plasma 6 widget that shows the state of your [MEGA](https://mega.nz) account on
top of [MEGAcmd](https://github.com/meganz/MEGAcmd): synchronisations, FUSE
mounts, running transfers, public links, storage quota and the local FUSE cache.

There is no official MEGA widget for Plasma. The official MEGAsync GUI shows
neither FUSE mounts nor the size of the cache they fill up, and it gives you no
list of the links you have shared over the years. This widget does all three.

## What it does

The popup has two tabs, in the shape the system volume applet uses.

### Status

- **Synchronisations** — state of each one, pause and resume, open the local
  folder. A row is only busy when the sync is actually running: MEGAcmd leaves
  the old `STATUS` on a stopped sync, so the widget judges by `RUN_STATE`.
- **FUSE mounts** — mount, unmount, open in the file manager.
- **Transfers** — direction, progress and state of every active transfer,
  including the ones a synchronisation starts (which `transfers` hides unless
  asked). While data moves, a progress ring sits on the tray icon.
- **Storage quota** and the **FUSE cache** size, with a *Clear cache* button
  that stops the server, empties the cache and starts it again. It is disabled
  while transfers are queued: writes through a mount are deferred, and clearing
  the cache would drop data that has not reached the cloud yet.

### Shared

Every public link of the account: file name, the link itself, one click to open
it in the browser, one button to stop sharing. Handy for the links you made from
a phone years ago and forgot — they are permanent, and anyone who still has one
can download the file without a MEGA account.

Listing them walks the whole account, so it runs when you open the tab rather
than on every poll.

### Set everything up without a terminal

*Configure MEGA… → Folders* adds and removes synchronisations and mounts: pick
the local folder with a file dialog, browse the cloud tree for the remote one.
Nothing reaches the server until you press *Apply* or *OK* — pending additions
and removals are listed in place, and leaving the page asks what to do with them.

**Exclusion rules come with profiles**: *MEGA defaults*, *Development*,
*Documents*, *Photos and video*, *No rules*, plus your own saved under a name.
Rules are shown in words — "Exclude directories named venv anywhere in the
folder" — not as `-dn:venv`, and a *Check* button reports what a filter would
match before you apply it.

The profile is written before the folder is created, so the synchronisation is
born with the right rules and nothing unwanted goes up in the meantime. This
matters more than it sounds: adding a rule later does not remove what already
reached the cloud, and taking a rule off makes the local and cloud copies
collide — a conflict MEGAcmd cannot resolve from the CLI.

`Development` keeps `.git`, `.env` and `.claude` synchronised, unlike MEGA's own
defaults, which exclude everything starting with a dot. For a folder full of code
that silently drops your repository history and your keys.

### Elsewhere

- **Hides itself when there is nothing to say.** The tray icon is `Passive` while
  everything is in sync, `Active` during transfers, and `NeedsAttention` on sync
  issues, low cloud space, an oversized FUSE cache, a dead server or a lost
  session.
- **Notifications** — seven event types, each switchable individually in
  *System Settings → Notifications → Applications → MEGA*.
- **Battery friendly** — with measurements, see [Polling](#polling).

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

The dialog has two pages. **General** holds the widget's own settings; **Folders**
manages synchronisations, mounts and exclusion rules. Nothing on the Folders page
touches the server until you press *Apply* or *OK*: pending additions and
removals are listed in place, and leaving the page asks what to do with them.

| Setting (General) | Default |
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

Measured on MEGAcmd 2.5.2 by the CPU time the server spends answering: one poll
cycle costs 52 ms, which is **0.03 % of one core** at the default 180 s interval
on battery, 0.17 % at 30 s on mains and 2.6 % while the popup is open. For scale,
`mega-cmd-server` burns 0.33 % of a core doing nothing at all. Expensive calls
that walk the whole account — the shared-links list — are never part of the
cycle; they run when you open the tab. See
[docs/MEGACMD-BEHAVIOUR.md](docs/MEGACMD-BEHAVIOUR.md) for the numbers.

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
- **Exclusion rules are easy to add and hard to undo.** Adding one leaves what
  already reached the cloud in place, frozen; taking one off makes the local and
  cloud copies collide, and MEGAcmd offers no way to resolve such a conflict from
  the CLI. That is why the widget lets you set the rules before a folder is
  created, and warns when you remove one.
- **Rules do not travel with the folder.** MEGA never uploads `.megaignore`, so
  on a second machine they come from that machine's profile — or from the copy
  you keep in git.
- **Revoking a public link is permanent.** A new link for the same file gets a
  different key; the old one cannot be brought back.
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

Four of them cost real time to find and are worth repeating here:

- **Without `X-Plasma-NotificationAreaCategory` in `metadata.json` the applet
  never appears in the tray's entry list**, so it cannot be given tray
  visibility. `plasmoidregistry.cpp` skips any applet whose category is empty.
  Nothing is logged: the widget installs, works in a panel, and simply is not
  offered to the tray.
- A tray widget must **not** declare its own `header` *for a heading* — the tray
  draws that itself (back arrow, title, high-priority action buttons, hamburger
  menu, configure gear, pin) and appends the applet's header as a *second* row
  below it. Action buttons belong in `Plasmoid.contextualActions` with
  `priority: PlasmaCore.Action.HighPriority`. A **tab bar**, on the other hand,
  is exactly what that second row is for, and the volume applet puts one there.
- **In Breeze the sizes of one icon are separate files with different
  colouring.** `places/22/folder-cloud.svg` is `ColorScheme-Text`;
  `places/32/folder-cloud.svg` is `ColorScheme-Accent`, i.e. blue. A tray icon
  picked by name alone turns colourful on a thick panel and monochrome on a thin
  one. The `-symbolic` suffix guarantees nothing — 454 of Breeze's 7628 symbolic
  files use the accent colour.
- A `ListView` inside a `ColumnLayout` needs `implicitHeight: contentHeight`,
  not just `Layout.preferredHeight`. Without it the layout treats the list as
  zero-height, reserves no space, and the sections below overlap — while the
  rows still paint, because `clip` is off.

MEGAcmd's own behaviour — what it really does with exclusion rules, transfers and
shared links, and what each poll costs — is in
**[docs/MEGACMD-BEHAVIOUR.md](docs/MEGACMD-BEHAVIOUR.md)** (in English).

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).

MEGA and MEGAcmd are products of Mega Limited. This widget is an unofficial
third-party front-end and is not affiliated with or endorsed by Mega Limited.
