# Keysmith Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Quickshell overlay for Omarchy 4 that adds shortcuts to installed
apps, changes existing shortcuts, and removes shortcuts without opening a text
editor, warning first when a combination is already taken.

**Status:** The original add/change implementation below is complete. The
active Add/Change/Remove product plan is under "Phase 2" at the end of this
file; the unchecked original steps are retained as implementation history.

**Architecture:** Three separable pieces. Shell scripts own everything that reads or writes config (`keysmith-read`, `keysmith-write`, `keysmith-keys`); QML owns only presentation and key capture. The overlay never parses or writes Lua. Key normalization lives in exactly one place — `keysmith-keys` — because a conflict that exists but compares unequal is the one bug that discredits the tool.

**Tech Stack:** QML (Quickshell 0.3.0), bash, `jq`, `hyprctl`. No new dependencies.

**Spec:** `DESIGN.md` (same directory). Project laws: `CLAUDE.md`. Read both before starting.

## Global Constraints

- Plugin id is `sinkeat.keysmith`. Never the reserved `omarchy.` prefix.
- Never write to `/usr/share/omarchy/`. Reading it is expected.
- The only file Keysmith writes is `~/.config/hypr/bindings.lua`.
- Styling: import `qs.Commons` for theme tokens only. Draw controls with plain
  QtQuick. Do not import `qs.Ui` components without an explicit decision.
- Any surface taking `WlrKeyboardFocus.Exclusive` must handle `Escape` before
  anything else. No exceptions — this can lock the user out of their session.
- Validate with `omarchy plugin validate .` and `qmllint` before every commit.
- Plugin lives at `~/.config/omarchy/plugins/sinkeat.keysmith/`. Develop via a
  symlink from the repo so `git` and the live shell see the same files.
- Omarchy 4.0.0-1, Hyprland 0.56.2, Quickshell 0.3.0.

---

## File Structure

| File | Responsibility |
|---|---|
| `manifest.json` | Plugin identity and entry point |
| `Keysmith.qml` | Overlay: search, list, capture UI, conflict prompt |
| `keysmith-keys` | Key normalization. One canonical form, three input formats |
| `keysmith-read` | Emit the catalog as JSON: conflicts, rebindables, apps |
| `keysmith-write` | Apply a binding with baseline-compare rollback |
| `test/test-keys` | Asserts for normalization |
| `test/test-write` | Asserts for the writer's rollback logic |
| `README.md` | Install, usage, config, removal |

---

### Task 1: Live skeleton

Proves four things and nothing else: the manifest loads, summon opens and
closes, theme tokens arrive from a real plugin path, and Escape works before
any capture code exists. If any of this fails, it is the cheapest possible
moment to find out.

**Files:**
- Create: `manifest.json`
- Create: `Keysmith.qml`

**Interfaces:**
- Consumes: nothing.
- Produces: root `Item` with injected `shell` and `manifest` properties, and
  functions `open(payloadJson)`, `close()`, `dismiss()`, `toggle()`. Later
  tasks add to this same root object.

- [ ] **Step 1: Write the manifest**

```json
{
  "schemaVersion": 1,
  "id": "sinkeat.keysmith",
  "name": "Keysmith",
  "version": "0.1.0",
  "author": "Ahmed-Sinkeat",
  "license": "MIT",
  "description": "Rebind Omarchy keyboard shortcuts without editing config files",
  "kinds": ["overlay"],
  "entryPoints": { "overlay": "Keysmith.qml" }
}
```

Note `keepLoaded` is absent on purpose. Keysmith is summoned rarely; loading on
demand costs nothing and keeps it out of shell memory.

- [ ] **Step 2: Write the skeleton overlay**

`Keysmith.qml`. Theme values come from `Style` and `Color` in `qs.Commons`; the
card is a plain `Rectangle`, not `qs.Ui.BorderSurface`, per the styling
constraint.

```qml
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color borderColor: Color.menu.border
  property color scrim: Color.menu.scrim
  property string fontFamily: Style.font.menuFamily

  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.opened = false }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "sinkeat.keysmith")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "keysmith"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: root.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    Rectangle {
      id: card
      width: Math.min(Style.space(560), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(420), panel.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: root.background
      border.color: root.borderColor
      border.width: 1

      MouseArea { anchors.fill: parent; onClicked: {} }

      Text {
        anchors.centerIn: parent
        text: "Keysmith\ntokens OK — Escape to close"
        horizontalAlignment: Text.AlignHCenter
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.dismiss()
            event.accepted = true
          }
        }
      }
    }
  }
}
```

- [ ] **Step 3: Install as a live plugin via symlink**

```bash
mkdir -p ~/.config/omarchy/plugins
ln -sfn ~/Projects/keysmith ~/.config/omarchy/plugins/sinkeat.keysmith
omarchy plugin validate ~/Projects/keysmith
```

