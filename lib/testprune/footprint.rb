# frozen_string_literal: true

require 'set'
require_relative 'semantic_map'

module Testprune
  # A single test's semantic coverage: the set of AST-aware unit IDs it executed,
  # plus the metadata needed to report and patch it.
  Footprint = Struct.new(:id, :description, :file, :line, :wall_time, :units, keyword_init: true) do
    def empty?
      units.empty?
    end
  end

  # Turns recorded per-test coverage (run.json) into Footprints by mapping
  # Coverage locations onto Prism semantic units. Caches one SemanticMap per file.
  class SemanticIndex
    def initialize(root)
      @root = root
      @maps = {}
    end

    def build_footprints(tests)
      tests.map { |test| footprint(test) }
    end

    def footprint(test)
      units = Set.new
      (test['coverage'] || {}).each do |file, data|
        next unless File.exist?(file)

        map = map_for(file)
        collect_methods(units, map, data['methods'])
        collect_branches(units, map, data['branches'])
        collect_lines(units, map, data['lines'])
      end

      Footprint.new(
        id: test['id'], description: test['description'], file: test['file'],
        line: test['line'], wall_time: test['wall_time'] || 0.0, units: units
      )
    end

    def label_for(id)
      @maps.each_value do |map|
        unit = map.units[id]
        return unit.label if unit
      end
      id
    end

    private

    def collect_methods(units, map, entries)
      (entries || []).each do |entry|
        _name, sl, sc, = entry
        unit = map.method_unit(sl, sc)
        units << unit.id if unit
      end
    end

    def collect_branches(units, map, entries)
      (entries || []).each do |entry|
        type, sl, sc, el, ec = entry
        units << map.branch_unit(type, sl, sc, el, ec).id
      end
    end

    def collect_lines(units, map, lines)
      (lines || []).each do |lineno|
        unit = map.line_unit(lineno)
        units << unit.id if unit
      end
    end

    def map_for(file)
      @maps[file] ||= SemanticMap.for_file(file, relpath: relativize(file))
    rescue StandardError => e
      warn "testprune: could not parse #{file} (#{e.class}: #{e.message}) — skipping"
      @maps[file] = SemanticMap.new(file, '', relativize(file))
    end

    def relativize(file)
      file.start_with?("#{@root}/") ? file[(@root.length + 1)..] : file
    end
  end
end
