# frozen_string_literal: true

module Testprune
  # Estimates CI time recovered by removing the approved candidates. Reports
  # aggregate test time removed — honest about the fact that parallel runners mean
  # wall-clock savings are smaller.
  class SavingsEstimator
    def initialize(run, detector_result)
      @run = run
      @detector = detector_result
    end

    def approved_count
      @detector.approved_removals.size
    end

    def approved_time
      @detector.approved_removals.sum { |c| c.footprint.wall_time || 0.0 }
    end

    def total_test_time
      (@run['tests'] || []).sum { |t| t['wall_time'] || 0.0 }
    end

    def percent_of_test_time
      base = total_test_time
      base.zero? ? 0.0 : (approved_time / base * 100)
    end
  end
end
