# Tasks: Lipgloss Terminal UI Redesign

**Input**: Design documents from `specs/001-lipgloss-terminal-ui/`
**Prerequisites**: plan.md ✅, spec.md ✅, data-model.md ✅, contracts/ui-contracts.md ✅

**Tests**: Included — constitution requires TDD; tests written before implementation.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no inter-task dependency)
- **[Story]**: Which user story this task belongs to (US1–US4)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add lipgloss dependency and bootstrap the `lib/testprune/ui/` module.

- [ ] T001 Add `spec.add_dependency('lipgloss', '>= 0.1')` to `testprune.gemspec`
- [ ] T002 Run `rv run bundle install` to lock lipgloss into Gemfile.lock
- [ ] T003 Create `lib/testprune/ui.rb` — module entry point that requires all ui submodules; add `require_relative 'ui'` in `lib/testprune.rb`
- [ ] T004 Create `lib/testprune/ui/styles.rb` with `UI::Styles` — frozen color hex constants (PURPLE, GREEN, AMBER, GRAY, RED, EMERALD, META, DIM, TEXT) and pre-built reusable `Lipgloss::Style` objects (HEADER_BOX, SUCCESS_BOX, HIGH_BADGE, MEDIUM_BADGE, LOW_BADGE, SAFE_LINE, META_TEXT, DIM_TEXT, PURPLE_TEXT, ERROR_TEXT, AMBER_TEXT) as per plan.md component interface spec

**Checkpoint**: `rv run ruby -e "require 'testprune/ui/styles'; puts Testprune::UI::Styles::PURPLE"` prints `#7D56F4`

---

## Phase 2: Foundational (Blocking Prerequisites)

No additional foundational tasks beyond Phase 1 — `UI::Styles` (T004) is the only shared dependency for all UI components.

**⚠️ CRITICAL**: T001–T004 must complete before any user story work begins.

---

## Phase 3: User Story 1 — Scan with quiet progress + non-blocking error indicator (Priority: P1) 🎯 MVP

**Goal**: `testprune scan` shows a spinner/counter/elapsed instead of raw output. Test errors are flagged non-blocking with an interactive expand/collapse after the scan completes.

**Independent Test**: Run `testprune scan` on any project with tests. Verify raw output is absent; styled progress and summary are visible. Run with `--verbose` to confirm raw output streams. Run with `NO_COLOR=1` to confirm no ANSI codes appear.

### Tests (write first — must fail before implementation)

- [ ] T005 Write `test/ui/progress_test.rb` — tests for `UI::Progress`: `#start` begins a thread; `#stop` returns elapsed seconds and test_count; `#increment` advances counter; `#tty?` returns false when $stderr is a StringIO; `FRAMES` constant is defined
- [ ] T006 Write `test/ui/error_toggle_test.rb` — tests for `UI::ErrorToggle`: with zero errors, `#run` returns immediately without prompting; with errors and simulated `e\n` input, `#run` emits the error lines to io; with `\n` input, `#run` skips without printing errors; output is ANSI-free when io is a StringIO (non-TTY)

### Implementation

- [ ] T007 [P] Create `lib/testprune/ui/progress.rb` — `UI::Progress` class: `FRAMES` Braille array; `start` launches spinner thread (sleep 0.1, write `\r⠸ Running suite…  N tests  MM:SS elapsed` to `@io`); `increment` bumps `@counter`; `stop(test_count:, elapsed:)` kills thread, writes `\r` + blank to clear spinner line, returns stats; guards all output behind `tty?` (`@io.respond_to?(:isatty) && @io.isatty`)
- [ ] T008 Create `lib/testprune/ui/error_toggle.rb` — `UI::ErrorToggle` class: init takes `errors:` (array of strings) and `io:`; `run` does nothing and returns if `errors.empty?`; otherwise prints amber `⚠ N test errors (non-blocking)` line, then loops: prompt `  [e + Enter] show errors  [Enter] skip > `, read line via `$stdin.gets`, if `e` toggle `@expanded` (print errors when true, hide when false), if empty/Enter break; uses `Testprune::UI::Styles` for color if io is a TTY
- [ ] T009 Modify `lib/testprune/runner.rb` `#call` — replace `system(env, *command)` with an `Open3.popen2e` block; read output line-by-line in a Thread, buffering all lines into `@output_lines` and calling `progress.increment` per line matching `/\.|F|E|S/`; scan each line for `/Error|FAILED|Failure:|error:/i` and append to `@error_lines`; start `UI::Progress` before the subprocess, call `progress.stop` after it exits; pass `@error_lines` to `UI::ErrorToggle.new(errors: @error_lines, io: $stderr).run`; add `attr_reader :verbose` and accept `verbose:` keyword in `#call` — when `verbose: true`, fall back to original `system()` behavior (no capture, no spinner)
- [ ] T010 Modify `lib/testprune/cli.rb` — add `--verbose` / `-V` flag to `parse_options`; thread `verbose:` opt through `cmd_scan` → `runner.call`; update BANNER to document `--verbose`; after scan complete, print styled success summary box (emerald border, `✓ Scan complete`, test count, elapsed) using `UI::Styles` if stdout/stderr is a TTY
- [ ] T011 Extend `test/integration_test.rb` — add test: `NO_COLOR=1 testprune scan` output contains no ANSI escape codes; add test: `testprune scan --verbose` streams raw test output to stderr

