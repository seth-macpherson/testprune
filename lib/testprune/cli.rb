# frozen_string_literal: true

require 'optparse'
require_relative '../testprune'
require_relative 'ui'

module Testprune
  # Command-line front end. Three real commands:
  #   run     boots the target suite under coverage instrumentation -> run.json
  #   report  analyzes run.json and prints grouped candidates (read-only)
  #   apply   prompts for approval, then writes a removal patch (never edits in place)
  class CLI
    NOISY_PATTERNS = %w[selenium request piper integration].freeze

    BANNER = <<~TXT
      testprune — audit a Ruby test suite for redundant coverage

      Usage:
        testprune scan [options] [-- <test command>]
        testprune report [options]
        testprune apply [options]
        testprune prune [options] [-- <test command>]

      Commands:
        scan     Run the target suite instrumented; capture per-test coverage + timing
        report   Analyze captured data and print removal candidates (read-only)
        apply    Review candidates, ask for approval, emit a git-applyable patch
        prune    Run scan + apply in one step (the full workflow)

      Options:
        -s, --source PATH      Source dir to analyze (repeatable; default: app, lib)
        -o, --output DIR       Output dir for captured data (default: .testprune)
            --baseline FRAC    Treat units run by >= FRAC of tests as shared-setup
                               noise and subtract them (0..1; default 0.5; 0 to disable)
            --json             Emit machine-readable JSON (report only)
        -V, --verbose          Show raw test output during scan (disables progress display)
        -y, --yes              Skip interactive review; accept all safe removals (apply)
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
      when 'scan'           then cmd_scan(argv)
      when 'report'         then cmd_report(argv)
      when 'apply'          then cmd_apply(argv)
      when 'prune'          then cmd_prune(argv)
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
        o.on('-V', '--verbose')     { opts[:verbose] = true }
        o.on('-y', '--yes')         { opts[:yes] = true }
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

    def cmd_scan(argv)
      cmd_argv, test_command = split_test_command(argv)
      opts, paths = parse_options(cmd_argv)
      apply_config(opts)
      require_relative 'runner'
      runner = Runner.new(Testprune.config)
      if test_command.nil? && paths.empty?
        test_command = prompt_noisy_exclusions(runner)
      elsif test_command.nil?
        test_command = runner.command_for_paths(paths)
      end
      runner.call(test_command, verbose: opts[:verbose])
    end

    def prompt_noisy_exclusions(runner)
      test_dir = File.join(Testprune.config.root, 'test')
      return nil unless File.directory?(test_dir)

      all_subdirs = Dir.children(test_dir)
                       .select { |d| File.directory?(File.join(test_dir, d)) }
                       .sort
      noisy = all_subdirs.select { |d| NOISY_PATTERNS.any? { |p| d.downcase.include?(p) } }
      return nil if noisy.empty?

      warn("testprune: found folders that may be slow or integration-heavy:")
      noisy.each { |d| warn("  test/#{d}") }
      $stderr.print("Include them in this run? [y/N]: ")
      answer = $stdin.gets&.strip&.downcase

      return nil if %w[y yes].include?(answer)

      kept = (all_subdirs - noisy).map { |d| "test/#{d}" }
      return nil if kept.empty?

      runner.command_for_paths(kept)
    end

    def cmd_prune(argv)
      if UI.tty?($stderr)
        $stderr.puts UI::Styles::HEADER_BOX.render("✂️  testprune prune — scan + apply in one step")
        $stderr.puts
      end
      cmd_scan(argv)
      if UI.tty?($stderr)
        sep = UI::Styles::PURPLE_TEXT.render('  ' + '━' * 58)
        $stderr.puts
        $stderr.puts sep
        $stderr.puts "  #{UI::Styles::PURPLE_TEXT.render('✂️')}  Moving to apply…"
        $stderr.puts sep
        $stderr.puts
      end
      patch_path = cmd_apply([])
      # T018: done summary
      if UI.tty?($stdout)
        summary = case patch_path
                  when String then "  ✂️  Done — patch written\n     #{UI::Styles::PURPLE_TEXT.render("git apply #{patch_path}")}"
                  when false  then "  ✂️  Done — aborted, no patch written"
                  else             "  ✂️  Done — nothing to prune"
                  end
        puts UI::Styles::SUCCESS_BOX.render(summary)
      end
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

      approved = result.approved_removals
      if approved.empty?
        require_relative 'report'
        puts(Report.new(result).render)
        msg = "  Nothing safe to remove. No patch written."
        puts(UI.tty?($stdout) ? UI::Styles::SUCCESS_BOX.render(msg) : "\n#{msg.strip}")
        return nil
      end

      accepted =
        if opts[:yes]
          approved
        elsif UI.tty?($stdout)
          require_relative 'ui/reviewer'
          UI::Reviewer.new(result).run
        else
          noninteractive_confirm(result, approved)
        end

      return false if accepted == false # explicit abort at the non-interactive prompt
      if accepted.nil? || accepted.empty?
        msg = "  Nothing accepted — no patch written."
        puts(UI.tty?($stdout) ? UI::Styles::DIM_TEXT.render(msg) : msg.strip)
        return nil
      end

      require_relative 'patch_writer'
      path = PatchWriter.new(Testprune.config).write(accepted)
      print_patch_written(path, accepted.size)
      path
    end

    # Non-TTY (piped/CI without --yes): show the full report and ask once.
    # Returns the approved set on yes, or false on abort.
    def noninteractive_confirm(result, approved)
      require_relative 'report'
      puts(Report.new(result).render)
      print("\nApply #{approved.size} HIGH-confidence, safety-verified removal(s) as a patch?\n" \
            "(MEDIUM/LOW review-only candidates are NOT patched automatically.) [y/N] ")
      answer = $stdin.gets&.strip&.downcase
      %w[y yes].include?(answer) ? approved : false
    end

    def print_patch_written(path, count)
      if UI.tty?($stdout)
        box = [
          "  #{UI::Styles::GREEN_TEXT.render('✓')}  Patch written — #{count} test(s)",
          "     #{path}",
          "     #{UI::Styles::DIM_TEXT.render('Apply with:')}  " \
          "#{UI::Styles::PURPLE_TEXT.render("git apply #{path}")}"
        ].join("\n")
        puts UI::Styles::SUCCESS_BOX.render(box)
      else
        puts("Wrote #{path}")
        puts("Review it, then apply with:  git apply #{path}")
      end
    end
  end
end
