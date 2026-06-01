# frozen_string_literal: true

module Testprune
  # Holds run/analysis settings. `source_paths` define which files count as the
  # system-under-test — coverage in any other file (test helpers, vendored gems,
  # the bundle) is ignored so footprints stay precise and cheap to diff.
  class Configuration
    attr_reader :source_paths, :exclude_globs, :output_dir,
                :overlap_threshold, :baseline_fraction, :root
    attr_writer :output_dir, :overlap_threshold, :baseline_fraction

    def source_paths=(val)
      @source_paths = val
      @source_roots = nil
    end

    def exclude_globs=(val)
      @exclude_globs = val
      @source_roots = nil
    end

    def root=(val)
      @root = File.expand_path(val)
      @source_roots = nil
    end

    def initialize(root: Dir.pwd)
      @root             = File.expand_path(root)
      @source_paths     = %w[app lib]
      @exclude_globs    = %w[**/vendor/** **/node_modules/** **/db/** **/config/**]
      @output_dir       = File.join(@root, 'tmp', '.testprune')
      @overlap_threshold = 0.9 # Jaccard cutoff for LOW-confidence overlap pairs
      # Units executed by >= this fraction of tests are treated as ambient
      # shared-setup noise and subtracted before detection. nil disables it.
      @baseline_fraction = 0.5
    end

    # Rebuild config inside the instrumented subprocess from env vars set by Runner.
    def self.from_env(env = ENV)
      cfg = new(root: env.fetch('TESTPRUNE_ROOT', Dir.pwd))
      cfg.source_paths  = split_env(env['TESTPRUNE_SOURCE_PATHS']) || cfg.source_paths
      cfg.exclude_globs = split_env(env['TESTPRUNE_EXCLUDE']) || cfg.exclude_globs
      cfg.output_dir    = env['TESTPRUNE_OUTPUT_DIR'] || cfg.output_dir
      cfg
    end

    def self.split_env(value)
      return nil if value.nil? || value.empty?

      value.split(File::PATH_SEPARATOR)
    end

    # Env vars the Runner must export so the subprocess reconstructs this config.
    def to_env
      {
        'TESTPRUNE_ROOT'         => @root,
        'TESTPRUNE_SOURCE_PATHS' => @source_paths.join(File::PATH_SEPARATOR),
        'TESTPRUNE_EXCLUDE'      => @exclude_globs.join(File::PATH_SEPARATOR),
        'TESTPRUNE_OUTPUT_DIR'   => @output_dir
      }
    end

    # Absolute, existing source roots under which coverage is considered in-scope.
    # Memoized: re-allocating this array on every source_file? call is O(tests * files).
    def source_roots
      @source_roots ||= @source_paths.map { |p| File.expand_path(p, @root) }
                                     .select { |p| File.directory?(p) }
    end

    # True when an absolute file path is part of the system-under-test.
    def source_file?(path)
      abs = File.expand_path(path)
      return false unless source_roots.any? { |root| abs.start_with?("#{root}/") }

      @exclude_globs.none? { |glob| File.fnmatch?(glob, abs, File::FNM_PATHNAME) }
    end

    def run_file
      File.join(@output_dir, 'run.json')
    end

    def patch_file
      File.join(@output_dir, 'removal.patch')
    end
  end
end
