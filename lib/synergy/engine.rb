# frozen_string_literal: true

require "set"

module Synergy
  # Evaluates the rules over a deck and produces the synergistic pairs.
  class Engine
    attr_reader :cards, :tag_store, :rules, :settings

    def initialize(cards:, tag_store:, rules:, settings: Settings.new)
      @cards = Engine.order(cards)
      @tag_store = tag_store
      @rules = rules
      @settings = settings
      @by_name = @cards.to_h { |c| [c.name, c] }
    end

    # Commanders first, then alphabetical: the row/column order of the matrix.
    def self.order(cards)
      cards.sort_by { |c| [c.commander? ? 0 : 1, c.name] }
    end

    def card(name) = @by_name[name]

    def roles(card)
      @roles ||= {}
      @roles[card.name] ||= card.derived_roles | tag_store.roles_for(card.name)
    end

    # { [name_a, name_b] (sorted) => Set of reasons }
    def pairs
      @pairs ||= begin
        result = Hash.new { |h, k| h[k] = Set.new }
        rules.select(&:synergy).each do |rule|
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

    # Number of cards this card has synergy with.
    def degree(card)
      @degrees ||= pairs.keys.flatten.tally
      @degrees.fetch(card.name, 0)
    end

    # The deck's synergy score: number of synergistic pairs (sum of the matrix / 2).
    def score = pairs.size

    # Cards that can fetch +card+ from the library, per the rules marked `finder: true`.
    def finders_of(card)
      @finders ||= {}
      @finders[card.name] ||= rules.select(&:finder).flat_map do |rule|
        next [] unless rule.b.matches?(roles(card))

        cards.select { |c| !c.equal?(card) && rule.a.matches?(roles(c)) }
      end.uniq
    end

    def narrow = @narrow ||= Narrow.new(self, settings)

    # 1.0 for an ordinary card, lower for a card that needs specific things to function.
    def multiplier(card) = narrow.multiplier(card)

    def pair_weight(a_name, b_name) = narrow.pair_weight(card(a_name), card(b_name))

    # The score with every pair weighted by the narrow multipliers of its two cards.
    def effective_score = pairs.keys.sum { |a, b| pair_weight(a, b) }

    def effective_degree(card)
      @effective_degrees ||= pairs.keys.each_with_object(Hash.new(0.0)) do |(a, b), h|
        w = pair_weight(a, b)
        h[a] += w
        h[b] += w
      end
      @effective_degrees.fetch(card.name, 0.0)
    end

    def report
      degrees = cards.map { |c| [c.name, degree(c)] }
      possible = cards.size * (cards.size - 1) / 2.0
      lines = []
      lines << "cards: #{cards.size}   synergy pairs: #{pairs.size}   density: #{(pairs.size / possible).round(3)}"
      lines << format("effective score (narrow-adjusted): %.1f", effective_score)
      lines << "zero-synergy cards: #{degrees.select { |_, d| d.zero? }.map(&:first).join(', ')}"
      lines << "lowest:  " + degrees.sort_by { |n, d| [d, n] }.first(10).map { |n, d| "#{n} (#{d})" }.join(", ")
      lines << "highest: " + degrees.sort_by { |n, d| [-d, n] }.first(10).map { |n, d| "#{n} (#{d})" }.join(", ")
      narrow.results.each do |r|
        lines << format("narrow:  x%.2f  %s  (%d pairs -> %.1f effective)", r.multiplier, r.card.name, degree(r.card), effective_degree(r.card))
      end
      lines.join("\n")
    end
  end
end
