# lucid

A code review assistant for Vim. Like a teammate walking you through a PR.

When AI tools generate code, you get diffs you didn't write. `lucid` explains them — grouped by intent, with a diagram of how components connect, a review order, and a checklist of what to verify.

## What it does

For any git diff, `lucid` gives you:

- **Summary** — one sentence, what changed and why
- **Verdict** — where to focus your attention
- **Diagram** — ASCII flow showing how changed components connect
- **Review order** — which files to read first (by risk)
- **Intent groups** — changes grouped by purpose, not by file
- **Checklist** — specific things to verify, test, or question

The tone is casual and direct — like a sharp teammate at a desk, not a formal report.

### Example

```
Summary:
  Adds notification retry with outbox pattern,
  paginates user processing, fixes double-counting.

Verdict:
  Focus on the SQL changes and retry logic — easy
  to get wrong.

Diagram:
  [cron] ──► RunOnce
               ├─► processUsers (batched)
               │     └─► emit ──► notify
               └─► RetryFailed
                     └─► notify (retry)

Review order:
  1. repository.go
  2. service.go
  3. config.yaml

[1] Notification retry with outbox  (high risk)
  Replaces async event consumer with direct calls.
  Adds outbox columns and retry cron.

Checklist:
  [ ] Test pagination with empty cursor
  [ ] Check SQL bind parameter order
  [ ] Confirm schedule change is intentional
```

## Install

Requires [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI and [vim-fugitive](https://github.com/tpope/vim-fugitive).

### Vim plugin

Add to your `.vimrc`:

```vim
Plug 'ivanpaulovich/lucid'
```

Run `:PlugInstall`. No other setup needed — the plugin finds the bundled script automatically.

### CLI (optional)

For terminal use outside Vim:

```sh
sudo make install              # /usr/local/bin
make install PREFIX=~/.local   # without sudo
```

## Usage

### In Vim (recommended)

Open `:Git` (fugitive) to see your changed files, then:

| Key | Action |
|-----|--------|
| `e` | Explain file under cursor |
| `x` | Mark file as reviewed ✓ |
| `\ln` | Add comment on current line 💬 |
| `\ls` | Overview of the whole diff |
| `\le` | Explain current file (from any buffer) |
| `\lc` | Open chat |
| `\la` | Add visual selection to chat context |

### PR review

```
:LucidPR 42             → AI overview of the PR
```

Or for a deep review:

```sh
gh pr checkout 42        # get the code
```
```
:Git                     → see files
e                        → explain each file
x                        → mark reviewed ✓
\ln                      → comment on a line
:LucidSubmitReview       → post comments to GitHub
```

### Chat

Build up context from multiple files, then ask questions:

```
1. Select code     → \la   (adds to context)
2. More code       → \la   (accumulates)
3. Open chat       → \lc
4. Type question   → Enter
```

### CLI

```sh
lucid                         # auto-detect and explain
lucid HEAD~3                  # explain last 3 commits
lucid main..feature           # explain a branch
lucid --pr 42                 # explain a GitHub PR
lucid --file server.go        # explain one file
lucid --ask "is this safe?"   # ask about the diff
lucid --list                  # list changed files (instant)
```

### All commands

| Command | Description |
|---------|-------------|
| `:LucidExplain` | Explain file under cursor |
| `:LucidSummary` | Explain the whole diff |
| `:LucidPR 123` | Explain a GitHub PR |
| `:LucidChat` | Open chat buffer |
| `:LucidClear` | Clear chat context |
| `:LucidComments` | List collected PR comments |
| `:LucidSubmitReview` | Post comments to GitHub PR |
| `:LucidClearComments` | Discard collected comments |
| `:LucidClearCache` | Delete cached responses |
| `:LucidLog` | Debug output |

### All flags

| Flag | Description |
|------|-------------|
| `--format` | `terminal` (default) or `json` |
| `--level` | `summary`, `default`, or `full` |
| `--file` | Explain one file only |
| `--ask` | Ask a question about the diff |
| `--context` | Inline code context |
| `--context-file` | Read context from a file |
| `--list` | List changed files (no LLM) |
| `--no-cache` | Force fresh LLM call |
| `--clear-cache` | Delete all cached responses |
| `--prompt` | Custom prompt file |
| `--pr N` | Explain a GitHub PR |

## Custom prompts

Tailor reviews to your codebase:

```sh
mkdir -p ~/.config/lucid
cat > ~/.config/lucid/prompt.txt << 'EOF'
Focus on:
- All SQL must use parameterized statements
- Flag any new dependencies
- New API endpoints need auth middleware
- Check error handling in Go (no silent swallows)
EOF
```

Per-project: `lucid --prompt .lucid-prompt.txt` or `export LUCID_PROMPT=path`.

## How it works

`lucid` is a ~350 line shell script. It resolves a git diff, builds a review-oriented prompt, and pipes it to `claude -p`. Responses are cached in `~/.cache/lucid/`.

No API keys. No config files. No HTTP client. No dependencies beyond `claude` CLI. The prompt is the product.

## License

MIT
