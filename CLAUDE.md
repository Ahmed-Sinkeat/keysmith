# Project laws

Keysmith — a Quickshell overlay plugin for Omarchy 4 (Quattro).
Read this before changing anything. Every line here was earned, not assumed.

## Scope

- This is a **plugin, not an application**. Smallest thing that works.
- Core value is **conflict detection**: knowing a combo is already bound and
  emitting `hl.unbind` before `o.bind`.
- **Not** a goal: auto-adding shortcuts for installed apps. Quattro already
  ships 30 of the 35 bindings a typical user hand-wrote under Omarchy 3.

## Build

- **There is no build step.** QML is interpreted by the running shell and
  hot-reloads when a file under `~/.config/omarchy/plugins/` is saved.
- Never add a Makefile, package.json, or a BUILD doc. Verified: no build file
  exists in any of the 23 first-party plugins, and the manual states no
  compilation occurs.

## Files we ship

- **Required** by the registry: `manifest.json`, entry-point `.qml`,
  `README.md`, `LICENSE`. Optional `preview.png`.
- Implementation files beyond those are fine — required is not a maximum.
  First-party plugins ship them too (`clipboard/capture.sh`,
  `image-picker/list.sh`, `reminders/ReminderFlowModel.js`). Splitting the code
  that touches config away from the UI is worth more than a file count.
- **No extra documentation**: no CONTRIBUTING, ARCHITECTURE, CHANGELOG, `docs/`.
  That is the rule this law is actually about.
- README covers four things only: install, usage, config, removal.
- Plain writing. No AI slop.

## Boundaries

- Never write to `/usr/share/omarchy/` — package-owned, wiped by
  `omarchy update`. Reading it is fine and encouraged.
- Plugin lives in `~/.config/omarchy/plugins/<id>/`.
- `id` must not start with `omarchy.` — that namespace is reserved.
- User bindings are written to `~/.config/hypr/bindings.lua` as an
  `hl.unbind(...)` followed by `o.bind(...)`. Never edit packaged defaults.

## Proven — do not re-litigate

- Key capture works via `zwp_keyboard_shortcuts_inhibit`. Hyprland 0.56.2
  implements it; Quickshell 0.3.0 exposes `ShortcutInhibitor`
  (`enabled`, `window`, readonly `active`). Confirmed capturing `SUPER+SPACE`
  and `SUPER+SHIFT+W` with Hyprland's own binds fully suppressed.
  No submaps, no evdev, no elevated permissions.
- `nativeScanCode` is unreliable — it came back as a constant `9` for every
  key under `wtype`. Map `Qt::Key` + modifiers to Hyprland key names via a
  lookup table. Re-check against a physical keypress before trusting it.

## Safety

- Any overlay taking `WlrKeyboardFocus.Exclusive` **must** have an escape
  hatch — a timeout, or Escape handled before anything else. A fullscreen
  exclusive keyboard grab with no exit locks the user out of their session.

## Checks

- `omarchy plugin validate ./<plugin-dir>`
- `qmllint <file>.qml`
- After writing Hyprland config: `hyprctl reload`, then `hyprctl configerrors`
