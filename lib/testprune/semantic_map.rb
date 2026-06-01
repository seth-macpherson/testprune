# frozen_string_literal: true

require 'prism'

module Testprune
  # Parses one source file with Prism and resolves Coverage locations to
  # AST-aware semantic units:
  #   - methods   (DefNode)            -> "Class#method"
  #   - branch arms (IfNode/CaseNode/…) -> "if then-branch", labelled by the
  #     innermost enclosing control node
  #   - lines collapse to their innermost enclosing method, or a per-file
  #     top-level unit when outside any def — so straight-line code still
  #     contributes a stable unit.
  class SemanticMap
    Unit = Struct.new(:id, :kind, :label, :file, :line, keyword_init: true)

    def self.for_file(path, relpath:)
      # Read with replacement for invalid/undefined bytes so non-UTF-8 content
      # (Latin-1 comments, etc.) never raises an encoding error.
      source = File.read(path, encoding: 'UTF-8:UTF-8', invalid: :replace, undef: :replace)
      new(path, source, relpath)
    end

    attr_reader :units

    def initialize(path, source, relpath)
      @path    = path
      @relpath = relpath
      @units            = {}  # id => Unit
      @methods_by_pos   = {}  # [start_line, start_col] => Unit
      @method_intervals = []  # [start_line, end_line, Unit]
      @controls         = []  # [sl, sc, el, ec, type]
      Visitor.new(self).visit(Prism.parse(source).value)
    end

    # Registration callbacks used by the Visitor.

    def add_method(node, scope, sep)
      loc = node.location
      sl  = loc.start_line
      sc  = loc.start_column
      owner = scope.empty? ? '' : "#{scope.join('::')}#{sep}"
      id  = "#{@relpath}#m@#{sl}:#{sc}"
      unit = Unit.new(id: id, kind: :method, label: "#{owner}#{node.name} (#{@relpath}:#{sl})",
                      file: @relpath, line: sl)
      @units[id] = unit
      @methods_by_pos[[sl, sc]] = unit
      @method_intervals << [sl, loc.end_line, unit]
    end

    def add_control(node, type)
      loc = node.location
      @controls << [loc.start_line, loc.start_column, loc.end_line, loc.end_column, type]
    end

    # Resolution used when building footprints.

    def method_unit(start_line, start_col)
      @methods_by_pos[[start_line, start_col]]
    end

    def branch_unit(type, start_line, start_col, _end_line, _end_col)
      id = "#{@relpath}#b:#{type}@#{start_line}:#{start_col}"
      @units[id] ||= begin
        control_type = innermost_control(start_line, start_col) || type
        Unit.new(id: id, kind: :branch,
                 label: "#{control_type} #{type}-branch (#{@relpath}:#{start_line})",
                 file: @relpath, line: start_line)
      end
    end

    def line_unit(lineno)
      best = nil
      @method_intervals.each do |sl, el, unit|
        next unless lineno >= sl && lineno <= el

        best = unit if best.nil? || sl > best.line
      end
      best || toplevel_unit
    end

    private

    def toplevel_unit
      id = "#{@relpath}#top"
      @units[id] ||= Unit.new(id: id, kind: :toplevel, label: "#{@relpath} (top-level)",
                              file: @relpath, line: 0)
    end

    # Innermost control node containing a position; returns its type or nil.
    def innermost_control(line, col)
      match = nil
      @controls.each do |sl, sc, el, ec, type|
        next unless contains?(sl, sc, el, ec, line, col)

        match = [sl, sc, type] if match.nil? || sl > match[0] || (sl == match[0] && sc > match[1])
      end
      match && match[2]
    end

    def contains?(sl, sc, el, ec, line, col)
      return false if line < sl || line > el
      return false if line == sl && col < sc
      return false if line == el && col > ec

      true
    end

    # Walks the AST, tracking class/module nesting, registering methods and
    # control-flow nodes.
    class Visitor < Prism::Visitor
      def initialize(map)
        @map = map
        @scope = []
        super()
      end

      def visit_class_node(node)
        with_scope(node.constant_path.slice) { super }
      end

      def visit_module_node(node)
        with_scope(node.constant_path.slice) { super }
      end

      def visit_def_node(node)
        @map.add_method(node, @scope, node.receiver ? '.' : '#')
        super
      end

      def visit_if_node(node)
        @map.add_control(node, 'if')
        super
      end

      def visit_unless_node(node)
        @map.add_control(node, 'unless')
        super
      end

      def visit_case_node(node)
        @map.add_control(node, 'case')
        super
      end

      def visit_case_match_node(node)
        @map.add_control(node, 'case')
        super
      end

      def visit_while_node(node)
        @map.add_control(node, 'while')
        super
      end

      def visit_until_node(node)
        @map.add_control(node, 'until')
        super
      end

      def visit_rescue_node(node)
        @map.add_control(node, 'rescue')
        super
      end

      def visit_and_node(node)
        @map.add_control(node, '&&')
        super
      end

      def visit_or_node(node)
        @map.add_control(node, '||')
        super
      end

      private

      def with_scope(name)
        @scope.push(name)
        yield
        @scope.pop
      end
    end
  end
end
