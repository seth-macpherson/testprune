# frozen_string_literal: true

require 'testprune/ui/styles'

module Testprune
  module UI
    # Live scan progress display. Shows a Braille spinner, running test counter,
    # and elapsed time. All output goes to io (default $stderr) and is suppressed
    # when not a TTY or when NO_COLOR is set.
    class Progress
      FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

      def initialize(io: $stderr)
        @io       = io
        @counter  = 0
        @frame    = 0
        @thread   = nil
        @mu       = Mutex.new
      end

      def tty?
        return false if ENV['NO_COLOR']
        @io.respond_to?(:isatty) && @io.isatty
      end

      def start
        return unless tty?
        @start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @thread = Thread.new do
          loop do
            draw
            sleep 0.1
          end
        end
      end

      def increment(count: 1)
        @mu.synchronize { @counter += count }
      end

      # Stops the spinner thread and clears the line. Returns stats hash.
      def stop(test_count:, elapsed:)
        @thread&.kill
        @thread&.join(0.2)
        @thread = nil
        @io.print("\r\e[K") if tty?
        { test_count: test_count, elapsed: elapsed }
      end

      private

      def draw
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start
        count   = @mu.synchronize { @counter }
        frame   = FRAMES[@frame % FRAMES.size]
        @frame += 1
        mins    = (elapsed / 60).to_i
        secs    = (elapsed % 60).to_i
        time_s  = format('%02d:%02d', mins, secs)
        line    = "#{Styles::PURPLE_TEXT.render(frame)}  Running suite…   " \
                  "#{Styles::GREEN_TEXT.render(count.to_s)} tests   " \
                  "#{Styles::META_TEXT.render(time_s)} elapsed"
        @io.print("\r\e[K#{line}")
        @io.flush
      end
    end
  end
end
