# frozen_string_literal: true

RSpec.describe Synergy::Attributes do
  let(:attrs) { described_class.load }
  let(:col) { ->(name) { attrs.columns.find { |c| c.name == name } } }

  def card(oracle, mana_cost: "{1}")
    Synergy::Card.new(name: "X", type_line: "Instant", oracle_text: oracle, mana_cost: mana_cost, mana_value: 1, colors: [], board: "mainboard")
  end

  it "flags counterspells as anti_stack and removal as anti_permanent" do
    expect(attrs.value(col["anti_stack"], card("Counter target noncreature spell."), Set.new)).to eq 1
    expect(attrs.value(col["anti_permanent"], card("Destroy target artifact."), Set.new)).to eq 1
    expect(attrs.value(col["anti_permanent"], card("Untap target permanent."), Set.new)).to eq 0
  end

  it "flags Treasure makers and tap-for-mana as mana" do
    expect(attrs.value(col["mana"], card("Its controller creates two Treasure tokens. Create two Treasure tokens."), Set.new)).to eq 1
    expect(attrs.value(col["mana"], card("{T}: Add {C}."), Set.new)).to eq 1
    expect(attrs.value(col["mana"], card("Draw a card."), Set.new)).to eq 0
  end

  it "flags 'adds an additional' mana wording as mana, but not other uses of 'additional'" do
    expect(attrs.value(col["mana"], card("Whenever you tap a creature for mana, add an additional {G}."), Set.new)).to eq 1
    expect(attrs.value(col["mana"], card("Whenever enchanted Forest is tapped for mana, its controller adds an additional one mana of the chosen color."), Set.new)).to eq 1
    expect(attrs.value(col["mana"], card("If a triggered ability of equipped creature triggers, that ability triggers an additional time."), Set.new)).to eq 0
    expect(attrs.value(col["mana"], card("You may play an additional land on each of your turns."), Set.new)).to eq 0
  end

  it "flags free casts from the mana cost" do
    expect(attrs.value(col["free_cast"], card("", mana_cost: "{0}"), Set.new)).to eq 1
    expect(attrs.value(col["free_cast"], card("", mana_cost: "{U/P}"), Set.new)).to eq 1
    expect(attrs.value(col["free_cast"], card("", mana_cost: "{1}{U}"), Set.new)).to eq 0
  end

  it "uses roles for the role-based columns" do
    expect(attrs.value(col["untap"], card("nothing"), Set["untaps_all_each_turn"])).to eq 1
    expect(attrs.value(col["land"], card("nothing"), Set["land"])).to eq 1
  end
end
