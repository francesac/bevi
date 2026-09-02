#!/bin/bash
# costruisci.sh — da quattro file di testo a un'app vera. Serve solo Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

NOME="Bevi"
FUORI="build/${NOME}.app"

command -v swiftc >/dev/null || {
  echo "Manca swiftc. Installalo con:  xcode-select --install"; exit 1; }

rm -rf "$FUORI"
mkdir -p "$FUORI/Contents/MacOS" "$FUORI/Contents/Resources"
cp Risorse/Info.plist "$FUORI/Contents/Info.plist"
[ -f Risorse/Bevi.icns ] && cp Risorse/Bevi.icns "$FUORI/Contents/Resources/"

echo "Compilo…"
swiftc -O -swift-version 5 \
  -target "$(uname -m)-apple-macos13.0" \
  Sorgenti/*.swift \
  -o "$FUORI/Contents/MacOS/${NOME}"

# Firma «ad-hoc»: non serve un account sviluppatore, e basta perché macOS accetti l'app
# sulla macchina dove è stata compilata. È anche la condizione per l'avvio automatico.
codesign --force --sign - --timestamp=none "$FUORI" >/dev/null 2>&1 || \
  echo "⚠️  non sono riuscito a firmarla: l'app funziona lo stesso, ma l'avvio automatico
    potrebbe non attivarsi. In quel caso aggiungila a mano in
    Impostazioni di Sistema › Generali › Elementi login."

echo "✓ Pronta: $(pwd)/${FUORI}"
