#!/usr/bin/env bash
# rebrand.sh - Element Web -> PrivatCloud Chat
# Aufruf im Repo-Root:  bash rebrand.sh
set -euo pipefail

BRAND="PrivatCloud Chat"
CALL_BRAND="PrivatCloud Call"
LOGO_URL="https://api.knapp-seligenstadt.de/img/logov2.png"
THEME_COLOR="#76CFA6"   # bei Bedarf an dein Logo anpassen

ROOT="$(pwd)"
WEB="$ROOT/apps/web"
[ -d "$WEB" ] || { echo "Fehler: $WEB nicht gefunden (im Repo-Root ausfuehren)"; exit 1; }

command -v curl >/dev/null || { echo "curl fehlt"; exit 1; }
command -v convert >/dev/null || { echo "ImageMagick (convert) fehlt"; exit 1; }
command -v python3 >/dev/null || { echo "python3 fehlt"; exit 1; }

# ---------- Backup ----------
BACKUP="$ROOT/.rebrand-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
cp -r "$WEB/res" "$BACKUP/res" 2>/dev/null || true
cp -r "$WEB/src" "$BACKUP/src" 2>/dev/null || true
cp "$WEB/webpack.config.ts" "$BACKUP/" 2>/dev/null || true
echo "Backup: $BACKUP"

# ---------- Logo laden ----------
TMP="$(mktemp -d)"
LOGO="$TMP/logo.png"
curl -fsSL "$LOGO_URL" -o "$LOGO"
echo "Logo geladen: $(identify -format '%wx%h' "$LOGO")"

# quadratische Basis (transparent, zentriert) fuer Icons
SQUARE="$TMP/square.png"
convert "$LOGO" -background none -gravity center -resize 1024x1024 -extent 1024x1024 "$SQUARE"

# ---------- Dateien finden und ersetzen ----------
# Alle bekannten Element-Logos/Icons (PNG, SVG, ICO) im Web-Projekt
mapfile -t TARGETS < <(find "$WEB/res" "$WEB/src" \
    \( -iname '*logo*' -o -iname '*favicon*' -o -iname 'element*' -o -iname 'riot*' \
       -o -path '*vector-icons/*' -o -path '*welcome/images/*' -o -iname 'apple-touch-icon*' \
       -o -iname 'mstile*' -o -iname 'android-chrome*' -o -iname 'safari-pinned-tab*' \) \
    -type f \( -iname '*.png' -o -iname '*.svg' -o -iname '*.ico' \) 2>/dev/null | sort -u)

echo "Zu ersetzende Bilddateien: ${#TARGETS[@]}"

for f in "${TARGETS[@]}"; do
    ext="${f##*.}"
    ext="$(echo "$ext" | tr 'A-Z' 'a-z')"
    case "$ext" in
        png)
            dims="$(identify -format '%wx%h' "$f" 2>/dev/null || echo '')"
            if [ -n "$dims" ]; then
                w="${dims%x*}"; h="${dims#*x}"
                convert "$SQUARE" -background none -gravity center -resize "${w}x${h}" -extent "${w}x${h}" "$f"
            else
                cp "$SQUARE" "$f"
            fi
            ;;
        ico)
            convert "$SQUARE" -define icon:auto-resize=256,128,64,48,32,16 "$f"
            ;;
        svg)
            # SVG durch SVG mit eingebettetem PNG ersetzen (Groesse beibehalten)
            B64="$(base64 -w0 "$SQUARE")"
            cat > "$f" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="512" height="512" viewBox="0 0 512 512">
  <image width="512" height="512" xlink:href="data:image/png;base64,${B64}"/>
</svg>
EOF
            ;;
    esac
done

# ---------- Texte ersetzen (Python, JSON-sicher) ----------
python3 - "$WEB" "$BRAND" "$CALL_BRAND" "$THEME_COLOR" <<'PY'
import sys, os, re, json

web, brand, call_brand, theme = sys.argv[1:5]

def rw(path, fn):
    if not os.path.isfile(path):
        return False
    with open(path, encoding="utf-8") as fh:
        src = fh.read()
    out = fn(src)
    if out != src:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(out)
        print("angepasst:", os.path.relpath(path, web))
        return True
    return False

