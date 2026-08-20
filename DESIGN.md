# Design — Keysmith

Working document, not a shipped file. See `CLAUDE.md` for project laws.

Status: **reviewed and settled.** No open questions remain.

## The problem

Changing a keybinding in Omarchy 4 means opening `~/.config/hypr/bindings.lua`
in a text editor. `Setup → Keybindings` in the Omarchy menu does exactly that
today:

```jsonc
"setup.keybindings": {"action":"omarchy-launch-config-editor \"$HOME/.config/hypr/bindings.lua\""}
```

Editing that file correctly requires knowing something non-obvious: if the key
you want is already bound, you must call `hl.unbind(...)` *before* `o.bind(...)`
or your binding silently does nothing. Nothing tells you the key is taken.

That is the whole problem this solves.

## What it is

A Quickshell overlay plugin. You open it, search for the thing you want a key
for, press the keys, and it writes the binding — warning you first if something
already owns that combination.

## Non-goals

- Not a keybinding viewer. `SUPER+K` already does that and stays untouched.
- Not an auto-configurator. Quattro already ships bindings for the apps people
  want; adding them again has no value.
- Not a replacement for the editor. Opening the file stays available as a row.
- Not custom shell commands in v1. That needs typing, which defeats the point.

Removing and resetting bindings are wanted and planned — they follow once add
and replace work end to end. See "Decided".

## Insertion point

Override the existing menu id in `~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"setup.keybindings": {"action":"omarchy-shell shell summon sinkeat.keysmith"}
```

The extension format documents id reuse as the supported override mechanism,
and three built-in entries already summon overlays this way
(`omarchy.wifiqr`, `omarchy.speedtest`, `omarchy.disk-speedtest`).

Deleting that one line restores the editor. Nothing is patched or forked.

Optionally also bind a key directly in `bindings.lua`.

## Architecture

Three pieces, each independently testable.

| Piece | Responsibility | Form |
|---|---|---|
| **Reader** | Enumerate what exists: current bindings + installed apps | shell script → JSON |
| **Overlay** | Search, select, capture keypress, show conflicts | QML |
| **Writer** | Append the `hl.unbind` / `o.bind` pair, reload, verify | shell script |

The overlay never edits files directly and never parses Lua. It calls the
reader on open and the writer on save. Keeping Lua handling in one script means
the risky part is one small testable surface.

### Reader

**`hyprctl binds` cannot give us actions under Quattro.** All 230 binds report
`dispatcher: __lua` with an opaque integer `arg` — the Lua callback handle.
Verified: `hyprctl binds | grep dispatcher | sort -u` yields exactly one value.
Any design that assumed a recoverable action from there was wrong.

The action comes from the packaged Lua instead, and the key insight is that
**Keysmith never needs to understand an action, only to copy it verbatim.**
The third argument to `o.bind` is either a shell-command string or an
`hl.dsp.*` expression:

```lua
o.bind("SUPER + CTRL + Q", "Calculator", "omacalc")
o.bind("SUPER + W", "Close window", hl.dsp.window.close())
```

Capturing everything after the second argument as opaque text and re-emitting
it under a new key handles both uniformly, trailing option tables included.

So the reader has three sources and produces three tiers:

| Source | Gives | Tier |
|---|---|---|
| `hyprctl binds` | every taken combo + description (230) | **conflict data — complete** |
| `$OMARCHY_PATH/default/hypr/bindings/*.lua` + user `bindings.lua` | verbatim action text | **rebindable** |
| `.desktop` entries | apps with no binding | **addable** |

Row: `{ label, canonicalKey|null, source, actionText|null, rebindable }`.

**Not everything is rebindable, and that is fine.** `tiling.lua` generates the
workspace bindings in `for` loops and a few calls span multiple lines, so a
line-based parse cannot recover their action text. Those rows still appear and
still participate in conflict detection — they just show *"can't rebind here —
open the file"* instead of offering capture. The unrecoverable set is almost
exactly the 71 workspace/focus bindings nobody rebinds.

Conflict detection — the core feature — is complete for all 230 because it only
needs keys and descriptions. Only rebinding is partial.

### Key normalization

