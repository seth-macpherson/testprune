# UI Behavioral Contracts

These contracts define the behavioral guarantees each command must honour
after the lipgloss UI redesign. They are implementation-agnostic (no mention
of specific methods), focused on observable terminal behavior.

---

## C-1: `testprune scan` — quiet mode (no --verbose)

- **MUST** suppress raw test runner stdout/stderr during the run
- **MUST** print a spinner with elapsed time to stderr while the suite runs
- **MUST** print `⚠ N errors detected (non-blocking)` to stderr if test errors occur during the run (while spinner is still running)
- **MUST** print a scan-complete summary to stderr after the suite exits
- **MUST** include `[e + Enter] show errors  [Enter] skip` in the summary if errors were captured
- **MUST NOT** print the buffered output unless the user requests it via the toggle
- **MUST** write `run.json` regardless of whether test errors occurred (non-blocking contract)
- When `NO_COLOR=1` or stdout/stderr is not a TTY, **MUST** degrade to plain text equivalents (no ANSI codes)

## C-2: `testprune scan --verbose`

- **MUST** stream raw test runner output directly to the terminal (same as pre-feature behavior)
- **MUST NOT** suppress or buffer any output
- Spinner and progress display are **NOT REQUIRED** in verbose mode
- All other `scan` behavior (run.json write, error handling) **MUST** be identical

## C-3: `testprune report`

- **MUST** render candidates grouped by HIGH / MEDIUM / LOW
- **MUST** visually distinguish the three confidence tiers (color or clear labeling)
- **MUST** render a savings summary
- When `--json` flag is passed, **MUST** emit raw JSON with **zero** ANSI escape codes — byte-identical to pre-feature behavior
- When `NO_COLOR=1` or output is piped, **MUST** produce readable plain text (no ANSI codes)

## C-4: `testprune apply`

- **MUST** render the full styled report before the confirmation prompt
- **MUST** print a styled confirmation prompt showing the count of HIGH-confidence removals
- **MUST** print a styled success box after writing the patch, including the patch path and `git apply` command
- **MUST** still require `y/N` input (no auto-apply behavior)
- The content of the patch **MUST** be identical to pre-feature behavior

## C-5: `testprune prune`

- **MUST** display a header box containing ✂️ and "scan + apply in one step"
- **MUST** display a styled phase separator (━━━ ✂️ Moving to apply… ━━━) between the scan summary and the apply report
- **MUST** display a final summary box after the patch is written (or skipped)
- All scan and apply contracts (C-1, C-4) **MUST** hold within the prune workflow

## C-6: Graceful degradation

- When `NO_COLOR=1` is set, **all** commands **MUST** produce output free of ANSI escape sequences
- When stdout (or stderr for progress) is not a TTY (e.g., piped), same no-ANSI requirement applies
- The `--json` flag output **MUST** always be ANSI-free regardless of TTY state
- No command **MUST** crash or raise an exception due to lipgloss rendering in a non-color environment
