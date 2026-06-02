# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require_relative '../testprune'
require_relative 'ui'

module Testprune
  # Boots the target project's suite in a subprocess, instrumented so the adapters
  # capture per-test coverage. Reuses the gem's lib via RUBYOPT (-I) so the target
  # project does not need testprune in its Gemfile.
  class Runner
    # Progress-line patterns: match single-char Minitest/RSpec progress indicators.
    TEST_PROGRESS_RE = /\A[.FES*P]+\z/
    # Lines that indicate a test error or failure.
    ERROR_RE = /Error:|FAILED|Failure:|error:/

    def initialize(config)
      @config = config
    end

    # explicit_command: array form of a user-supplied test command (after `--`), or nil.
    # verbose: when true, stream raw output directly (no capture, no spinner).
    def call(explicit_command = nil, verbose: false)
      framework, command = resolve(explicit_command)

      FileUtils.mkdir_p(@config.output_dir)
      File.delete(@config.run_file) if File.exist?(@config.run_file)

      if verbose
        warn("testprune: framework=#{framework}  running: #{command.join(' ')}")
        ok = system(env, *command, chdir: @config.root)
      else
        ok = run_captured(framework, command)
      end

      unless File.exist?(@config.run_file)
        raise Error, 'suite finished but no run.json was captured — the adapter may ' \
                     'not have loaded. Check the framework/command and source paths.'
      end

      count = begin
        JSON.parse(File.read(@config.run_file)).fetch('tests', []).size
      rescue JSON::ParserError
        '(unreadable — suite may have been interrupted mid-write)'
      end

      unless verbose
        warn("testprune: captured #{count} test(s) -> #{@config.run_file}")
      end

      ok
    end

    def command_for_paths(paths)
      bundler = File.exist?(File.join(@config.root, 'Gemfile'))
      prefix  = bundler ? %w[bundle exec] : []
      if File.directory?(File.join(@config.root, 'spec'))
        prefix + %w[rspec] + paths
      elsif File.exist?(File.join(@config.root, 'bin', 'rails'))
        prefix + %w[rails test] + paths
      else
        prefix + %w[rake test] + paths
      end
    end

    private

    def run_captured(framework, command)
      progress   = UI::Progress.new(io: $stderr)
      output     = []
      error_lines = []

      progress.start
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      ok = Open3.popen2e(env, *command, chdir: @config.root) do |_stdin, oe, wait_thr|
        oe.each_line do |line|
          output << line
          # Count progress chars
          progress.increment if line.match?(TEST_PROGRESS_RE)
          error_lines << line.chomp if line.match?(ERROR_RE)
        end
        wait_thr.value.success?
      end

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      test_count = begin
        File.exist?(@config.run_file) ? JSON.parse(File.read(@config.run_file)).fetch('tests', []).size : 0
      rescue StandardError
        0
      end

      progress.stop(test_count: test_count, elapsed: elapsed)
      print_scan_summary(test_count, elapsed, error_lines)

      ok
    end

    def print_scan_summary(test_count, elapsed, error_lines)
      mins = (elapsed / 60).to_i
      secs = (elapsed % 60).to_i
      time_s = format('%02d:%02d', mins, secs)

      if UI.tty?($stderr)
        lines = []
        lines << "  #{UI::Styles::GREEN_TEXT.render('✓')}  Scan complete"
        lines << "     #{test_count} tests · #{time_s} elapsed"
        lines << "     Data written to #{@config.output_dir}/"
        $stderr.puts UI::Styles::SUCCESS_BOX.render(lines.join("\n"))
      else
        $stderr.puts("testprune: scan complete — #{test_count} tests in #{time_s}")
      end

      return if error_lines.empty?

      UI::ErrorToggle.new(errors: error_lines, io: $stderr).run
    end

    def env
      gem_lib = File.expand_path('..', __dir__)
      rubyopt = ["-I#{gem_lib}", '-rtestprune/autostart', ENV['RUBYOPT']].compact.reject(&:empty?).join(' ')
      @config.to_env.merge('RUBYOPT' => rubyopt)
    end

    def resolve(explicit_command)
      if explicit_command && !explicit_command.empty?
        [framework_of(explicit_command.join(' ')), explicit_command]
      else
        autodetect
      end
    end

    def framework_of(command_string)
      command_string.include?('rspec') ? :rspec : :minitest
    end

    def autodetect
      bundler = File.exist?(File.join(@config.root, 'Gemfile'))
      prefix  = bundler ? %w[bundle exec] : []

      if File.directory?(File.join(@config.root, 'spec'))
        [:rspec, prefix + ['rspec']]
      elsif File.directory?(File.join(@config.root, 'test'))
        [:minitest, prefix + ['rake', 'test']]
      else
        raise Error, 'could not autodetect a test suite (no spec/ or test/ dir). ' \
                     'Pass an explicit command after `--`.'
      end
    end
  end
end
