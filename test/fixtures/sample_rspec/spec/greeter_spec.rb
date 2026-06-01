# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'greeter'

RSpec.describe Greeter do
  subject(:greeter) { described_class.new }

  it 'greets a named person' do
    expect(greeter.greet('Sam')).to eq('Hello, Sam')
  end

  # Same coverage as the example above (only the else branch) -> redundant.
  it 'greets another named person' do
    expect(greeter.greet('Alex')).to eq('Hello, Alex')
  end

  it 'greets a stranger when the name is empty' do
    expect(greeter.greet('')).to eq('Hello, stranger')
  end
end
