# frozen_string_literal: true

RSpec.describe Synergy::Selector do
  let(:roles) { Set.new(%w[creature green mv_le_2]) }

  it "accepts a single role" do
    expect(described_class.from_yaml("creature").matches?(roles)).to be true
    expect(described_class.from_yaml("land").matches?(roles)).to be false
  end

  it "requires every role of a list" do
    expect(described_class.from_yaml(%w[creature green]).matches?(roles)).to be true
    expect(described_class.from_yaml(%w[creature red]).matches?(roles)).to be false
  end

  it "supports all / any / none" do
    sel = described_class.from_yaml("all" => "creature", "any" => %w[red green], "none" => "commander")
    expect(sel.matches?(roles)).to be true
    expect(sel.matches?(roles | ["commander"])).to be false
    expect(sel.matches?(Set.new(%w[creature blue]))).to be false
  end

  it "rejects an empty selector" do
    expect { described_class.from_yaml({}) }.to raise_error(Synergy::Error)
  end
end
