#!/bin/bash
# Bygger AgentPill, installerar i /Applications, slår på "starta vid inloggning" och startar appen.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
pkill -x AgentPill 2>/dev/null || true
sleep 0.5
rm -rf /Applications/AgentPill.app
cp -R build/AgentPill.app /Applications/AgentPill.app
/Applications/AgentPill.app/Contents/MacOS/AgentPill --register-login-item
/Applications/AgentPill.app/Contents/MacOS/AgentPill --install-hooks
open /Applications/AgentPill.app
echo "Installerad: /Applications/AgentPill.app"
