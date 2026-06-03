# frozen_string_literal: true

require 'testprune/ui/styles'

module Testprune
  module UI
    # Styled replacement for Report#render_text. Renders the analysis result as a
    # rich, color-coded terminal report using lipgloss. Degrades to plain text when
    # NO_COLOR=1 is set or when output is not a TTY (lipgloss handles this automatically).
    class ReportRenderer
      GROUP_LABELS = {
        identical:  'identical',
        subset:     'subset',
        structural: 'structural',
        overlap:    'overlap'
      }.freeze

      def initialize(result)
        @result = result
      end

      def render
        parts = []
        parts << header_section
        parts << ''

        if @result.candidates.empty?
          parts << nothing_found_section
        else
          parts << confidence_section(:high,   'HIGH confidence — safe to remove',    Styles::HIGH_BADGE,   '●')
          parts << confidence_section(:medium, 'MEDIUM confidence — review',           Styles::MEDIUM_BADGE, '●')
          parts << confidence_section(:low,    'LOW confidence — review',              Styles::LOW_BADGE,    '●')
          parts << savings_section unless @result.approved_removals.empty?
          parts << ''
          parts << cta_line
        end

        parts.compact.join("\n")
      end

      private

      def tty?
        return false if ENV['NO_COLOR']

        $stdout.respond_to?(:isatty) && $stdout.isatty
      end

      def styled(text, style)
        tty? ? style.render(text) : text
      end

      # ── Sections ─────────────────────────────────────────────────────────────

      def header_section
        framework  = @result.run['framework'] || 'unknown'
        test_count = (@result.run['tests'] || []).size
        baseline_info = @result.ambient_units.positive? ?
          "  baseline: subtracted #{@result.ambient_units} shared-setup unit(s)" : ''

        lines = [
          "  testprune — coverage redundancy report",
          "  #{test_count} tests · #{framework}#{baseline_info}"
        ]

        if tty?
          Styles::REPORT_BOX.render(lines.join("\n"))
        else
          lines.join("\n") + "\n" + ('─' * 64)
        end
      end

      def confidence_section(tier, title, badge_style, bullet)
        candidates = @result.candidates.select { |c| c.confidence == tier }
        return nil if candidates.empty?

        lines = []
        badge = styled("  #{bullet} ", badge_style)
        title_text = styled(title, badge_style)
        count_text = styled("  (#{candidates.size})", Styles::META_TEXT)
        lines << "#{badge}#{title_text}#{count_text}"
        lines << styled('  ' + '─' * 62, Styles::DIM_TEXT)
        lines << ''
        candidates.each do |c|
          lines.concat(candidate_lines(c))
          lines << ''
        end
        lines.join("\n")
      end

      def candidate_lines(candidate)
        fp = candidate.footprint
        lines = []

        group_badge = styled("[#{GROUP_LABELS[candidate.group] || candidate.group}]", Styles::PURPLE_TEXT)
        lines << "    #{group_badge}  #{fp.id}"
        lines << "    #{styled('at: ', Styles::DIM_TEXT)}#{styled("#{fp.file}:#{fp.line}", Styles::META_TEXT)}" if fp.file
        lines << "    #{styled('reason: ', Styles::DIM_TEXT)}#{styled(candidate.reason, Styles::META_TEXT)}"

        unless candidate.kept_by.empty?
          lines << "    #{styled('kept by: ', Styles::DIM_TEXT)}#{styled(candidate.kept_by.join(', '), Styles::DIM_TEXT)}"
        end

        lines.concat(coverage_detail_lines(candidate, fp))

        safety = case candidate.safe
                 when true  then styled('    ✓ safe — every covered unit is retained by another test', Styles::SAFE_LINE)
                 when false then styled("    ✗ NOT safe — #{candidate.safety_note}", Styles::UNSAFE_LINE)
                 else            styled('    · review-only — not auto-applied', Styles::DIM_TEXT)
                 end
        lines << safety
        lines
      end

      def savings_section
        s = @result.savings
        lines = [
          '  Estimated CI savings',
          "  #{styled("#{s.approved_count} test(s)", Styles::GREEN_TEXT)}" \
          "#{styled('  ·  ', Styles::META_TEXT)}" \
          "#{styled(format('%.4fs saved', s.approved_time), Styles::GREEN_TEXT)}" \
          "#{styled('  ·  ', Styles::META_TEXT)}" \
          "#{styled(format('~%.1f%% of suite', s.percent_of_test_time), Styles::GREEN_TEXT)}",
          styled('  Note: wall-clock savings lower on parallel CI runners', Styles::META_TEXT)
        ]

        if tty?
          Styles::REPORT_BOX.render(lines.join("\n"))
        else
          lines.join("\n")
        end
      end

      def nothing_found_section
        msg = '  Nothing redundant found — suite looks clean.'
        tty? ? Styles::SUCCESS_BOX.render(msg) : msg
      end

      def coverage_detail_lines(candidate, fp)
        case candidate.group
        when :identical
          [coverage_line('both cover', fp.units)]
        when :subset
          keeper = keeper_footprint(candidate)
          lines = [coverage_line('candidate covers', fp.units)]
          if keeper
            extra = keeper.units - fp.units
            lines << coverage_line('keeper adds', extra) unless extra.empty?
          end
          lines
        else
          [coverage_line('covers', fp.units)]
        end
      end

      def coverage_line(label, units)
        "    #{styled("#{label}: ", Styles::DIM_TEXT)}#{styled(format_units(units), Styles::DIM_TEXT)}"
      end

      def keeper_footprint(candidate)
        return nil if candidate.kept_by.empty?
        return nil unless @result.respond_to?(:detector_result)

        @result.detector_result.footprints.find { |f| f.id == candidate.kept_by.first }
      end

      def format_units(units)
        labels = units.map { |id| @result.label_for(id) }.sort
        labels.size <= 4 ? labels.join(' · ') : "#{labels.first(4).join(' · ')} (+#{labels.size - 4} more)"
      end

      def cta_line
        "  #{styled('Run ', Styles::META_TEXT)}" \
        "#{styled('testprune apply', Styles::PURPLE_TEXT)}" \
        "#{styled(' to review and emit a removal patch.', Styles::META_TEXT)}"
      end
    end
  end
end
