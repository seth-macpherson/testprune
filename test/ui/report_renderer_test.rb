# frozen_string_literal: true

require 'test_helper'
require 'testprune/ui/report_renderer'
require 'set'

module Testprune
  module UI
    class ReportRendererTest < Minitest::Test
      # Minimal stub helpers
      Fp = Struct.new(:id, :file, :line, :units, :wall_time, keyword_init: true)
      Cand = Struct.new(:footprint, :confidence, :group, :reason, :kept_by,
                        :review_only, :safe, :safety_note, keyword_init: true)
      Savings = Struct.new(:approved_count, :approved_time, :total_test_time,
                           :percent_of_test_time, keyword_init: true)

      def make_result(candidates: [], approved: [])
        savings = Savings.new(
          approved_count: approved.size,
          approved_time: approved.sum { |c| c.footprint.wall_time },
          total_test_time: 100.0,
          percent_of_test_time: 0.0
        )
        stub = Object.new
        stub.define_singleton_method(:candidates)        { candidates }
        stub.define_singleton_method(:approved_removals) { approved }
        stub.define_singleton_method(:savings)           { savings }
        stub.define_singleton_method(:run)               { { 'framework' => 'minitest', 'tests' => [] } }
        stub.define_singleton_method(:ambient_units)     { 0 }
        stub.define_singleton_method(:setup_only)        { 0 }
        stub.define_singleton_method(:label_for)         { |id| id }
        dr = Object.new
        dr.define_singleton_method(:footprints) { [] }
        stub.define_singleton_method(:detector_result)   { dr }
        stub
      end

      def high_candidate
        fp = Fp.new(id: 'UserTest#test_foo', file: 'test/user_test.rb', line: 10,
                    units: Set.new(['unit1']), wall_time: 0.5)
        Cand.new(footprint: fp, confidence: :high, group: :identical,
                 reason: 'coverage is a strict subset', kept_by: ['OtherTest#test_bar'],
                 review_only: false, safe: true, safety_note: nil)
      end

      def medium_candidate
        fp = Fp.new(id: 'FooTest#test_baz', file: 'test/foo_test.rb', line: 20,
                    units: Set.new(['unit2']), wall_time: 0.3)
        Cand.new(footprint: fp, confidence: :medium, group: :structural,
                 reason: 'structurally duplicated body', kept_by: [],
                 review_only: true, safe: nil, safety_note: nil)
      end

      def test_render_returns_string
        result = make_result
        r = ReportRenderer.new(result)
        assert_kind_of String, r.render
      end

      def test_render_includes_header_info
        result = make_result
        r = ReportRenderer.new(result)
        output = r.render
        assert_includes output, 'minitest'
      end

      def test_high_section_present
        c = high_candidate
        result = make_result(candidates: [c], approved: [c])
        output = ReportRenderer.new(result).render
        assert_includes output, 'HIGH confidence'
        assert_includes output, 'UserTest#test_foo'
      end

      def test_medium_section_present
        c = medium_candidate
        result = make_result(candidates: [c])
        output = ReportRenderer.new(result).render
        assert_includes output, 'MEDIUM confidence'
        assert_includes output, 'FooTest#test_baz'
      end

      def test_safe_line_shown_for_high
        c = high_candidate
        result = make_result(candidates: [c], approved: [c])
        output = ReportRenderer.new(result).render
        assert_includes output, 'safe'
      end

      def test_identical_shows_both_cover
        c = high_candidate
        result = make_result(candidates: [c], approved: [c])
        output = ReportRenderer.new(result).render
        assert_includes output, 'both cover'
        refute_includes output, 'covers: '
      end

      def test_subset_shows_candidate_covers_and_keeper_adds
        keeper_fp = Fp.new(id: 'OtherTest#test_bar', file: 'test/user_test.rb', line: 20,
                           units: Set.new(%w[unit1 unit2 unit3]), wall_time: 0.6)
        candidate_fp = Fp.new(id: 'UserTest#test_foo', file: 'test/user_test.rb', line: 10,
                              units: Set.new(['unit1']), wall_time: 0.5)
        c = Cand.new(footprint: candidate_fp, confidence: :high, group: :subset,
                     reason: 'coverage is a strict subset of OtherTest#test_bar',
                     kept_by: ['OtherTest#test_bar'], review_only: false, safe: true, safety_note: nil)

        savings = Savings.new(approved_count: 1, approved_time: 0.5, total_test_time: 100.0, percent_of_test_time: 0.5)
        stub = Object.new
        stub.define_singleton_method(:candidates)        { [c] }
        stub.define_singleton_method(:approved_removals) { [c] }
        stub.define_singleton_method(:savings)           { savings }
        stub.define_singleton_method(:run)               { { 'framework' => 'minitest', 'tests' => [] } }
        stub.define_singleton_method(:ambient_units)     { 0 }
        stub.define_singleton_method(:setup_only)        { 0 }
        stub.define_singleton_method(:label_for)         { |id| id }
        dr = Object.new
        dr.define_singleton_method(:footprints) { [keeper_fp] }
        stub.define_singleton_method(:detector_result)   { dr }

        output = ReportRenderer.new(stub).render
        assert_includes output, 'candidate covers'
        assert_includes output, 'keeper adds'
      end

      def test_no_candidates_message
        result = make_result
        output = ReportRenderer.new(result).render
        assert_includes output, 'Nothing redundant found'
      end

      def test_savings_section_present_with_approved
        c = high_candidate
        result = make_result(candidates: [c], approved: [c])
        output = ReportRenderer.new(result).render
        assert_includes output, 'CI savings'
      end

      def test_no_ansi_when_no_color_set
        old = ENV['NO_COLOR']
        ENV['NO_COLOR'] = '1'
        c = high_candidate
        result = make_result(candidates: [c], approved: [c])
        output = ReportRenderer.new(result).render
        refute_includes output, "\e[", 'Expected no ANSI codes with NO_COLOR=1'
      ensure
        ENV['NO_COLOR'] = old
      end
    end
  end
end
