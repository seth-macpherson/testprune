# frozen_string_literal: true

require 'test_helper'
require 'testprune/ui/progress'

module Testprune
  module UI
    class ProgressTest < Minitest::Test
      def test_frames_defined
        assert_kind_of Array, Progress::FRAMES
        refute_empty Progress::FRAMES
      end

      def test_tty_false_for_stringio
        io = StringIO.new
        p = Progress.new(io: io)
        refute p.tty?
      end

      def test_stop_returns_stats
        io = StringIO.new
        p = Progress.new(io: io)
        p.start
        p.increment
        p.increment
        result = p.stop(test_count: 2, elapsed: 1.23)
        assert_equal 2, result[:test_count]
        assert_in_delta 1.23, result[:elapsed], 0.01
      end

      def test_no_output_when_not_tty
        io = StringIO.new
        p = Progress.new(io: io)
        p.start
        sleep 0.15
        p.stop(test_count: 0, elapsed: 0.1)
        assert_empty io.string, 'Expected no output to non-TTY io'
      end
    end
  end
end