Expected: validation passes. If it rejects the symlink, copy the directory
instead and re-copy after each edit.

- [ ] **Step 4: Verify it loads**

```bash
omarchy plugin list | grep keysmith
```

Expected: a row with id `sinkeat.keysmith`, kind `overlay`. If it is absent,
run `omarchy restart shell` and check again before debugging anything else.

- [ ] **Step 5: Verify summon, tokens, and Escape**

```bash
omarchy-shell shell summon sinkeat.keysmith
```

Expected, in order: a themed card appears; its background and text colours
match the current Omarchy theme rather than defaulting to black and white
(this is the proof that `qs.Commons` resolves from a plugin path); pressing
`Escape` closes it; the shell is still alive afterwards.

Recovery if the shell wedges: `omarchy restart shell`.

- [ ] **Step 6: Lint and commit**

```bash
qmllint Keysmith.qml
git add manifest.json Keysmith.qml
git commit -m "feat: live skeleton overlay proving load, summon, tokens, escape"
```

---

### Task 2: Key normalization

One canonical string, three input formats. Everything downstream compares
canonical strings and nothing else.

Canonical form: modifiers in fixed order `SUPER CTRL ALT SHIFT`, joined to the
key with ` + `, e.g. `SUPER + SHIFT + W`. Modifier names uppercase. Key names
keep xkbcommon spelling — `comma` stays lowercase, because Omarchy's own source
carries the comment *"xkbcommon names the comma keysym `comma`; the upper-case
`COMMA` does not match."*

**Files:**
- Create: `keysmith-keys`
- Test: `test/test-keys`

**Interfaces:**
- Consumes: nothing.
- Produces: `keysmith-keys hypr <modmask:int> <keysym>` → canonical string.
  `keysmith-keys qt <qtKeyDecimal> <qtModifierMask:int>` → canonical string.
  `keysmith-keys lua "<source text>"` → canonical string. All print one line
  and exit 0, or print nothing and exit 1 on an unmappable key.

- [ ] **Step 1: Write the failing test**

`test/test-keys`:

```bash
#!/usr/bin/env bash
set -uo pipefail
K="$(dirname "$0")/../keysmith-keys"
fail=0
check() {
  local got; got="$("$K" "${@:2}")"
  if [[ $got == "$1" ]]; then echo "ok   ${*:2} -> $got"
  else echo "FAIL ${*:2} -> '$got' (want '$1')"; fail=1; fi
}

# Qt: Meta=0x10000000(268435456) Shift=0x02000000(33554432) Ctrl=0x04000000 Alt=0x08000000
check "SUPER + SHIFT + W"  qt 87 301989888
check "SUPER + SPACE"      qt 32 268435456
# hypr modmask: SUPER=64 SHIFT=1 CTRL=4 ALT=8
check "SUPER + SHIFT + W"  hypr 65 w
check "SUPER + SPACE"      hypr 64 space
# lua source text
check "SUPER + SHIFT + W"  lua "SUPER + SHIFT + W"
check "SUPER + SHIFT + W"  lua "super+shift+w"
# all three formats of the same combo must agree
check "SUPER + comma"      hypr 64 comma
check "SUPER + comma"      lua "SUPER + comma"
# comma must never be uppercased
check "SUPER + comma"      qt 44 268435456

[[ $fail == 0 ]] && echo "PASS" || echo "FAILED"
exit $fail
```

- [ ] **Step 2: Run it to verify it fails**

```bash
chmod +x test/test-keys && ./test/test-keys
```

Expected: fails — `keysmith-keys` does not exist.

- [ ] **Step 3: Implement `keysmith-keys`**

