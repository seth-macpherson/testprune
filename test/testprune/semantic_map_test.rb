# frozen_string_literal: true

require 'test_helper'
require 'tempfile'

class SemanticMapTest < Minitest::Test
  SOURCE = <<~RUBY
    class Calculator
      def add(a, b)
        a + b
      end

      def classify(n)
        if n.positive?
          :positive
        else
          :nonpositive
        end
      end
    end
  RUBY

  def map
    @map ||= begin
      file = Tempfile.create(['calc', '.rb'])
      file.write(SOURCE)
      file.flush
      Testprune::SemanticMap.new(file.path, SOURCE, 'lib/calculator.rb')
    end
  end

  def test_method_unit_resolves_qualified_label
    unit = map.method_unit(2, 2) # `def add` at line 2, col 2
    refute_nil unit
    assert_equal :method, unit.kind
    assert_includes unit.label, 'Calculator#add'
  end

  def test_branch_unit_labels_with_enclosing_control
    unit = map.branch_unit('then', 8, 6, 8, 15) # `:positive` arm
    assert_equal :branch, unit.kind
    assert_includes unit.label, 'if then-branch'
  end

  def test_opposite_branch_arms_are_distinct_units
    then_arm = map.branch_unit('then', 8, 6, 8, 15)
    else_arm = map.branch_unit('else', 10, 6, 10, 18)

    refute_equal then_arm.id, else_arm.id
  end

  def test_line_collapses_to_enclosing_method
    unit = map.line_unit(3) # `a + b` inside #add
    assert_equal map.method_unit(2, 2).id, unit.id
  end
end
