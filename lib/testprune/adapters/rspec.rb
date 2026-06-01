# frozen_string_literal: true

require_relative '../recorder'

module Testprune
  module Adapters
    # RSpec integration. Installed by autostart once ::RSpec is defined. Wraps each
    # example to capture its coverage delta + timing, and dumps run.json after the
    # suite.
    module RSpec
      def self.install
        recorder = Testprune::Recorder.instance
        recorder.framework = 'rspec'

        ::RSpec.configure do |config|
          config.around(:each) do |example|
            md = example.metadata
            Testprune::Recorder.instance.around(
              id:          example.id,
              description: example.full_description,
              file:        md[:file_path],
              line:        md[:line_number]
            ) { example.run }
          end

          config.after(:suite) { Testprune::Recorder.instance.dump }
        end
      end
    end
  end
end