```bash
#!/usr/bin/env bash
# Canonical key representation. The ONLY place key strings are normalized.
set -uo pipefail

MODS_ORDER=(SUPER CTRL ALT SHIFT)

# Keys whose xkbcommon name is lowercase and must stay that way.
lower_keys="comma period slash semicolon apostrophe grave minus equal \
backslash bracketleft bracketright space return escape tab backspace"

canon_key() {
  local k="$1"
  local lk="${k,,}"
  for w in $lower_keys; do [[ $lk == "$w" ]] && { echo "$lk"; return; }; done
  # Single letters and digits uppercase; everything else keeps source casing.
  if [[ ${#k} == 1 ]]; then echo "${k^^}"; else echo "$k"; fi
}

emit() { # emit <SUPER?> <CTRL?> <ALT?> <SHIFT?> <key>
  local out=() ; local s=$1 c=$2 a=$3 sh=$4 key=$5
  [[ $s == 1 ]] && out+=(SUPER); [[ $c == 1 ]] && out+=(CTRL)
  [[ $a == 1 ]] && out+=(ALT);   [[ $sh == 1 ]] && out+=(SHIFT)
  out+=("$(canon_key "$key")")
  local IFS=" + "; echo "${out[*]}"
}

case "${1:-}" in
  hypr) # modmask bits: SHIFT=1 CTRL=4 ALT=8 SUPER=64
    m=$2
    emit $(( (m & 64) ? 1:0 )) $(( (m & 4) ? 1:0 )) \
         $(( (m & 8) ? 1:0 )) $(( (m & 1) ? 1:0 )) "$3" ;;
  qt)  # Qt masks: Shift=0x02000000 Ctrl=0x04000000 Alt=0x08000000 Meta=0x10000000
    k=$2; m=$3
    key=$(printf '%b' "$(printf '\\x%x' "$k")" 2>/dev/null)
    case $k in
      32) key=space ;; 44) key=comma ;; 46) key=period ;;
      16777216) key=escape ;; 16777220) key=return ;;
    esac
    emit $(( (m & 268435456) ? 1:0 )) $(( (m & 67108864) ? 1:0 )) \
         $(( (m & 134217728) ? 1:0 )) $(( (m & 33554432) ? 1:0 )) "$key" ;;
  lua) # free text like "SUPER + SHIFT + W" or "super+shift+w"
    s=0 c=0 a=0 sh=0 key=""
    IFS='+' read -ra parts <<<"${2// /}"
    for p in "${parts[@]}"; do
      case "${p^^}" in
        SUPER) s=1 ;; CTRL|CONTROL) c=1 ;; ALT) a=1 ;; SHIFT) sh=1 ;;
        *) key="$p" ;;
      esac
    done
    [[ -z $key ]] && exit 1
    emit $s $c $a $sh "$key" ;;
  *) echo "usage: keysmith-keys hypr|qt|lua ..." >&2; exit 1 ;;
esac
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
chmod +x keysmith-keys && ./test/test-keys
```

Expected: `PASS`. If the `qt` letter conversion misbehaves, fix `canon_key`
rather than adding cases per letter — the test is the contract.

- [ ] **Step 5: Commit**

```bash
git add keysmith-keys test/test-keys
git commit -m "feat: canonical key normalization with asserts for all three input formats"
```

---

### Task 3: Reader

Emits the catalog the overlay searches. Three sources, three tiers, as
`DESIGN.md` specifies. `hyprctl binds` is authoritative for *what is taken*;
the packaged Lua is the only source of *what an action does*, because every
bind reports `dispatcher: __lua` under Quattro.

**Files:**
- Create: `keysmith-read`

**Interfaces:**
- Consumes: `keysmith-keys` from Task 2.
- Produces: `keysmith-read` prints a JSON array to stdout. Each element:
  `{"label":string,"key":string|null,"source":"binding"|"app","action":string|null,"rebindable":bool}`.
  `key` is canonical. `action` is verbatim Lua text for rebindable rows, the
  desktop `Exec` for app rows, and `null` when unrecoverable.

- [ ] **Step 1: Confirm the two facts this task depends on**

```bash
hyprctl binds | grep -c 'dispatcher: __lua'
grep -hE '^o\.bind\("' /usr/share/omarchy/default/hypr/bindings/*.lua | head -3
```

Expected: the first prints a number equal to the total bind count (every bind
is `__lua`, so actions are unrecoverable from `hyprctl` — this is why the Lua
parse exists). The second prints single-line `o.bind(...)` calls.

- [ ] **Step 2: Implement the reader**

