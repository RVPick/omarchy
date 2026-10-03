echo "Launch Spotify with native Wayland rendering"

[[ -x /usr/bin/spotify ]] || exit 0

desktop_file="$HOME/.local/share/applications/spotify.desktop"

# Install the launcher entry, or mark an existing Omarchy one with its package so removing it
# from Apps uninstalls Spotify; leave a launcher entry the user wrote themselves alone
if [[ ! -f $desktop_file ]]; then
  mkdir -p "$HOME/.local/share/applications"
  install -m 644 "$OMARCHY_PATH/default/applications/spotify.desktop" "$desktop_file"
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
elif grep -q '^Exec=.*omarchy-launch-spotify' "$desktop_file" && ! grep -q '^X-Omarchy-Package=' "$desktop_file"; then
  [[ -n $(tail -c1 "$desktop_file") ]] && echo >>"$desktop_file"
  echo 'X-Omarchy-Package=spotify' >>"$desktop_file"
fi