One module, used by the reader, the capture step, and the writer. Nothing
compares key strings anywhere else.

Three input formats must converge: `hyprctl`'s `modmask` integer plus keysym,
Omarchy's `"SUPER + SHIFT + W"` source text, and captured `Qt::Key` plus
modifier mask. Canonical form fixes modifier order (SUPER, CTRL, ALT, SHIFT),
casing, and keysym spelling.

**Two forms are required, not one.** Measured against the live system,
`hyprctl binds` echoes each bind's *source* spelling rather than a normalized
keysym — and Omarchy's own defaults are internally inconsistent, containing
both `Delete` and `DELETE`. Compared literally those are different keys.

- **canonical** — for comparison. Uppercase everything, so spelling variance
  collapses. `mouse:272`, `mouse_down` and `code:201` pass through untouched,
  having no case.
- **spelling** — for writing. Some keysyms only match in xkbcommon's lowercase
  form; the packaged Lua says so of comma directly: *"xkbcommon names the comma
  keysym `comma`; the upper-case `COMMA` does not match."*

A single form cannot do both jobs: uppercase-only breaks writing, lowercase-only
fails to collapse `Delete`/`DELETE`. A conflict that exists but compares unequal
is the one bug that would discredit the whole tool.

### App identity

Merging `.desktop` rows with bound rows needs a stable identity, or the list
shows Obsidian twice.

Rule: identity is the **executable basename** from the desktop entry's `Exec`,
first token, flags stripped. A binding belongs to an app when its action text
contains that basename as a word. On match the rows merge and the app shows its
current key.

`# ponytail:` this is a heuristic. It has a known false negative on webapps
(`omarchy-launch-webapp 'https://chatgpt.com'` has no executable in common with
any `.desktop`), which shows as a harmless duplicate row rather than a wrong
binding. Upgrade to matching desktop-entry ids only if duplicates prove
annoying in use.

### Overlay

Single screen:

```
  Keybindings                    search: code_

   Visual Studio Code       ·  not bound
   Color picker             ·  SUPER + PRINT
  ──────────────────────────────────────────────
   Open bindings.lua in editor
```

Select a row → capture mode → confirm → writer runs.

Conflict is the load-bearing state:

```
          SUPER + SHIFT + W
   taken by "Omawrite"  (Omarchy default)
   [ Replace it ]    [ Try another ]
```

*Replace it* is what emits the `hl.unbind` the user would otherwise have to
know about.

### Writer

Appends an **owned block** to `~/.config/hypr/bindings.lua`:

```lua
-- keysmith:begin 7f3a91
hl.unbind("SUPER + SHIFT + W")
o.bind("SUPER + SHIFT + W", "Visual Studio Code", { launch = "code" })
-- keysmith:end 7f3a91
```

The markers exist from v1 even though nothing reads them until remove/reset
ships. Removing an override then means deleting a delimited block Keysmith
knows it wrote — never inferring intent from someone's hand-written Lua. Adding
markers later would mean heuristics over user code, which is the failure mode
worth spending four comment characters to avoid.

`hl.unbind` is emitted only when the combo was actually bound.

**Apply sequence.** A non-empty `configerrors` does not by itself mean this
write broke anything — the file may have been broken before Keysmith touched
it, and treating a pre-existing error as our failure would roll back a correct
change:

1. Read `hyprctl configerrors` as a **baseline** and save the file bytes.
2. Append the block.
3. `hyprctl reload`, then read `configerrors` again.
4. Compare against baseline. Unchanged → success, even if non-empty.
5. New errors → restore the saved bytes, **`hyprctl reload` a second time**,
   then read `configerrors` once more to confirm the restore actually landed.
6. If the post-restore state still differs from baseline, stop and tell the
   user plainly, with the file path. Do not retry silently.

Step 5's second reload is not optional. Hyprland has already loaded the bad
config into runtime state; deleting bytes from disk does not undo that. Without
it a failed write leaves the file correct and the session wrong — the worst
outcome available, because it looks fine.

Never writes anywhere but the user's own `bindings.lua`.

## Key capture