```bash
#!/usr/bin/env bash
# Emit the Keysmith catalog as JSON. Read-only.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KEYS="$HERE/keysmith-keys"
OMARCHY="${OMARCHY_PATH:-/usr/share/omarchy}"
USER_BINDINGS="$HOME/.config/hypr/bindings.lua"

# 1. Authoritative conflict map: every taken combo + description.
binds_json() {
  hyprctl binds | awk '
    function flush() {
      if (!seen) return; seen=0
      printf "%s\t%s\t%s\n", f["modmask"], f["key"], f["description"]
    }
    /^bind/ { flush(); seen=1; delete f; next }
    seen && match($0, /^\t[a-z]+: /) { f[substr($0,2,RLENGTH-3)] = substr($0, RLENGTH+1) }
    END { flush() }
  ' | while IFS=$'\t' read -r mask key desc; do
      [[ -z $key ]] && continue
      canon="$("$KEYS" hypr "$mask" "$key" 2>/dev/null)" || continue
      printf '%s\t%s\n' "$canon" "$desc"
    done
}

# 2. Action text, verbatim, from single-line o.bind calls.
#    Loop-generated and multi-line calls are deliberately not matched; those
#    rows stay non-rebindable rather than being half-parsed.
lua_actions() {
  grep -hE '^\s*o\.bind\("' "$OMARCHY"/default/hypr/bindings/*.lua "$USER_BINDINGS" 2>/dev/null |
    sed -E 's/^\s*o\.bind\("([^"]*)"\s*,\s*("([^"]*)"|nil)\s*,\s*(.*)\)\s*$/\1\t\3\t\4/' |
    while IFS=$'\t' read -r key desc action; do
      [[ -z ${key:-} ]] && continue
      canon="$("$KEYS" lua "$key" 2>/dev/null)" || continue
      printf '%s\t%s\t%s\n' "$canon" "$desc" "$action"
    done
}

# 3. Installed apps, for combos that do not exist yet.
apps() {
  for d in /usr/share/applications ~/.local/share/applications; do
    [[ -d $d ]] || continue
    for f in "$d"/*.desktop; do
      [[ -f $f ]] || continue
      grep -q '^NoDisplay=true' "$f" && continue
      name=$(sed -n 's/^Name=//p' "$f" | head -1)
      exec_=$(sed -n 's/^Exec=//p' "$f" | head -1 | sed 's/ *%[a-zA-Z]//g')
      [[ -z $name || -z $exec_ ]] && continue
      printf '%s\t%s\n' "$name" "$exec_"
    done
  done
}

jq -n \
  --rawfile binds <(binds_json) \
  --rawfile acts  <(lua_actions) \
  --rawfile app   <(apps) '
  def lines: split("\n") | map(select(length > 0));
  ($acts | lines | map(split("\t")) | map({key: .[0], action: .[3-1]}) ) as $A
  | ($A | map({(.key): .action}) | add // {}) as $actmap
  | ($binds | lines | map(split("\t")) | map({
      label: (.[1] // ""), key: .[0], source: "binding",
      action: ($actmap[.[0]] // null),
      rebindable: ($actmap[.[0]] != null)
    })) as $B
  | ($B | map(.action // "") | join(" ")) as $bound
  | ($app | lines | map(split("\t")) | map({
      label: .[0], key: null, source: "app",
      action: .[1], rebindable: true
    }) | map(select(
      ($bound | test("\\b" + (.action | split(" ")[0] | split("/") | last) + "\\b")) | not
    ))) as $P
  | $B + $P'
```

`# ponytail:` app-to-binding matching is the `Exec` basename heuristic from
`DESIGN.md`. Its known false negative is webapps, which surface as a harmless
duplicate row. Upgrade to desktop-entry ids only if duplicates annoy in use.

- [ ] **Step 3: Verify against the real system**

```bash
chmod +x keysmith-read
./keysmith-read | jq 'length'
./keysmith-read | jq '[.[] | select(.source=="binding")] | length'
./keysmith-read | jq '[.[] | select(.rebindable)] | length'
./keysmith-read | jq '.[] | select(.key=="SUPER + SHIFT + W")'
```

Expected: total is a few hundred; binding count is near 230; rebindable is
meaningfully smaller than the binding count (loop-generated workspace binds are
correctly excluded); the last query returns the Omawrite row with a non-null
`action`. If rebindable equals the binding count, the Lua parse is matching
things it should not.

- [ ] **Step 4: Commit**

```bash
git add keysmith-read
git commit -m "feat: catalog reader merging hyprctl conflicts, Lua actions, and desktop apps"
```

---

### Task 4: Writer

The riskiest file in the project. Everything here exists because a pre-existing
config error must not be mistaken for one Keysmith caused, and because deleting
bytes from disk does not undo what Hyprland already loaded.

**Files:**
- Create: `keysmith-write`
- Test: `test/test-write`

**Interfaces:**
- Consumes: `keysmith-keys` from Task 2.
- Produces: `keysmith-write <canonicalKey> <label> <actionText> [--replace]`.
  Exit 0 on success. Exit 2 when the combo is taken and `--replace` was not
  given. Exit 3 when the write was rolled back. Exit 4 when rollback itself
  failed to restore the baseline.

- [ ] **Step 1: Write the failing test**

`test/test-write`. It exercises block emission and the baseline logic against a
temporary file, never the real config.

