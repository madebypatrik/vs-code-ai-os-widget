# Claude Agent Rules

AgentPill is a macOS menu bar app (Swift 6, SwiftPM, macOS 14+) that shows when the GitHub Copilot agent in VS Code waits for the user. It receives VS Code hook events on `127.0.0.1:47823`. The sibling app ClaudePill lives in [claude-ai-os-widget](https://github.com/madebypatrik/claude-ai-os-widget) and shares the same design; keep shared behavior in sync when changing one of them.

## Commands

| Task | Command |
|---|---|
| Build | `swift build` |
| Test | `swift test` |
| Build the .app | `scripts/build-app.sh` (add `--dmg` for a disk image) |
| Install locally | `scripts/install.sh` (builds, copies to `/Applications`, login item, hooks) |
| Regenerate icon | `scripts/make-icon.sh` |
| Render UI previews | `.build/debug/AgentPill --render-previews <dir>` |
| Send a fake event | `scripts/send-test-event.sh approval` |

## Files outside the repo that the app touches

| Path | Written by | Purpose |
|---|---|---|
| `~/.agentpill/report.sh` | `--install-hooks` | Forwards hook payloads to the app |
| `~/.copilot/hooks/agentpill.json` | `--install-hooks` | Registers the hooks in VS Code |
| `/Applications/AgentPill.app` | `scripts/install.sh` | Installed app |

## Rules

- Run `swift test` before every commit. All tests must pass.
- `report.sh` must never write to stdout and must always exit 0. Hook output can reach the agent.
- The event server must stay bound to `127.0.0.1` and keep rejecting requests that carry an `Origin` header.
- Keep `AgentPillCore` free of AppKit and SwiftUI so the state machine stays unit-testable. Time is always passed in.
- Never commit personal data: no real home paths, client or project names, emails or tokens. Fixtures and previews use `/Users/dev/projects/my-app`.
- Never commit `.build/`, `build/` or `.env*` files.
- UI strings are Swedish; README and code comments are English.
- Use the git skills in `.claude/skills/` for branches, commits, pushes and PRs. Show commit messages and PRs for review before creating them.
