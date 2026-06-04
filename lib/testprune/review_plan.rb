# frozen_string_literal: true

require 'set'

module Testprune
  # Pure (IO-free) transformation of an Analysis::Result into an ordered, clustered
  # review plan. Candidates are ordered by tier — identical first — and within each
  # tier grouped by their *keeper*, so a reviewer can approve a whole cluster of
  # redundant tests in one decision instead of N. File paths are relativized to the
  # scan root here so every consumer renders short, consistent locations.
  module ReviewPlan
    # Review order. `actionable` tiers contain candidates that can actually be
    # patched (HIGH-confidence, safety-verified); the rest are review-only.
    TIERS = [
      { tier: :identical,  title: 'Identical coverage',          actionable: true  },
      { tier: :subset,     title: 'Subset / subsumed coverage',  actionable: true  },
      { tier: :structural, title: 'Structurally duplicated body', actionable: false },
      { tier: :overlap,    title: 'High coverage overlap',        actionable: false }
    ].freeze

    Loc     = Struct.new(:id, :method, :file, :line, :unit_count, keyword_init: true)
    Member  = Struct.new(:candidate, :loc, :safe, keyword_init: true)
    Cluster = Struct.new(:keeper, :members, keyword_init: true) do
      def size = members.size
    end
    TierPlan = Struct.new(:tier, :title, :actionable, :clusters, keyword_init: true) do
      def count = clusters.sum(&:size)
    end

    module_function

    # Returns an array of TierPlan in review order. Empty tiers are omitted.
    # When actionable_only: true, only safety-verified removable candidates are
    # included (what the interactive reviewer turns into a patch).
    def build(result, actionable_only: false)
      root      = result.run['root']
      keepers   = index_footprints(result)
      approved  = result.approved_removals.to_set

      TIERS.filter_map do |spec|
        members = result.candidates.select { |c| c.group == spec[:tier] }
        members = members.select { |c| approved.include?(c) } if actionable_only
        next if members.empty?

        clusters = members
                   .group_by { |c| c.kept_by.first }
                   .map { |keeper_id, group| cluster_for(keeper_id, group, keepers, approved, root) }
                   .sort_by { |cl| [-cl.size, cl.keeper&.id || ''] }

        TierPlan.new(tier: spec[:tier], title: spec[:title],
                     actionable: spec[:actionable], clusters: clusters)
      end
    end

    def cluster_for(keeper_id, group, keepers, approved, root)
      keeper_fp = keepers[keeper_id]
      keeper_loc = keeper_fp && loc_for(keeper_id, keeper_fp.file, keeper_fp.line,
                                        keeper_fp.units.size, root)
      members = group
                .sort_by { |c| [c.footprint.file.to_s, c.footprint.line.to_i, c.footprint.id] }
                .map do |c|
        fp = c.footprint
        Member.new(candidate: c, safe: approved.include?(c),
                   loc: loc_for(fp.id, fp.file, fp.line, fp.units.size, root))
      end
      Cluster.new(keeper: keeper_loc, members: members)
    end

    def loc_for(id, file, line, unit_count, root)
      Loc.new(id: id, method: short_method(id), file: relpath(file, root),
              line: line, unit_count: unit_count)
    end

    # `ClassName#method` -> `#method`; leaves bare ids untouched.
    def short_method(id)
      idx = id.index('#')
      idx ? id[idx..] : id
    end

    def relpath(file, root)
      return file unless file && root && file.start_with?("#{root}/")

      file[(root.length + 1)..]
    end

    def index_footprints(result)
      return {} unless result.respond_to?(:detector_result)

      result.detector_result.footprints.each_with_object({}) { |fp, h| h[fp.id] = fp }
    end
  end
end
