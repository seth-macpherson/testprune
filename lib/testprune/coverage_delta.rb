# frozen_string_literal: true

module Testprune
  # Computes what a single test executed by diffing two `Coverage.peek_result`
  # snapshots. A unit (line / branch arm / method) belongs to the test iff its
  # execution count *increased* between the snapshots — this is order-independent,
  # so coverage shared with earlier tests is still attributed correctly.
  #
  # Output (per in-scope source file):
  #   { "lines" => [Integer, ...],
  #     "branches" => [[type, sl, sc, el, ec], ...],
  #     "methods"  => [[name, sl, sc, el, ec], ...] }
  # Locations come straight from Coverage's keys so the analysis phase can map
  # them onto Prism AST nodes without re-deriving positions.
  module CoverageDelta
    module_function

    def compute(before, after, config)
      result = {}
      after.each do |file, aft|
        next unless config.source_file?(file)

        bef = before[file]
        lines    = delta_lines(bef && bef[:lines], aft[:lines])
        branches = delta_branches(bef && bef[:branches], aft[:branches])
        methods  = delta_methods(bef && bef[:methods], aft[:methods])
        next if lines.empty? && branches.empty? && methods.empty?

        result[file] = { 'lines' => lines, 'branches' => branches, 'methods' => methods }
      end
      result
    end

    def delta_lines(before, after)
      return [] unless after

      newly = []
      after.each_with_index do |after_count, idx|
        next if after_count.nil? # non-executable line

        before_count = before && before[idx] ? before[idx] : 0
        newly << (idx + 1) if after_count > before_count
      end
      newly
    end

    # Coverage branch shape: { node_key => { branch_key => count } }.
    # We record each *branch arm* (then/else/when/...) that newly executed,
    # keyed by the arm's own location + type.
    def delta_branches(before, after)
      return [] unless after

      newly = []
      after.each do |node_key, arms|
        before_arms = before && before[node_key]
        arms.each do |arm_key, after_count|
          before_count = before_arms && before_arms[arm_key] ? before_arms[arm_key] : 0
          next unless after_count > before_count

          type, _id, sl, sc, el, ec = arm_key
          newly << [type.to_s, sl, sc, el, ec]
        end
      end
      newly
    end

    # Coverage method shape: { [class, name, sl, sc, el, ec] => count }.
    def delta_methods(before, after)
      return [] unless after

      newly = []
      after.each do |method_key, after_count|
        before_count = before && before[method_key] ? before[method_key] : 0
        next unless after_count > before_count

        _klass, name, sl, sc, el, ec = method_key
        newly << [name.to_s, sl, sc, el, ec]
      end
      newly
    end
  end
end
