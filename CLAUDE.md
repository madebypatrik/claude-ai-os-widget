# Claude Agent Rules

ClaudePill is a macOS menu bar app (Swift 6, SwiftPM, macOS 14+) that shows which Claude Code sessions are working and which one waits for the user. It receives Claude Code hook events on `127.0.0.1:47824`. The sibling app AgentPill lives in [vs-code-ai-os-widget](https://github.com/madebypatrik/vs-code-ai-os-widget) and shares the same design; keep shared behavior in sync when changing one of them.

## Commands

| Task | Command |
|---|---|
| Build | `swift build` |
| Test | `swift test` |
| Build the .app | `scripts/build-app.sh` (add `--dmg` for a disk image) |
| Install locally | `scripts/install.sh` (builds, copies to `/Applications`, login item, hooks) |
| Regenerate icon | `scripts/make-icon.sh` |
| Render UI previews | `.build/debug/ClaudePill --render-previews <dir>` |
| Send fake events | `scripts/send-test-event.sh flow` |

## Files outside the repo that the app touches

| Path | Written by | Purpose |
|---|---|---|
| `~/.claudepill/report.sh` | `--install-hooks` | Forwards hook payloads to the app |
| `~/.claude/settings.json` | `--install-hooks` | Hook entries are merged in; existing hooks are kept |
| `~/.claude/settings.json.claudepill.bak` | `--install-hooks` | Backup taken before the first change |
| `/Applications/ClaudePill.app` | `scripts/install.sh` | Installed app |

## Rules

- Run `swift test` before every commit. All tests must pass.
- The hook installer must never overwrite a `settings.json` it cannot parse, and must only touch hook groups whose command contains `/.claudepill/report.sh`. When testing the installer, point it at a copy with `CLAUDEPILL_HOME`.
- `report.sh` must never write to stdout and must always exit 0. Hook output is injected into Claude's context.
- The event server must stay bound to `127.0.0.1` and keep rejecting requests that carry an `Origin` header.
- Keep `ClaudePillCore` free of AppKit and SwiftUI so the state machine stays unit-testable. Time is always passed in.
- Never commit personal data: no real home paths, client or project names, emails or tokens. Fixtures and previews use `/Users/dev/projects/my-app`.
- Never commit `.build/`, `build/` or `.env*` files.
- UI strings are Swedish; README and code comments are English.
- Use the git skills in `.claude/skills/` for branches, commits, pushes and PRs. Show commit messages and PRs for review before creating them.
