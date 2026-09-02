#!/bin/bash
# installa.sh — costruisce l'app, la mette fra le Applicazioni e la accende.
set -euo pipefail
cd "$(dirname "$0")"

./costruisci.sh

DESTINAZIONE="$HOME/Applications"
mkdir -p "$DESTINAZIONE"

# se sta girando, si spegne prima di essere sostituita
pkill -x Bevi 2>/dev/null && sleep 1 || true

rm -rf "$DESTINAZIONE/Bevi.app"
cp -R build/Bevi.app "$DESTINAZIONE/Bevi.app"
open "$DESTINAZIONE/Bevi.app"

echo
echo "✓ Bevi è nella barra in alto, accanto all'orologio."
echo "  Vive in: $DESTINAZIONE/Bevi.app"
echo "  Per farla partire da sola quando accendi il Mac: clic sulla goccia →"
echo "  «Parti all'avvio del Mac»."
