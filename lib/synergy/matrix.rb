# frozen_string_literal: true

require "csv"

module Synergy
  # CSV writers for the matrix and the pair list.
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

    def write_pairs(engine, path)
      CSV.open(path, "w") do |csv|
        csv << %w[card_a card_b reasons]
        engine.pairs.sort.each { |(a, b), reasons| csv << [a, b, reasons.sort.join("; ")] }
      end
    end
  end
end
