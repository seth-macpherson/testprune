# frozen_string_literal: true

require 'coverage'
require 'json'
require 'fileutils'
require_relative '../testprune'
require_relative 'coverage_delta'

module Testprune
  # Process-wide singleton that the framework adapters drive. It starts Coverage,
  # snapshots peek_result around each test, and writes run.json when the suite ends.
  class Recorder
    def self.instance
      @instance ||= new(Configuration.from_env)
    end

    # Used in testprune's own test suite to prevent Recorder state from leaking
    # between test runs (the singleton is normally process-scoped by design).
    def self.reset!
      @instance = nil
    end

    def initialize(config)
      @config = config
      @tests  = []
      @framework = nil
    end

    attr_accessor :framework

    # Start Coverage with all required options and keep it running for the
    # entire suite. Staying always-on means `Coverage.running?` is true before
    # SimpleCov (or any other coverage tool) loads, so they see it already
    # running and skip their own `Coverage.start` call — no guard needed in
    # test_helper.rb. Per-test footprints are captured by diffing `peek_result`
    # snapshots before and after each test; `peek_result` is non-destructive so
    # SimpleCov's final `Coverage.result` call at suite end still gets the full
    # aggregate unaffected.
    def start_coverage
      return if @started

      Coverage.setup(lines: true, branches: true, methods: true)
      Coverage.resume
      @started = true
    end

    # Bracket a single test (RSpec around(:each)). Minitest uses start_test/
    # finish_test directly from lifecycle hooks instead, to avoid wrapping #run.
    def around(id:, file:, line:, description: nil)
      start_test
      begin
        yield
      ensure
        finish_test(id: id, file: file, line: line, description: description)
      end
    end

    # Snapshot coverage counts before the test begins.
    def start_test
      @before = Coverage.peek_result
      @test_started = monotonic
    end

    # Record this test's coverage delta + wall time. Coverage keeps running
    # between tests — the peek_result diff is accurate for serial suites because
    # nothing else executes between start_test and finish_test.
    def finish_test(id:, file:, line:, description: nil)
      wall = monotonic - @test_started
      delta = CoverageDelta.compute(@before, Coverage.peek_result, @config)
      @tests << {
        'id'          => id,
        'description' => description || id,
        'file'        => file && File.expand_path(file),
        'line'        => line,
        'wall_time'   => wall,
        'coverage'    => delta
      }
    end

    def dump
      return if @dumped

      @dumped = true
      FileUtils.mkdir_p(@config.output_dir)
      File.write(@config.run_file, JSON.generate(payload))
    end

    private

    def payload
      {
        'root'      => @config.root,
        'framework' => @framework,
        'tests'     => @tests
      }
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
