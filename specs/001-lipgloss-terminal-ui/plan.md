# Implementation Plan: Lipgloss Terminal UI Redesign

**Branch**: `001-lipgloss-terminal-ui` | **Date**: 2026-06-02 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/001-lipgloss-terminal-ui/spec.md`

---

## Summary

Replace testprune's plain-text terminal output with a rich, styled UI built on
`lipgloss-ruby`. Key changes: (1) scan suppresses raw output by default and
shows a spinner/progress display with non-blocking error indicator and a
post-scan error toggle, (2) report is rendered with colored confidence badges
and bordered sections, (3) apply uses a styled confirmation prompt and success
box, (4) prune gets a ✂️ header and labeled phase transitions.

---

## Technical Context

**Language/Version**: Ruby ≥ 3.2 (matches existing `required_ruby_version`)
**Primary Dependencies**: `lipgloss` (new runtime dep), `prism` ≥ 1.0 < 3 (existing)
**Storage**: File-based (`.testprune/run.json`, `removal.patch`) — unchanged
**Testing**: Minitest (existing `test/integration_test.rb` + unit tests)
**Target Platform**: macOS + Linux TTY; CI (degrades to plain text via `NO_COLOR`)
**Project Type**: Ruby gem / CLI tool
**Performance Goals**: Spinner refresh ≤ 100 ms; no measurable overhead on scan
**Constraints**: Must not break `--json` flag (raw JSON output unchanged); no new mandatory deps beyond `lipgloss`
**Scale/Scope**: Single gem with ~20 lib files; changes touch ~6 files + new `lib/testprune/ui/` module

---

## Constitution Check

### Gate I — Safety Is Non-Negotiable
✅ No changes to analysis, safety check, or coverage logic. UI layer is purely
presentational.

### Gate II — Human-in-the-Loop for Every Patch
✅ `cmd_apply` still requires `y/N` approval. The styled prompt replaces the
bare `print` call but preserves the requirement. The summary box now shows the
confirmation clearly.

### Gate III — Confidence Gradation and Honest Signaling
✅ HIGH / MEDIUM / LOW tiers are preserved. Styled badges make tiers MORE
visible, not less. AUTO-PATCH eligibility rules unchanged.

### Gate IV — Non-Destructive Output Only
✅ No file write logic changes. Patch path unchanged.

### Gate V — Semantic Precision via Prism AST
✅ No changes to `SemanticMap`, `DuplicationDetector`, or coverage collection.

**Verdict**: No constitution violations. No Complexity Tracking required.

---

## Project Structure

### Documentation (this feature)

```text
specs/001-lipgloss-terminal-ui/
├── plan.md              ← this file
├── research.md          ← Phase 0 output
├── data-model.md        ← Phase 1 output
├── preview.svg          ← UI mockup (existing)
├── contracts/
│   └── ui-contracts.md  ← CLI output contracts
└── tasks.md             ← /speckit-tasks output (not yet)
```

### Source Code (new + modified)

```text
lib/testprune/
├── ui/                        ← NEW module
│   ├── styles.rb              ← centralized lipgloss style palette
│   ├── progress.rb            ← live scan spinner + counter + elapsed
│   ├── report_renderer.rb     ← styled replacement for Report#render_text
│   └── error_toggle.rb        ← post-scan error expand/collapse prompt
├── cli.rb                     ← MODIFIED: --verbose flag, styled apply prompt/summary
├── report.rb                  ← MODIFIED: delegate render_text → UI::ReportRenderer
├── runner.rb                  ← MODIFIED: capture output, drive progress display
└── testprune.gemspec          ← MODIFIED: add lipgloss runtime dep

