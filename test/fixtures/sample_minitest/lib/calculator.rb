# frozen_string_literal: true

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
