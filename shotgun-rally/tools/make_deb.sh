#!/usr/bin/env bash
# A Chromebook (or any Debian / Ubuntu) package of the Linux build: double-click it
# in the Chromebook's Files app ("Install with Linux") and SHOTGUN RALLY appears in
# the launcher. Usage: tools/make_deb.sh <game binary> <amd64|arm64> <version> <out.deb>
# A Chromebook runs the light Compatibility renderer (OpenGL): the desktop builds use
# Forward+ (Vulkan), which Chromebooks' Linux mostly can't do, or only in software.
set -euo pipefail
BIN="$1"; ARCH="$2"; VER="$3"; OUT="$4"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
D="$(mktemp -d)"
chmod 755 "$D"
mkdir -p "$D/DEBIAN" "$D/opt/shotgun-rally" "$D/usr/share/applications" "$D/usr/share/icons/hicolor/256x256/apps" "$D/usr/bin"
install -m 755 "$BIN" "$D/opt/shotgun-rally/ShotgunRally"
cat > "$D/usr/bin/shotgun-rally" <<'RUN'
#!/bin/sh
exec /opt/shotgun-rally/ShotgunRally --rendering-method gl_compatibility "$@"
RUN
chmod 755 "$D/usr/bin/shotgun-rally"
if command -v convert > /dev/null; then
  convert "$HERE/icon.png" -resize 256x256 "$D/usr/share/icons/hicolor/256x256/apps/shotgun-rally.png"
else
  cp "$HERE/icon.png" "$D/usr/share/icons/hicolor/256x256/apps/shotgun-rally.png"
fi
cat > "$D/usr/share/applications/shotgun-rally.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=SHOTGUN RALLY
Comment=Co-op rally: one drives, one rides shotgun with the notes
Exec=/opt/shotgun-rally/ShotgunRally --rendering-method gl_compatibility
Icon=shotgun-rally
Terminal=false
Categories=Game;
DESK
cat > "$D/DEBIAN/control" <<CTRL
Package: shotgun-rally
Version: $VER
Architecture: $ARCH
Maintainer: SHOTGUN RALLY <noreply@users.noreply.github.com>
Section: games
Priority: optional
Depends: libgl1, libx11-6, libxcursor1, libxext6, libxi6, libxinerama1, libxrandr2, libxrender1, libfontconfig1, libasound2t64 | libasound2, libpulse0
Description: SHOTGUN RALLY, a co-op rally game
 One of you drives, the other rides shotgun reading the pacenotes. Online with a
 friend, or alone with the AI co-driver.
CTRL
dpkg-deb --build --root-owner-group "$D" "$OUT" > /dev/null
rm -rf "$D"
echo "built $OUT ($(du -h "$OUT" | cut -f1))"
