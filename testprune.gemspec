# frozen_string_literal: true

require_relative 'lib/testprune/version'

Gem::Specification.new do |spec|
  spec.name        = 'testprune'
  spec.version     = Testprune::VERSION
  spec.platform    = Gem::Platform::RUBY
  spec.author      = 'Seth MacPherson'
  spec.email       = 'seth.macpherson@appfolio.com'
  spec.summary     = 'Audits a Ruby test suite for duplicate/redundant coverage using Prism AST + Coverage data'
  spec.description = 'Combines Ruby\'s native Coverage execution counts with Prism AST analysis to map per-test ' \
                     'coverage onto semantic units (methods, branches, conditions), find redundant tests grouped ' \
                     'by duplication type with confidence levels, and emit a removal patch — never deleting a ' \
                     'test that would open a coverage gap. Report + patch only; asks for approval before any change.'
  spec.homepage    = 'https://github.com/seth-macpherson/testprune'
  spec.license     = 'MIT'

  spec.files = Dir['lib/**/*.rb'] + Dir['exe/*'] + Dir['assets/*'] + %w[README.md LICENSE]
  spec.bindir      = 'exe'
  spec.executables = ['testprune']
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.add_dependency('prism', ['>= 1.0', '< 3'])
end
