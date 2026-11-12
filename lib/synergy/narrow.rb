# frozen_string_literal: true

module Synergy
  # The "narrow penalty": a multiplier between 0 and 1 for cards that only function
  # when something specific is around (Earthcraft needs a basic land, Lion's Eye
  # Diamond needs Underworld Breach, Gemstone Caverns needs to be in the opening hand
  # of a player who is not going first).
  #
  # The multiplier answers "given that I have this card, how likely is it to work?",
  # so an ordinary card is 1.0. It is declared in the card's tag file:
  #
  #   narrow:
  #     needs:                      # alternatives; any one makes the card work
  #       - match: basic_land       # selector, same syntax as in rules.yml
  #         strength: 1.0           # how fully this alternative turns the card on
  #     conditions: [in_opening_hand, not_first_player]
  #     chance: 1.0                 # extra fixed factor, for anything the model can't express
  #     floor: 0.0                  # value the card keeps when nothing lines up
  #     note: why
  #
  # Model: every other card of the library is seen with probability
  # q = (cards_seen - 1) / (library - 1); commanders are always available. Each card
  # that satisfies a need counts with the need's strength, each card that can tutor
  # for one (rules marked `finder: true`) with strength x finder_weight.
  #
  #   access     = 1 - product over those cards of (1 - strength x q)
  #   multiplier = floor + (1 - floor) x chance x conditions x access
  class Narrow
    CONDITIONS = %w[in_opening_hand not_first_player].freeze
    KEYS = %w[needs conditions chance floor note].freeze

    Need = Struct.new(:selector, :strength)
    Spec = Struct.new(:needs, :conditions, :chance, :floor, :note)
    Result = Struct.new(:card, :multiplier, :access_probability, :chance, :floor, :access, :spec)

    # Parses the `narrow:` block of a tag file. Raises Synergy::Error on bad input.
    def self.parse(raw)
      raise Error, "narrow must be a mapping" unless raw.is_a?(Hash)

      unknown = raw.keys - KEYS
      raise Error, "narrow: unknown key(s) #{unknown.join(', ')}" unless unknown.empty?

      needs = Array(raw["needs"]).map do |n|
        raise Error, "narrow.needs entries need a 'match' selector" unless n.is_a?(Hash) && n["match"]

        Need.new(Selector.from_yaml(n["match"]), unit(n.fetch("strength", 1.0), "strength"))
      end
      conditions = Array(raw["conditions"]).map(&:to_s)
      bad = conditions - CONDITIONS
      raise Error, "narrow: unknown condition(s) #{bad.join(', ')} (known: #{CONDITIONS.join(', ')})" unless bad.empty?
      raise Error, "narrow needs at least one of: needs, conditions, chance" if needs.empty? && conditions.empty? && !raw.key?("chance")

      Spec.new(needs, conditions, unit(raw.fetch("chance", 1.0), "chance"), unit(raw.fetch("floor", 0.0), "floor"), raw["note"])
    end

    def self.unit(value, name)
      f = Float(value)
      raise Error, "narrow: #{name} must be between 0 and 1" unless (0.0..1.0).cover?(f)

      f
    rescue ArgumentError, TypeError
      raise Error, "narrow: #{name} must be a number"
    end

    attr_reader :engine, :settings

    def initialize(engine, settings)
      @engine = engine
      @settings = settings
      @results = {}
    end

    # Cards that sit in the library: not commanders, not sticker sheets.
    def library
      @library ||= engine.cards.reject { |c| c.commander? || c.sticker? }
    end

    # Result for a narrow-tagged card, nil for every other card.
    def result(card)
      return @results[card.name] if @results.key?(card.name)

      raw = engine.tag_store.narrow_for(card.name)
      @results[card.name] = raw && compute(card, Narrow.parse(raw))
    end

    def results = engine.cards.filter_map { |c| result(c) }

    def multiplier(card) = result(card)&.multiplier || 1.0

    # Weight of the pair a/b: both cards have to function. A card is not penalised
    # on the link to the very card that turns it on (or that finds it).
    def pair_weight(a, b)
      side_weight(a, b) * side_weight(b, a)
    end

    private

    def side_weight(card, other)
      r = result(card)
      return 1.0 unless r
      return 1.0 if r.access.key?(other.name)

      r.multiplier
    end

    def seen_probability(card)
      others = library.size - (card.commander? ? 0 : 1)
      seen = settings.cards_seen - (card.commander? ? 0 : 1)
      return 1.0 if others <= 0

      (seen.to_f / others).clamp(0.0, 1.0)
    end

    # { card name => strength } of everything that gives +card+ what it needs.
    def access_for(card, spec)
      access = Hash.new(0.0)
      spec.needs.each do |need|
        engine.cards.each do |enabler|
          next if enabler.equal?(card) || enabler.sticker?
          next unless need.selector.matches?(engine.roles(enabler))

          access[enabler.name] = [access[enabler.name], need.strength].max
          next if enabler.commander?

          engine.finders_of(enabler).each do |finder|
            next if finder.equal?(card)

            access[finder.name] = [access[finder.name], need.strength * settings.finder_weight].max
          end
        end
      end
      access
    end

    def condition_chance(spec)
      spec.conditions.reduce(1.0) do |acc, cond|
        acc * case cond
              # Given the card is among the cards seen, was it one of the opening ones?
              when "in_opening_hand" then (settings.opening_hand.to_f / settings.cards_seen).clamp(0.0, 1.0)
              when "not_first_player" then (settings.players - 1).to_f / settings.players
              end
      end
    end

    def compute(card, spec)
      access = access_for(card, spec)
      q = seen_probability(card)
      miss = access.reduce(1.0) do |acc, (name, strength)|
        acc * (1.0 - strength * (engine.card(name).commander? ? 1.0 : q))
      end
      access_probability = spec.needs.empty? ? 1.0 : 1.0 - miss
      chance = spec.chance * condition_chance(spec)
      multiplier = spec.floor + (1.0 - spec.floor) * chance * access_probability
      Result.new(card, multiplier, access_probability, chance, spec.floor, access.sort_by { |n, s| [-s, n] }.to_h, spec)
    end
  end
end
