# frozen_string_literal: true

require 'set'

module Testprune
  # Identifies "ambient" coverage units — ones executed by so many tests that they
  # carry no signal about what a given test is *for*. In real suites these come
  # from shared `setup`/fixture code (e.g. creating a User fires the same callbacks
  # in hundreds of tests). Left in, they make unrelated tests look identical and
  # produce false "redundant" clusters, so the detector subtracts them first.
  module Baseline
    # A unit is ambient if it appears in >= fraction of all tests. fraction nil,
    # <= 0, or >= 1.0 disables subtraction entirely.
    def self.ambient_units(footprints, fraction)
      return Set.new if fraction.nil? || fraction <= 0.0 || fraction >= 1.0 || footprints.empty?

      threshold = (footprints.size * fraction).ceil
      counts = Hash.new(0)
      footprints.each { |fp| fp.units.each { |unit| counts[unit] += 1 } }
      counts.select { |_unit, count| count >= threshold }.keys.to_set
    end
  end
end
