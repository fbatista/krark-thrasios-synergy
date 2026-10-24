# frozen_string_literal: true

require_relative "../lib/synergy"

FIXTURES = File.join(__dir__, "fixtures")

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
end
