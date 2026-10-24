# frozen_string_literal: true

require "csv"

module Synergy
  # Compares two synergy matrices (two deck versions, or two rule sets).
  class Comparison
    Side = Struct.new(:names, :degree, :pairs, :label) do
      # The deck's synergy score: number of synergistic pairs (= sum of the matrix / 2).
      def score = pairs.size
      def average = names.empty? ? 0.0 : 2.0 * pairs.size / names.size

      def self.from_engine(engine, label: nil)
        new(engine.cards.map(&:name), engine.cards.to_h { |c| [c.name, engine.degree(c)] }, Set.new(engine.pairs.keys), label)
      end

      def self.from_csv(path)
        rows = CSV.read(path)
        names = rows.first[1..]
        degree = {}
        pairs = Set.new
        rows[1..].each do |row|
          degree[row[0]] = row[1..].count { |v| v == "1" }
          names.each_with_index { |b, i| pairs << [row[0], b].sort if row[i + 1] == "1" }
        end
        new(names, degree, pairs, File.basename(File.dirname(File.expand_path(path))))
      end
    end

    attr_reader :old, :new

    def initialize(old_side, new_side)
      @old = old_side
      @new = new_side
    end

    def added = new.names - old.names
    def removed = old.names - new.names
    def kept = new.names & old.names

    def deltas
      kept.map { |n| [n, new.degree[n] - old.degree[n]] }.reject { |_, d| d.zero? }.sort_by { |n, d| [d, n] }
    end

    def report
      l = []
      l << "#{old.label || 'old'} -> #{new.label || 'new'}"
      l << "synergy score (pairs): #{old.score} -> #{new.score} (#{format('%+d', new.score - old.score)})"
      l << format("avg synergies per card: %.1f -> %.1f", old.average, new.average)
      l << "" << "removed (synergies in old version):"
      removed.each { |n| l << format("  %3d  %s", old.degree[n], n) }
      l << "added (synergies in new version):"
      added.each { |n| l << format("  %3d  %s", new.degree[n], n) }
      l << "" << "kept cards that changed:"
      deltas.each { |n, d| l << format("  %+d  %s  (%d -> %d)", d, n, old.degree[n], new.degree[n]) }
      l.join("\n")
    end

    def write_csv(path)
      CSV.open(path, "w") do |csv|
        csv << %w[card status synergies_old synergies_new delta]
        (old.names | new.names).sort.each do |n|
          status = removed.include?(n) ? "removed" : added.include?(n) ? "added" : "kept"
          csv << [n, status, old.degree[n], new.degree[n], status == "kept" ? new.degree[n] - old.degree[n] : nil]
        end
      end
    end
  end
end
