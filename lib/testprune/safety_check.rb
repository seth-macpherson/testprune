# frozen_string_literal: true

module Testprune
  # The hard guarantee: never confirm a removal that drops any semantic unit's
  # coverage to zero. Cascading-aware — evaluates candidates against the units
  # still covered by the *retained* set, decrementing as removals are confirmed,
  # so two individually-safe removals that are jointly unsafe can't both pass.
  #
  # Only non-review candidates (the auto-applicable ones) are checked; review-only
  # candidates are left with `safe = nil` since they're never patched.
  class SafetyCheck
    # original_footprints: pre-ambient-stripping footprints. When baseline subtraction
    # is active, the candidates' footprint.units are stripped — but removing a test
    # also removes its ambient units from coverage. We track and decrement original
    # units so ambient units are guaranteed not to drop to zero.
    def initialize(footprints, original_footprints: nil)
      originals = original_footprints || footprints
      @cover_count = Hash.new(0)
      originals.each { |fp| fp.units.each { |unit| @cover_count[unit] += 1 } }
      # Map id -> original units so evaluate always decrements the right set.
      @original_units = originals.each_with_object({}) { |fp, h| h[fp.id] = fp.units }
    end

    def apply(candidates)
      removable = candidates.reject(&:review_only).sort_by { |c| c.footprint.id }
      removable.each { |candidate| evaluate(candidate) }
      candidates
    end

    private

    def evaluate(candidate)
      units = @original_units.fetch(candidate.footprint.id, candidate.footprint.units)
      at_risk = units.reject { |unit| @cover_count[unit] >= 2 }

      if at_risk.empty?
        candidate.safe = true
        units.each { |unit| @cover_count[unit] -= 1 }
      else
        candidate.safe = false
        candidate.safety_note = "would leave #{at_risk.size} unit(s) with no other test"
      end
    end
  end
end
