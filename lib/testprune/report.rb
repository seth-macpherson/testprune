# frozen_string_literal: true

require 'json'

module Testprune
  # Renders the analysis as a grouped, human-readable report (or JSON). Candidates
  # are grouped by confidence; HIGH shows safety status, MEDIUM/LOW are marked
  # review-only.
  class Report
    GROUP_TITLES = {
      identical:  'Identical coverage',
      subset:     'Subset / subsumed coverage',
      structural: 'Structurally duplicated test body',
      overlap:    'High coverage overlap'
    }.freeze

    def initialize(result, json: false)
      @result = result
      @json   = json
    end

    def render
      @json ? render_json : render_text
    end

    private

    def render_text
      require_relative 'ui/report_renderer'
      UI::ReportRenderer.new(@result).render
    end

    def covered_labels(units)
      labels = units.map { |id| @result.label_for(id) }.sort
      labels.size <= 4 ? labels.join('; ') : "#{labels.first(4).join('; ')} (+#{labels.size - 4} more)"
    end

    def test_count        = (@result.run['tests'] || []).size

    def render_json
      JSON.pretty_generate(
        framework: @result.run['framework'],
        test_count: test_count,
        savings: {
          approved_count: @result.savings.approved_count,
          approved_time: @result.savings.approved_time,
          total_test_time: @result.savings.total_test_time,
          percent_of_test_time: @result.savings.percent_of_test_time
        },
        candidates: @result.candidates.map { |c| candidate_json(c) }
      )
    end

    def candidate_json(candidate)
      fp = candidate.footprint
      {
        id: fp.id, file: fp.file, line: fp.line,
        confidence: candidate.confidence, group: candidate.group,
        reason: candidate.reason, kept_by: candidate.kept_by,
        review_only: candidate.review_only, safe: candidate.safe,
        safety_note: candidate.safety_note,
        covers: fp.units.map { |id| @result.label_for(id) }.sort
      }
    end
  end
end
