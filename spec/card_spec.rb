# frozen_string_literal: true

RSpec.describe Synergy::Card do
  def card(**attrs)
    described_class.new(**{ name: "X", type_line: "", oracle_text: "", mana_cost: "", mana_value: 0, colors: [], board: "mainboard" }.merge(attrs))
  end

  it "derives type, cost and color roles" do
    c = card(name: "Krark, the Thumbless", type_line: "Legendary Creature — Goblin Wizard", mana_cost: "{1}{R}", mana_value: 2, colors: ["R"], board: "commanders")
    expect(c.derived_roles).to include("nonland", "creature", "legendary_creature", "commander", "wizard", "mv_le_2", "generic_in_cost", "red", "red_or_green")
    expect(c.derived_roles).not_to include("mv_le_1", "nonlegendary_creature", "land")
  end

  it "derives fetchland roles from the rules text" do
    c = card(type_line: "Land", oracle_text: "{T}, Pay 1 life, Sacrifice this land: Search your library for a Forest or Island card, put it onto the battlefield, then shuffle.")
    expect(c.derived_roles).to include("land", "fetchland", "fetches_forest", "fetches_island")
    expect(c.derived_roles).not_to include("forest_land")
  end

  it "derives basic land types and never mana-value roles for lands" do
    c = card(type_line: "Land — Forest Island")
    expect(c.derived_roles).to include("forest_land", "island_land")
    expect(c.derived_roles).not_to include("mv_le_1")
  end

  it "joins the faces of a double-faced card and falls back to the mana cost for colors" do
    c = card(name: "Birgi // Harnfel", type_line: "Legendary Creature — God // Legendary Artifact", mana_cost: "{2}{R}", mana_value: 3,
             faces: [{ "oracle_text" => "front" }, { "oracle_text" => "back" }])
    expect(c.oracle_text).to eq "front\nback"
    expect(c.colors).to eq ["R"]
  end

  it "builds a filesystem slug" do
    expect(described_class.slug("Birgi, God of Storytelling // Harnfel, Horn of Bounty")).to eq "birgi-god-of-storytelling-harnfel-horn-of-bounty"
    expect(described_class.slug("An Offer You Can't Refuse")).to eq "an-offer-you-can-t-refuse"
  end
end
