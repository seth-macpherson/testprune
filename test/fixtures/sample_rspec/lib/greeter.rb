# frozen_string_literal: true

class Greeter
  def greet(name)
    if name.nil? || name.empty?
      'Hello, stranger'
    else
      "Hello, #{name}"
    end
  end
end
