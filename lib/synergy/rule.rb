# frozen_string_literal: true

require "yaml"

module Synergy
  # Two selectors and a reason: every card matching +a+ has synergy with every
  # card matching +b+. The matrix is symmetric, so a/b order is only for reading.
  class Rule
    attr_reader :reason, :a, :b

    def initialize(reason:, a:, b:)
      @reason = reason
      @a = a
      @b = b
    end

    def self.load(path = File.join(DATA_DIR, "rules.yml"))
      Array(YAML.safe_load_file(path)).map do |h|
        raise Error, "rule without reason: #{h.inspect}" unless h["reason"]

        new(reason: h["reason"], a: Selector.from_yaml(h["a"]), b: Selector.from_yaml(h["b"]))
      end
    end

    def roles = a.roles + b.roles
  end
end
