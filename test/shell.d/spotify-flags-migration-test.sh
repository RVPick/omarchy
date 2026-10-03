#!/bin/bash
#
# The Spotify video migration must install the default flags only when the
# user has none, and otherwise add the video decode switch next to the user's
# own flags without duplicating it.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/home" "$test_dir/usr/bin"

# The migration only acts when the packaged launcher exists, so point its guard
# at a stand-in instead of the real /usr/bin/spotify.
sed "s|/usr/bin/spotify|$test_dir/usr/bin/spotify|g" "$ROOT/migrations/1791036944.sh" >"$test_dir/migration.sh"
flags="$test_dir/home/.config/spotify-flags.conf"

run_migration() {
  HOME="$test_dir/home" OMARCHY_PATH="$ROOT" bash -euo pipefail "$test_dir/migration.sh" >/dev/null
}

run_migration
[[ ! -e $flags ]] || fail "migration leaves users without Spotify alone"
pass "migration leaves users without Spotify alone"

printf '#!/bin/bash\n' >"$test_dir/usr/bin/spotify"
chmod +x "$test_dir/usr/bin/spotify"

run_migration
cmp -s "$ROOT/config/spotify-flags.conf" "$flags" || fail "migration installs the default Spotify flags"
pass "migration installs the default Spotify flags"

run_migration
cmp -s "$ROOT/config/spotify-flags.conf" "$flags" || fail "migration can be rerun"
pass "migration can be rerun"

printf -- '--force-device-scale-factor=1.5' >"$flags"
run_migration
[[ $(cat "$flags") == $'--force-device-scale-factor=1.5\n--disable-accelerated-video-decode' ]] || fail "migration appends the decode switch to the user's flags" "$(cat "$flags")"
pass "migration appends the decode switch to the user's flags"

printf -- '# --disable-accelerated-video-decode\n' >"$flags"
run_migration
grep -Fxq -- '--disable-accelerated-video-decode' "$flags" || fail "migration ignores a commented-out decode switch" "$(cat "$flags")"
pass "migration ignores a commented-out decode switch"
