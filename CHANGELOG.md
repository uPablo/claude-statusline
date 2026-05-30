# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/), and the project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-05-30

### Added
- **4-line status line** for Claude Code: code · session · usage limits · system.
- **Framed Unicode progress bars** (`▕▰▱▏`) with one color per metric.
- **Usage limits** with countdown *and* absolute reset time: 5-hour, weekly, and per-model (Opus / Sonnet).
- **Context window**: percentage, exact token count (from `current_usage`), and prompt-cache hit %.
- **Burn rate ($/h)** and **daily spend** via `ccusage` (cached 60s).
- **Git**: branch, commit-readiness (`●N`/`✓`), ahead/behind, stash count, in-progress state (MERGE/REBASE/…), and `owner/repo`.
- **Multi-language auto-detect** with emoji + real version: ⬢ node · 🐘 php · 🐍 python · 🐹 go · 💎 ruby · 🦀 rust · 🥟 bun · 🦕 deno. Node honors project pin or nvm default. Cached per directory.
- **System**: memory, free disk, battery (+charging), CPU load, clock.
- Session info: model, thinking effort, session cost/duration, lines changed, output style, vim mode, Claude Code version, account email.
- **Portable Bash** (`status-line.sh`) — macOS, Linux, and Windows via Git Bash / WSL (OS detection for memory, battery, CPU, date, stat, paths).
- **Native PowerShell** build (`windows/status-line.ps1`) for Windows without Bash.
- Installers (`install.sh`, `windows/install.ps1`).

[1.0.0]: https://github.com/uPablo/claude-statusline/releases/tag/v1.0.0
