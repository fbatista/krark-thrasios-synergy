# frozen_string_literal: true

require "tmpdir"

RSpec.describe Synergy::Narrow do
  let(:root) { Dir.mktmpdir }
  let(:dir) { File.join(root, "tags").tap { |d| FileUtils.mkdir_p(d) } }
  after { FileUtils.rm_rf(root) }

  def card(name, board: "mainboard", type_line: "Artifact")
    Synergy::Card.new(name: name, type_line: type_line, oracle_text: "", mana_cost: "{2}", mana_value: 2, colors: [], board: board)
  end

  def tag(name, roles = [], narrow = nil)
    doc = { "name" => name, "roles" => roles }
    doc["narrow"] = narrow if narrow
    File.write(File.join(dir, "#{Synergy::Card.slug(name)}.yml"), doc.to_yaml)
  end

  def rule(reason, a, b, **opts)
    Synergy::Rule.new(reason: reason, a: Synergy::Selector.from_yaml(a), b: Synergy::Selector.from_yaml(b), **opts)
  end

  # One commander and a five-card library; with cards_seen 3 every other library
  # card is seen with probability (3 - 1) / (5 - 1) = 0.5.
  let(:settings) { Synergy::Settings.new("cards_seen" => 3, "finder_weight" => 0.5, "players" => 4, "opening_hand" => 2) }
  let(:cards) { [card("Boss", board: "commanders"), card("Needy"), card("Enabler"), card("Finder"), card("Filler"), card("Other")] }
  let(:rules) do
    [
      rule("needy likes filler", "needy", "filler"),
      rule("needy uses the thing", "needy", "thing"),
      rule("finds the thing", "finds_thing", "thing", finder: true, synergy: false)
    ]
  end
  let(:engine) { Synergy::Engine.new(cards: cards, tag_store: Synergy::TagStore.new(tags_dir: dir), rules: rules, settings: settings) }

  before do
    tag("Boss", %w[boss])
    tag("Enabler", %w[thing])
    tag("Finder", %w[finds_thing])
    tag("Filler", %w[filler])
    tag("Other", %w[filler])
  end

  it "leaves ordinary cards at 1.0" do
    tag("Needy", %w[needy])
    expect(engine.multiplier(engine.card("Needy"))).to eq 1.0
    expect(engine.effective_score).to eq engine.score
  end

  it "combines the enabler and its finders: 1 - (1 - 1.0 x q)(1 - finder_weight x q)" do
    tag("Needy", %w[needy], "needs" => [{ "match" => "thing" }])
    r = engine.narrow.result(engine.card("Needy"))
    expect(r.access).to eq("Enabler" => 1.0, "Finder" => 0.5)
    expect(r.multiplier).to be_within(1e-9).of(1 - (0.5 * 0.75))
  end

  it "scales an alternative by its strength" do
    tag("Needy", %w[needy], "needs" => [{ "match" => "thing", "strength" => 0.5 }])
    expect(engine.narrow.result(engine.card("Needy")).access).to eq("Enabler" => 0.5, "Finder" => 0.25)
    expect(engine.multiplier(engine.card("Needy"))).to be_within(1e-9).of(1 - (0.75 * 0.875))
  end

  it "treats a commander as always available" do
    tag("Needy", %w[needy], "needs" => [{ "match" => "boss" }])
    expect(engine.multiplier(engine.card("Needy"))).to eq 1.0
  end

  it "gives 0 when nothing in the deck satisfies the need" do
    tag("Needy", %w[needy], "needs" => [{ "match" => "missing_role" }])
    expect(engine.multiplier(engine.card("Needy"))).to eq 0.0
  end

  it "applies conditions, chance and floor" do
    tag("Needy", %w[needy], "conditions" => %w[in_opening_hand not_first_player])
    expect(engine.multiplier(engine.card("Needy"))).to be_within(1e-9).of((2.0 / 3) * 0.75)

    tag("Needy", %w[needy], "chance" => 0.5, "floor" => 0.2)
    fresh = Synergy::Engine.new(cards: cards, tag_store: Synergy::TagStore.new(tags_dir: dir), rules: rules, settings: settings)
    expect(fresh.multiplier(fresh.card("Needy"))).to be_within(1e-9).of(0.2 + (0.8 * 0.5))
  end

  it "weights pairs by the multiplier, except the link to the card's own enabler" do
    tag("Needy", %w[needy], "needs" => [{ "match" => "thing" }])
    expect(engine.pair_weight("Needy", "Filler")).to be_within(1e-9).of(0.625)
    expect(engine.pair_weight("Enabler", "Needy")).to eq 1.0
    expect(engine.score).to eq 3
    expect(engine.effective_score).to be_within(1e-9).of(0.625 + 0.625 + 1.0)
    expect(engine.effective_degree(engine.card("Needy"))).to be_within(1e-9).of(2.25)
  end

  it "keeps finder-only rules out of the matrix" do
    tag("Needy", %w[needy])
    expect(engine.synergy?("Finder", "Enabler")).to be false
    expect(engine.finders_of(engine.card("Enabler")).map(&:name)).to eq ["Finder"]
  end

  it "rejects malformed narrow blocks" do
    expect { described_class.parse("needs" => [{ "match" => "x", "strength" => 2 }]) }.to raise_error(Synergy::Error, /strength/)
    expect { described_class.parse("conditions" => ["full_moon"]) }.to raise_error(Synergy::Error, /unknown condition/)
    expect { described_class.parse("nedes" => []) }.to raise_error(Synergy::Error, /unknown key/)
    expect { described_class.parse({}) }.to raise_error(Synergy::Error, /at least one/)
  end

  it "is linted: unknown roles in needs are errors" do
    File.write(File.join(root, "roles.yml"), { "needy" => "x", "thing" => "x", "finds_thing" => "x", "filler" => "x", "boss" => "x" }.to_yaml)
    tag("Needy", %w[needy], "needs" => [{ "match" => "no_such_role" }])
    errors, = Synergy::TagStore.new(tags_dir: dir, roles_path: File.join(root, "roles.yml")).lint(cards, rules: rules)
    expect(errors).to include(a_string_matching(/needy.yml: narrow: unknown role "no_such_role"/))
  end
end
