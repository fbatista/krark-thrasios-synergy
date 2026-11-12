# frozen_string_literal: true

require "yaml"

module Synergy
  # Two selectors and a reason: every card matching +a+ has synergy with every
  # card matching +b+. The matrix is symmetric, so a/b order is only for reading,
  # except for finder rules.
  #
  #   finder: true    +a+ can fetch +b+ from the library (a tutor). Used by the
  #                   narrow penalty: a tutor for the card you need is nearly as
  #                   good as the card.
  #   synergy: false  the rule adds no link to the matrix; it only records who can
  #                   find what ("Expedition Map finds any land").
  class Rule
    attr_reader :reason, :a, :b, :finder, :synergy

    def initialize(reason:, a:, b:, finder: false, synergy: true)
      @reason = reason
      @a = a
      @b = b
      @finder = finder ? true : false
      @synergy = synergy ? true : false
    end

    def self.load(path = File.join(DATA_DIR, "rules.yml"))
      Array(YAML.safe_load_file(path)).map do |h|
        raise Error, "rule without reason: #{h.inspect}" unless h["reason"]

        unknown = h.keys - %w[reason a b finder synergy]
        raise Error, "rule #{h['reason'].inspect}: unknown key(s) #{unknown.join(', ')}" unless unknown.empty?

        new(reason: h["reason"], a: Selector.from_yaml(h["a"]), b: Selector.from_yaml(h["b"]),
            finder: h.fetch("finder", false), synergy: h.fetch("synergy", true))
      end
    end

    def roles = a.roles + b.roles
  end
end
