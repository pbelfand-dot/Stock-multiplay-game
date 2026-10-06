#!/usr/bin/env bash
# The auto-updater, start to finish, on this machine (no GitHub needed):
#   * two copies of the game: "installed" (build 5) and "new" (build 6, which
#     prints a marker when it starts)
#   * the new one is exported as an update pack + version.json and served by a
#     local web server that answers like GitHub's release downloads do (a 302
#     redirect to where the file really is)
#   * the installed copy, at the menu, finds build 6, downloads it and checks it
#   * started again, it runs as build 6 (the marker shows) and clears the
#     "trying" flag at the menu
#   * a pack that never made it to the menu last time is dropped
#   * a download whose SHA-256 doesn't match is thrown away
# Usage: GODOT=/path/to/godot tests/update_check.sh     (prints [update] lines, exits 1 on a FAIL)
set -u
G="${GODOT:-godot}"
G="$(command -v "$G" || echo "$G")"
cd "$(dirname "$0")/.."
T=$(mktemp -d)
PORT=${SR_UPDATE_PORT:-$((20000 + RANDOM % 30000))}
USERDIR="${XDG_DATA_HOME:-$HOME/.local/share}/ShotgunRallyUpdateTest"
fail=0
ok()  { echo "[update] ok   $1"; }
bad() { echo "[update] FAIL $1"; fail=1; }

copy() {   # copy <dir> <build>
  mkdir -p "$1"
  tar --exclude=./docs --exclude=./build -cf - . | tar -xf - -C "$1"
  sed -i '/^\[application\]/a config/version="'"$2"'"\nconfig/update_base="test-base"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="ShotgunRallyUpdateTest"' "$1/project.godot"
}
copy "$T/installed" 5
copy "$T/new" 6
sed -i '0,/^func _ready() -> void:$/s//func _ready() -> void:\n\tprint("UPDATE-MARKER this is the new build")/' "$T/new/scripts/main.gd"

mkdir -p "$T/www"
"$G" --headless --path "$T/new" --export-pack "Linux" "$T/www/ShotgunRally.pck" > "$T/export.log" 2>&1
[ -s "$T/www/ShotgunRally.pck" ] || { bad "couldn't export the update pack"; tail -20 "$T/export.log"; exit 1; }
SHA=$(sha256sum "$T/www/ShotgunRally.pck" | cut -d' ' -f1)
SIZE=$(stat -c %s "$T/www/ShotgunRally.pck")
echo "{\"build\": 6, \"base\": \"test-base\", \"sha256\": \"$SHA\", \"size\": $SIZE}" > "$T/www/version.json"
ok "update pack exported ($((SIZE / 1024)) KB)"
cat > "$T/serve.py" <<'PY'
import http.server, sys
class H(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if not self.path.startswith("/files/"):          # like github.com/.../releases/download/...
            self.send_response(302)
            self.send_header("Location", "/files" + self.path)
            self.end_headers()
            return
        self.path = self.path[len("/files"):]
        super().do_GET()
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
(cd "$T/www" && exec python3 "$T/serve.py" "$PORT") > "$T/www.log" 2>&1 &
WWW=$!
trap 'kill $WWW 2>/dev/null; rm -rf "$T"' EXIT
sleep 1

# run the installed copy until its updater says one of `$2` (or 60 s), log in $1
run_until() {
  "$G" --headless --path "$T/installed" -- --update_url="http://127.0.0.1:$PORT/" > "$1" 2>&1 &
  local pid=$! i
  for i in $(seq 1 120); do
    grep -qE "$2" "$1" && break
    sleep 0.5
  done
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
}

rm -rf "$USERDIR"
run_until "$T/run1.log" "Update ready|failed|Can't check|Up to date"
grep -q "Update ready (build 6)" "$T/run1.log" && grep -q '"GET /files/ShotgunRally.pck' "$T/www.log" \
  && ok "build 5 found build 6, followed the redirect, downloaded it, size + SHA-256 match" \
  || { bad "build 5 didn't get the update"; grep "\[update\]" "$T/run1.log"; }
[ -f "$USERDIR/update/ShotgunRally.pck" ] || bad "no pack on disk"

run_until "$T/run2.log" "Up to date|failed|Can't check"
grep -q "UPDATE-MARKER" "$T/run2.log" && grep -q "running build 6" "$T/run2.log" && ok "started again: it runs as build 6 (the new build's code)" \
  || { bad "the update didn't apply"; grep -E "\[update\]|MARKER|ERROR" "$T/run2.log" | head; }
grep -q "Up to date  ·  build 6" "$T/run2.log" && ok "...and says it's up to date" || bad "build 6 didn't say up to date"
[ -f "$USERDIR/update/trying" ] && bad "the trying flag is still there after the menu" || ok "made it to the menu: trying flag cleared"

echo 6 > "$USERDIR/update/trying"                  # as if build 6 crashed before the menu
run_until "$T/run3.log" "Update ready|failed|Can't check|Up to date"
grep -q "UPDATE-MARKER" "$T/run3.log" && bad "a pack that didn't reach the menu was used again" \
  || ok "a pack that never reached the menu is dropped: starts as installed (build 5)"
grep -q "Update ready (build 6)" "$T/run3.log" && ok "...and downloads it again" || true

rm -rf "$USERDIR"
echo "{\"build\": 6, \"base\": \"test-base\", \"sha256\": \"$(printf '0%.0s' $(seq 64))\", \"size\": $SIZE}" > "$T/www/version.json"
run_until "$T/run4.log" "Update ready|failed|Can't check|Up to date"
grep -q "Update download failed" "$T/run4.log" && [ ! -f "$USERDIR/update/ShotgunRally.pck" ] && ok "a download with the wrong SHA-256 is thrown away" \
  || { bad "a bad download wasn't refused"; grep "\[update\]" "$T/run4.log"; }

echo "{\"build\": 9, \"base\": \"another-base\"}" > "$T/www/version.json"
run_until "$T/run5.log" "needs a fresh download|Update ready|failed|Can't check|Up to date"
grep -q "needs a fresh download" "$T/run5.log" && ok "a build that can't be a pack (new base) offers the download page" || bad "new base not handled"

rm -rf "$USERDIR"
echo "[update] $([ $fail -eq 0 ] && echo "UPDATER OK" || echo "UPDATER FAIL")"
exit $fail
