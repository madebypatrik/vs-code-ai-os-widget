#!/bin/bash
# AgentPill: skickar hook-payload till AgentPill. Får ALDRIG skriva till stdout.
# (Referenskopia – appen skriver ~/.agentpill/report.sh själv via HookInstaller.)
curl -s -m 1 -X POST \
  -H "Content-Type: application/json" \
  --data-binary @- \
  http://127.0.0.1:47823/event >/dev/null 2>&1
exit 0
