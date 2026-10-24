# frozen_string_literal: true

require "set"

module Synergy
  # Evaluates the rules over a deck and produces the synergistic pairs.
  class Engine
    attr_reader :cards, :tag_store, :rules

    def initialize(cards:, tag_store:, rules:)
      @cards = Engine.order(cards)
      @tag_store = tag_store
      @rules = rules
    end

    # Commanders first, then alphabetical: the row/column order of the matrix.
    def self.order(cards)
      cards.sort_by { |c| [c.commander? ? 0 : 1, c.name] }
    end

    def roles(card)
      @roles ||= {}
      @roles[card.name] ||= card.derived_roles | tag_store.roles_for(card.name)
    end

    # { [name_a, name_b] (sorted) => Set of reasons }
    def pairs
      @pairs ||= begin
        result = Hash.new { |h, k| h[k] = Set.new }
        rules.each do |rule|
          as = cards.select { |c| rule.a.matches?(roles(c)) }
          bs = cards.select { |c| rule.b.matches?(roles(c)) }
          as.product(bs).each do |x, y|
            next if x.equal?(y)

            result[[x.name, y.name].sort] << rule.reason
          end
        end
        result
      end
    end

    def synergy?(a, b) = pairs.key?([a, b].sort)

    def degree(card) = pairs.keys.count { |k| k.include?(card.name) }

    def report
      degrees = cards.map { |c| [c.name, degree(c)] }
      possible = cards.size * (cards.size - 1) / 2.0
      lines = []
      lines << "cards: #{cards.size}   synergy pairs: #{pairs.size}   density: #{(pairs.size / possible).round(3)}"
      lines << "zero-synergy cards: #{degrees.select { |_, d| d.zero? }.map(&:first).join(', ')}"
      lines << "lowest:  " + degrees.sort_by { |n, d| [d, n] }.first(10).map { |n, d| "#{n} (#{d})" }.join(", ")
      lines << "highest: " + degrees.sort_by { |n, d| [-d, n] }.first(10).map { |n, d| "#{n} (#{d})" }.join(", ")
      lines.join("\n")
    end
  end
end
