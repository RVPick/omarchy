#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/data/applications" "$tmp_dir/system/applications" "$tmp_dir/bin"

write_fake_command() {
  local name="$1"
  local prefix="$2"

  cat >"$tmp_dir/bin/$name" <<SCRIPT
#!/bin/bash
printf '%s:%s:%s\\n' '$prefix' "\${OMARCHY_REMOVE_NOTIFY:-}" "\$*" >>"\$TEST_LOG"
SCRIPT
  chmod +x "$tmp_dir/bin/$name"
}

write_fake_command omarchy-webapp-remove web
write_fake_command omarchy-tui-remove tui
write_fake_command omarchy-launch-floating-terminal-with-presentation terminal

cat >"$tmp_dir/bin/omarchy-notification-send" <<'SCRIPT'
#!/bin/bash
printf 'notify::%s\n' "$*" >>"$TEST_LOG"
SCRIPT
chmod +x "$tmp_dir/bin/omarchy-notification-send"

cat >"$tmp_dir/bin/update-desktop-database" <<'SCRIPT'
#!/bin/bash
:
SCRIPT
chmod +x "$tmp_dir/bin/update-desktop-database"

cat >"$tmp_dir/bin/pacman" <<'SCRIPT'
#!/bin/bash
if [[ $1 == "-Qqo" && $2 == */native.desktop ]]; then
  printf 'native-pkg\n'
elif [[ $1 == "-Qqo" && $2 == */system/applications/spotify.desktop ]]; then
  printf 'spotify\n'
else
  exit 1
fi
SCRIPT
chmod +x "$tmp_dir/bin/pacman"

cat >"$tmp_dir/data/applications/Basecamp.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Basecamp
Exec=omarchy-launch-webapp https://example.com
DESKTOP

cat >"$tmp_dir/data/applications/Docker.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Docker
Exec=xdg-terminal-exec --app-id=TUI.tile -e lazydocker
DESKTOP

cat >"$tmp_dir/system/applications/native.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Native
Exec=native
DESKTOP

cat >"$tmp_dir/data/applications/aliens.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Aliens
Exec=retroarch -L /usr/lib/libretro/fbneo_libretro.so /home/example/Games/roms/fbneo/aliens.zip
DESKTOP

# User overrides of packaged entries: Spotify's is owned by a package, the
# other shadows an entry nothing owns.
for name in spotify unowned; do
  printf '[Desktop Entry]\nName=%s\nExec=%s\n' "$name" "$name" >"$tmp_dir/system/applications/$name.desktop"
  printf '[Desktop Entry]\nName=%s\nExec=omarchy-launch-%s\n' "$name" "$name" >"$tmp_dir/data/applications/$name.desktop"
done

export TEST_LOG="$tmp_dir/log"
export PATH="$tmp_dir/bin:$PATH"
export XDG_DATA_HOME="$tmp_dir/data"
export XDG_DATA_DIRS="$tmp_dir/system"

"$ROOT/bin/omarchy-remove-launcher-entry" Basecamp.desktop Basecamp
"$ROOT/bin/omarchy-remove-launcher-entry" Docker.desktop Docker
"$ROOT/bin/omarchy-remove-launcher-entry" native.desktop Native
"$ROOT/bin/omarchy-remove-launcher-entry" aliens.desktop Aliens
"$ROOT/bin/omarchy-remove-launcher-entry" spotify.desktop Spotify
"$ROOT/bin/omarchy-remove-launcher-entry" unowned.desktop Unowned

mapfile -t lines <"$TEST_LOG"

[[ ${lines[0]} == "web:false:Basecamp" ]] || fail "launcher remove routes web apps by desktop name" "${lines[0]}"
pass "launcher remove routes web apps by desktop name"

[[ ${lines[1]} == "tui:false:Docker" ]] || fail "launcher remove routes TUIs by desktop name" "${lines[1]}"
pass "launcher remove routes TUIs by desktop name"

[[ ${lines[2]} == "terminal::echo Uninstalling Native...; sudo pacman -Rns native-pkg" ]] || fail "launcher remove opens package uninstall flow" "${lines[2]}"
pass "launcher remove opens package uninstall flow"

[[ ! -e $tmp_dir/data/applications/aliens.desktop ]] || fail "launcher remove deletes user-owned desktop files"
pass "launcher remove deletes user-owned desktop files"

[[ ${lines[3]:-} == "terminal::echo Uninstalling Spotify...; sudo pacman -Rns spotify" ]] || fail "launcher remove uninstalls the package behind a user override" "${lines[3]:-}"
pass "launcher remove uninstalls the package behind a user override"

[[ ! -e $tmp_dir/data/applications/spotify.desktop ]] || fail "launcher remove deletes the user override of a packaged entry"
pass "launcher remove deletes the user override of a packaged entry"

[[ ! -e $tmp_dir/data/applications/unowned.desktop && -e $tmp_dir/system/applications/unowned.desktop ]] || fail "launcher remove only deletes the override of an entry no package owns"
pass "launcher remove only deletes the override of an entry no package owns"

(( ${#lines[@]} == 4 )) || fail "launcher remove does not notify for user-owned desktop files" "$(printf '%s\n' "${lines[@]}")"
pass "launcher remove does not notify for user-owned desktop files"
