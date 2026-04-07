# CLAUDE.md — lucid

## What is this project?

`lucid` is a CLI tool + Vim 9 plugin that explains git diffs using AI. When developers use AI coding tools (Claude Code, Amp, Cursor, etc.) to generate code, they end up with changes they didn't write. `lucid` explains those changes top-down — like a teammate walking you through a PR — so developers stay in control of their codebase.

It is **not** a diff viewer. It is an **explainer**. The output is structured, human-friendly explanations grouped by intent, not hunk-by-hunk raw diffs.

## Tech stack

- **Go** for the CLI
- **Vim9script** for the Vim 9 plugin
- No frameworks. Standard library + minimal dependencies.

## Architecture

Two parts:
1. **Go CLI** (`lucid`) — reads a diff from stdin, sends it to an LLM, outputs a structured top-down explanation as JSON or pretty-printed terminal output.
2. **Vim9script plugin** — calls the Go binary via `job_start()`, displays results using popup windows and text properties.

The LLM backend is pluggable via an interface. Users configure which provider they want in `~/.lucid.yaml`.

---

## Implementation Plan

### Phase 1: Project scaffold

Create the Go module and directory structure:

```
lucid/
├── cmd/lucid/main.go
├── internal/
│   ├── diff/parser.go
│   ├── explain/
│   │   ├── explainer.go
│   │   ├── prompt.go
│   │   └── claude.go
│   ├── model/types.go
│   └── output/
│       ├── terminal.go
│       └── json.go
├── config/config.go
├── vim/
│   ├── plugin/lucid.vim
│   └── autoload/lucid.vim
├── go.mod
└── README.md
```

- Initialize Go module: `github.com/lunar/lucid` (or whatever org).
- No external dependencies yet. Use `net/http` for API calls, `encoding/json` for parsing.
- Create a `Makefile` with `build`, `test`, `install` targets.

### Phase 2: Core types

Define the data model in `internal/model/types.go`:

```go
package model

type Explanation struct {
    Summary      string        `json:"summary"`
    IntentGroups []IntentGroup `json:"intent_groups"`
    Stats        DiffStats     `json:"stats"`
}

type IntentGroup struct {
    Intent      string       `json:"intent"`
    Description string       `json:"description"`
    Files       []FileChange `json:"files"`
    Risk        string       `json:"risk"`
}

type FileChange struct {
    Path    string `json:"path"`
    Summary string `json:"summary"`
    Hunks   []Hunk `json:"hunks"`
}

type Hunk struct {
    StartLine  int    `json:"start_line"`
    EndLine    int    `json:"end_line"`
    RawDiff    string `json:"raw_diff"`
    Annotation string `json:"annotation"`
}

type DiffStats struct {
    FilesChanged int `json:"files_changed"`
    Additions    int `json:"additions"`
    Deletions    int `json:"deletions"`
}
```

### Phase 3: Diff parser

Implement `internal/diff/parser.go`.

- Read unified diff format from stdin.
- Parse into a structured representation: list of files, each with a list of hunks.
- Extract file paths from `--- a/` and `+++ b/` lines.
- Extract hunk headers from `@@ -n,n +n,n @@` lines.
- Count additions (`+` lines) and deletions (`-` lines) for stats.
- Return a `ParsedDiff` struct that the explainer can consume.
- Handle edge cases: new files, deleted files, renamed files, binary files.

Write tests using real diff samples. Create a `testdata/` directory with sample diffs:
- `testdata/simple.diff` — a small one-file change
- `testdata/multifile.diff` — changes across 3-4 files
- `testdata/newfile.diff` — includes a new file
- `testdata/rename.diff` — a renamed file

### Phase 4: Explainer interface + Claude backend

Define the interface in `internal/explain/explainer.go`:

```go
package explain

type Explainer interface {
    Explain(ctx context.Context, diff string) (*model.Explanation, error)
}
```

Implement the Claude backend in `internal/explain/claude.go`:
- Use the Anthropic Messages API (`https://api.anthropic.com/v1/messages`).
- Model: `claude-sonnet-4-20250514`.
- Send the diff with a system prompt that asks for a structured JSON response.
- Parse the response into `model.Explanation`.
- Handle errors: rate limits, auth failures, context too long.
- If the diff is very large (>100KB), consider summarizing or chunking.

### Phase 5: Prompt engineering

This is the most important part. The prompt lives in `internal/explain/prompt.go`.

The system prompt should instruct the LLM to:

1. First provide a 1-2 sentence summary of the entire change.
2. Group changes by **intent** (what the developer was trying to achieve), not by file or hunk.
3. For each intent group, list which files are involved and why.
4. Assign a risk level (low/medium/high) based on whether the change touches error handling, concurrency, auth, data mutations, public APIs, etc.
5. Respond ONLY in JSON matching the `Explanation` struct schema.

Include the JSON schema in the prompt so the LLM knows exactly what to produce.

