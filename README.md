# Keysmith

Add, change, and remove Omarchy keyboard shortcuts from an overlay instead of
editing `~/.config/hypr/bindings.lua` by hand.

Keysmith reads the shortcuts you actually have — Omarchy's defaults, your own
bindings, and installed apps that have none yet — and shows which combos are
already taken. It can add a shortcut to an app, move an existing shortcut, or
leave an action unbound without modifying Omarchy's packaged files.

## Install

```
omarchy plugin add https://github.com/Ahmed-Sinkeat/keysmith.git --enable
```

Then restart the shell:

```
omarchy restart shell
```

The enabled plugin adds a keyboard button to the Omarchy bar. Click it to open
Keysmith; the terminal command below is only a fallback.

When updating an older overlay-only Keysmith install, move it into the bar
once:

```
omarchy plugin disable sinkeat.keysmith
omarchy plugin enable sinkeat.keysmith --section right
```

## Usage

Open the overlay from its keyboard button in the Omarchy bar. If the button is
not on the bar yet, add it from `Setup → Plugins → Enable Plugin`, or use:

```
omarchy-shell shell toggle sinkeat.keysmith
```

To give it a key of its own, add a free combo to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + J", "Keysmith", "omarchy-shell shell toggle sinkeat.keysmith")
```

In the overlay:

- Type to search, `Up`/`Down` to move.
- Dimmed rows marked `view only` are generated or shared shortcuts that
  Keysmith cannot safely rewrite. They still count when checking conflicts.
- `Enter` adds or changes the selected row, then records the combo you want.
  Hyprland's own shortcuts
  are suppressed while recording, so a combo that is already in use still
  reaches Keysmith instead of firing what owns it.
- `Enter` again saves. If the combo belongs to something else, Keysmith says so
  first and replaces it only when you confirm.
- `Right Arrow` opens the visible More menu. Remove shortcut lives there and
  asks for confirmation; removing leaves the item unbound rather than resetting
  it to an Omarchy default.
- `Escape` backs out one step at a time, and always works. Recording also closes
  automatically after 20 seconds.

Shortcuts Keysmith cannot parse — loop-generated ones like the workspace keys —
are listed so they still count as conflicts, but cannot be rebound here. The
last row opens `bindings.lua` in your editor for those.

## Config

None. Keysmith has no settings.

It writes to `~/.config/hypr/bindings.lua`, only inside marked state blocks it
owns:

```lua
-- keysmith:begin a1b2c3d4e5f6
-- keysmith:data <encoded state>
hl.unbind("SUPER + W")
o.bind("SUPER + ALT + W", "Close window", hl.dsp.window.close())
-- keysmith:end a1b2c3d4e5f6
```

The data comment lets later changes and removal update this same owned block
instead of stacking another override. It is internal state, not configuration.

Packaged defaults under `/usr/share/omarchy/` are never modified. After each
write Keysmith reloads Hyprland and compares `hyprctl configerrors` against the
reading it took beforehand; if the change introduced an error, the file is
restored byte for byte and reloaded again.

## Removal

```
omarchy plugin remove sinkeat.keysmith
```

Bindings Keysmith wrote stay where they are. To undo them, delete the
`keysmith:begin` / `keysmith:end` blocks from `~/.config/hypr/bindings.lua`
and run `hyprctl reload`.
