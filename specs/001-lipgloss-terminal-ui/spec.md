# Feature Specification: Lipgloss Terminal UI Redesign

**Feature Branch**: `001-lipgloss-terminal-ui`
**Created**: 2026-06-02
**Status**: Draft
**Input**: Re-imagine the terminal UX for each step of testprune using lipgloss-ruby. Hidden test output during scan (togglable). Emoji-driven prune command. Rich, enjoyable output throughout.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Scan with quiet progress display (Priority: P1)

A developer runs `testprune scan` on a project with hundreds of tests. Today they see a wall of raw Minitest/RSpec output scroll past with no sense of progress. After this feature, they see a clean, styled progress display: a spinner, a running test counter, and elapsed time. Raw test output is suppressed by default. If something goes wrong they can rerun with `--verbose` to see the full output.

**Why this priority**: The scan is the most-used command and the most painful UX today. Silencing the noise immediately transforms the experience.

**Independent Test**: Run `testprune scan` on any project with tests. Verify the terminal shows styled progress and that raw test output is not printed to stdout. Verify `testprune scan --verbose` shows the full output.

**Acceptance Scenarios**:

1. **Given** a project with a test suite, **When** `testprune scan` is run without flags, **Then** the terminal shows a live spinner + test counter + elapsed time and raw test runner output is suppressed.
2. **Given** `testprune scan --verbose` is run, **Then** raw test output streams normally alongside (or in place of) the progress display.
3. **Given** the scan completes successfully, **Then** a styled summary box is printed showing total tests run, time elapsed, and a "Scan complete" confirmation.
4. **Given** test errors occur during the run (non-zero exit or captured test failures), **Then** the scan completes anyway (non-blocking) and the summary box includes an amber error count with `[e] expand / [enter] skip` prompt.
5. **Given** the user presses `e` at the error prompt, **Then** the buffered error output expands inline; a second `[e]` keypress collapses it. The user can toggle as many times as they like before continuing.

---

### User Story 2 — Rich, scannable report output (Priority: P1)

A developer runs `testprune report` and today sees an undifferentiated wall of monospaced text. After this feature they see a styled, grouped report with colored confidence badges, bordered sections, clear visual hierarchy, and a summary box with the estimated CI savings.

**Why this priority**: The report is the decision surface — it must be easy to read and act on. The current output is effectively unusable on large suites.

**Independent Test**: Run `testprune report` after a scan with known redundant tests. Verify the output uses colors and borders. Verify HIGH/MEDIUM/LOW candidates are visually distinct. Verify the savings summary is rendered prominently.

**Acceptance Scenarios**:

1. **Given** analysis finds HIGH/MEDIUM/LOW candidates, **When** `testprune report` is run, **Then** each confidence tier is rendered in a visually distinct styled section.
2. **Given** a candidate has a `kept by` field, **Then** that field is indented and styled in a subdued color to reduce visual noise.
3. **Given** no candidates are found, **Then** a friendly styled box says "Nothing redundant found — suite looks clean."
4. **Given** the `--json` flag is used, **Then** output is raw JSON (no styling), unchanged from today.

---

### User Story 3 — Apply with styled confirmation flow (Priority: P2)

A developer runs `testprune apply`. After the report renders, a styled prompt asks for confirmation before writing the patch. The confirmation shows the count of removals and uses a clear visual treatment. After patching, a styled success box shows the patch path and the `git apply` command.

**Why this priority**: Apply is the destructive step; it benefits most from a clear, reassuring visual presentation.

**Independent Test**: Run `testprune apply` with known HIGH-confidence candidates. Verify the prompt is styled. Verify the post-patch success message is clearly readable and includes the git command.

**Acceptance Scenarios**:

1. **Given** HIGH-confidence candidates exist, **When** the apply prompt appears, **Then** it is styled (bordered box, color-coded Y/N), not a bare `print`.
2. **Given** the user confirms, **Then** a styled success box shows the written patch path and `git apply <path>` command.
3. **Given** the user declines, **Then** a styled "Aborted" message is shown.
4. **Given** no approved candidates exist, **Then** a styled info box says "Nothing safe to remove."

---

### User Story 4 — Prune command with trimming emoji identity (Priority: P2)

A developer runs `testprune prune` — the all-in-one command. The terminal header for this command uses a trimming/pruning emoji (✂️ or 🌿) to signal the nature of the operation. Progress through scan and apply phases is clearly labeled so the user knows which phase they're in.