Do NOT ask for hunk-level annotations by default — those are only for `--level full`.

The prompt should also receive context about the programming language (infer from file extensions in the diff) to give language-aware explanations (e.g., Go interface satisfaction, goroutine safety).

### Phase 6: Config

Implement `config/config.go`:

- Load from `~/.lucid.yaml` (use `os.UserHomeDir()`).
- Support environment variable expansion for API keys: `${ANTHROPIC_API_KEY}`.
- Fall back to env vars directly if no config file: `LUCID_BACKEND`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`.
- Config struct:

```go
type Config struct {
    Backend string       `yaml:"backend"`
    Claude  ClaudeConfig `yaml:"claude"`
    OpenAI  OpenAIConfig `yaml:"openai"`
    Ollama  OllamaConfig `yaml:"ollama"`
}
```

- Use a small YAML parser. `gopkg.in/yaml.v3` is fine as the one external dependency.

### Phase 7: CLI entry point

Implement `cmd/lucid/main.go`:

- Read diff from stdin. If stdin is a terminal (no pipe), print usage and exit.
- Flags:
  - `--backend` — override config file backend
  - `--format` — `terminal` (default) or `json`
  - `--level` — `summary`, `default`, or `full`
  - `--config` — path to config file
- Flow: read stdin → parse diff → select backend → call Explain() → format output → print.
- Keep it simple. No cobra or fancy CLI framework. Use `flag` from stdlib.

### Phase 8: Terminal output

Implement `internal/output/terminal.go`:

- Pretty-print the `Explanation` struct to the terminal.
- Use ANSI colors (detect if terminal supports them with `os.Getenv("TERM")`).
- Summary at the top in a box.
- Numbered intent groups with risk level color-coded (green/yellow/red).
- File list indented under each group.
- For `--level full`, show hunk annotations inline.
- Keep it readable at 80 columns.

### Phase 9: JSON output

Implement `internal/output/json.go`:

- Simply marshal `model.Explanation` to JSON.
- Use `json.MarshalIndent` for human-readable output.
- This is what the Vim plugin consumes.

### Phase 10: OpenAI backend

Implement `internal/explain/openai.go`:

- Same interface, same prompt, different API call.
- Use the OpenAI Chat Completions API.
- Model: `gpt-4o`.
- This proves the pluggable backend works.

### Phase 11: Vim 9 plugin

Implement the Vim9script plugin in `vim/`:

**`vim/plugin/lucid.vim`** — entry point:
- Guard: check for Vim 9 (`has('vim9script')` and `v:version >= 900`).
- Define commands: `:Lucid`, `:LucidSummary`, `:LucidFull`.
- Define keybindings under `<leader>l`.

**`vim/autoload/lucid.vim`** — core logic:
- `Run(level)` — calls `git diff | lucid --format json --level {level}` via `job_start()`.
- Collects stdout into a buffer via `out_cb`.
- On `exit_cb`, parses the JSON with `json_decode()`.
- Shows the summary in a `popup_create()` at the center of the screen.
- Lists intent groups as selectable items.
- When user selects a group (press 1, 2, 3...), shows that group's detail in a new popup or split.
- `]g` / `[g` to navigate between intent groups.
- `q` to close.

Keep the Vim plugin minimal. All intelligence is in the Go binary.

### Phase 12: Testing & demo prep

- Write Go unit tests for the diff parser.
- Write integration tests that use a mock LLM backend (returns canned responses).
- Create 2-3 real-world demo diffs from actual AI-generated code changes.
- Prepare a 2-minute demo flow:
  1. Show a messy multi-file diff in the terminal.
  2. Run `git diff | lucid` — show the top-down explanation.
  3. Open Vim, run `:Lucid` — show the popup summary.
  4. Drill into an intent group.
  5. Switch backend with `--backend openai` to show pluggability.

---

## Coding conventions

- Go: use standard `gofmt`, no linter exceptions.
- Error handling: wrap errors with context using `fmt.Errorf("parsing diff: %w", err)`.
- No global state. Pass config and dependencies explicitly.
- Tests go next to the code: `parser_test.go` alongside `parser.go`.
- Vim9script: follow `:h vim9script` conventions. Use `def` not `function`, typed variables.

## What NOT to build

- No diff viewer — Vim already has `:diffthis`. This tool explains, it doesn't show.
- No git integration beyond reading stdin — don't shell out to git from Go.
- No TUI framework — keep terminal output simple print statements with ANSI.
- No web UI.
- No Neovim support (for now) — this is deliberately Vim 9 first.

## Dependencies

- `gopkg.in/yaml.v3` — config parsing. The only external Go dependency.
- Everything else is Go standard library.

## Environment variables

- `ANTHROPIC_API_KEY` — for Claude backend
- `OPENAI_API_KEY` — for OpenAI backend
- `LUCID_BACKEND` — override default backend
- `LUCID_CONFIG` — override config file path

