# frozen_string_literal: true

require "csv"

module Synergy
  # CSV writers for the matrix, the pair list and the narrow-card table.
  module Matrix
    module_function

    def write_matrix(engine, path)
      names = engine.cards.map(&:name)
      CSV.open(path, "w") do |csv|
        csv << [nil] + names
        names.each do |a|
          csv << [a] + names.map { |b| a == b ? nil : (engine.synergy?(a, b) ? 1 : 0) }
        end
      end
    end

    # weight = product of the two cards' narrow multipliers (1 for ordinary cards).
    def write_pairs(engine, path)
      CSV.open(path, "w") do |csv|
        csv << %w[card_a card_b reasons weight]
        engine.pairs.sort.each do |(a, b), reasons|
          csv << [a, b, reasons.sort.join("; "), engine.pair_weight(a, b).round(3)]
        end
      end
    end

    def narrow_rows(engine)
      engine.narrow.results.map do |r|
        [r.card.name, r.multiplier.round(3), engine.degree(r.card), engine.effective_degree(r.card).round(1),
         r.access_probability.round(3), r.chance.round(3), r.floor,
         r.access.map { |name, strength| "#{name} (#{strength.round(2)})" }.join("; "), r.spec.note]
      end
    end

    def write_narrow(engine, path)
      CSV.open(path, "w") do |csv|
        csv << %w[card multiplier pairs effective access_probability chance floor enablers note]
        narrow_rows(engine).each { |row| csv << row }
      end
    end
  end
end
