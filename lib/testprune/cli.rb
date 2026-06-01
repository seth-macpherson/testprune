# frozen_string_literal: true

require 'optparse'
require_relative '../testprune'

module Testprune
  # Command-line front end. Three real commands:
  #   run     boots the target suite under coverage instrumentation -> run.json
  #   report  analyzes run.json and prints grouped candidates (read-only)
  #   apply   prompts for approval, then writes a removal patch (never edits in place)
  class CLI
    BANNER = <<~TXT
      testprune — audit a Ruby test suite for redundant coverage

      Usage:
        testprune run [options] [-- <test command>]
        testprune report [options]
        testprune apply [options]

      Commands:
        run      Run the target suite instrumented; capture per-test coverage + timing
        report   Analyze captured data and print removal candidates (read-only)
        apply    Review candidates, ask for approval, emit a git-applyable patch

      Options:
        -s, --source PATH      Source dir to analyze (repeatable; default: app, lib)
        -o, --output DIR       Output dir for captured data (default: .testprune)
            --baseline FRAC    Treat units run by >= FRAC of tests as shared-setup
                               noise and subtract them (0..1; default 0.5; 0 to disable)
            --json             Emit machine-readable JSON (report only)
        -h, --help             Show this help
        -v, --version          Show version
    TXT

    def self.start(argv)
      new.run(argv)
    end

    def run(argv)
      argv = argv.dup
      command = argv.shift
      case command
      when 'run'            then cmd_run(argv)
      when 'report'         then cmd_report(argv)
      when 'apply'          then cmd_apply(argv)
      when '-v', '--version' then puts(Testprune::VERSION)
      when nil, '-h', '--help' then puts(BANNER)
      else
        warn("testprune: unknown command #{command.inspect}\n\n#{BANNER}")
        return 1
      end
      0
    rescue Testprune::Error => e
      warn("testprune: #{e.message}")
      1
    end

    private

    # Splits argv at a literal `--`; everything after is the user's test command.
    def split_test_command(argv)
      idx = argv.index('--')
      return [argv, nil] unless idx

      [argv[0...idx], argv[(idx + 1)..]]
    end

    def parse_options(argv)
      sources = []
      opts = { json: false }
      parser = OptionParser.new do |o|
        o.on('-s', '--source PATH') { |v| sources << v }
        o.on('-o', '--output DIR')  { |v| opts[:output] = v }
        o.on('--baseline FRAC', Float) { |v| opts[:baseline] = v }
        o.on('--json')              { opts[:json] = true }
        o.on('-h', '--help')        { puts(BANNER); exit(0) }
      end
      rest = parser.parse(argv)
      opts[:sources] = sources unless sources.empty?
      [opts, rest]
    end

    def apply_config(opts)
      Testprune.configure do |c|
        c.source_paths = opts[:sources] if opts[:sources]
        c.output_dir   = File.expand_path(opts[:output], c.root) if opts[:output]
        c.baseline_fraction = (opts[:baseline]).positive? ? opts[:baseline] : nil if opts.key?(:baseline)
      end
    end

    def cmd_run(argv)
      cmd_argv, test_command = split_test_command(argv)
      opts, = parse_options(cmd_argv)
      apply_config(opts)
      require_relative 'runner'
      Runner.new(Testprune.config).call(test_command)
    end

    def cmd_report(argv)
      opts, = parse_options(argv)
      apply_config(opts)
      require_relative 'analysis'
      result = Analysis.new(Testprune.config).call
      require_relative 'report'
      puts(Report.new(result, json: opts[:json]).render)
    end

    def cmd_apply(argv)
      opts, = parse_options(argv)
      apply_config(opts)
      require_relative 'analysis'
      result = Analysis.new(Testprune.config).call
      require_relative 'report'
      puts(Report.new(result).render)

      approved = result.approved_removals
      if approved.empty?
        puts("\nNothing safe to remove. No patch written.")
        return
      end

      print("\nApply #{approved.size} HIGH-confidence, safety-verified removal(s) as a patch?\n" \
            "(MEDIUM/LOW review-only candidates are NOT patched automatically.) [y/N] ")
      answer = $stdin.gets&.strip&.downcase
      unless %w[y yes].include?(answer)
        puts('Aborted. No patch written.')
        return
      end

      require_relative 'patch_writer'
      path = PatchWriter.new(Testprune.config).write(approved)
      puts("Wrote #{path}")
      puts("Review it, then apply with:  git apply #{path}")
    end
  end
end
