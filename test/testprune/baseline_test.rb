# frozen_string_literal: true

require 'test_helper'

class BaselineTest < Minitest::Test
  include FootprintHelpers

  def test_units_at_or_above_fraction_are_ambient
    # :setup is in all 4 tests (100%); :a/:b/:c/:d are in one each (25%).
    fps = [
      footprint('t1', :setup, :a),
      footprint('t2', :setup, :b),
      footprint('t3', :setup, :c),
      footprint('t4', :setup, :d)
    ]

    ambient = Testprune::Baseline.ambient_units(fps, 0.5)

    assert_equal Set[:setup], ambient, 'only the unit shared by >= 50% of tests is ambient'
  end

  def test_threshold_is_inclusive_at_the_fraction
    # :shared is in exactly 2 of 4 tests (50%); at fraction 0.5 it is ambient.
    fps = [footprint('t1', :shared), footprint('t2', :shared),
           footprint('t3', :x), footprint('t4', :y)]

    assert_equal Set[:shared], Testprune::Baseline.ambient_units(fps, 0.5)
  end

  def test_nil_or_full_fraction_disables_subtraction
    fps = [footprint('t1', :setup), footprint('t2', :setup)]

    assert_empty Testprune::Baseline.ambient_units(fps, nil)
    assert_empty Testprune::Baseline.ambient_units(fps, 1.1)
  end

  # fraction == 1.0 must disable subtraction (not strip every unit): the comment
  # documents ">= 1.0 disables". The old guard used `> 1.0`, missing this boundary.
  def test_fraction_exactly_one_disables_subtraction
    fps = [footprint('t1', :setup), footprint('t2', :setup)]

    assert_empty Testprune::Baseline.ambient_units(fps, 1.0),
                 'fraction 1.0 must disable subtraction entirely, not strip 100%-present units'
  end

  # fraction <= 0 should disable subtraction (0 means "ambient threshold = 0%",
  # which would strip every unit — the CLI maps --baseline 0 to nil, but direct
  # API callers deserve the same safety net).
  def test_fraction_zero_or_negative_disables_subtraction
    fps = [footprint('t1', :a), footprint('t2', :b)]

    assert_empty Testprune::Baseline.ambient_units(fps, 0.0),
                 'fraction 0.0 must disable subtraction'
    assert_empty Testprune::Baseline.ambient_units(fps, -0.1),
                 'negative fraction must disable subtraction'
  end
end
