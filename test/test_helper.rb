# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'minitest/autorun'
require 'set'
require 'testprune'
require 'testprune/footprint'
require 'testprune/baseline'
require 'testprune/duplication_detector'
require 'testprune/safety_check'
require 'testprune/semantic_map'
require 'testprune/coverage_delta'

module FootprintHelpers
  # Footprints default to a shared file so identical/subset coverage earns HIGH
  # (same-scenario duplication). Pass distinct `file:` to exercise the locality
  # gate that demotes cross-file coverage-equivalence to review-only.
  def footprint(id, *units, file: 'test/shared_test.rb', line: nil, wall: 0.001)
    Testprune::Footprint.new(
      id: id, description: id, file: file, line: line, wall_time: wall,
      units: Set.new(units)
    )
  end

  # Minimal candidate proposing `fp` for removal, for testing SafetyCheck directly.
  def removal(fp)
    Testprune::Candidate.new(footprint: fp, confidence: :high, group: :identical,
                             reason: 'test', kept_by: [], review_only: false)
  end
end
