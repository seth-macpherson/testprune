# Data Model: Lipgloss Terminal UI

No new persistent entities. The UI layer reads from existing data structures and
produces strings. This document defines the component interaction model.

## Existing Data Structures (read by UI layer)

### `Analysis::Result` (unchanged)

Used by `UI::ReportRenderer`.

| Field | Type | Used by |
|-------|------|---------|
| `candidates` | `Array<Candidate>` | Section grouping |
| `run` | `Hash` | Header (`framework`, `tests` count) |
| `ambient_units` | `Integer` | Header (baseline info) |
| `setup_only` | `Integer` | Header |
| `approved_removals` | `Array<Candidate>` | Savings box, apply count |
| `savings` | `Savings` | Savings box |

### `Candidate` (unchanged)

| Field | Type | Used by |
|-------|------|---------|
| `footprint` | `Footprint` | Location, covers list |
| `confidence` | `:high \| :medium \| :low` | Badge color selection |
| `group` | `:identical \| :subset \| :structural \| :overlap` | Group badge text |
| `reason` | `String` | Detail line |
| `kept_by` | `Array<String>` | Subdued "kept by" line |
| `safe` | `true \| false \| nil` | Safety line (HIGH only) |
| `safety_note` | `String?` | Safety detail when false |
| `review_only` | `Boolean` | Whether auto-patchable |

## New In-Memory Structures

### `UI::Progress` state (ephemeral, lives for scan duration)

```
thread:   Thread         # spinner refresh loop
counter:  Integer        # tests seen so far (incremented by line parser)
start_at: Time           # wall-clock start
frames:   Array<String>  # Braille spinner chars
frame_idx: Integer       # current frame (cycles)
io:       IO             # $stderr (default)
```

### `UI::ErrorToggle` state (ephemeral, lives for interactive prompt)

```
errors:   Array<String>  # error lines from buffered output
expanded: Boolean        # current show/hide state
io:       IO             # $stderr (default)
```

## Data Flow

```
testprune scan
  │
  ├─ CLI#cmd_scan
  │    └─ Runner#call
  │         ├─ Open3.popen2e → output buffer (Thread A reads lines)
  │         ├─ UI::Progress (Thread B: spinner + counter updates)
  │         ├─ on exit: collect error lines → UI::ErrorToggle#run
  │         └─ writes run.json (unchanged)
  │
testprune report
  │
  ├─ CLI#cmd_report
  │    └─ Report#render
  │         ├─ if json: → JSON.pretty_generate (unchanged)
  │         └─ if tty: → UI::ReportRenderer#render → styled string
  │
testprune apply
  │
  ├─ CLI#cmd_apply
  │    ├─ Report#render → (styled, as above)
  │    ├─ styled prompt (inline in CLI, using Lipgloss styles)
  │    └─ PatchWriter#write (unchanged)
```
