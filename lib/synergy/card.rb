# frozen_string_literal: true

require "set"

module Synergy
  # One card of the deck: printed data plus the roles the engine can derive
  # mechanically from the type line, mana cost and rules text.
  class Card
    BASIC_TYPES = %w[Plains Island Swamp Mountain Forest].freeze
    COLOR_NAMES = { "W" => "white", "U" => "blue", "B" => "black", "R" => "red", "G" => "green" }.freeze

    attr_reader :name, :type_line, :oracle_text, :mana_cost, :mana_value, :colors, :board, :faces, :power, :toughness

    def initialize(name:, type_line:, oracle_text:, mana_cost:, mana_value:, colors:, board:, faces: [], power: nil, toughness: nil)
      @name = name
      @type_line = type_line.to_s
      @faces = faces || []
      @power = power
      @toughness = toughness
      @oracle_text = oracle_text.to_s
      @oracle_text = @faces.map { |f| f["oracle_text"].to_s }.join("\n") if @oracle_text.empty? && @faces.any?
      @mana_cost = mana_cost.to_s
      @mana_value = (mana_value || 0).to_f
      @colors = Array(colors).map(&:to_s)
      @colors = @mana_cost.scan(/[WUBRG]/).uniq if @colors.empty?
      @board = board.to_s
    end

    # Builds a card from one entry of cards.json.
    def self.from_h(h)
      new(
        name: h["name"], type_line: h["type_line"], oracle_text: h["oracle_text"],
        mana_cost: h["mana_cost"], mana_value: h["cmc"] || h["mana_value"], colors: h["colors"],
        board: h["board"], faces: h["faces"], power: h["power"], toughness: h["toughness"]
      )
    end

    def to_h
      {
        "board" => board, "name" => name, "type_line" => type_line, "oracle_text" => faces.any? ? nil : oracle_text,
        "mana_cost" => mana_cost, "cmc" => mana_value, "colors" => colors, "faces" => faces,
        "power" => power, "toughness" => toughness
      }
    end

    def commander? = board == "commanders"

    # Type line of the face you cast / play. The back face of a double-faced card
    # is not what sits in your library or hand.
    def front_type_line = faces.any? ? faces.first["type_line"].to_s : type_line

    def type?(word) = front_type_line.include?(word)
    def sticker? = type?("Stickers")
    def power_le_2? = power.to_s.match?(/\A\d+\z/) && power.to_i <= 2
    def land? = type?("Land")
    def creature? = type?("Creature")
    def legendary? = type?("Legendary")
    def instant_or_sorcery? = type?("Instant") || type?("Sorcery")
    def generic_in_cost? = mana_cost.match?(/\{(X|[1-9]\d*)\}/)
    def fetchland? = oracle_text.include?("Sacrifice this land: Search your library")

    # Land types a fetchland can search for ("Forest or Island card").
    def fetched_types
      m = oracle_text.match(/Search your library for an? (\w+) or (\w+) card/)
      m ? [m[1], m[2]] : []
    end

    # Roles that follow from the card data alone. Curated roles live in data/tags.
    def derived_roles
      r = Set.new
      return r << "sticker" if sticker?

      r << (land? ? "land" : "nonland")
      r << "creature" if creature?
      r << "noncreature_spell" if !land? && !creature?
      r << "instant" if type?("Instant")
      r << "sorcery" if type?("Sorcery")
      r << "instant_sorcery" if instant_or_sorcery?
      r << "artifact" if type?("Artifact") && !land?
      r << "enchantment" if type?("Enchantment")
      r << "legendary" if legendary?
      r << "legendary_creature" if legendary? && creature?
      r << "nonlegendary_creature" if creature? && !legendary?
      r << "legendary_noncreature_spell" if legendary? && !land? && !creature?
      r << "commander" if commander?
      r << "wizard" if creature? && type?("Wizard")
      r << "shaman" if creature? && type?("Shaman")
      r << "power_le_2" if creature? && power_le_2?
      if land?
        BASIC_TYPES.each { |t| r << "#{t.downcase}_land" if type?(t) }
        if fetchland?
          r << "fetchland"
          fetched_types.each { |t| r << "fetches_#{t.downcase}" }
        end
      else
        r << "mv_le_1" if mana_value <= 1
        r << "mv_le_2" if mana_value <= 2
        r << "mana_cost_0_or_1" if ["{0}", "{1}"].include?(mana_cost)
        r << "generic_in_cost" if generic_in_cost?
        colors.each { |c| r << COLOR_NAMES.fetch(c, c.downcase) }
        r << "red_or_green" if (colors & %w[R G]).any?
      end
      r
    end

    # The list every tag file and rule can rely on, for roles.yml and docs.
    DERIVED_ROLE_NAMES = (
      %w[land nonland creature noncreature_spell instant sorcery instant_sorcery artifact enchantment legendary
         legendary_creature nonlegendary_creature legendary_noncreature_spell commander wizard shaman fetchland
         mv_le_1 mv_le_2 mana_cost_0_or_1 generic_in_cost red_or_green power_le_2 sticker] +
      BASIC_TYPES.map { |t| "#{t.downcase}_land" } + BASIC_TYPES.map { |t| "fetches_#{t.downcase}" } +
      COLOR_NAMES.values
    ).freeze

    def slug = Card.slug(name)

    def self.slug(name)
      name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
    end
  end
end