```bash
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$HERE/../keysmith-write"
fail=0
say() { if [[ $1 == 0 ]]; then echo "ok   $2"; else echo "FAIL $2"; fail=1; fi }

tmp=$(mktemp -d); export KEYSMITH_BINDINGS="$tmp/bindings.lua"
export KEYSMITH_DRYRUN=1   # skip hyprctl reload; still exercises file logic
printf -- '-- user bindings\n' > "$KEYSMITH_BINDINGS"

# 1. Free key writes o.bind only, wrapped in markers.
"$W" "SUPER + SHIFT + V" "Code" '{ launch = "code" }' >/dev/null
grep -q 'keysmith:begin' "$KEYSMITH_BINDINGS"; say $? "block markers written"
grep -q 'o.bind("SUPER + SHIFT + V", "Code", { launch = "code" })' "$KEYSMITH_BINDINGS"; say $? "o.bind emitted"
! grep -q 'hl.unbind' "$KEYSMITH_BINDINGS"; say $? "no unbind for a free key"

# 2. Taken key without --replace refuses, exit 2, file untouched.
before=$(cat "$KEYSMITH_BINDINGS")
KEYSMITH_TAKEN="SUPER + SHIFT + W" "$W" "SUPER + SHIFT + W" "Typora" '"typora"' >/dev/null 2>&1
[[ $? == 2 ]]; say $? "refuses taken key with exit 2"
[[ "$(cat "$KEYSMITH_BINDINGS")" == "$before" ]]; say $? "file untouched on refusal"

# 3. Taken key with --replace emits unbind before bind.
KEYSMITH_TAKEN="SUPER + SHIFT + W" "$W" "SUPER + SHIFT + W" "Typora" '"typora"' --replace >/dev/null
grep -A1 'hl.unbind("SUPER + SHIFT + W")' "$KEYSMITH_BINDINGS" | grep -q 'o.bind("SUPER + SHIFT + W"'
say $? "unbind emitted immediately before bind"

# 4. A PRE-EXISTING config error must not trigger rollback.
export KEYSMITH_DRYRUN=0
export KEYSMITH_FAKE_BASELINE="pre-existing error"
export KEYSMITH_FAKE_AFTER="pre-existing error"
before=$(cat "$KEYSMITH_BINDINGS")
"$W" "SUPER + ALT + J" "Thing" '"thing"' >/dev/null
[[ $? == 0 ]]; say $? "pre-existing error does not roll back"
grep -q 'SUPER + ALT + J' "$KEYSMITH_BINDINGS"; say $? "write survived pre-existing error"

# 5. A NEW error rolls back AND reloads a second time.
export KEYSMITH_FAKE_BASELINE=""
export KEYSMITH_FAKE_AFTER="new error"
export KEYSMITH_RELOAD_LOG="$tmp/reloads"; : > "$KEYSMITH_RELOAD_LOG"
before=$(cat "$KEYSMITH_BINDINGS")
"$W" "SUPER + ALT + K" "Bad" '"bad"' >/dev/null 2>&1
[[ $? == 3 ]]; say $? "new error exits 3"
[[ "$(cat "$KEYSMITH_BINDINGS")" == "$before" ]]; say $? "bytes restored"
[[ $(wc -l < "$KEYSMITH_RELOAD_LOG") -ge 2 ]]; say $? "second reload issued after restore"

rm -rf "$tmp"
[[ $fail == 0 ]] && echo "PASS" || echo "FAILED"
exit $fail
```

- [ ] **Step 2: Run it to verify it fails**

```bash
chmod +x test/test-write && ./test/test-write
```

Expected: fails — `keysmith-write` does not exist.

- [ ] **Step 3: Implement the writer**

```bash
#!/usr/bin/env bash
# Apply one binding to the user's bindings.lua, with baseline-compare rollback.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BINDINGS="${KEYSMITH_BINDINGS:-$HOME/.config/hypr/bindings.lua}"

key="${1:?canonical key}"; label="${2:?label}"; action="${3:?action text}"
replace=0; [[ "${4:-}" == "--replace" ]] && replace=1

# Test seams: let the suite drive reload/errors without touching Hyprland.
configerrors() {
  if [[ -n ${KEYSMITH_FAKE_BASELINE+x} && $phase == baseline ]]; then
    printf '%s' "$KEYSMITH_FAKE_BASELINE"; return
  fi
  if [[ -n ${KEYSMITH_FAKE_AFTER+x} && $phase != baseline ]]; then
    printf '%s' "$KEYSMITH_FAKE_AFTER"; return
  fi
  hyprctl configerrors 2>/dev/null | grep -v '^\s*$'
}
reload() {
  [[ -n ${KEYSMITH_RELOAD_LOG:-} ]] && echo reload >> "$KEYSMITH_RELOAD_LOG"
  [[ ${KEYSMITH_DRYRUN:-0} == 1 ]] && return 0
  hyprctl reload >/dev/null 2>&1
}

is_taken() {
  [[ -n ${KEYSMITH_TAKEN:-} ]] && { [[ $KEYSMITH_TAKEN == "$key" ]]; return; }
  hyprctl binds | grep -q . && "$HERE/keysmith-read" 2>/dev/null |
    jq -e --arg k "$key" 'any(.[]; .key == $k)' >/dev/null
}

if is_taken && (( ! replace )); then
  echo "taken: $key" >&2; exit 2
fi

mkdir -p "$(dirname "$BINDINGS")"; touch "$BINDINGS"
phase=baseline; baseline="$(configerrors)"
saved="$(cat "$BINDINGS")"
id=$(printf '%s%s' "$key" "$RANDOM" | sha256sum | cut -c1-6)

{
  printf '\n-- keysmith:begin %s\n' "$id"
  (( replace )) && printf 'hl.unbind("%s")\n' "$key"
  printf 'o.bind("%s", "%s", %s)\n' "$key" "$label" "$action"
  printf -- '-- keysmith:end %s\n' "$id"
} >> "$BINDINGS"

reload
phase=after; after="$(configerrors)"

if [[ "$after" == "$baseline" ]]; then
  echo "$id"; exit 0
fi

# New errors: restore bytes, then reload AGAIN. Hyprland has already loaded the
# bad config into runtime state; deleting bytes alone leaves the file right and
# the session wrong, which looks like success and is not.
printf '%s' "$saved" > "$BINDINGS"
reload
phase=restored; restored="$(configerrors)"
if [[ "$restored" == "$baseline" ]]; then
  echo "rolled back: $BINDINGS" >&2; exit 3
fi
echo "ROLLBACK INCOMPLETE - inspect $BINDINGS by hand" >&2; exit 4
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
chmod +x keysmith-write && ./test/test-write
```

