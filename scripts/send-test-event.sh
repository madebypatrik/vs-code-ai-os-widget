#!/bin/bash
# Simulerar hook-events mot AgentPill utan VS Code.
#   scripts/send-test-event.sh approval   # PreToolUse som blir hängande -> "Väntar"
#   scripts/send-test-event.sh flow       # hela flödet: prompt -> verktyg -> godkännande -> klart
#   scripts/send-test-event.sh <Event> [session] [cwd]   # enskilt event
set -euo pipefail
PORT="${AGENTPILL_PORT:-47823}"
URL="http://127.0.0.1:$PORT/event"
SESSION="${2:-test-1}"
CWD="${3:-$HOME/projects/my-app}"

send() {
  echo "-> $1"
  curl -s -X POST "$URL" -H "Content-Type: application/json" -d "$2"; echo
}

event() { # name [tool] [command]
  local tool="${2:-}" cmd="${3:-}"
  local extra=""
  [[ -n "$tool" ]] && extra=",\"tool_name\":\"$tool\",\"tool_input\":{\"command\":\"$cmd\"}"
  send "$1" "{\"hook_event_name\":\"$1\",\"session_id\":\"$SESSION\",\"cwd\":\"$CWD\"$extra}"
}

case "${1:-flow}" in
  approval)
    event UserPromptSubmit
    event PreToolUse run_in_terminal "npm run build"
    echo "Vänta ~3 s – pillen ska bli orange (Väntar)." ;;
  flow)
    event UserPromptSubmit; sleep 2
    event PreToolUse read_file; sleep 0.3
    event PostToolUse read_file; sleep 1
    event PreToolUse run_in_terminal "npm run build"
    echo "Väntar på godkännande i 8 s…"; sleep 8
    event PostToolUse run_in_terminal "npm run build"; sleep 2
    event Stop
    echo "Klart – pillen ska vara grön (Din tur)." ;;
  health)
    curl -s "http://127.0.0.1:$PORT/health"; echo ;;
  *)
    event "$1" "${4:-}" "${5:-}" ;;
esac
