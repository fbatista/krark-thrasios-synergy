# frozen_string_literal: true

require "csv"

module Synergy
  # Compares two synergy matrices (two deck versions, or two rule sets).
  class Comparison
    # weights: { [a, b] => pair weight }, multipliers: { name => narrow multiplier };
    # both optional (a bare matrix CSV carries neither, every weight is then 1).
    Side = Struct.new(:names, :degree, :pairs, :label, :weights, :multipliers) do
      # The deck's synergy score: number of synergistic pairs (= sum of the matrix / 2).
      def score = pairs.size
      def average = names.empty? ? 0.0 : 2.0 * pairs.size / names.size

      def weight(pair) = weights ? weights.fetch(pair, 1.0) : 1.0

      # The score with each pair weighted by its cards' narrow multipliers.
      def effective_score = pairs.sum { |p| weight(p) }

      def effective_degree
        @effective_degree ||= pairs.each_with_object(Hash.new(0.0)) do |p, h|
          p.each { |n| h[n] += weight(p) }
        end
      end

      def multiplier(name) = multipliers ? multipliers.fetch(name, 1.0) : 1.0

      def self.from_engine(engine, label: nil)
        new(engine.cards.map(&:name), engine.cards.to_h { |c| [c.name, engine.degree(c)] }, Set.new(engine.pairs.keys), label,
            engine.pairs.keys.to_h { |k| [k, engine.pair_weight(*k)] },
            engine.cards.to_h { |c| [c.name, engine.multiplier(c)] })
      end

      # Reads a saved synergy_matrix.csv; picks up weights and multipliers from the
      # synergy_pairs.csv and narrow.csv next to it when they are there.
      def self.from_csv(path)
        rows = CSV.read(path)
        names = rows.first[1..]
        degree = {}
        pairs = Set.new
        rows[1..].each do |row|
          degree[row[0]] = row[1..].count { |v| v == "1" }
          names.each_with_index { |b, i| pairs << [row[0], b].sort if row[i + 1] == "1" }
        end
        dir = File.dirname(File.expand_path(path))
        new(names, degree, pairs, File.basename(dir), saved_weights(dir), saved_multipliers(dir))
      end

      def self.saved_weights(dir)
        file = File.join(dir, "synergy_pairs.csv")
        return nil unless File.exist?(file)

        table = CSV.read(file, headers: true)
        return nil unless table.headers.include?("weight")

        table.to_h { |r| [[r["card_a"], r["card_b"]].sort, r["weight"].to_f] }
      end

      def self.saved_multipliers(dir)
        file = File.join(dir, "narrow.csv")
        return nil unless File.exist?(file)

        CSV.read(file, headers: true).to_h { |r| [r["card"], r["multiplier"].to_f] }
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
      l << format("effective score (narrow-adjusted): %.1f -> %.1f (%+.1f)", old.effective_score, new.effective_score, new.effective_score - old.effective_score)
      l << format("avg synergies per card: %.1f -> %.1f", old.average, new.average)
      l << "" << "removed (pairs, effective, in old version):"
      removed.each { |n| l << card_line(old, n) }
      l << "added (pairs, effective, in new version):"
      added.each { |n| l << card_line(new, n) }
      narrow = kept.select { |n| new.multiplier(n) < 1.0 || old.multiplier(n) < 1.0 }
      unless narrow.empty?
        l << "" << "kept narrow cards (multiplier old -> new):"
        narrow.each { |n| l << format("  x%.2f -> x%.2f  %s", old.multiplier(n), new.multiplier(n), n) }
      end
      l << "" << "kept cards that changed:"
      deltas.each { |n, d| l << format("  %+d  %s  (%d -> %d)", d, n, old.degree[n], new.degree[n]) }
      l.join("\n")
    end

    def write_csv(path)
      CSV.open(path, "w") do |csv|
        csv << %w[card status synergies_old synergies_new delta effective_old effective_new multiplier_old multiplier_new]
        (old.names | new.names).sort.each do |n|
          status = removed.include?(n) ? "removed" : added.include?(n) ? "added" : "kept"
          in_old = old.names.include?(n)
          in_new = new.names.include?(n)
          csv << [n, status, old.degree[n], new.degree[n], status == "kept" ? new.degree[n] - old.degree[n] : nil,
                  in_old ? old.effective_degree[n].round(1) : nil, in_new ? new.effective_degree[n].round(1) : nil,
                  in_old ? old.multiplier(n).round(3) : nil, in_new ? new.multiplier(n).round(3) : nil]
        end
      end
    end

    private

    def card_line(side, name)
      m = side.multiplier(name)
      format("  %3d  %6.1f  %s%s", side.degree[name], side.effective_degree[name], name, m < 1.0 ? format("  (narrow x%.2f)", m) : "")
    end
  end
end
