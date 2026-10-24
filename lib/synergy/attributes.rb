# frozen_string_literal: true

require "csv"
require "yaml"

module Synergy
  # The 100 x N attribute table. Each column in data/attributes.yml is a name
  # plus any of: oracle (regex on rules text), mana_cost (regex), roles (any of).
  class Attributes
    Column = Struct.new(:name, :oracle, :mana_cost, :roles, :description)

    attr_reader :columns

    def initialize(columns)
      @columns = columns
    end

    def self.load(path = File.join(DATA_DIR, "attributes.yml"))
      new(Array(YAML.safe_load_file(path)).map do |h|
        Column.new(h["name"],
                   h["oracle"] && Regexp.new(h["oracle"], Regexp::IGNORECASE),
                   h["mana_cost"] && Regexp.new(h["mana_cost"]),
                   Array(h["roles"]).map(&:to_s),
                   h["description"])
      end)
    end

    def value(column, card, roles)
      hit = (column.oracle && card.oracle_text.match?(column.oracle)) ||
            (column.mana_cost && card.mana_cost.match?(column.mana_cost)) ||
            column.roles.any? { |r| roles.include?(r) }
      hit ? 1 : 0
    end

    def write(engine, path)
      CSV.open(path, "w") do |csv|
        csv << %w[card type_line mana_cost] + columns.map(&:name)
        engine.cards.each do |c|
          roles = engine.roles(c)
          csv << [c.name, c.type_line, c.mana_cost.empty? ? nil : c.mana_cost] + columns.map { |col| value(col, c, roles) }
        end
      end
    end
  end
end
