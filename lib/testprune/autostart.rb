# frozen_string_literal: true

# Loaded via `RUBYOPT=-r testprune/autostart` in the instrumented subprocess.
# Starts Coverage (lines + branches + methods) immediately and keeps it running
# for the entire suite. Starting early means every file compiled after this point
# is measurable. Keeping Coverage always-on means `Coverage.running?` is true
# before SimpleCov or any other coverage tool loads, so they skip their own
# Coverage.start and no guard is needed in test_helper.rb. Then watches for the
# test framework to be defined and installs the matching adapter.
require_relative 'recorder'

warn "[testprune-debug] autostart loaded in pid #{Process.pid}" if ENV['TESTPRUNE_DEBUG']

Testprune::Recorder.instance.start_coverage

# Fallback: ensure run.json is written even if the suite crashes before the
# framework's after-suite hook fires (unhandled exception, SIGTERM, etc.).
# The @dumped flag in Recorder prevents double-writes on clean exits.
at_exit { Testprune::Recorder.instance.dump }

installed = false
tracepoint = TracePoint.new(:end) do
  next if installed

  if defined?(::Minitest::Test)
    installed = true
    require_relative 'adapters/minitest'
    recorder = Testprune::Recorder.instance
    recorder.framework = 'minitest'
    Testprune::Adapters::Minitest.install
    ::Minitest.after_run { Testprune::Recorder.instance.dump }
  elsif defined?(::RSpec) && ::RSpec.respond_to?(:configure)
    installed = true
    require_relative 'adapters/rspec'
    Testprune::Adapters::RSpec.install
  end

  tracepoint.disable if installed
end
tracepoint.enable
