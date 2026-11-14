#!/usr/bin/env bash
# check-branding.sh: nur lesen, nichts verändern
# Aufruf im Repo-Root: bash check-branding.sh [web|android]

set -u
MODE="${1:-web}"
EXCL=(--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=build \
      --exclude-dir=.gradle --exclude-dir=.rebrand-backup-* --exclude-dir=lib \
      --exclude=pnpm-lock.yaml --exclude=yarn.lock)

section() { printf '\n=== %s ===\n' "$1"; }

# 4) Element-Dienste und Endpunkte
section "Element-Dienste (scalar, vector.im, element.io, matrix.org)"
grep -rnIE "scalar[a-z-]*\.vector\.im|vector\.im|element\.io|matrix\.org|call\.element|jitsi\.riot" \
  "${EXCL[@]}" . 2>/dev/null \
  | grep -vE "SPDX|LICENSE|Copyright|github\.com/element-hq|github\.com/vector-im|/docs?/|\.md:" \
  | head -n 200

section "Config-Felder zu Integrationen/Bugreport/Push"
grep -rnIE "integrations_(ui|rest|widgets)|bug_report_endpoint|push_gateway|sentry|posthog|piwik|analytics" \
  "${EXCL[@]}" --include=*.json --include=*.js --include=*.ts --include=*.kt --include=*.xml --include=*.properties . 2>/dev/null \
  | grep -v "node_modules" | head -n 100

# 3) Sichtbare Element-Reste
section "Sichtbare Element-Reste (Texte, Titel, Manifeste)"
grep -rnIE "\bElement\b" \
  "${EXCL[@]}" --include=*.html --include=*.json --include=*.xml --include=*.webmanifest . 2>/dev/null \
  | grep -vE "SPDX|LICENSE|Copyright|createElement|querySelector|DOM|React\.|HTMLElement|PersistedElement" \
  | head -n 200

section "Logo- und Icon-Dateien mit Element-Bezug"
find . \( -path ./node_modules -o -path ./.git \) -prune -o -type f \
  \( -iname "*element*" -o -iname "*riot*" -o -iname "*vector*" \) \
  \( -iname "*.png" -o -iname "*.svg" -o -iname "*.ico" -o -iname "*.webp" -o -iname "*.xml" \) -print 2>/dev/null | head -n 100

if [ "$MODE" = "android" ]; then
  # 2) Package-ID und App-Name
  section "Android: applicationId, namespace, Package-IDs"
  grep -rnIE "applicationId|namespace\s*=|io\.element\.|im\.vector\." \
    "${EXCL[@]}" --include=*.kts --include=*.gradle --include=*.xml --include=*.toml --include=*.pro . 2>/dev/null \
    | head -n 200

  section "Android: App-Name und Strings"
  grep -rnIE "name=\"app_name\"|android:label" \
    "${EXCL[@]}" --include=strings.xml --include=AndroidManifest.xml . 2>/dev/null | head -n 50

  section "Android: Firebase/Google-Services/Deeplinks"
  find . -name "google-services.json" -not -path "*/node_modules/*" 2>/dev/null
  grep -rnIE "app\.element\.io|mobile\.element\.io|element://|io\.element" \
    "${EXCL[@]}" --include=AndroidManifest.xml . 2>/dev/null | head -n 50
else
  section "Web: Manifest, Titel, PWA"
  grep -nE "\"(name|short_name)\"" apps/web/res/manifest.json 2>/dev/null
  grep -nE "<title>|apple-mobile-web-app-title|application-name" apps/web/src/vector/index.html 2>/dev/null
  section "Web: apple-app-site-association / assetlinks (Element-App-IDs)"
  grep -rnIE "io\.element" apps/web/res 2>/dev/null | head -n 20
fi

section "Fertig"
echo "Treffer manuell prüfen. Technische Bezeichner (CSS-Klassen mx_*, Importe) können bleiben."