Expected: `PASS`, with all nine assertions green. The two that matter most are
*"pre-existing error does not roll back"* and *"second reload issued after
restore"* — they are the reason this file is structured the way it is.

- [ ] **Step 5: Commit**

```bash
git add keysmith-write test/test-write
git commit -m "feat: writer with owned blocks and baseline-compare rollback"
```

---

### Task 5: Search and conflict UI

Wires the reader into the overlay. No key capture yet — selecting a row shows
the conflict verdict for a combo typed as text, so the list and the conflict
logic are proven before the hardest part is added.

**Files:**
- Modify: `Keysmith.qml`

**Interfaces:**
- Consumes: `keysmith-read` (Task 3), root `Item` (Task 1).
- Produces: root property `rows` (array of catalog objects), `selected`
  (object or null), and function `conflictFor(canonicalKey)` returning the
  matching row or `null`.

- [ ] **Step 1: Load the catalog on open**

Add to `Keysmith.qml`, and add `import Quickshell.Io` at the top:

```qml
  property var rows: []
  property string filterText: ""
  property var selected: null

  Process {
    id: readProc
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/sinkeat.keysmith/keysmith-read"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.rows = JSON.parse(this.text) } catch (e) { root.rows = [] }
      }
    }
  }

  function conflictFor(canonicalKey) {
    for (var i = 0; i < root.rows.length; i++)
      if (root.rows[i].key === canonicalKey) return root.rows[i]
    return null
  }

  readonly property var filtered: {
    var q = root.filterText.toLowerCase()
    if (!q) return root.rows.slice(0, 200)
    return root.rows.filter(function(r) {
      return r.label.toLowerCase().indexOf(q) !== -1
    }).slice(0, 200)
  }
```

Call `readProc.running = true` inside `open()`, before `forceActiveFocus`.

- [ ] **Step 2: Replace the placeholder Text with a search field and list**

```qml
      Column {
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.space(8)

        Text {
          text: root.filterText.length ? root.filterText : "Type to search…"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }

        ListView {
          width: parent.width
          height: parent.height - Style.space(40)
          clip: true
          model: root.filtered
          delegate: Item {
            width: ListView.view.width
            height: Style.space(28)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              color: root.foreground
              font.family: root.fontFamily
              opacity: modelData.rebindable ? 1.0 : 0.5
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.key ? modelData.key
                                  : (modelData.source === "app" ? "not bound" : "")
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
            }
          }
        }
      }
```

- [ ] **Step 3: Make typing filter the list**

Extend the existing `Keys.onPressed` in `keyCatcher`, keeping the Escape branch
first:

```qml
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.filterText = ""
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace) {
            root.filterText = root.filterText.slice(0, -1)
            event.accepted = true
          } else if (event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32
                     && event.text.charCodeAt(0) !== 127) {
            root.filterText += event.text
            event.accepted = true
          }
```

- [ ] **Step 4: Verify on the live shell**

```bash
qmllint Keysmith.qml && omarchy restart shell
omarchy-shell shell summon sinkeat.keysmith
```

Expected: the list populates; typing `obs` narrows it to Obsidian showing
`SUPER + SHIFT + O`; typing `code` shows an app row reading `not bound`;
non-rebindable rows render dimmed; `Escape` clears the filter, then closes.

- [ ] **Step 5: Commit**

```bash
git add Keysmith.qml
git commit -m "feat: searchable catalog list with conflict lookup"
```

---

### Task 6: Key capture

The proven mechanism from `DESIGN.md`. `ShortcutInhibitor` suppresses
Hyprland's own binds so a taken combo can be recorded instead of firing.

**Files:**
- Modify: `Keysmith.qml`

**Interfaces:**
- Consumes: `keysmith-keys` (Task 2), `conflictFor` (Task 5).
- Produces: root property `capturing` (bool), `capturedKey` (canonical string
  or `""`).

