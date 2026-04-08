# CLAUDE.md — lucid

## What is this project?

`lucid` is a CLI tool + Vim 9 plugin that helps developers review git diffs they didn't write. It groups changes by intent, assigns risk levels, and tells the reviewer what to verify — like a senior teammate walking you through a PR.

It is **not** a diff viewer. It is a **reviewer's assistant**.

## Tech stack

- **POSIX shell** for the CLI (delegates to `claude` CLI for LLM calls)
- **Vim9script** for the Vim 9 plugin
- No frameworks. No dependencies beyond `claude` CLI.

## Architecture

The `claude` CLI is already installed and authenticated. We don't need API keys, HTTP clients, or config files. The prompt is the product.

```
lucid/
├── lucid                      # POSIX shell script — the CLI
├── plugin/lucid.vim           # commands, keybindings, g:lucid_bin path resolution
├── autoload/lucid.vim         # explain, chat, fugitive integration
├── Makefile                   # install/uninstall/test
└── README.md
```

**Shell CLI** (`lucid`) — resolves a diff (auto-detect, commit, PR, file), caches responses, sends to `claude -p` with a review-oriented prompt, outputs text or JSON.

**Vim plugin** — integrates with vim-fugitive's `:Git` buffer. Adds `e` (explain file) and `x` (mark reviewed ✓) keybindings. Provides an explain buffer for AI output and a chat buffer for questions with accumulated code context. Uses `g:lucid_bin` to call the CLI from the plugin's own repo directory — no PATH install needed.

## CLI flags

```
lucid                       # auto-detect: staged > unstaged > untracked > last commit
lucid <commit>              # explain a specific commit
lucid <commit>..<commit>    # explain a range
lucid --pr 123              # explain a GitHub PR (requires gh)
git diff ... | lucid        # pipe mode

--format       terminal | json
--level        summary | default | full
--file         explain one file's changes only
--list         list changed files with stats (no LLM, instant)
--ask          ask a question about the diff
--context      inline code context
--context-file read context from file
--prompt       path to custom prompt file
--no-cache     skip ~/.cache/lucid/ cache
--clear-cache  delete all cached responses
```

## Vim plugin

**Requires:** Vim 9.0+, vim-fugitive

**In `:Git` buffer:**
- `e` — explain file under cursor (AI)
- `x` — toggle reviewed ✓ sign
- All other fugitive keybindings work normally

**Commands:**
- `:Lucid` — open `:Git` + AI summary
- `:LucidExplain` — explain file under cursor
- `:LucidPR 123` — explain a GitHub PR
- `:LucidChat` — open chat buffer for questions
- `:LucidClear` — clear accumulated context
- `:LucidComments` — list collected PR comments
- `:LucidSubmitReview` — post comments to GitHub PR
- `:LucidClearComments` — discard collected comments
- `:LucidClearCache` — delete all cached responses
- `:LucidLog` — debug output

**Keybindings (leader = `\`):**
- `\ll` — `:Lucid`
- `\le` — explain file (normal) or selection (visual)
- `\la` — add visual selection to chat context
- `\lc` — open chat
- `\ln` — add comment on current line

**In chat:** type on `> ` prompt line, `Enter` to send, `q` to close.

**PR review workflow:**
- Quick: `:LucidPR 42` for overview
- Deep: `gh pr checkout 42`, then `:Git` → `e` to explain → `x` to mark reviewed
- Comments: `\ln` to annotate lines → `:LucidSubmitReview` to post to GitHub

## Prompt philosophy

The prompt is the core product. It instructs the LLM to act as a senior code reviewer:

1. **Group by intent**, not by file.
2. **Review guidance over description** — every sentence either explains what changed or tells the reviewer what to verify.
3. **Risk levels** signal where to focus attention.
4. **Flag suspicious patterns** — missing error handling, auth gaps, untested paths.
5. **Be terse** — no filler, no preamble.

## Custom prompts

Users customize review focus by creating `~/.config/lucid/prompt.txt`. This is appended to the built-in system prompt. Per-project override with `--prompt` flag or `LUCID_PROMPT` env var.

## Cache

Responses cached in `~/.cache/lucid/<hash>.json`. Key = md5(diff + level). `--no-cache` to bypass. `--clear-cache` to wipe.

## Coding conventions

- Shell: POSIX sh, no bashisms. `set -e`. Quote variables.
- Vim9script: `def` not `function`, typed variables, `:h vim9script` conventions.
- Named `def` callbacks for `job_start()` — Vim9 lambdas can't mutate script-level vars with `..=`.
- Plugin resolves CLI path via `g:lucid_bin` — no PATH dependency.

## What NOT to build

- No diff viewer — Vim has `:diffthis`.
- No API key management — `claude` CLI handles auth.
- No config file format — custom prompts are plain text, everything else is flags.
- No TUI framework — fugitive is the file browser.
- No web UI.
- No Neovim support (for now) — Vim 9 first.