**Checkpoint**: `testprune scan` on the fixture shows spinner then summary box. `testprune scan --verbose` streams raw output. `NO_COLOR=1 testprune scan` shows plain text only.

---

## Phase 4: User Story 2 — Rich, scannable report output (Priority: P1)

**Goal**: `testprune report` renders styled, color-coded sections with confidence badges, borders, and a savings summary box. `--json` output is unchanged.

**Independent Test**: Run `testprune report` after scanning the fixture. Verify color-coded HIGH/MEDIUM/LOW sections and a savings box appear. Run with `--json` to confirm byte-identical JSON output. Run piped (`testprune report | cat`) to confirm no ANSI codes leak.

### Tests (write first — must fail before implementation)

- [ ] T012 Write `test/ui/report_renderer_test.rb` — tests for `UI::ReportRenderer`: `#render` returns a non-empty String; with HIGH candidates, output includes `HIGH confidence`; with no candidates, output includes `Nothing redundant found`; with MEDIUM candidates, output includes `MEDIUM confidence`; savings section appears when approved_removals > 0; output contains no ANSI codes when `$stdout.isatty` is false (use StringIO)

### Implementation

- [ ] T013 Create `lib/testprune/ui/report_renderer.rb` — `UI::ReportRenderer` class: `initialize(result)` stores the `Analysis::Result`; `render` calls `header_box + confidence_section(:high) + confidence_section(:medium) + confidence_section(:low) + savings_box + cta_line`; `header_box` renders a purple-bordered box with gem name, test count, framework, baseline; `confidence_section(tier)` renders a color-coded `●` label + `─` separator + candidate blocks; `candidate_block(c)` renders `[group]` badge in purple, then `at:` / `reason:` / `kept by:` / `covers:` in META/DIM; `savings_box` renders a purple-bordered box with green numbers; when `$stdout.tty?` is false, all `Lipgloss::Style#render` calls pass through plain text (lipgloss auto-degrades; add a guard that strips if `ENV['NO_COLOR']` is set); `render` returns empty string when result has no candidates and appends a friendly `Nothing redundant found — suite looks clean.` styled line
- [ ] T014 Modify `lib/testprune/report.rb` `#render_text` — replace body with `require_relative 'ui/report_renderer'; UI::ReportRenderer.new(@result).render`; keep `#render_json` entirely unchanged; add `tty?` guard so that in non-TTY environments the renderer still runs (lipgloss handles degradation) but `NO_COLOR=1` is respected

**Checkpoint**: `testprune report` after scanning the fixture shows colored sections. `testprune report | cat` shows plain text. `testprune report --json` produces byte-identical JSON.

---

## Phase 5: User Story 3 — Apply with styled confirmation flow (Priority: P2)

**Goal**: `testprune apply` renders a styled confirmation prompt and a success box with the git command after patching.

**Independent Test**: Run `testprune apply` after a scan on the fixture with known HIGH candidates. Verify the prompt is styled (shows count, colored `[y/N]`). Confirm `y` produces a styled success box containing the patch path and `git apply` command. Confirm `N` shows a styled "Aborted" message.

### Implementation

- [ ] T015 Modify `lib/testprune/cli.rb` `#cmd_apply` — replace bare `print "\nApply…"` prompt with a styled prompt using `UI::Styles::PURPLE_TEXT.render("[y/N]")`; replace bare `puts("Wrote #{path}")` success message with a styled emerald-bordered success box containing the patch path and `git apply <path>` command; replace bare `puts('Aborted.')` with a styled DIM_TEXT "Aborted — no patch written." line; all styling guarded on `$stdout.tty?`

**Checkpoint**: `testprune apply` with HIGH candidates shows a styled prompt. After `y`, a bordered success box appears with patch path and `git apply` command.

---

## Phase 6: User Story 4 — Prune command with trimming emoji identity (Priority: P2)

**Goal**: `testprune prune` displays a ✂️ header box, a styled phase separator between scan and apply, and a ✂️ done summary box at the end.

