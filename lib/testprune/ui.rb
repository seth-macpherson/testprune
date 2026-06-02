# frozen_string_literal: true

require 'lipgloss'
require_relative 'ui/styles'
require_relative 'ui/progress'
require_relative 'ui/error_toggle'
require_relative 'ui/report_renderer'

module Testprune
  # Terminal UI components built on lipgloss-ruby.
  # All components degrade gracefully when NO_COLOR=1 is set or output is not a TTY.
  module UI
    # Returns true when styled output is appropriate for the given IO.
    # Respects NO_COLOR (https://no-color.org/) and non-TTY output streams.
    def self.tty?(io = $stdout)
      return false if ENV['NO_COLOR']

      io.respond_to?(:isatty) && io.isatty
    end
  end
end
