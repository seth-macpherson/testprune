# frozen_string_literal: true

require 'test_helper'

# The safety check is the gem's hard guarantee. These tests must fail if the
# cascading invariant ever breaks — i.e. if removing a set of tests could drop a
# semantic unit's coverage to zero.
class SafetyCheckTest < Minitest::Test
  include FootprintHelpers

  def test_jointly_unsafe_removals_demote_one
    # Unit :x is covered ONLY by t1 and t2. If the detector ever proposed removing
    # both, the cascade must keep exactly one so :x stays covered.
    t1 = footprint('t1', :x)
    t2 = footprint('t2', :x)
    candidates = [removal(t1), removal(t2)]

    Testprune::SafetyCheck.new([t1, t2]).apply(candidates)

    assert_equal 1, candidates.count(&:safe), 'exactly one removal may be safe'
    refute candidates.all?(&:safe), 'both must not be safe — that would uncover :x'

    # SafetyCheck evaluates in sorted id order (t1 before t2). t1 is approved first
    # (cover_count[:x] was 2), then t2 is demoted (cover_count[:x] is now 1 < 2).
    safe_candidate   = candidates.find(&:safe)
    demoted_candidate = candidates.find { |c| c.safe == false }
    assert_equal 't1', safe_candidate.footprint.id,   't1 (lower id) is approved first'
    assert_equal 't2', demoted_candidate.footprint.id, 't2 is demoted because :x count drops to 1'
    refute_nil demoted_candidate.safety_note
  end

  # Three-way cascade: t1, t2, t3 all cover :x exclusively. The first two pass the
  # safety check, the third must be demoted — the safety guarantee holds for any
  # number of candidates, not just pairs.
  def test_three_way_cascade_demotes_third_candidate
    t1 = footprint('t1', :x)
    t2 = footprint('t2', :x)
    t3 = footprint('t3', :x)
    candidates = [removal(t1), removal(t2), removal(t3)]

    Testprune::SafetyCheck.new([t1, t2, t3]).apply(candidates)

    assert_equal 2, candidates.count(&:safe),
                 'two removals are safe when three tests cover a unit'
    assert_equal 1, candidates.count { |c| c.safe == false },
                 'exactly one is demoted — :x must remain covered'
    demoted = candidates.find { |c| c.safe == false }
    assert_equal 't3', demoted.footprint.id,
                 't3 (last in sorted order) is demoted after t1 and t2 are approved'
    refute_nil demoted.safety_note
  end

  def test_removal_is_safe_when_a_retained_test_still_covers_each_unit
    # :x covered by keeper + candidate; removing the candidate leaves the keeper.
    keeper    = footprint('keeper', :x, :y)
    candidate = footprint('cand', :x)
    cands = [removal(candidate)]

    Testprune::SafetyCheck.new([keeper, candidate]).apply(cands)

    assert cands.first.safe
  end

  def test_unique_coverage_is_never_safe_to_remove
    only = footprint('only', :unique)
    cands = [removal(only)]

    Testprune::SafetyCheck.new([only]).apply(cands)

    refute cands.first.safe
  end

  def test_review_only_candidates_are_not_evaluated
    fp = footprint('t', :x)
    candidate = Testprune::Candidate.new(footprint: fp, confidence: :low, group: :overlap,
                                         reason: 'r', kept_by: [], review_only: true)

    Testprune::SafetyCheck.new([fp]).apply([candidate])

    assert_nil candidate.safe
  end
end
