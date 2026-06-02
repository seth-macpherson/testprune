# frozen_string_literal: true

require 'testprune/ui/styles'

module Testprune
  module UI
    # Post-scan interactive prompt. When test errors occurred (non-blocking),
    # shows a count indicator and lets the user toggle the error detail on/off
    # before continuing the workflow.
    class ErrorToggle
      def initialize(errors:, io: $stderr, stdin: $stdin)
        @errors   = errors
        @io       = io
        @stdin    = stdin
        @expanded = false
      end

      def run
        return if @errors.empty?

        print_indicator
        loop do
          @io.print("  [e + Enter] #{styled('[e]', Styles::PURPLE_TEXT)} show/hide errors" \
                    "  [Enter] skip > ")
          @io.flush
          input = @stdin.gets&.strip&.downcase
          break if input.nil? || input.empty?
          if input == 'e'
            @expanded = !@expanded
            @expanded ? print_errors : clear_errors
          end
        end
      end

      private

      def tty?
        return false if ENV['NO_COLOR']
        @io.respond_to?(:isatty) && @io.isatty
      end

      def styled(text, style)
        tty? ? style.render(text) : text
      end

      def print_indicator
        label = styled("⚠  #{@errors.size} test error(s) detected", Styles::AMBER_TEXT)
        note  = styled('  (non-blocking — scan completed)', Styles::META_TEXT)
        @io.puts("#{label}#{note}")
      end

      def print_errors
        sep = styled('  ' + '─' * 62, Styles::DIM_TEXT)
        @io.puts(sep)
        @errors.each { |line| @io.puts("    #{styled(line, Styles::ERROR_TEXT)}") }
        @io.puts(sep)
      end

      def clear_errors
        # Errors are already scrolled — just note they're hidden
        @io.puts(styled('  (errors hidden)', Styles::DIM_TEXT))
      end
    end
  end
end
