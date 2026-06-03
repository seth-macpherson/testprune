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

    def section(title, candidates)
      return [] if candidates.empty?

      out = ["#{title}: #{candidates.size}"]
      candidates.each { |c| out.concat(candidate_lines(c)) }
      out << ''
      out
    end

    def candidate_lines(candidate)
      fp = candidate.footprint
      out = []
      out << "  [#{candidate.group}] #{fp.id}"
      out << "      at: #{fp.file}:#{fp.line}" if fp.file
      out << "      reason: #{candidate.reason}"
      out << "      kept by: #{candidate.kept_by.join(', ')}" unless candidate.kept_by.empty?
      out.concat(coverage_text_lines(candidate, fp))
      out << "      #{safety_line(candidate)}"
      out
    end

    def coverage_text_lines(candidate, fp)
      case candidate.group
      when :identical
        ["      both cover: #{covered_labels(fp.units)}"]
      when :subset
        keeper = find_keeper(candidate)
        lines = ["      candidate covers: #{covered_labels(fp.units)}"]
        if keeper
          extra = keeper.units - fp.units
          lines << "      keeper adds: #{covered_labels(extra)}" unless extra.empty?
        end
        lines
      else
        ["      covers: #{covered_labels(fp.units)}"]
      end
    end

    def find_keeper(candidate)
      return nil if candidate.kept_by.empty?
      return nil unless @result.respond_to?(:detector_result)

      @result.detector_result.footprints.find { |f| f.id == candidate.kept_by.first }
    end

    def covered_labels(units)
      labels = units.map { |id| @result.label_for(id) }.sort
      labels.size <= 4 ? labels.join('; ') : "#{labels.first(4).join('; ')} (+#{labels.size - 4} more)"
    end

    def safety_line(candidate)
      case candidate.safe
      when true  then '✓ safe — every covered unit remains covered by a retained test'
      when false then "✗ NOT safe — #{candidate.safety_note} (kept)"
      else            '· review-only — not auto-applied'
      end
    end

    def savings_section
      s = @result.savings
      [
        'Estimated CI savings:',
        "  #{s.approved_count} test(s), #{format('%.4f', s.approved_time)}s " \
        "(~#{format('%.1f', s.percent_of_test_time)}% of #{format('%.4f', s.total_test_time)}s test time)",
        '  Note: under parallel CI runners, wall-clock savings will be lower.'
      ]
    end

    def high_candidates   = @result.candidates.select { |c| c.confidence == :high }
    def medium_candidates = @result.candidates.select { |c| c.confidence == :medium }
    def low_candidates    = @result.candidates.select { |c| c.confidence == :low }
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
