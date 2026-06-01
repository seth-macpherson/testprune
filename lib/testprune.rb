# frozen_string_literal: true

require_relative 'testprune/version'
require_relative 'testprune/configuration'

module Testprune
  class Error < StandardError; end

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end
  end
end
