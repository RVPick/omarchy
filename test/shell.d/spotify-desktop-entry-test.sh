#!/bin/bash
#
# The Spotify installer and migration must deliver the launcher entry that
# routes Spotify through omarchy-launch-spotify, mark an existing Omarchy
# entry with its package so Apps removal uninstalls Spotify, and leave a
# launcher entry the user wrote themselves alone.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/home" "$test_dir/bin" "$test_dir/usr/bin"

for stub in omarchy-pkg-add omarchy-launch-spotify update-desktop-database; do
  printf '#!/bin/bash\n' >"$test_dir/bin/$stub"
  chmod +x "$test_dir/bin/$stub"
done

# The migration only acts when the packaged launcher exists, so point its guard
# at a stand-in instead of the real /usr/bin/spotify.
migration="$ROOT/migrations/1791036813.sh"
sed "s|/usr/bin/spotify|$test_dir/usr/bin/spotify|g" "$migration" >"$test_dir/migration.sh"
entry="$test_dir/home/.local/share/applications/spotify.desktop"

run_migration() {
  HOME="$test_dir/home" OMARCHY_PATH="$ROOT" PATH="$test_dir/bin:$PATH" bash -euo pipefail "$test_dir/migration.sh" >/dev/null
}

run_installer() {
  HOME="$test_dir/home" OMARCHY_PATH="$ROOT" PATH="$test_dir/bin:$PATH" bash "$ROOT/bin/omarchy-install-service-spotify" >/dev/null
}

run_migration
[[ ! -e $entry ]] || fail "migration leaves users without Spotify alone"
pass "migration leaves users without Spotify alone"

printf '#!/bin/bash\n' >"$test_dir/usr/bin/spotify"
chmod +x "$test_dir/usr/bin/spotify"

run_migration
cmp -s "$ROOT/default/applications/spotify.desktop" "$entry" || fail "migration installs the Spotify launcher entry"
pass "migration installs the Spotify launcher entry"

printf '[Desktop Entry]\nName=My Spotify\n' >"$entry"
run_migration
[[ $(cat "$entry") == $'[Desktop Entry]\nName=My Spotify' ]] || fail "migration keeps a custom Spotify launcher entry" "$(cat "$entry")"
pass "migration keeps a custom Spotify launcher entry"

run_installer
[[ $(cat "$entry") == $'[Desktop Entry]\nName=My Spotify' ]] || fail "installer keeps a custom Spotify launcher entry" "$(cat "$entry")"
pass "installer keeps a custom Spotify launcher entry"

rm "$entry"
run_installer
cmp -s "$ROOT/default/applications/spotify.desktop" "$entry" || fail "installer installs the Spotify launcher entry"
pass "installer installs the Spotify launcher entry"

grep -qx 'Exec=omarchy-launch-spotify %u' "$entry" || fail "the launcher entry starts Spotify through omarchy-launch-spotify"
pass "the launcher entry starts Spotify through omarchy-launch-spotify"

grep -qx 'X-Omarchy-Package=spotify' "$entry" || fail "the launcher entry names the package it fronts"
pass "the launcher entry names the package it fronts"

# An Omarchy entry delivered without the package marker gets it, once.
unmarked=$'[Desktop Entry]\nName=Spotify\nExec=omarchy-launch-spotify %u'
for step in migration installer; do
  printf '%s' "$unmarked" >"$entry"
  "run_$step"
  "run_$step"
  [[ $(cat "$entry") == "$unmarked"$'\nX-Omarchy-Package=spotify' ]] || fail "$step marks an existing Omarchy entry with its package" "$(cat "$entry")"
  pass "$step marks an existing Omarchy entry with its package"
done
