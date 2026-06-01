# frozen_string_literal: true

require 'test_helper'

class DuplicationDetectorTest < Minitest::Test
  include FootprintHelpers

  def detect(footprints, **opts)
    Testprune::DuplicationDetector.new(footprints, **opts).call
  end

  def test_identical_footprints_keep_one_and_flag_the_rest_high
    a = footprint('a', :u1, :u2)
    b = footprint('b', :u1, :u2)
    c = footprint('c', :u1, :u2)

    result = detect([a, b, c])
    removed = result.candidates.map { |x| x.footprint.id }

    assert_equal 2, result.candidates.size
    assert(result.candidates.all? { |x| x.confidence == :high && x.group == :identical })
    assert_equal %w[a], (%w[a b c] - removed), 'lowest id is kept'
    assert result.approved_removals.size == 2, 'both duplicates are safe to remove'
  end

  def test_strict_subset_is_flagged_high_and_safe
    small = footprint('small', :u1)
    big   = footprint('big', :u1, :u2)

    result = detect([small, big])

    assert_equal 1, result.candidates.size
    candidate = result.candidates.first
    assert_equal 'small', candidate.footprint.id
    assert_equal :subset, candidate.group
    assert candidate.safe
    assert_equal ['big'], candidate.kept_by
  end

  def test_opposite_branch_arms_are_not_duplicates
    # Mirrors the real fixture: both touch the same method but different branch
    # arms. Sharing only the method (Jaccard 1/3) must not flag either.
    positive = footprint('positive', :classify_method, :then_branch)
    negative = footprint('negative', :classify_method, :else_branch)

    result = detect([positive, negative])

    assert_empty result.candidates
  end

  def test_high_overlap_non_subset_is_low_review_only
    a = footprint('a', :u1, :u2, :u3, :u4, :u5, :u6, :u7, :u8, :u9, :a_only)
    b = footprint('b', :u1, :u2, :u3, :u4, :u5, :u6, :u7, :u8, :u9, :b_only)

    result = detect([a, b], overlap_threshold: 0.8)

    overlap = result.candidates.select { |c| c.group == :overlap }
    assert_equal 1, overlap.size
    assert_equal :low, overlap.first.confidence
    assert overlap.first.review_only
    assert_empty result.approved_removals
  end

  def test_unique_tests_yield_no_candidates
    result = detect([footprint('a', :x), footprint('b', :y)])

    assert_empty result.candidates
  end

  # The tportal false-positive: several unrelated tests share only shared-setup
  # units (:s1/:s2 here, run by every test). Without baseline subtraction they
  # look "identical" and all-but-one get flagged HIGH — a dangerous false positive.
  # With baseline on, the setup units are ambient, those footprints become empty,
  # and nothing is proposed. This is the test that must fail if the guard breaks.
  def test_setup_only_footprints_are_not_flagged_when_baseline_on
    fps = [
      footprint('t1', :s1, :s2),
      footprint('t2', :s1, :s2),
      footprint('t3', :s1, :s2),
      footprint('t4', :s1, :s2, :x)
    ]

    # Control: without the guard, the shared-setup tests are wrongly flagged.
    assert_equal 2, detect(fps).candidates.size

    # With the guard: ambient setup is stripped, no false positives.
    assert_empty detect(fps, baseline_fraction: 0.5).candidates
  end

  # Baseline must not blind us to *real* redundancy: two tests whose distinctive
  # (non-setup) coverage is identical are still flagged, even with the guard on.
  # Identical coverage across DIFFERENT test files is the tportal false positive:
  # e.g. many `test_perform__af_pay_disabled` tests in different job classes all
  # hit the same 3-line guard but assert about different jobs. Such cross-file
  # equivalence must be demoted to LOW review-only, never auto-removed.
  def test_cross_file_identical_coverage_is_demoted_to_review
    a = footprint('JobATest#test_disabled', :guard1, :guard2, file: 'test/jobs/job_a_test.rb')
    b = footprint('JobBTest#test_disabled', :guard1, :guard2, file: 'test/jobs/job_b_test.rb')

    result = detect([a, b])

    assert_equal 1, result.candidates.size
    candidate = result.candidates.first
    assert_equal :low, candidate.confidence
    assert candidate.review_only
    assert_empty result.approved_removals, 'cross-file equivalence is never auto-removable'
  end

  def test_same_file_identical_coverage_stays_high
    a = footprint('SameTest#test_x', :u1, :u2, file: 'test/same_test.rb')
    b = footprint('SameTest#test_y', :u1, :u2, file: 'test/same_test.rb')

    result = detect([a, b])

    assert_equal 1, result.candidates.size
    assert_equal :high, result.candidates.first.confidence
    assert_equal 1, result.approved_removals.size
  end

  # Locality gate also applies to SUBSET: A ⊊ B but in different files → LOW review-only.
  def test_cross_file_subset_coverage_is_demoted_to_review
    small = footprint('FileA#test_thing', :u1,      file: 'test/file_a_test.rb')
    big   = footprint('FileB#test_thing', :u1, :u2, file: 'test/file_b_test.rb')

    result = detect([small, big])

    assert_equal 1, result.candidates.size
    candidate = result.candidates.first
    assert_equal :subset, candidate.group
    assert_equal :low, candidate.confidence
    assert candidate.review_only
    assert_empty result.approved_removals, 'cross-file subset is never auto-removable'
  end

  # Detect handles an empty footprint list without crashing.
  def test_empty_footprint_list_yields_no_candidates
    result = detect([])

    assert_empty result.candidates
    assert_equal 0, result.footprints.size
  end

  # nil file on both sides: same_file?(nil, nil) must return false so we don't
  # accidentally grant HIGH confidence to tests with unknown file metadata.
  def test_identical_coverage_with_nil_file_is_demoted_not_high
    a = footprint('a', :u1, :u2, file: nil)
    b = footprint('b', :u1, :u2, file: nil)

    result = detect([a, b])

    assert_equal 1, result.candidates.size
    assert_equal :low, result.candidates.first.confidence,
                 'nil==nil must not satisfy the locality gate — confidence stays LOW'
    assert_empty result.approved_removals
  end

  def test_genuine_duplicate_survives_baseline
    fps = [
      footprint('dup1', :setup, :r),
      footprint('dup2', :setup, :r),
      footprint('t3', :setup, :a),
      footprint('t4', :setup, :b),
      footprint('t5', :setup, :c),
      footprint('t6', :setup, :d)
    ]

    result = detect(fps, baseline_fraction: 0.5)

    assert_equal 1, result.candidates.size
    candidate = result.candidates.first
    assert_equal 'dup2', candidate.footprint.id
    assert_equal :identical, candidate.group
    assert_equal ['dup1'], candidate.kept_by
    assert candidate.safe, 'distinctive unit :r still covered by retained dup1'
  end
end
