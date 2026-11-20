#!/bin/bash
# Bygger ClaudePill, installerar i /Applications, slår på "starta vid inloggning" och startar appen.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
pkill -x ClaudePill 2>/dev/null || true
sleep 0.5
rm -rf /Applications/ClaudePill.app
cp -R build/ClaudePill.app /Applications/ClaudePill.app
/Applications/ClaudePill.app/Contents/MacOS/ClaudePill --register-login-item
/Applications/ClaudePill.app/Contents/MacOS/ClaudePill --install-hooks
open /Applications/ClaudePill.app
echo "Installerad: /Applications/ClaudePill.app"
