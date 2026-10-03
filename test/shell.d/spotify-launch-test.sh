#!/bin/bash
#
# omarchy-launch-spotify must start Spotify on native Wayland and shrink it
# just enough that its layout fits a half-width tile on the focused monitor,
# leaving it alone where a half tile is already wide enough. A running window
# is focused instead of relaunched, and a spotify: link is handed to Spotify.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/usr/bin"

# The launcher only starts the packaged client, so point it at a stand-in.
sed "s|/usr/bin/spotify|$test_dir/usr/bin/spotify|g" "$ROOT/bin/omarchy-launch-spotify" >"$test_dir/launch"
printf '#!/bin/bash\n' >"$test_dir/usr/bin/spotify"
chmod +x "$test_dir/usr/bin/spotify"

cat >"$test_dir/bin/hyprctl" <<'STUB'
#!/bin/bash
case "$*" in
  "monitors -j") printf '[{"focused":false,"width":3840,"height":2160,"scale":1,"transform":0},{"focused":true,"width":%s,"height":%s,"scale":%s,"transform":%s}]\n' "$WIDTH" "$HEIGHT" "$SCALE" "${TRANSFORM:-0}" ;;
  "clients -j") printf '%s\n' "${CLIENTS:-[]}" ;;
  dispatch*) printf '%s\n' "${*:2}" >>"$DISPATCH_LOG" ;;
esac
STUB
cat >"$test_dir/bin/uwsm-app" <<'STUB'
#!/bin/bash
shift
printf '%s\n' "${@:2}"
STUB
cat >"$test_dir/bin/setsid" <<'STUB'
#!/bin/bash
exec "$@"
STUB
chmod +x "$test_dir/bin/"*

launch() {
  PATH="$test_dir/bin:$PATH" DISPATCH_LOG="$test_dir/dispatch.log" bash "$test_dir/launch" "$@"
}

expect_flags() {
  local monitor="$1" expected="$2" description="$3" actual width height scale transform

  IFS=' ' read -r width height scale transform <<<"$monitor"
  actual=$(WIDTH=$width HEIGHT=$height SCALE=$scale TRANSFORM=${transform:-0} launch)
  [[ $actual == "$expected" ]] || fail "$description" "$actual"
  pass "$description"
}

wayland="--ozone-platform=wayland"

expect_flags "1920 1080 1" "$wayland"$'\n--force-device-scale-factor=0.96' "a 1080p monitor at 1x shrinks Spotify slightly"
expect_flags "3840 2160 2" "$wayland"$'\n--force-device-scale-factor=0.96' "a 4K monitor at 2x shrinks Spotify slightly"
expect_flags "1920 1080 1.25" "$wayland"$'\n--force-device-scale-factor=0.768' "a 1080p monitor at 1.25x fits Spotify in a half tile"
expect_flags "1920 1080 1.5" "$wayland"$'\n--force-device-scale-factor=0.64' "a 1080p monitor at 1.5x fits Spotify in a half tile"
expect_flags "1920 1080 2" "$wayland"$'\n--force-device-scale-factor=0.48' "a 1080p monitor at 2x fits Spotify in a half tile"
expect_flags "2560 1600 1.6" "$wayland"$'\n--force-device-scale-factor=0.8' "a 2560px monitor at 1.6x fits Spotify in a half tile"
expect_flags "2560 1440 1" "$wayland" "a 1440p monitor at 1x leaves Spotify at its own scale"
expect_flags "1920 1080 1 1" "$wayland"$'\n--force-device-scale-factor=0.54' "a portrait monitor measures its rotated width"

actual=$(WIDTH=2560 HEIGHT=1440 SCALE=1 launch spotify:track:abc)
[[ $actual == $'--ozone-platform=wayland\n--uri=spotify:track:abc' ]] || fail "a spotify: link is handed to Spotify" "$actual"
pass "a spotify: link is handed to Spotify"

actual=$(WIDTH=1920 HEIGHT=1080 SCALE=1.25 CLIENTS='[{"class":"spotify","title":"Spotify Premium","address":"0xabc"}]' launch)
[[ -z $actual ]] && grep -q 'address:0xabc' "$test_dir/dispatch.log" || fail "a running Spotify is focused instead of relaunched" "$actual"
pass "a running Spotify is focused instead of relaunched"

actual=$(WIDTH=2560 HEIGHT=1440 SCALE=1 CLIENTS='[{"class":"org.gnome.Nautilus","title":"spotify-screenshots","address":"0xdef"}]' launch)
[[ $actual == "--ozone-platform=wayland" ]] || fail "a window merely titled after Spotify does not count as Spotify" "$actual"
pass "a window merely titled after Spotify does not count as Spotify"