**Independent Test**: Run `testprune prune` on the fixture. Verify: (1) ✂️ appears in the header, (2) a `━━━ ✂️ Moving to apply… ━━━` separator appears between scan completion and the report, (3) a ✂️ done box appears after the patch is written or skipped.

### Implementation

- [ ] T016 Modify `lib/testprune/cli.rb` `#cmd_prune` — before calling `cmd_scan(argv)`, print a purple-bordered header box: `✂️  testprune prune — scan + apply in one step` using `UI::Styles::HEADER_BOX`
- [ ] T017 Modify `lib/testprune/cli.rb` `#cmd_prune` — between `cmd_scan(argv)` and `cmd_apply([])`, print a styled phase separator: purple `━` line + `  ✂️  Moving to apply…` + purple `━` line using `UI::Styles::PURPLE_TEXT`
- [ ] T018 Modify `lib/testprune/cli.rb` `#cmd_prune` — after `cmd_apply` returns, print a ✂️ done summary box (emerald border): "Done — N test(s) pruned" or "Done — nothing pruned" depending on apply outcome; thread a return value from `cmd_apply` indicating whether a patch was written and how many removals it contained

**Checkpoint**: Full `testprune prune` run shows ✂️ header → spinner → scan summary → `━━ ✂️ Moving to apply… ━━` → report → prompt → ✂️ done box.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T019 [P] Update `README.md` — document `--verbose` flag in the scan section; add a note that `NO_COLOR=1` disables styled output; update the quick-start block if scan behavior changed visibly
- [ ] T020 Bump `lib/testprune/version.rb` to `0.4.0` — major UX release
- [ ] T021 Run `rv run bundle exec rake test` — confirm all tests green; fix any regressions in integration_test.rb caused by changed output format (update expected strings for styled output)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately; T001→T002→T003→T004 (sequential, each builds on previous)
- **Phase 2 (Foundational)**: Absorbed into Phase 1
- **Phase 3 (US1)**: Requires Phase 1 complete; T005/T006 parallel → T007/T008 parallel → T009 → T010 → T011
- **Phase 4 (US2)**: Requires Phase 1 complete; independent of Phase 3; T012 → T013 → T014
- **Phase 5 (US3)**: Requires T014 complete (report renderer wired) and T010 (CLI structure)
- **Phase 6 (US4)**: Requires T010 and T015
- **Phase 7 (Polish)**: Requires all story phases complete

### User Story Dependencies

- **US1 and US2**: Both require only Phase 1 — can run in parallel with separate developers
- **US3**: Requires US2 (report renderer must be wired) and US1 (CLI structure)
- **US4**: Requires US1 (CLI structure, cmd_prune); US3 recommended first for the apply step

### Within Each User Story (TDD)

- Tests MUST be written first and MUST FAIL before implementation begins
- Models/components before integrations
- Unit complete before wiring into CLI

### Parallel Opportunities

- T005 and T006 are independent files (test vs impl) — can parallelize after T004
- T007 and T008 are independent files (test vs impl) — can parallelize
- T012 and T013 are independent (test vs impl) — can parallelize after T004
- Phases 3 and 4 are fully independent — can run in parallel across two developers

---

## Parallel Example: User Story 1

```bash
# After T004 completes, launch in parallel:
# Dev A: T005 (write progress_test.rb) then T007 (write progress.rb)
# Dev B: T006 (write error_toggle_test.rb) then T008 (write error_toggle.rb)
# Then: T009 (runner.rb), T010 (cli.rb), T011 (integration_test.rb) — sequential
```

---

## Implementation Strategy

### MVP First (US1 + US2 Only)

1. Complete Phase 1 (T001–T004) — Setup + Styles
2. Complete Phase 3 (T005–T011) — Scan progress + error toggle
3. Complete Phase 4 (T012–T014) — Styled report
4. **STOP and VALIDATE**: `testprune scan` + `testprune report` both look great
5. The two highest-impact visible improvements are done

### Incremental Delivery

1. Phase 1 → Styles palette ready
2. Phase 3 (US1) → Scan UX dramatically better → publish 0.4.0-beta
3. Phase 4 (US2) → Report readable → publish 0.4.0-beta.2
4. Phase 5 (US3) → Apply polished
5. Phase 6 (US4) → Prune identity complete
6. Phase 7 → Polish → publish 0.4.0

---

## Notes

- `[P]` tasks operate on different files and have no incomplete-task dependencies
- TDD: every test task (T005, T006, T012) must produce failing tests before the corresponding implementation task runs
- All styled output uses the `tty?` / `NO_COLOR` guard — never crash in CI
- `--json` flag output must remain byte-identical; test this explicitly in T011
- Commit after each checkpoint before moving to the next phase