Proven working — see `CLAUDE.md`. `ShortcutInhibitor` from
`Quickshell.Wayland` with `WlrKeyboardFocus.Exclusive`. Captured
`SUPER+SHIFT+W`, `SUPER+SPACE` and `SUPER+K` with Hyprland's own binds fully
suppressed. No submaps, no evdev, no elevated permissions.

Two constraints this creates:

1. `nativeScanCode` is unusable (constant `9`). Map `Qt::Key` + modifier mask to
   Hyprland key names via a lookup table. Hyprland's `code:XX` binding form is
   therefore out of reach.
2. Exclusive keyboard focus with no exit locks the user out of their session.
   Escape must be handled before anything else, plus a timeout.

## Looking native

Import `qs.Commons` (`Style`, `Color`) and `qs.Ui` (`Panel`, `TextField`, …),
which is what `emojis`, `clipboard`, and `reminders` all do. `Style.qml` is
theme-token driven, so the plugin tracks the user's active Omarchy theme with
no work.

The import resolves. `omarchy-shell` launches `quickshell -p $OMARCHY_PATH/shell`,
and Quickshell registers that config root as the `qs` namespace — so `Ui/` and
`Commons/` become `qs.Ui` / `qs.Commons`. The path is engine-global and plugins
load into that same engine, so directory of origin does not matter.

**Risk is stability, not availability.** These are internal modules. The
third-party *bar widget* example deliberately uses plain `QtQuick` with injected
theme properties instead, which suggests `qs.*` is not a supported third-party
contract and may change between Omarchy releases. Mitigation: depend on
`Style`/`Color` tokens (small surface) rather than deep component reuse, so a
break is a restyle and not a rewrite.

## Distribution

Registry first, upstream second. A working plugin with users is evidence; a PR
proposing an idea is easy to decline. A declined PR costs nothing if the plugin
already ships on its own.

1. **Third-party plugin.** Publish the git repo, install via
   `omarchy plugin add <git-url>`. Submit to omarchyplugins.com through its
   GitHub issue template. That registry is an independent community project,
   unaffiliated with Omarchy or 37signals.
2. **Then propose upstream.** Open a discussion on `basecamp/omarchy` linking
   the working plugin before opening a PR — cheaper to gauge interest than to
   build toward a maybe.

Keep both doors open:

- **License MIT**, matching Omarchy (`pacman -Qi omarchy` → MIT). Anything else
  adds friction to a merge with no upside.
- Keep the manifest contract and file layout identical to a first-party plugin,
  so adoption is a move rather than a rewrite.
- On adoption the only changes are the id (`sinkeat.keysmith` →
  `omarchy.keysmith`) and the menu override becoming unnecessary, since
  `setup.keybindings` would be wired directly. OPEN-4 also dissolves — first
  party code uses `qs.Ui` freely.

Note first-party manifests omit `license`; the registry requires it for
third-party plugins, so ours carries it.

## Testing

Per project laws: cheap checks only.

- `omarchy plugin validate ./<dir>` and `qmllint` on every QML file.
- One assert-based script covering the writer, which is where the risk is:
  conflict → `hl.unbind` emitted; no conflict → `o.bind` only; block markers
  present and matched; **pre-existing `configerrors` does not trigger rollback**;
  new error → bytes restored *and* a second reload issued. That last pair is the
  point of the test.
- One assert covering normalization: `modmask`+keysym, `"SUPER + SHIFT + W"`,
  and a captured `Qt::Key` all collapse to the same canonical string, and
  `comma` never becomes `COMMA`.
- Manual: capture a combo with a physical keypress and confirm the scancode
  finding still holds.

## Decided

- **Name: Keysmith**, id `sinkeat.keysmith`. Not `omarchy.*` (reserved).
- **Styling: tokens yes, components no.** Import `qs.Commons` for theme tokens;
  draw controls with plain QtQuick. Exception only for a single component that
  saves disproportionate work. Keeps a future break a restyle, not a rewrite.

- **Apps/System split — deferred until after testing.** Ship one searchable
  list. Split only if it turns out muddled in real use, not before.
- **Remove and reset — planned, sequenced second.** Not cut. v1 gets add and
  replace working end to end; remove and reset-to-default follow immediately
  after, before anything else is considered.
