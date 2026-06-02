# frozen_string_literal: true

require 'test_helper'
require 'testprune/ui/error_toggle'

module Testprune
  module UI
    class ErrorToggleTest < Minitest::Test
      def test_run_returns_immediately_with_no_errors
        io = StringIO.new
        et = ErrorToggle.new(errors: [], io: io)
        # Should not call $stdin at all — would hang if it did
        et.run
        assert_empty io.string
      end

      def test_skips_errors_on_enter
        io = StringIO.new
        # Simulate pressing Enter (no 'e')
        stdin = StringIO.new("\n")
        et = ErrorToggle.new(errors: ['Error: something broke'], io: io, stdin: stdin)
        et.run
        refute_includes io.string, 'Error: something broke'
      end

      def test_shows_errors_on_e_then_hides_on_enter
        io = StringIO.new
        # Simulate: 'e' + Enter (show), then just Enter (skip/hide)
        stdin = StringIO.new("e\n\n")
        et = ErrorToggle.new(errors: ['Failure: bad assertion'], io: io, stdin: stdin)
        et.run
        assert_includes io.string, 'Failure: bad assertion'
      end

      def test_ansi_free_on_non_tty
        io = StringIO.new
        stdin = StringIO.new("e\n\n")
        et = ErrorToggle.new(errors: ['Error: oops'], io: io, stdin: stdin)
        et.run
        # StringIO is not a TTY → lipgloss NO_COLOR path → no ANSI escapes
        refute_includes io.string, "\e["
      end
    end
  end
end
