# frozen_string_literal: true

require 'minitest/autorun'
require 'calculator'

class CalculatorTest < Minitest::Test
  def setup
    @calc = Calculator.new
  end

  def test_add
    assert_equal 3, @calc.add(1, 2)
  end

  # Same footprint as test_add (only exercises #add) -> redundant candidate.
  def test_add_again
    assert_equal 5, @calc.add(2, 3)
  end

  def test_positive
    assert_equal :positive, @calc.classify(4)
  end

  # Opposite branch of the same if -> must NOT be flagged as a duplicate.
  def test_nonpositive
    assert_equal :nonpositive, @calc.classify(-1)
  end
end
