<!--
Sync Impact Report
==================
Version change: [PLACEHOLDER] → 1.0.0
Modified principles: N/A (initial population from blank template)
Added sections:
  - Core Principles (I–V)
  - Technical Standards
  - Development Workflow
  - Governance
Removed sections: none (all were placeholders)
Templates updated:
  ✅ .specify/memory/constitution.md — this file
  ⚠ .specify/templates/plan-template.md — "Constitution Check" gates still use placeholder text;
      recommended: replace [Gates determined based on constitution file] with concrete I–V gates
  ✅ .specify/templates/spec-template.md — no constitution-specific references; no update needed
  ✅ .specify/templates/tasks-template.md — no constitution-specific references; no update needed
Deferred TODOs: none
-->

# testprune Constitution

## Core Principles

### I. Safety Is Non-Negotiable

Every recommended removal MUST preserve the coverage safety guarantee: no
semantic unit's `cover_count` may drop to zero. The cascading safety check MUST
evaluate candidates in order, decrementing counts as each removal is confirmed,
so jointly-unsafe pairs are never both approved.

Ambient units (stripped by baseline subtraction) MUST be protected against
uncovering even when invisible to the detector — `cover_count` tracking MUST use
original, unstripped footprints.

Rationale: the tool's entire value proposition rests on the promise that running
its recommendations never silently removes production-code coverage.

### II. Human-in-the-Loop for Every Patch

No test file MUST ever be modified without explicit human approval. The apply
step MUST reprint the full report, prompt `y/N`, and write only to
`tmp/.testprune/removal.patch`. The user then decides whether to run
`git apply`.

Rationale: coverage measures execution, not assertion strength. Two tests with
identical footprints may assert different values. The tool provides signal; the
engineer makes the final call.

### III. Confidence Gradation and Honest Signaling

Findings MUST be classified into three tiers:

- **HIGH** — identical footprint or strict subset (A ⊊ B): eligible for
  auto-patch after safety check passes. MUST include a `✓ safe` or `✗ NOT safe`
  line.
- **MEDIUM** — structural duplicate (Prism-normalized body match with overlapping
  footprints): review-only. MUST NOT be auto-patched.
- **LOW** — high-Jaccard-overlap (≥ 0.9) non-subsets: review-only. MUST NOT be
  auto-patched.

The locality gate MUST demote cross-file identical/subset coverage to LOW —
two tests in different files covering the same guard are testing different
contexts.

Rationale: mixed-confidence recommendations erode trust. Tiers make the tool's
certainty explicit and actionable.

### IV. Non-Destructive Output Only

Approved removals MUST be expressed as comments, not deletions. Each removed
test block MUST be annotated with a reason line:

```ruby
# testprune: removed redundant test — <reason>
#   def test_name
#     ...
#   end
```

Patch files (`removal.patch`) MUST be written to `tmp/.testprune/` and MUST NOT
be applied automatically. No files in the target project MUST be written or
deleted by testprune without an intervening `git apply` by the user.

Rationale: commenting out preserves recoverability and forces conscious review of
what was removed and why.

### V. Semantic Precision via Prism AST

Coverage analysis MUST be grounded in Prism AST semantic units (named methods,
branch arms, call sites), not raw line numbers. Location-to-semantic-unit mapping
MUST be built per source file using `SemanticMap` before any footprint comparison.

Baseline subtraction MUST strip units present in ≥ FRAC of tests (default 0.5)
to suppress shared-setup noise before detection runs. Tests with zero distinctive
coverage after stripping MUST NOT be proposed for removal.

Rationale: line-based comparison produces false positives whenever two tests hit
the same fixture setup. Semantic units expose what is actually being tested.

## Technical Standards

- **Ruby ≥ 3.2** is required. `Coverage.setup` with `:branches` and `:methods`
  modes MUST be used; no fallback to lines-only coverage is acceptable.
- **Prism ≥ 1.0, < 3** is required for AST-based semantic mapping.
- The gem MUST work with Minitest and RSpec out of the box via `RUBYOPT`
  injection — no changes to the target project are required.
- The gem MUST NOT conflict with SimpleCov: `Coverage.start` MUST be guarded so
  SimpleCov finds Coverage already running and skips its own start.
- Output directories (`tmp/.testprune/`) MUST be scoped per-project via
  `TESTPRUNE_ROOT` and MUST NOT pollute the gem install path.

## Development Workflow

- Tests MUST be written before implementation (TDD). The Red-Green-Refactor
  cycle MUST be followed: tests fail first, then implementation makes them pass.
- All public behaviour MUST be covered by unit or integration tests. The
  integration test (`test/integration_test.rb`) MUST exercise the full CLI
  end-to-end against the bundled calculator fixture.
- `rake test` MUST pass before any commit to `main`.
- Before publishing a new gem version, the README MUST be updated to reflect
  any new or changed behaviour. The version MUST be bumped in
  `lib/testprune/version.rb` and the changelog updated.

## Governance

This constitution supersedes all other practices documented for this project.
Amendments require:

1. A concrete motivation (bug, new capability, or correctness concern).
2. A version bump following semantic versioning:
   - **MAJOR**: removal or redefinition of a core principle.
   - **MINOR**: new principle or materially expanded guidance added.
   - **PATCH**: wording clarification, typo fix, non-semantic refinement.
3. The `Last Amended` date MUST be updated to the amendment date.
4. The Sync Impact Report HTML comment MUST be updated to document what changed.

All PRs MUST be reviewed against principles I–V before merge. Complexity that
violates Principle II (human-in-the-loop) or Principle I (safety guarantee)
MUST be rejected regardless of other merits.

**Version**: 1.0.0 | **Ratified**: 2026-06-02 | **Last Amended**: 2026-06-02