test/
├── ui/
│   ├── styles_test.rb
│   ├── report_renderer_test.rb
│   └── progress_test.rb
└── integration_test.rb        ← EXTENDED: verify --verbose and NO_COLOR behavior
```

---

## Phase 0: Research

*Resolved via codebase reading, lipgloss-ruby README, and Ruby stdlib.*

### R-1: lipgloss-ruby API surface

**Decision**: Use `Lipgloss::Style.new.foreground(hex).bold(true).border(:rounded).padding(v, h).render(text)`.
**Border types available**: `:normal`, `:rounded`, `:thick`, `:double`, `:hidden`, `:block`, `:ascii`.
**Layout**: `Lipgloss.join_horizontal(:top, a, b)`, `Lipgloss.join_vertical(:center, a, b)`.
**Color types**: hex string, `Lipgloss::AdaptiveColor.new(light:, dark:)`, `Lipgloss::CompleteColor`.
**Rationale**: The API is a clean Ruby wrapper over charmbracelet/lipgloss (Go). Styles are
immutable value objects; chaining returns new instances. This fits our use case of a shared
palette of reusable style constants.
**NO_COLOR support**: lipgloss-ruby inherits the underlying Go library's `NO_COLOR` / non-TTY
detection and strips ANSI when appropriate. We additionally guard on `$stdout.tty?` to skip
the styled path entirely when piped.

### R-2: Capturing subprocess output while showing progress

**Decision**: Use `Open3.popen2e` to merge stdout+stderr into one stream, read line-by-line
in a Thread, and buffer all output. The main thread runs a polling loop (sleep 0.1 s) driving
the spinner. A shared counter tracks test progress by scanning each line for Minitest dot
patterns (`.`, `F`, `E`, `S`) and RSpec progress chars.

**Progress counter strategy**:
- Minitest: first line matching `/Run options/` gives the run command context; dot chars `.FES`
  in subsequent progress lines each represent one test.
- RSpec: similar (`.`, `*`, `F`, `P`).
- Total: parsed from `run.json` **after** completion (not needed during spin).

**Why not PTY?**: `pty` is a stdlib module but adds complexity (line-discipline handling).
`Open3.popen2e` is sufficient since we only need the data, not interactive control.

**Fallback**: If `Open3` or threading fails, fall back to `system()` (current behavior).

### R-3: Single-character input for error toggle

**Decision**: Use `$stdin.gets` (line-buffered, requires Enter). Prompt reads `[e + Enter] show errors  [Enter] skip`.

**Rationale**: Single-char input requires raw terminal mode (`stty raw`) which is fragile
across platforms and not worth the complexity for a secondary feature. Requiring Enter is
the standard Ruby CLI convention and consistent with how we handle the apply `[y/N]` prompt.
The UX cost is minimal.

### R-4: Spinner mechanics

**Decision**: Braille spinner frames `%w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏]`, refreshed via `\r` (carriage
return) to overwrite the current line. Elapsed time formatted as `MM:SS`. All progress output
goes to `$stderr` so it doesn't interfere with `--json` stdout.

**Cleanup**: Before printing the final summary, print `\r` + blank line to clear the spinner line.

### R-5: Error detection in buffered output

**Decision**: Scan the buffer for lines matching `/Error|FAILED|Failure:|error:/i`. This
is intentionally liberal — we want to surface anything that looks like a test problem.
The count of matching lines (not lines in total) is shown in the `⚠ N errors detected` indicator.

A more precise approach would parse Minitest's result line (`7 runs, 3 failures, 0 errors`)
but this requires framework-specific parsing that is already partially done by the adapters.
The liberal approach is simpler and sufficient for the indicator's purpose.

---

## Phase 1: Design & Contracts

### Data Model

No new persistent data. The UI layer is stateless and reads from existing data structures:
- `Analysis::Result` → `ReportRenderer`
- `Runner` output buffer → `Progress`, `ErrorToggle`

See [data-model.md](./data-model.md) for component interface specs.

### Component Interfaces

#### `UI::Styles` (lib/testprune/ui/styles.rb)

A module of frozen style constants. All other UI classes import from here.

```ruby
module Testprune::UI::Styles
  PURPLE  = "#7D56F4"
  GREEN   = "#22C55E"
  AMBER   = "#F59E0B"
  GRAY    = "#6B7280"
  RED     = "#EF4444"
  EMERALD = "#10B981"
  META    = "#9CA3AF"
  DIM     = "#3D3D5C"
  TEXT    = "#E2E8F0"

  # Pre-built reusable styles
  HEADER_BOX    = Lipgloss::Style.new.border(:rounded).border_foreground(PURPLE).padding(0, 1)
  SUCCESS_BOX   = Lipgloss::Style.new.border(:rounded).border_foreground(EMERALD).padding(0, 1)
  HIGH_BADGE    = Lipgloss::Style.new.foreground(GREEN).bold(true)
  MEDIUM_BADGE  = Lipgloss::Style.new.foreground(AMBER).bold(true)
  LOW_BADGE     = Lipgloss::Style.new.foreground(GRAY)
  SAFE_LINE     = Lipgloss::Style.new.foreground(GREEN)
  META_TEXT     = Lipgloss::Style.new.foreground(META)
  DIM_TEXT      = Lipgloss::Style.new.foreground(DIM)
  PURPLE_TEXT   = Lipgloss::Style.new.foreground(PURPLE)
  ERROR_TEXT    = Lipgloss::Style.new.foreground(RED).bold(true)
  AMBER_TEXT    = Lipgloss::Style.new.foreground(AMBER)
