# frozen_string_literal: true

require "tmpdir"

RSpec.describe Synergy::Engine do
  let(:dir) { Dir.mktmpdir }
  after { FileUtils.rm_rf(dir) }

  def write_tag(name, roles)
    File.write(File.join(dir, "#{Synergy::Card.slug(name)}.yml"), { "name" => name, "roles" => roles }.to_yaml)
  end

  let(:cards) do
    [
      Synergy::Card.new(name: "Krark", type_line: "Legendary Creature — Goblin Wizard", oracle_text: "", mana_cost: "{1}{R}", mana_value: 2, colors: ["R"], board: "commanders"),
      Synergy::Card.new(name: "Brainstorm", type_line: "Instant", oracle_text: "", mana_cost: "{U}", mana_value: 1, colors: ["U"], board: "mainboard"),
      Synergy::Card.new(name: "Sol Ring", type_line: "Artifact", oracle_text: "", mana_cost: "{1}", mana_value: 1, colors: [], board: "mainboard"),
      Synergy::Card.new(name: "Taiga", type_line: "Land — Mountain Forest", oracle_text: "", mana_cost: "", mana_value: 0, colors: [], board: "mainboard")
    ]
  end
  let(:rules) do
    [
      Synergy::Rule.new(reason: "copies spells", a: Synergy::Selector.from_yaml("copies_spells"), b: Synergy::Selector.from_yaml("instant_sorcery")),
      Synergy::Rule.new(reason: "cheap artifacts", a: Synergy::Selector.from_yaml("cheap_stuff"), b: Synergy::Selector.from_yaml(%w[artifact mv_le_1])),
      Synergy::Rule.new(reason: "self", a: Synergy::Selector.from_yaml("copies_spells"), b: Synergy::Selector.from_yaml("copies_spells"))
    ]
  end
  let(:engine) do
    write_tag("Krark", %w[copies_spells cheap_stuff])
    write_tag("Brainstorm", [])
    write_tag("Sol Ring", [])
    write_tag("Taiga", [])
    described_class.new(cards: cards, tag_store: Synergy::TagStore.new(tags_dir: dir), rules: rules)
  end

  it "orders commanders first, then alphabetically" do
    expect(engine.cards.map(&:name)).to eq %w[Krark Brainstorm Sol\ Ring Taiga]
  end

  it "links cards through role selectors, symmetrically, never with themselves" do
    expect(engine.synergy?("Krark", "Brainstorm")).to be true
    expect(engine.synergy?("Brainstorm", "Krark")).to be true
    expect(engine.synergy?("Krark", "Sol Ring")).to be true
    expect(engine.synergy?("Krark", "Taiga")).to be false
    expect(engine.pairs.keys).not_to include(%w[Krark Krark])
    expect(engine.pairs[%w[Brainstorm Krark]]).to eq Set["copies spells"]
  end

  it "counts degrees" do
    expect(engine.degree(cards[0])).to eq 2
    expect(engine.degree(cards[3])).to eq 0
  end

  it "writes a symmetric matrix with an empty diagonal" do
    path = File.join(dir, "m.csv")
    Synergy::Matrix.write_matrix(engine, path)
    rows = CSV.read(path)
    expect(rows[0]).to eq [nil, "Krark", "Brainstorm", "Sol Ring", "Taiga"]
    expect(rows[1]).to eq ["Krark", nil, "1", "1", "0"]
    expect(rows[2]).to eq ["Brainstorm", "1", nil, "0", "0"]
  end
end