**Why this priority**: `prune` is the power-user shortcut; giving it visual personality reinforces the gem's identity.

**Independent Test**: Run `testprune prune` on a project. Verify a trimming emoji appears in the header. Verify phase transitions (scan → apply) are clearly indicated with styled phase labels.

**Acceptance Scenarios**:

1. **Given** `testprune prune` is run, **Then** the terminal header includes a trimming emoji (✂️) and the gem name.
2. **Given** the scan phase completes, **Then** a styled phase separator announces "Moving to apply…" before the report renders.
3. **Given** the full workflow completes, **Then** a final styled summary shows what was removed (or that nothing was removed).

---

### Edge Cases

- What happens when the terminal does not support color (e.g., CI, `NO_COLOR=1`, or output piped to a file)? Styled output must degrade gracefully to plain text.
- What happens if lipgloss is not installed? The gem should gracefully fall back to plain output rather than crashing.
- What if the terminal width is very narrow (< 40 columns)? Bordered boxes must not overflow or corrupt the display.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The `scan` command MUST suppress raw test runner output by default, redirecting it to an internal buffer.
- **FR-002**: The `scan` command MUST display a live progress indicator (spinner + test counter + elapsed time) while the suite runs.
- **FR-003**: A `--verbose` flag on `scan` MUST stream raw test output in addition to or instead of the styled progress display.
- **FR-004**: Test errors during scan are NON-BLOCKING — the scan completes regardless of individual test failures or a non-zero suite exit code.
- **FR-004a**: If one or more test errors are captured during scan, the progress display MUST show an amber `⚠ N errors detected (non-blocking)` indicator as soon as they appear.
- **FR-004b**: After scan completes, if errors were captured, the summary box MUST include an error count and a `[e] expand · [enter] skip` interactive prompt.
- **FR-004c**: Pressing `e` at the error prompt MUST expand the buffered error detail inline; pressing `e` again MUST collapse it. This toggle MUST be repeatable before the user continues.
- **FR-005**: The `report` command MUST render output using styled, color-coded sections grouped by confidence level (HIGH / MEDIUM / LOW).
- **FR-006**: Each candidate in the report MUST include a confidence badge and visually distinct treatment for its `kept by` and `covers` fields.
- **FR-007**: The savings summary MUST be rendered in a prominent styled box at the end of the report.
- **FR-008**: The `apply` command's confirmation prompt MUST be styled (bordered, color-coded).
- **FR-009**: The `apply` command's post-patch output MUST include a styled success box with the patch path and the `git apply` invocation.
- **FR-010**: The `prune` command MUST display a trimming emoji (✂️) in its header and labeled phase transitions between scan and apply.
- **FR-011**: All styled output MUST degrade gracefully to unstyled plain text when `NO_COLOR=1` is set or when stdout is not a TTY (piped output).
- **FR-012**: The `--json` flag on `report` MUST continue to emit raw JSON with no ANSI escape codes.
- **FR-013**: lipgloss-ruby MUST be added as a runtime dependency of the gem.

### Key Entities

- **Style palette**: A centralized set of reusable Lipgloss styles (colors, borders, typography) defining the gem's visual identity.
- **Progress display**: The live scan progress component (spinner, counter, timer).
- **Report renderer**: The styled replacement for `Report#render_text`.
- **Phase label**: A styled separator used by `prune` to announce scan→apply transitions.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer running `testprune scan` on a 500-test suite sees a clean progress display with no raw test output visible by default.
- **SC-002**: A developer running `testprune report` can visually identify the confidence tier of every candidate without reading the full text of each entry.
- **SC-003**: All commands produce identical output content (same data) in `NO_COLOR=1` environments as in color-enabled environments — only styling differs.
- **SC-004**: The `--json` flag on `report` produces output that is byte-for-byte identical to the pre-feature output (no regressions).
- **SC-005**: Test errors during scan are visibly flagged in the progress display in real time, and the error toggle (`[e]`) is available in the summary — the user is never left wondering whether errors occurred or how to see them.
- **SC-006**: A scan with test failures still produces a `.testprune/` data file for analysis — errors never silently abort the scan.

---

## Assumptions

- lipgloss-ruby is available on RubyGems and works on the Ruby versions testprune already supports (Ruby 3.x).
- The terminal progress display for `scan` will use a polling/thread approach to update in place rather than a full TUI framework, keeping the implementation lightweight.
- The live spinner and counter will use ANSI cursor control (`\r`) rather than a full alternate-screen UI — compatible with most CI environments when color is off.
- Mobile/Windows terminal support is not a priority; the primary target is macOS and Linux terminals.
- The `report --json` output format is frozen and must not change.

