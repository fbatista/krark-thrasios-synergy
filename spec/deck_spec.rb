# frozen_string_literal: true

RSpec.describe Synergy::Deck do
  it "parses the pipe format" do
    deck = described_class.parse("c|1|Krark, the Thumbless\nm|1|Sol Ring\n")
    expect(deck.names).to eq ["Krark, the Thumbless", "Sol Ring"]
    expect(deck.board_for("Krark, the Thumbless")).to eq "commanders"
    expect(deck.board_for("Sol Ring")).to eq "mainboard"
  end

  it "parses a Moxfield text export with set codes, markers and sections" do
    text = <<~DECK
      Commander
      1 Thrasios, Triton Hero (CMR) 456
      1 Krark, the Thumbless (CMR) 500 *F*

      Mainboard
      1 Sol Ring (C21) 263
      1x Lion's Eye Diamond
      1 Ragavan, Nimble Pilferer (MH2) 138 *CMDR*

      Sideboard
      1 Counterspell
    DECK
    deck = described_class.parse(text)
    expect(deck.names).to eq ["Thrasios, Triton Hero", "Krark, the Thumbless", "Sol Ring", "Lion's Eye Diamond", "Ragavan, Nimble Pilferer"]
    expect(deck.board_for("Krark, the Thumbless")).to eq "commanders"
    expect(deck.board_for("Ragavan, Nimble Pilferer")).to eq "commanders"
    expect(deck.board_for("Sol Ring")).to eq "mainboard"
    expect(deck.size).to eq 5
  end

  it "keeps names that contain parentheses-free punctuation" do
    deck = described_class.parse("1 An Offer You Can't Refuse\n1 Birgi, God of Storytelling // Harnfel, Horn of Bounty\n")
    expect(deck.names).to include("An Offer You Can't Refuse", "Birgi, God of Storytelling // Harnfel, Horn of Bounty")
  end

  it "fails loudly on an unparseable line" do
    expect { described_class.parse("Sol Ring\n") }.to raise_error(Synergy::Error, /cannot parse/)
  end
end
