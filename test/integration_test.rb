# frozen_string_literal: true

require 'test_helper'
require 'open3'

# Drives the real CLI end-to-end against the bundled Minitest fixture: capture a
# run, analyze it, and emit a patch. Proves the adapter loads, the redundant test
# is found at HIGH confidence, and the opposite-branch tests are not auto-removed.
class IntegrationTest < Minitest::Test
  GEM_ROOT = File.expand_path('..', __dir__)
  LIB      = File.join(GEM_ROOT, 'lib')
  EXE      = File.join(GEM_ROOT, 'exe', 'testprune')
  FIXTURE  = File.join(GEM_ROOT, 'test', 'fixtures', 'sample_minitest')

  def setup
    FileUtils.rm_rf(File.join(FIXTURE, 'tmp', '.testprune'))
  end

  def teardown
    FileUtils.rm_rf(File.join(FIXTURE, 'tmp', '.testprune'))
  end

  def cli(*args)
    out, _err, status = Open3.capture3(
      'ruby', "-I#{LIB}", EXE, *args, chdir: FIXTURE
    )
    [out.force_encoding('UTF-8'), status]
  end

  def test_capture_report_and_patch
    _, run_status = cli('scan', '-s', 'lib', '--',
                        'ruby', '-Itest', '-Ilib', 'test/calculator_test.rb')
    assert run_status.success?
    assert File.exist?(File.join(FIXTURE, 'tmp', '.testprune', 'run.json'))

    # Baseline subtraction is disabled here: with only 4 tests the deliberately
    # duplicated coverage is itself >= 50% prevalent, so the statistical
    # ambient-unit guard would (correctly, for its purpose) strip it. This fixture
    # exercises detection mechanics, not the large-suite noise filter.
    report, report_status = cli('report', '-s', 'lib', '--baseline', '0')
    assert report_status.success?

    assert_match(/HIGH confidence/, report)
    assert_match(/test_add_again/, report, 'the redundant duplicate should be flagged HIGH')
    # The opposite-branch test must not be an auto-removable HIGH candidate.
    refute_match(/HIGH.*\n(?:.*\n)*?\s+\[\w+\] CalculatorTest#test_nonpositive/, report)
  end
end