---

## Terminal UI Preview

The mockups below use ASCII approximations of what lipgloss-ruby borders and colors will produce. Actual output will use true Unicode box-drawing characters and ANSI color.

### `testprune scan` — default (quiet mode)

```
╭─────────────────────────────────────────────────────╮
│  testprune scan                                     │
╰─────────────────────────────────────────────────────╯

  ⠸  Running suite…   312 / 528 tests   00:14 elapsed

  (pass --verbose to see test output)

╭──────────────────────────────────────────╮
│  ✓  Scan complete                        │
│     528 tests   00:31 elapsed            │
│     Data written to .testprune/          │
╰──────────────────────────────────────────╯
```

### `testprune scan` — test failure (output auto-revealed)

```
  ✗  Suite exited with errors — showing output:

  ─────────────────────────────────────────────────────
  [raw minitest/rspec output here]
  ─────────────────────────────────────────────────────

  Scan aborted. Fix the failures above and re-run.
```

### `testprune report`

```
╭─────────────────────────────────────────────────────────────────────╮
│  testprune — coverage redundancy report                             │
│  528 tests · minitest · baseline: 0.5                               │
╰─────────────────────────────────────────────────────────────────────╯

  ● HIGH confidence — safe to remove  (3)
  ───────────────────────────────────────────────────────────────────

    [identical]  UserTest#test_versioning__update
    at: test/unit/user_test.rb:1482
    reason: coverage is an exact subset of PaymentProcessorTest#test_process_user_not_stale
    kept by: Payments::Ach::PaymentProcessorTest#test_process_user_not_stale
    covers: ActiveUser#clear_active_cache · User#clear_active_user_cache (+1 more)
    ✓ safe — every covered unit remains covered by a retained test

    [identical]  AccountUpdaterTest#test_deactivate
    at: test/unit/account_updater_test.rb:88
    ...

  ● MEDIUM confidence — review  (5)
  ───────────────────────────────────────────────────────────────────
    ...  (dimmed / less prominent)

  ● LOW confidence — review  (12)
  ───────────────────────────────────────────────────────────────────
    ...  (most subdued)

╭──────────────────────────────────────────────────────╮
│  Estimated CI savings                                │
│  3 test(s)  ·  191.8s saved  ·  ~26.3% of suite     │
│  (wall-clock savings lower on parallel CI runners)   │
╰──────────────────────────────────────────────────────╯

  Run `testprune apply` to review and emit a removal patch.
```

### `testprune apply` — confirmation prompt

```
  Apply 3 HIGH-confidence removal(s) as a patch?
  MEDIUM/LOW candidates are NOT auto-patched.

  ┌───────────────────┐
  │  [y] Yes  [N] No  │
  └───────────────────┘
  > _

  ✓  Patch written: .testprune/removals.patch
     Apply with:    git apply .testprune/removals.patch
```

### `testprune prune` — full workflow

```
╭──────────────────────────────────────────────────────────╮
│  ✂️  testprune prune — scan + apply in one step          │
╰──────────────────────────────────────────────────────────╯

  ⠸  Running suite…   312 / 528 tests   00:14 elapsed

╭──────────────────────────────────────────────────────────╮
│  ✓  Scan complete · 528 tests · 00:31                   │
╰──────────────────────────────────────────────────────────╯

  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✂️  Moving to apply…
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  [report renders here]

  Apply 3 HIGH-confidence removal(s)? [y/N] > y

╭──────────────────────────────────────────────────────────╮
│  ✂️  Done — 3 test(s) pruned                            │
│     Patch: .testprune/removals.patch                    │
│     Apply: git apply .testprune/removals.patch          │
╰──────────────────────────────────────────────────────────╯
```

### Color palette (proposed)

| Role                  | Color (hex)  | Usage                              |
|-----------------------|--------------|------------------------------------|
| Accent / brand        | `#7D56F4`    | Headers, borders, key labels       |
| HIGH confidence       | `#22C55E`    | Green — safe to remove             |
| MEDIUM confidence     | `#F59E0B`    | Amber — review                     |
| LOW confidence        | `#6B7280`    | Gray — least prominent             |
| Error / not-safe      | `#EF4444`    | Red — failures, unsafe removals    |
| Subdued / meta        | `#9CA3AF`    | `kept by`, `covers`, timestamps    |
| Success               | `#10B981`    | Patch written, scan complete       |
