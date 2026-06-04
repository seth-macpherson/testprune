# frozen_string_literal: true

require 'test_helper'
require 'set'
require 'testprune/footprint'
require 'testprune/duplication_detector'
require 'testprune/review_plan'

module Testprune
  class ReviewPlanTest < Minitest::Test
    ROOT = '/repo'

    def fp(id, file, line, units)
      Footprint.new(id: id, file: file, line: line, wall_time: 0.0, units: Set.new(units))
    end

    def cand(footprint, group:, keeper:, confidence: :high, safe: true, review_only: false)
      Candidate.new(footprint: footprint, group: group, confidence: confidence,
                    reason: "x", kept_by: [keeper], review_only: review_only, safe: safe)
    end

    # Two identical removals sharing one keeper, plus one review-only structural.
    def make_result
      keeper   = fp('A::T#keep',    "#{ROOT}/test/a_test.rb", 10, %w[u1 u2])
      dup1     = fp('A::T#dup_one', "#{ROOT}/test/a_test.rb", 20, %w[u1 u2])
      dup2     = fp('A::T#dup_two', "#{ROOT}/test/a_test.rb", 30, %w[u1 u2])
      struct   = fp('B::T#struct',  "#{ROOT}/test/b_test.rb", 5,  %w[u3])

      c1 = cand(dup1,   group: :identical,  keeper: keeper.id)
      c2 = cand(dup2,   group: :identical,  keeper: keeper.id)
      c3 = cand(struct, group: :structural, keeper: 'B::T#k2', confidence: :medium,
                        safe: nil, review_only: true)

      footprints = [keeper, dup1, dup2, struct]
      build_result(candidates: [c1, c2, c3], approved: [c1, c2], footprints: footprints)
    end

    def build_result(candidates:, approved:, footprints:)
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

    def test_identical_tier_comes_first
      plan = ReviewPlan.build(make_result)
      assert_equal :identical, plan.first.tier
    end

    def test_groups_members_under_shared_keeper
      plan    = ReviewPlan.build(make_result)
      ident   = plan.find { |t| t.tier == :identical }
      assert_equal 1, ident.clusters.size, 'two dups of one keeper => one cluster'
      cluster = ident.clusters.first
      assert_equal 2, cluster.size
      assert_equal 'A::T#keep', cluster.keeper.id
    end

    def test_paths_are_relativized_to_root
      plan = ReviewPlan.build(make_result)
      loc  = plan.first.clusters.first.members.first.loc
      assert_equal 'test/a_test.rb', loc.file
      assert_equal '#dup_one', loc.method
    end

    def test_actionable_only_excludes_review_only_tiers
      plan  = ReviewPlan.build(make_result, actionable_only: true)
      tiers = plan.map(&:tier)
      assert_includes tiers, :identical
      refute_includes tiers, :structural, 'review-only tiers are not patchable'
    end

    def test_unit_count_recorded
      plan = ReviewPlan.build(make_result)
      assert_equal 2, plan.first.clusters.first.keeper.unit_count
    end
  end
end
