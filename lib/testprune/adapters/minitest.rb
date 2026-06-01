# frozen_string_literal: true

require_relative '../recorder'

module Testprune
  module Adapters
    # Minitest integration. Brackets each test via the before_setup/after_teardown
    # lifecycle hooks rather than wrapping #run. Wrapping #run is unsafe here:
    # minitest-reporters does `alias_method :run_without_hooks, :run` after we'd
    # prepend, capturing our method into its alias and causing infinite recursion.
    # The lifecycle hooks are called exactly once per test and are not aliased.
    module Minitest
      module Hook
        def before_setup
          Testprune::Recorder.instance.start_test
          super
        end

        def after_teardown
          super
        ensure
          recorder = Testprune::Recorder.instance
          id = "#{self.class}##{name}"
          file, line = location
          recorder.finish_test(id: id, description: id, file: file, line: line)
        end

        private

        def location
          method(name).source_location
        rescue NameError
          [nil, nil]
        end
      end

      def self.install
        ::Minitest::Test.prepend(Hook)
      end
    end
  end
end
