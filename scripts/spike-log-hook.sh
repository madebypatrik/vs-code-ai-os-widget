#!/bin/bash
# Milstolpe 0: loggar rå hook-stdin till ~/agentpill-spike.log för alla fyra event.
#   scripts/spike-log-hook.sh install | uninstall
set -euo pipefail
DIR="$HOME/.agentpill"
SCRIPT="$DIR/spike-log.sh"
HOOKS="$HOME/.copilot/hooks/agentpill-spike.json"

case "${1:-install}" in
  install)
    mkdir -p "$DIR" "$(dirname "$HOOKS")"
    cat > "$SCRIPT" <<'SH'
#!/bin/bash
# AgentPill spike: logga payload med tidsstämpel. Skriver aldrig till stdout.
{ printf '\n=== %s ===\n' "$(perl -MPOSIX -MTime::HiRes=time -e '$t=time; print strftime("%Y-%m-%dT%H:%M:%S", localtime $t), sprintf(".%03d", ($t-int $t)*1000)')"; cat; } >> "$HOME/agentpill-spike.log" 2>/dev/null
exit 0
SH
    chmod +x "$SCRIPT"
    cat > "$HOOKS" <<JSON
{
  "version": 1,
  "hooks": {
    "UserPromptSubmit": [{ "type": "command", "command": "$SCRIPT", "timeoutSec": 2 }],
    "PreToolUse":       [{ "type": "command", "command": "$SCRIPT", "timeoutSec": 2 }],
    "PostToolUse":      [{ "type": "command", "command": "$SCRIPT", "timeoutSec": 2 }],
    "Stop":             [{ "type": "command", "command": "$SCRIPT", "timeoutSec": 2 }]
  }
}
JSON
    echo "Spike-hook installerad. Kör en chatt i VS Code, sedan: tail -f ~/agentpill-spike.log" ;;
  uninstall)
    rm -f "$HOOKS" "$SCRIPT"
    echo "Spike-hook borttagen (loggen ~/agentpill-spike.log finns kvar)." ;;
esac
