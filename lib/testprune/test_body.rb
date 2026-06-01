# frozen_string_literal: true

require 'prism'

module Testprune
  # Produces a structural signature for the test defined at file:line by parsing
  # its body with Prism and emitting a node-type sequence that ignores literal
  # values and identifiers but keeps called method names. Two tests that differ
  # only in their data (e.g. `assert_equal 3, add(1,2)` vs `assert_equal 5,
  # add(2,3)`) get the same signature.
  module TestBody
    @file_cache = {}

    module_function

    def signature(file, line)
      return nil unless file && line && File.exist?(file)

      tree = (@file_cache[file] ||= Prism.parse(File.read(file)).value)
      node = locate(tree, line)
      body = body_of(node)
      return nil unless body

      normalize(body)
    end

    # Innermost def or block whose definition starts on `line`.
    def locate(root, line)
      stack = [root]
      until stack.empty?
        node = stack.pop
        if node.location.start_line == line &&
           (node.is_a?(Prism::DefNode) || (node.is_a?(Prism::CallNode) && node.block))
          return node
        end

        stack.concat(node.compact_child_nodes)
      end
      nil
    end

    def body_of(node)
      return nil unless node

      node.is_a?(Prism::DefNode) ? node.body : node.block&.body
    end

    def normalize(node)
      tokens = []
      walk(node) do |n|
        tokens << (n.is_a?(Prism::CallNode) ? "call:#{n.name}" : n.type.to_s)
      end
      tokens.join(',')
    end

    def walk(node, &block)
      block.call(node)
      node.compact_child_nodes.each { |child| walk(child, &block) }
    end
  end
end