- [ ] **Step 1: Add the inhibitor and capture state**

Add `import Quickshell.Wayland` if not already present, then inside
`PanelWindow`:

```qml
    ShortcutInhibitor {
      id: inhibitor
      window: panel
      enabled: root.capturing
    }
```

And on `root`:

```qml
  property bool capturing: false
  property string capturedKey: ""

  Process {
    id: keysProc
    stdout: StdioCollector {
      onStreamFinished: root.capturedKey = this.text.trim()
    }
  }

  function canonicalize(qtKey, qtMods) {
    keysProc.command = [
      Quickshell.env("HOME") + "/.config/omarchy/plugins/sinkeat.keysmith/keysmith-keys",
      "qt", String(qtKey), String(qtMods)
    ]
    keysProc.running = true
  }
```

- [ ] **Step 2: Handle keys while capturing**

Insert at the very top of `Keys.onPressed`, before the Escape branch:

```qml
          if (root.capturing) {
            // Escape must still escape, or an exclusive grab traps the user.
            if (event.key === Qt.Key_Escape) {
              root.capturing = false; root.capturedKey = ""
              event.accepted = true; return
            }
            // Ignore bare modifier presses; wait for a real key.
            if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control
                || event.key === Qt.Key_Alt || event.key === Qt.Key_Meta) {
              event.accepted = true; return
            }
            root.canonicalize(event.key, event.modifiers)
            root.capturing = false
            event.accepted = true
            return
          }
```

- [ ] **Step 3: Show the verdict**

```qml
        Text {
          visible: root.capturedKey.length > 0
          width: parent.width
          wrapMode: Text.WordWrap
          color: root.foreground
          font.family: root.fontFamily
          text: {
            var c = root.conflictFor(root.capturedKey)
            if (!c) return root.capturedKey + "\nfree — nothing else uses this"
            return root.capturedKey + "\ntaken by \"" + c.label + "\""
          }
        }
```

- [ ] **Step 4: Verify capture beats Hyprland**

```bash
qmllint Keysmith.qml && omarchy restart shell
omarchy-shell shell summon sinkeat.keysmith
```

Then, with capture active, press `SUPER + SHIFT + W`.

Expected: the overlay shows `SUPER + SHIFT + W` and `taken by "Omawrite"`, and
**Omawrite does not launch**. Press `SUPER + SPACE`: it is captured and the
Omarchy menu does not open. Press `Escape`: capture cancels and the overlay
still closes.

If a bind fires instead of being captured, check `inhibitor.enabled` is true
before the keypress — the grab must be active first, not requested on demand.

- [ ] **Step 5: Commit**

```bash
git add Keysmith.qml
git commit -m "feat: key capture via shortcuts-inhibit with escape always first"
```

---

### Task 7: Wire it together and document

Connects capture to the writer, installs the menu override, and writes the
README the registry requires.

**Files:**
- Modify: `Keysmith.qml`
- Create: `README.md`

- [ ] **Step 1: Call the writer on confirm**

```qml
  Process {
    id: writeProc
    onExited: function(code) {
      root.capturedKey = ""
      root.selected = null
      if (code === 0) readProc.running = true   // refresh the catalog
    }
  }

  function applyBinding(replace) {
    if (!root.selected || !root.capturedKey) return
    var args = [
      Quickshell.env("HOME") + "/.config/omarchy/plugins/sinkeat.keysmith/keysmith-write",
      root.capturedKey, root.selected.label, root.selected.action
    ]
    if (replace) args.push("--replace")
    writeProc.command = args
    writeProc.running = true
  }
```

Bind `Return` to `applyBinding(root.conflictFor(root.capturedKey) !== null)`
in the non-capturing branch of `Keys.onPressed`.

- [ ] **Step 2: Install the menu override**

Add to `~/.config/omarchy/extensions/omarchy-menu.jsonc`, inside the object:

```jsonc
  "setup.keybindings": {"action":"omarchy-shell shell summon sinkeat.keysmith"},
```

Verified working earlier: reusing the id keeps the same row, label and icon,
and deleting the line restores the text editor.

- [ ] **Step 3: Write the README**

Four sections only, per project laws: install, usage, config, removal.