# Reihenfolge wichtig: laengere Begriffe zuerst
PAIRS = [
    ("Element Call", call_brand),
    ("Element Desktop", brand),
    ("Element Web", brand),
    ("Element Android", brand),
    ("Element Classic", brand),
    ("Element X", brand),
    ("Element Matrix Services", brand),
    ("Element Pro", brand),
    ("Element", brand),
    ("Riot", brand),
]

def replace_names(text):
    for old, new in PAIRS:
        text = re.sub(r"(?<![A-Za-z/_.\-])" + re.escape(old) + r"(?![A-Za-z_\-])", new, text)
    return text

# 1) HTML
for p in ("src/vector/index.html", "res/welcome.html", "res/home.html", "res/unsupported-browser.html"):
    rw(os.path.join(web, p), replace_names)

# 2) Manifest (JSON sicher)
mp = os.path.join(web, "res/manifest.json")
if os.path.isfile(mp):
    with open(mp, encoding="utf-8") as fh:
        m = json.load(fh)
    m["name"] = brand
    m["short_name"] = brand
    m["theme_color"] = theme
    with open(mp, "w", encoding="utf-8") as fh:
        json.dump(m, fh, indent=4, ensure_ascii=False)
        fh.write("\n")
    print("angepasst: res/manifest.json")

# 3) i18n JSON: nur Werte ersetzen, Keys unveraendert
def rewrite_json_values(path):
    if not os.path.isfile(path):
        return
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    def walk(o):
        if isinstance(o, dict):
            return {k: walk(v) for k, v in o.items()}
        if isinstance(o, list):
            return [walk(v) for v in o]
        if isinstance(o, str):
            return replace_names(o)
        return o
    new = walk(data)
    if new != data:
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(new, fh, indent=4, ensure_ascii=False)
            fh.write("\n")
        print("angepasst:", os.path.relpath(path, web))

for dirpath in (os.path.join(web, "src/i18n/strings"),):
    if os.path.isdir(dirpath):
        for fn in sorted(os.listdir(dirpath)):
            if fn.endswith(".json"):
                rewrite_json_values(os.path.join(dirpath, fn))

# shared-components i18n (liegt ausserhalb von apps/web)
root = os.path.abspath(os.path.join(web, "..", ".."))
sc = os.path.join(root, "packages", "shared-components", "src", "i18n", "strings")
if os.path.isdir(sc):
    for fn in sorted(os.listdir(sc)):
        if fn.endswith(".json"):
            rewrite_json_values(os.path.join(sc, fn))

# 4) Webpack / Config-Dateien: nur Anzeigenamen
for p in ("webpack.config.ts", "element.io/app/config.json", "config.sample.json"):
    rw(os.path.join(web, p), lambda s: re.sub(r'("brand"\s*:\s*)"Element"', r'\1"%s"' % brand, s))
PY

# ---------- config.sample.json / config.json Brand setzen ----------
for cfg in "$WEB/config.json" "$WEB/config.sample.json"; do
    [ -f "$cfg" ] || continue
    python3 - "$cfg" "$BRAND" "$CALL_BRAND" <<'PY'
import sys, json
p, brand, call = sys.argv[1:4]
with open(p, encoding="utf-8") as fh:
    c = json.load(fh)
c["brand"] = brand
c.setdefault("element_call", {})["brand"] = call
with open(p, "w", encoding="utf-8") as fh:
    json.dump(c, fh, indent=4, ensure_ascii=False)
    fh.write("\n")
print("brand gesetzt:", p)
PY
done

# ---------- Report ----------
echo
echo "=== Verbleibende 'Element'-Treffer (ohne node_modules, Lizenz, Importe) ==="
grep -RIn --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=webapp \
     --exclude='LICENSE*' --exclude='*.lock' --exclude='pnpm-lock.yaml' \
     --exclude='*.ts' --exclude='*.tsx' --exclude='*.js' --exclude='*.scss' \
     -i 'element' "$WEB/res" "$WEB/src/vector" "$WEB/src/i18n" 2>/dev/null | head -50 || true

echo
echo "Fertig. Backup liegt in: $BACKUP"
echo "Naechste Schritte: git diff | pnpm start (Hard-Reload im Browser)"
rm -rf "$TMP"