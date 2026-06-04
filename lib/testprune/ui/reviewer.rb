# frozen_string_literal: true

require 'prism'
require_relative 'styles'
require_relative '../review_plan'
require_relative '../test_body'

module Testprune
  module UI
    # Interactive, cluster-at-a-time reviewer for `apply`. Walks the actionable
    # removals in review order (identical first), grouping redundant tests under a
    # shared keeper so one keystroke accepts a whole cluster. Returns the list of
    # accepted candidates for the patch writer.
    #
    # Input is read one keystroke at a time. The key reader is injectable so the
    # flow is testable without a real TTY (see ReviewerTest).
    class Reviewer
      KEYS = "  [a] accept & remove   [s] skip   [d] diff vs keeper   [q] quit & write"

      def initialize(result, input: $stdin, output: $stdout, color: nil, read_key: nil)
        @result   = result
        @in       = input
        @out      = output
        @color    = color.nil? ? UI.tty?(output) : color
        @read_key = read_key || method(:default_read_key)
        @fp_by_id = ReviewPlan.index_footprints(result)
      end

      # Returns an Array of accepted Candidate objects (subset of approved_removals).
      def run
        clusters = ReviewPlan.build(@result, actionable_only: true)
                             .flat_map { |tier| tier.clusters.map { |c| [tier, c] } }
        return finish([]) if clusters.empty?

        accepted = []
        clusters.each_with_index do |(tier, cluster), i|
          @diff_idx = 0
          loop do
            render_cluster(tier, cluster, i + 1, clusters.size, accepted.size)
            case @read_key.call
            when 'a', ' ', "\r", "\n"
              accepted.concat(cluster.members.select(&:safe).map(&:candidate))
              break
            when 's' then break
            when 'd' then show_diff(cluster)
            when 'q', "", nil then return finish(accepted)
            end
          end
        end
        finish(accepted)
      end

      private

      # ── Rendering ──────────────────────────────────────────────────────────

      def render_cluster(tier, cluster, idx, total, accepted_count)
        clear
        line "  #{styled(tier.title, Styles::PURPLE_TEXT)}   " \
             "#{styled("cluster #{idx} / #{total}", Styles::META_TEXT)}   " \
             "#{styled("#{accepted_count} accepted", Styles::GREEN_TEXT)}"
        line "  #{progress_bar(idx, total)}"
        line ''

        keeper = cluster.keeper
        line "  #{badge('KEEP', Styles::GREEN_TEXT)}    #{loc(keeper)}"
        line "            #{styled(keeper.method, Styles::META_TEXT)}" if keeper && keeper.method != keeper.id

        n = cluster.size
        line ''
        units = keeper&.unit_count
        line "  #{badge('REMOVE', Styles::AMBER_TEXT)}  " \
             "#{n} test#{'s' if n > 1} with identical coverage — " \
             "#{styled("all #{units} unit#{'s' if units != 1} retained by the keeper", Styles::DIM_TEXT)}"
        cluster.members.each do |m|
          where = m.loc.file == keeper&.file ? "    :#{m.loc.line}" : "    #{m.loc.file}:#{m.loc.line}"
          line "          #{styled(where, Styles::DIM_TEXT)}  #{styled(m.loc.method, Styles::META_TEXT)}"
        end

        line ''
        line "  #{styled('✓ safe', Styles::GREEN_TEXT)}#{styled(' — every covered unit remains covered by the kept test', Styles::DIM_TEXT)}"
        line ''
        line styled(KEYS, Styles::META_TEXT)
      end

      def show_diff(cluster)
        member  = cluster.members[@diff_idx % cluster.size]
        @diff_idx += 1
        keeper_fp = cluster.keeper && @fp_by_id[cluster.keeper.id]

        clear
        kb = keeper_fp ? body_lines(keeper_fp.file, keeper_fp.line) : []
        mb = body_lines(member.candidate.footprint.file, member.candidate.footprint.line)
        render_diff(cluster.keeper&.method || '(keeper)', kb, member.loc.method, mb)
        more = cluster.size > 1 ? ' · [d] next member' : ''
        line ''
        line styled("  press any key to return#{more}", Styles::DIM_TEXT)
        @read_key.call
      end

      COL = 46

      def render_diff(keep_name, keep_lines, rm_name, rm_lines)
        line "  #{badge('KEEP', Styles::GREEN_TEXT)} #{styled(keep_name, Styles::META_TEXT)}" \
             "#{' ' * [COL - keep_name.length - 7, 1].max}#{badge('REMOVE', Styles::AMBER_TEXT)} #{styled(rm_name, Styles::META_TEXT)}"
        line "  #{styled('─' * COL, Styles::DIM_TEXT)} #{styled('─' * COL, Styles::DIM_TEXT)}"
        [keep_lines.size, rm_lines.size].max.times do |i|
          left  = fmt_code(keep_lines[i])
          right = fmt_code(rm_lines[i])
          line "  #{left} #{right}"
        end
      end

      def fmt_code(entry)
        return ' ' * COL unless entry

        num, text = entry
        s = format('%4d  %s', num, text)
        clip(s, COL)
      end

      def progress_bar(idx, total)
        width  = 28
        filled = total.zero? ? width : (idx.to_f / total * width).round
        bar = ('█' * filled) + ('░' * (width - filled))
        "#{styled(bar, Styles::PURPLE_TEXT)} #{styled("#{idx}/#{total}", Styles::META_TEXT)}"
      end

      def finish(accepted)
        clear
        if accepted.empty?
          line "  #{styled('No removals accepted', Styles::DIM_TEXT)} — no patch will be written."
        else
          line "  #{styled('✓', Styles::GREEN_TEXT)}  Accepted #{styled(accepted.size.to_s, Styles::GREEN_TEXT)} removal(s)."
        end

        review_only = ReviewPlan.build(@result).reject(&:actionable)
        unless review_only.empty?
          counts = review_only.map { |t| "#{t.count} #{t.title.downcase}" }.join(', ')
          line "  #{styled("Review-only candidates not shown here (never auto-patched): #{counts}.", Styles::DIM_TEXT)}"
          line "  #{styled('See them with:', Styles::DIM_TEXT)} testprune report"
        end
        accepted
      end

      # ── Helpers ────────────────────────────────────────────────────────────

      def loc(l)
        return styled('(keeper not found)', Styles::DIM_TEXT) unless l

        "#{styled("#{l.file}:#{l.line}", Styles::META_TEXT)}"
      end

      def badge(text, style) = styled(" #{text} ", style)

      def styled(text, style) = @color ? style.render(text) : text

      def line(text = '') = @out.puts(text)

      def clear = (@out.print("\e[2J\e[H") if @color)

      def clip(str, width)
        return str.ljust(width) if str.length <= width

        "#{str[0, width - 1]}…"
      end

      def body_lines(file, start_line)
        return [] unless file && File.exist?(file)

        src  = File.read(file).lines
        node = TestBody.locate(Prism.parse(File.read(file)).value, start_line)
        return [] unless node

        (node.location.start_line..node.location.end_line).map do |n|
          [n, (src[n - 1] || '').chomp]
        end
      rescue StandardError
        []
      end

      def default_read_key
        require 'io/console'
        if @color && @in.respond_to?(:getch)
          @in.getch
        else
          (@in.gets || 'q')[0]
        end
      end
    end
  end
end
