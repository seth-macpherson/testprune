# frozen_string_literal: true

require 'set'
require_relative 'footprint'
require_relative 'test_body'
require_relative 'safety_check'
require_relative 'baseline'

module Testprune
  # One test proposed for removal, with why and (after the safety pass) whether
  # it's safe. `review_only` candidates (structural/overlap) are reported but
  # never auto-patched.
  Candidate = Struct.new(
    :footprint, :confidence, :group, :reason, :kept_by,
    :review_only, :safe, :safety_note,
    keyword_init: true
  )

  # Holds the detection outcome and exposes the set that `apply` may patch.
  # `ambient_units`/`setup_only` record what baseline subtraction removed, so the
  # report can disclose it rather than silently dropping tests.
  class DetectorResult
    attr_reader :footprints, :candidates, :ambient_units, :setup_only

    def initialize(footprints, candidates, ambient_units: 0, setup_only: 0)
      @footprints = footprints
      @candidates = candidates
      @ambient_units = ambient_units
      @setup_only = setup_only
    end

    # Only HIGH-confidence, non-review candidates that passed the safety check are
    # auto-applicable. Structural (MEDIUM) and overlap (LOW) are review-only.
    def approved_removals
      @candidates.select { |c| c.confidence == :high && !c.review_only && c.safe }
    end
  end

  # Detects duplicate/redundant tests from semantic footprints. Each removable
  # candidate is justified by a *retained* keeper whose coverage is a superset
  # (or equal), which the SafetyCheck then re-verifies against cascading gaps.
  # Above this many post-identical/subset footprints, skip O(n²) overlap detection
  # and log a warning. ~500 yields ~125k pairs which is acceptable; 2000+ becomes
  # unusably slow on large suites.
  OVERLAP_SIZE_LIMIT = 500

  class DuplicationDetector
    def initialize(footprints, overlap_threshold: 0.9, baseline_fraction: nil)
      @original_footprints = footprints # preserved for SafetyCheck ambient-unit guarantee
      ambient      = Baseline.ambient_units(footprints, baseline_fraction)
      had_coverage = footprints.reject(&:empty?).size
      @footprints  = strip_ambient(footprints, ambient).reject(&:empty?)
      @ambient     = ambient.size
      @setup_only  = had_coverage - @footprints.size # lost all signal to baseline
      @threshold   = overlap_threshold
      @candidates  = []
      @seen        = Set.new # ids already proposed for removal
      @protected   = Set.new # ids chosen as keepers — never propose these
    end

    def call
      detect_identical
      detect_subset
      detect_structural
      detect_overlap
      SafetyCheck.new(@footprints, original_footprints: @original_footprints).apply(@candidates)
      DetectorResult.new(@footprints, @candidates,
                         ambient_units: @ambient, setup_only: @setup_only)
    end

    private

    # Returns copies of the footprints with ambient (shared-setup) units removed,
    # so detection compares only each test's *distinctive* coverage. A test whose
    # footprint was entirely ambient becomes empty and is dropped — we can't tell
    # what it uniquely exercises, so it must never be proposed for removal.
    def strip_ambient(footprints, ambient)
      return footprints if ambient.empty?

      footprints.map do |fp|
        fp.dup.tap { |copy| copy.units = fp.units - ambient }
      end
    end

    def available
      @footprints.reject { |fp| @seen.include?(fp.id) || @protected.include?(fp.id) }
    end

    def detect_identical
      @footprints.group_by(&:units).each_value do |members|
        next if members.size < 2

        members = members.sort_by(&:id)
        keeper = members.first
        @protected << keeper.id
        members.drop(1).each do |fp|
          propose_local(fp, keeper, group: :identical,
                        high_reason: "identical coverage to #{keeper.id}",
                        low_reason: "identical coverage to #{keeper.id}, but in a different " \
                                    'test file (likely a shared code path, not a redundant test)')
        end
      end
    end

    def detect_subset
      available.sort_by(&:id).each do |candidate|
        # Search for a keeper among all footprints not yet proposed for removal.
        # Crucially, we include @protected footprints (already-designated keepers):
        # excluding them caused false negatives in coverage chains where A ⊊ B ⊊ C —
        # after B is protected as A's keeper, C must still be findable as B's keeper.
        keeper = @footprints
                   .reject { |fp| @seen.include?(fp.id) || fp.id == candidate.id }
                   .find { |other| candidate.units.proper_subset?(other.units) }
        next unless keeper

        @protected << keeper.id
        propose_local(candidate, keeper, group: :subset,
                      high_reason: "coverage is a strict subset of #{keeper.id}",
                      low_reason: "coverage is a strict subset of #{keeper.id}, but in a different " \
                                  'test file (likely a shared code path, not a redundant test)')
      end
    end

    # Coverage-equivalence only earns HIGH (auto-removable) confidence when both
    # tests live in the same file — i.e. variations of one scenario. Equivalence
    # across files usually means the tests merely share a guard/middleware path
    # while asserting different things, so it's demoted to LOW review-only.
    def propose_local(footprint, keeper, group:, high_reason:, low_reason:)
      if same_file?(footprint, keeper)
        propose(footprint, confidence: :high, group: group, reason: high_reason, keeper: keeper)
      else
        propose(footprint, confidence: :low, group: group, review_only: true,
                reason: low_reason, keeper: keeper)
      end
    end

    def same_file?(a, b)
      !a.file.nil? && a.file == b.file
    end

    def detect_structural
      by_signature = {}
      available.each do |fp|
        sig = TestBody.signature(fp.file, fp.line)
        (by_signature[sig] ||= []) << fp if sig
      end

      by_signature.each_value do |members|
        next if members.size < 2

        members = members.sort_by(&:id)
        keeper = members.first
        @protected << keeper.id
        members.drop(1).each do |fp|
          next if (fp.units & keeper.units).empty? # require real coverage overlap

          propose(fp, confidence: :medium, group: :structural, review_only: true,
                  reason: "test body structurally identical to #{keeper.id}", keeper: keeper)
        end
      end
    end

    def detect_overlap
      pool = available
      if pool.size > OVERLAP_SIZE_LIMIT
        warn "testprune: #{pool.size} candidates after identical/subset detection; " \
             "overlap (LOW-confidence) detection skipped to avoid O(n²) cost at this " \
             "suite size. HIGH/MEDIUM results are unaffected."
        return
      end

      pool.combination(2).each do |a, b|
        next if @seen.include?(a.id) || @seen.include?(b.id)

        score = jaccard(a.units, b.units)
        next if score < @threshold

        smaller, larger = [a, b].sort_by { |fp| [fp.units.size, fp.id] }
        next if @protected.include?(smaller.id)

        @protected << larger.id
        propose(smaller, confidence: :low, group: :overlap, review_only: true,
                reason: "#{(score * 100).round}% coverage overlap with #{larger.id}",
                keeper: larger)
      end
    end

    def propose(footprint, confidence:, group:, reason:, keeper:, review_only: false)
      @candidates << Candidate.new(
        footprint: footprint, confidence: confidence, group: group, reason: reason,
        kept_by: [keeper.id], review_only: review_only
      )
      @seen << footprint.id
    end

    # Avoids materializing the union Set: uses inclusion-exclusion arithmetic instead.
    def jaccard(a, b)
      inter = (a & b).size
      union = a.size + b.size - inter
      union.zero? ? 0.0 : inter.to_f / union
    end
  end
end