```markdown
# Keysmith

Rebind Omarchy keyboard shortcuts without editing config files. Shows you what
already owns a combination before you take it.

Requires Omarchy 4 (Quattro).

## Install

    omarchy plugin add https://github.com/Ahmed-Sinkeat/keysmith

Then point the menu entry at it — add this line to
`~/.config/omarchy/extensions/omarchy-menu.jsonc`:

    "setup.keybindings": {"action":"omarchy-shell shell summon sinkeat.keysmith"},

## Usage

Open `Setup > Keybindings` from the Omarchy menu. Search for an app or an
action, press the keys you want, and confirm. If the combination is taken
Keysmith says what owns it and offers to replace it.

Escape clears the search, then closes.

Some bindings cannot be rebound here — Omarchy generates the workspace and
focus shortcuts in loops, so their definitions cannot be read back. They still
appear, so conflicts against them are still caught.

## Configuration

Keysmith writes only to `~/.config/hypr/bindings.lua`, in marked blocks:

    -- keysmith:begin a1b2c3
    hl.unbind("SUPER + SHIFT + W")
    o.bind("SUPER + SHIFT + W", "Typora", "typora")
    -- keysmith:end a1b2c3

Edit or delete those by hand any time. Omarchy's own defaults are never
touched.

## Removal

    omarchy plugin remove sinkeat.keysmith

Then delete the `setup.keybindings` line from your menu extensions file to get
the text editor back. Bindings Keysmith wrote stay in `bindings.lua` until you
remove them.
```

- [ ] **Step 4: Full verification**

```bash
./test/test-keys && ./test/test-write
qmllint Keysmith.qml
omarchy plugin validate ~/Projects/keysmith
omarchy restart shell
```

Then from the Omarchy menu: `Setup > Keybindings`, search `code`, press
`SUPER + SHIFT + V`, confirm. Verify the block appears in `bindings.lua`,
`hyprctl configerrors` is clean, and the new shortcut launches the app.

- [ ] **Step 5: Commit and push**

```bash
git add Keysmith.qml README.md
git commit -m "feat: wire capture to writer, add menu override and README"
git push
```

---

## Self-review notes

- **Spec coverage.** Insertion point → Task 7. Reader three tiers → Task 3.
  Normalization → Task 2. Conflict detection → Tasks 3 and 5. Capture → Task 6.
  Writer with markers and baseline rollback → Task 4. Distribution → README in
  Task 7, registry submission is post-v1 and out of scope here.
- **Deliberately deferred.** Undo and reset-to-default remain out of the first
  complete product. Remove is handled by Phase 2 below. Apps remain a
  first-class Add target in the shared searchable list.
- **Known soft spot.** The `is_taken` path in `keysmith-write` shells out to
  `keysmith-read`, which is slow for a single lookup. Acceptable at one call
  per save. `# ponytail:` pass the catalog in if it ever feels sluggish.

---

## Phase 2: complete the product loop

Agreed interaction contract:

- Enter is the primary action: Add when no key exists, Change when one does.
- Right Arrow or a visible More button opens contextual actions.
- Remove lives in More and requires confirmation. There is no global Delete
  shortcut and no action available only through right-click.
- Remove means leave the item unbound. It is not reset-to-default.
- Escape goes back one state at a time and remains first in capture handling.

### Task 8: Record the product contract

- [x] Define Add, Change, Replace, and Remove in `DESIGN.md`.
- [x] Keep installed applications as first-class Add targets.
- [x] Update the README and manifest language to describe the complete product.

### Task 9: Removal state and catalog continuity

**Files:** `keysmith-write`, `keysmith-read`, `test/test-write`, `test/test-read`.

- [x] Add a writer remove operation using the same baseline, reload, verify,
  rollback, byte, mode, and timestamp guarantees as Add/Change.
- [x] Update a matching Keysmith-owned action block instead of growing a new
  block for every later Change or Remove.
- [x] Never delete arbitrary handwritten Lua or packaged defaults.
- [x] Keep parseable removed actions in the catalog as unbound Add targets.
- [x] Protect multi-action keys from key-only removal.

### Task 10: Contextual actions UI

**File:** `Keysmith.qml`.

- [x] Add mouse selection to result rows.
- [x] Show visible Add/Change and More controls for the current row.
- [x] Open More with Right Arrow or mouse; close it with Left Arrow or Escape.
- [x] Offer Change, Remove, and Open bindings.lua as applicable.
- [x] Confirm Remove on a separate screen before calling the writer.
- [x] After Add, Change, or Remove, briefly state exactly what changed.

### Task 11: Verification

- [x] Run reader, writer, and key-normalization regression suites.
- [x] Run `qmllint`, `omarchy plugin validate .`, shell syntax checks, and
  `git diff --check`.
- [x] Exercise Add, Change, conflict Replace, and Remove in the live overlay
  with a reversible binding, then restore the original config exactly.
- [x] Confirm the More menu and Escape state transitions by keyboard, and
  verify visible mouse hit targets for rows and controls.

### Task 12: Discoverable launch and honest loading

- [x] Expose Keysmith as an optional Omarchy bar widget so enabled installs do
  not depend on a remembered terminal command.
- [x] Show an explicit loading state instead of briefly presenting the editor
  escape hatch as the complete catalog.
- [x] Label non-rebindable rows as view-only and explain why they are protected.
- [x] Validate both QML entry points and exercise the bar button in the live
  shell.
