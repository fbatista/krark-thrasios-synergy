# frozen_string_literal: true

require "yaml"

module Synergy
  # Tunable assumptions, read from data/settings.yml and overridable from the CLI.
  class Settings
    DEFAULTS = { "cards_seen" => 12, "finder_weight" => 0.75, "players" => 4, "opening_hand" => 7 }.freeze

    attr_reader :cards_seen, :finder_weight, :players, :opening_hand

    def initialize(values = {})
      v = DEFAULTS.merge(values.transform_keys(&:to_s).compact)
      @cards_seen = Integer(v["cards_seen"])
      @finder_weight = Float(v["finder_weight"])
      @players = Integer(v["players"])
      @opening_hand = Integer(v["opening_hand"])
      raise Error, "cards_seen must be at least 1" if @cards_seen < 1
      raise Error, "finder_weight must be between 0 and 1" unless (0.0..1.0).cover?(@finder_weight)
      raise Error, "players must be at least 1" if @players < 1
    end

    def self.load(path = File.join(DATA_DIR, "settings.yml"), overrides = {})
      file = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
      new((file["narrow"] || {}).merge(overrides.transform_keys(&:to_s).compact))
    end

    def to_s = "cards_seen=#{cards_seen}, finder_weight=#{finder_weight}, players=#{players}, opening_hand=#{opening_hand}"
  end
end
