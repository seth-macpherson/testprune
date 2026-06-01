# frozen_string_literal: true

require 'json'
require_relative '../testprune'
require_relative 'footprint'
require_relative 'duplication_detector'
require_relative 'savings_estimator'

module Testprune
  # Loads run.json, builds semantic footprints, runs detection + safety, and
  # bundles everything the report and patch writer need.
  class Analysis
    Result = Struct.new(:detector_result, :index, :savings, :run, keyword_init: true) do
      def candidates       = detector_result.candidates
      def approved_removals = detector_result.approved_removals
      def label_for(id)    = index.label_for(id)
      def ambient_units    = detector_result.ambient_units
      def setup_only       = detector_result.setup_only
    end

    def initialize(config)
      @config = config
    end

    def call
      unless File.directory?(@config.root)
        raise Error, "root directory #{@config.root.inspect} does not exist. " \
                     "Check TESTPRUNE_ROOT or --root."
      end

      unless File.exist?(@config.run_file)
        raise Error, "no captured data at #{@config.run_file}. Run `testprune run` first."
      end

      run = begin
        JSON.parse(File.read(@config.run_file))
      rescue JSON::ParserError => e
        raise Error, "run.json is not valid JSON (#{e.message}) — it may be truncated. " \
                     "Re-run 'testprune run'."
      end
      index = SemanticIndex.new(run['root'] || @config.root)
      footprints = index.build_footprints(run['tests'] || [])
      detector = DuplicationDetector.new(
        footprints,
        overlap_threshold: @config.overlap_threshold,
        baseline_fraction: @config.baseline_fraction
      ).call

      Result.new(detector_result: detector, index: index,
                 savings: SavingsEstimator.new(run, detector), run: run)
    end
  end
end