end
```

#### `UI::Progress` (lib/testprune/ui/progress.rb)

Drives the live spinner. Called by `Runner`.

```ruby
class Testprune::UI::Progress
  def initialize(io: $stderr)       # always stderr; never touches stdout
  def start                         # begins spinner thread
  def increment(count: 1)           # called per detected test line
  def stop(test_count:, elapsed:)   # stops spinner, prints cleared line
  def tty?                          # → false in CI/pipe → no spinner, no \r
end
```

#### `UI::ErrorToggle` (lib/testprune/ui/error_toggle.rb)

Post-scan interactive prompt. Called by `Runner` (or `CLI`) after subprocess exits.

```ruby
class Testprune::UI::ErrorToggle
  def initialize(errors:, io: $stderr)  # errors: array of error line strings
  def run                               # prints summary, loops on [e]/[Enter]
  # Returns when user presses Enter (without e), continuing the workflow
end
```

#### `UI::ReportRenderer` (lib/testprune/ui/report_renderer.rb)

Replaces `Report#render_text`. Called by `Report#render` when `json: false`.

```ruby
class Testprune::UI::ReportRenderer
  def initialize(result)            # Analysis::Result
  def render → String              # complete styled string (may include ANSI)
  private
  def header_box → String
  def confidence_section(title, candidates, badge_style) → String
  def candidate_block(candidate) → String
  def savings_box → String
end
```

### Contracts

See [contracts/ui-contracts.md](./contracts/ui-contracts.md) for the behavioral contracts
each command must honour.

### CLAUDE.md agent context update

The plan file at `specs/001-lipgloss-terminal-ui/plan.md` is the active implementation reference.

---

## Implementation Sequence

Tasks are delivered in dependency order by `/speckit-tasks`. High-level sequence:

1. **Dep**: Add `lipgloss` runtime dep to gemspec + `bundle install`
2. **Styles**: `UI::Styles` palette — frozen constants, no behavior
3. **ReportRenderer**: Styled report text (largest isolated unit; testable independently)
4. **Report integration**: Wire `Report#render_text` → `UI::ReportRenderer` with tty? guard
5. **Progress**: Spinner + elapsed display
6. **Runner capture**: Replace `system()` with `Open3.popen2e` + threaded buffer + Progress
7. **ErrorToggle**: Post-scan error expand/collapse prompt
8. **CLI verbose**: `--verbose` flag on `scan`; prune header + phase separator
9. **CLI apply**: Styled confirmation prompt + success box
10. **Tests**: Unit tests for `ReportRenderer`, `Progress`, `ErrorToggle`; integration test for `--verbose` and `NO_COLOR`

**Ordering rationale**: ReportRenderer first because it's the biggest user-visible change and
is fully testable without touching Runner. Progress + Runner capture second because they
interact with subprocess I/O. CLI changes last because they assemble the pieces.
