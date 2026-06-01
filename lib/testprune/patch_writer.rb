# frozen_string_literal: true

require 'open3'
require 'tempfile'
require 'fileutils'
require_relative '../testprune'
require_relative 'test_body'

module Testprune
  # Emits a git-applyable patch that comments out the approved tests. Locates each
  # test's exact AST block (def or `it`/`describe` block) with Prism, comments
  # those lines, and diffs against the original via `git diff --no-index`. Writes
  # only the .patch file — never mutates the target source.
  class PatchWriter
    def initialize(config)
      @config = config
    end

    def write(candidates)
      FileUtils.mkdir_p(@config.output_dir)
      patch = candidates.group_by { |c| c.footprint.file }
                        .map { |file, group| file_patch(file, group) }
                        .compact.join
      File.write(@config.patch_file, patch)
      @config.patch_file
    end

    private

    def file_patch(file, candidates)
      unless file && File.exist?(file)
        ids = candidates.map { |c| c.footprint.id }
        warn "testprune: #{ids.size} candidate(s) skipped — #{file || '(no file)'} not found:\n" \
             "  #{ids.join(', ')}"
        return nil
      end

      original = File.read(file, encoding: 'UTF-8:UTF-8', invalid: :replace, undef: :replace)
      tree = begin
        Prism.parse(original).value
      rescue StandardError => e
        warn "testprune: Prism parse failed for #{file} (#{e.message}) — skipping"
        return nil
      end
      ranges = candidates.filter_map { |c| block_range(tree, c) }
      return nil if ranges.empty?

      modified = comment_out(original, ranges)
      diff(file, modified)
    end

    # [start_line, end_line, reason] for the test block at the candidate's line.
    def block_range(tree, candidate)
      node = TestBody.locate(tree, candidate.footprint.line)
      return nil unless node

      loc = node.location
      [loc.start_line, loc.end_line, candidate.reason]
    end

    def comment_out(original, ranges)
      lines = original.lines
      commented = lines.dup
      annotations = {} # 0-based insert index => annotation text

      ranges.each do |start_line, end_line, reason|
        annotations[start_line - 1] = "# testprune: removed redundant test — #{reason}\n"
        (start_line..end_line).each do |lineno|
          idx = lineno - 1
          commented[idx] = "# #{commented[idx]}"
        end
      end

      # Insert annotations from the bottom up so earlier indexes stay valid.
      annotations.sort_by { |idx, _| -idx }.each do |idx, text|
        indent = lines[idx][/\A\s*/]
        commented.insert(idx, "#{indent}#{text}")
      end
      commented.join
    end

    # Unified diff via git, with headers rewritten to the repo-relative path so
    # the patch applies cleanly from the project root.
    def diff(file, modified)
      relpath = relativize(file)
      Tempfile.create(['testprune', '.rb']) do |tmp|
        tmp.write(modified)
        tmp.flush
        out, _err, status = Open3.capture3(
          'git', 'diff', '--no-index', '--no-color', file, tmp.path
        )
        raise Error, 'git diff failed while building patch' if status.exitstatus > 1

        rewrite_headers(out, relpath)
      end
    end

    def rewrite_headers(diff, relpath)
      diff.lines.map do |line|
        if line.start_with?('diff --git ')
          "diff --git a/#{relpath} b/#{relpath}\n"
        elsif line.start_with?('--- ')
          "--- a/#{relpath}\n"
        elsif line.start_with?('+++ ')
          "+++ b/#{relpath}\n"
        else
          line
        end
      end.join
    end

    def relativize(file)
      root = @config.root
      file.start_with?("#{root}/") ? file[(root.length + 1)..] : file
    end
  end
end
