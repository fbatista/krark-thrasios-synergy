# frozen_string_literal: true

require "tmpdir"

RSpec.describe Synergy::Comparison do
  def side(names, pairs, label)
    degree = names.to_h { |n| [n, pairs.count { |p| p.include?(n) }] }
    described_class::Side.new(names, degree, Set.new(pairs.map(&:sort)), label)
  end

  let(:old) { side(%w[A B C], [%w[A B], %w[B C]], "v1") }
  let(:new) { side(%w[A B D], [%w[A B], %w[A D], %w[B D]], "v2") }
  let(:cmp) { described_class.new(old, new) }

  it "scores a side by its number of pairs" do
    expect(old.score).to eq 2
    expect(new.score).to eq 3
    expect(new.average).to eq 2.0
  end

  it "lists added, removed and changed cards" do
    expect(cmp.added).to eq %w[D]
    expect(cmp.removed).to eq %w[C]
    expect(cmp.deltas).to eq [["A", 1]]
  end

  it "reports the score change" do
    expect(cmp.report).to include("v1 -> v2", "synergy score (pairs): 2 -> 3 (+1)", "+1  A  (1 -> 2)")
  end

  it "round-trips through a matrix CSV" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "synergy_matrix.csv")
      CSV.open(path, "w") { |csv| csv << [nil, "A", "B"]; csv << ["A", nil, 1]; csv << ["B", 1, nil] }
      s = described_class::Side.from_csv(path)
      expect(s.score).to eq 1
      expect(s.degree).to eq("A" => 1, "B" => 1)
    end
  end
end
