# frozen_string_literal: true

require 'test_helper'
require 'set'
require 'stringio'
require 'testprune/footprint'
require 'testprune/duplication_detector'
require 'testprune/ui/reviewer'

module Testprune
  module UI
    class ReviewerTest < Minitest::Test
      ROOT = '/repo'

      def fp(id, line, units)
        Footprint.new(id: id, file: "#{ROOT}/test/a_test.rb", line: line,
                      wall_time: 0.0, units: Set.new(units))
      end

      def cand(footprint, keeper:, group: :identical, confidence: :high, safe: true, review_only: false)
        Candidate.new(footprint: footprint, group: group, confidence: confidence,
                      reason: 'x', kept_by: [keeper], review_only: review_only, safe: safe)
      end

      # Two clusters: K1 has 2 dups, K2 has 1 dup; plus one review-only structural.
      def make_result
        k1 = fp('T#k1', 10, %w[u1 u2]); d1 = fp('T#d1', 20, %w[u1 u2]); d2 = fp('T#d2', 30, %w[u1 u2])
        k2 = fp('T#k2', 40, %w[u3]);    d3 = fp('T#d3', 50, %w[u3])
        s1 = fp('T#s1', 60, %w[u9])

        c1 = cand(d1, keeper: 'T#k1'); c2 = cand(d2, keeper: 'T#k1'); c3 = cand(d3, keeper: 'T#k2')
        sc = cand(s1, keeper: 'T#sk', group: :structural, confidence: :medium, safe: nil, review_only: true)

        build_result([c1, c2, c3, sc], [c1, c2, c3], [k1, d1, d2, k2, d3, s1])
      end

      def build_result(candidates, approved, footprints)
        dr = Object.new
        dr.define_singleton_method(:footprints) { footprints }
        r = Object.new
        r.define_singleton_method(:candidates)        { candidates }
        r.define_singleton_method(:approved_removals) { approved }
        r.define_singleton_method(:detector_result)   { dr }
        r.define_singleton_method(:run)               { { 'root' => ROOT } }
        r.define_singleton_method(:label_for)         { |id| id }
        r
      end

      def review(keys)
        out  = StringIO.new
        feed = keys.dup
        reviewer = Reviewer.new(make_result, output: out, color: false,
                                read_key: -> { feed.shift })
        [reviewer.run, out.string]
      end

      def test_accept_first_cluster_skip_second
        accepted, out = review(%w[a s])
        assert_equal 2, accepted.size, 'accepting the 2-dup cluster yields 2 removals'
        assert_includes out, 'cluster 1 / 2'
        assert_includes out, 'KEEP'
        assert_includes out, 'REMOVE'
      end

      def test_accept_all_clusters
        accepted, = review(%w[a a])
        assert_equal 3, accepted.size
      end

      def test_quit_writes_only_what_was_accepted
        accepted, out = review(%w[a q])
        assert_equal 2, accepted.size, 'quit after accepting cluster 1 keeps those removals'
        assert_includes out, 'Accepted'
      end

      def test_skip_everything_writes_nothing
        accepted, out = review(%w[s s])
        assert_empty accepted
        assert_includes out, 'no patch will be written'
      end

      def test_finish_summarizes_review_only_candidates
        _, out = review(%w[s s])
        assert_includes out, 'structurally duplicated body'
        assert_includes out, 'testprune report'
      end

      def test_identical_tier_reviewed_before_others
        # First cluster shown must be the largest identical cluster (K1, 2 members).
        _, out = review(%w[a a])
        first_screen = out.split('cluster 2').first
        assert_includes first_screen, ':20'
        assert_includes first_screen, ':30'
      end
    end
  end
end
