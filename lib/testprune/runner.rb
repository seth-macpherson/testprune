# frozen_string_literal: true

require 'fileutils'
require 'json'
require_relative '../testprune'

module Testprune
  # Boots the target project's suite in a subprocess, instrumented so the adapters
  # capture per-test coverage. Reuses the gem's lib via RUBYOPT (-I) so the target
  # project does not need testprune in its Gemfile.
  class Runner
    def initialize(config)
      @config = config
    end

    # explicit_command: array form of a user-supplied test command (after `--`),
    # or nil to autodetect.
    def call(explicit_command = nil)
      framework, command = resolve(explicit_command)

      FileUtils.mkdir_p(@config.output_dir)
      File.delete(@config.run_file) if File.exist?(@config.run_file)

      warn("testprune: framework=#{framework}  running: #{command.join(' ')}")
      ok = system(env, *command, chdir: @config.root)

      unless File.exist?(@config.run_file)
        raise Error, 'suite finished but no run.json was captured — the adapter may ' \
                     'not have loaded. Check the framework/command and source paths.'
      end

      count = begin
        JSON.parse(File.read(@config.run_file)).fetch('tests', []).size
      rescue JSON::ParserError
        '(unreadable — suite may have been interrupted mid-write)'
      end
      warn("testprune: captured #{count} test(s) -> #{@config.run_file}")
      warn('testprune: suite exited non-zero; coverage was still captured.') unless ok
      ok
    end

    private

    def env
      gem_lib = File.expand_path('..', __dir__)
      rubyopt = ["-I#{gem_lib}", '-rtestprune/autostart', ENV['RUBYOPT']].compact.reject(&:empty?).join(' ')
      @config.to_env.merge('RUBYOPT' => rubyopt)
    end

    def resolve(explicit_command)
      if explicit_command && !explicit_command.empty?
        [framework_of(explicit_command.join(' ')), explicit_command]
      else
        autodetect
      end
    end

    def framework_of(command_string)
      command_string.include?('rspec') ? :rspec : :minitest
    end

    def autodetect
      bundler = File.exist?(File.join(@config.root, 'Gemfile'))
      prefix  = bundler ? %w[bundle exec] : []

      if File.directory?(File.join(@config.root, 'spec'))
        [:rspec, prefix + ['rspec']]
      elsif File.directory?(File.join(@config.root, 'test'))
        [:minitest, prefix + ['rake', 'test']]
      else
        raise Error, 'could not autodetect a test suite (no spec/ or test/ dir). ' \
                     'Pass an explicit command after `--`.'
      end
    end
  end
end
