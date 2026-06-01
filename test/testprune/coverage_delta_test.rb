# frozen_string_literal: true

require 'test_helper'

class CoverageDeltaTest < Minitest::Test
  Config = Struct.new(:roots) do
    def source_file?(path)
      true
    end
  end

  def config
    Config.new
  end

  def test_line_counted_only_when_count_increases
    file = '/app/x.rb'
    before = { file => { lines: [nil, 1, 0, nil] } }
    after  = { file => { lines: [nil, 2, 0, nil] } } # line 2 ran again, line 3 still 0

    delta = Testprune::CoverageDelta.compute(before, after, config)

    assert_equal [2], delta[file]['lines']
  end

  def test_shared_coverage_attributed_via_count_diff
    # Even though line 2 was already executed by a prior test (count 5),
    # this test executing it again (6) must still attribute it.
    file = '/app/x.rb'
    before = { file => { lines: [nil, 5] } }
    after  = { file => { lines: [nil, 6] } }

    delta = Testprune::CoverageDelta.compute(before, after, config)

    assert_equal [2], delta[file]['lines']
  end

  def test_branch_arm_delta_records_location_and_type
    file = '/app/x.rb'
    node = [:if, 0, 1, 0, 5, 3]
    before = { file => { branches: { node => { [:then, 1, 2, 4, 2, 9] => 0, [:else, 2, 4, 4, 4, 9] => 0 } } } }
    after  = { file => { branches: { node => { [:then, 1, 2, 4, 2, 9] => 1, [:else, 2, 4, 4, 4, 9] => 0 } } } }

    delta = Testprune::CoverageDelta.compute(before, after, config)

    assert_equal [['then', 2, 4, 2, 9]], delta[file]['branches']
  end

  def test_method_delta_records_name_and_location
    file = '/app/x.rb'
    key = [Object, :foo, 1, 0, 3, 3]
    before = { file => { methods: { key => 0 } } }
    after  = { file => { methods: { key => 1 } } }

    delta = Testprune::CoverageDelta.compute(before, after, config)

    assert_equal [['foo', 1, 0, 3, 3]], delta[file]['methods']
  end

  def test_files_out_of_scope_are_dropped
    cfg = Config.new
    def cfg.source_file?(_path) = false
    before = { '/x.rb' => { lines: [nil, 0] } }
    after  = { '/x.rb' => { lines: [nil, 1] } }

    assert_empty Testprune::CoverageDelta.compute(before, after, cfg)
  end
end
