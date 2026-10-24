# frozen_string_literal: true

module Synergy
  # A deck list. Accepts three line formats, mixed freely:
  #   c|1|Krark, the Thumbless          pipe format: c = commander, m = mainboard
  #   1 Krark, the Thumbless (CMR) 500  Moxfield / Archidekt text export, set code and
  #                                     collector number optional, "*CMDR*" or
  #                                     "[Commander]" marks a commander
  #   Commander: / Mainboard: / Sideboard:   section headers (sideboard & maybeboard are skipped)
  class Deck
    Entry = Struct.new(:name, :quantity, :board)

    HEADERS = {
      /\A(commanders?|command zone)\z/i => "commanders",
      /\A(main ?board|main|deck)\z/i => "mainboard",
      /\A(side ?board|maybe ?board|considering|companion)\z/i => :skip
    }.freeze
    LINE = /\A(\d+)x?\s+(.+?)(?:\s+\([A-Za-z0-9]{2,6}\)(?:\s+[\w★-]+)?)?(?:\s+\*\w+\*)*(?:\s+\[[^\]]*\])?\z/

    attr_reader :entries, :name

    def initialize(entries, name: "deck")
      @entries = entries
      @name = name
    end

    def self.load(path)
      parse(File.read(path, encoding: "UTF-8"), name: File.basename(path, ".*"))
    end

    def self.parse(text, name: "deck")
      entries = []
      section = "mainboard"
      text.each_line do |raw|
        line = raw.strip.sub(/\s*#.*\z/, "")
        next if line.empty?

        if (header = HEADERS.find { |rx, _| line.sub(/:\z/, "").match?(rx) })
          section = header.last
          next
        end
        next if section == :skip

        if line.count("|") == 2 && line.match?(/\A[cm]\|\d+\|/)
          board, qty, card = line.split("|", 3)
          entries << Entry.new(card.strip, qty.to_i, board == "c" ? "commanders" : "mainboard")
        elsif (m = LINE.match(line))
          board = line.match?(/\*CMDR\*|\[Commander/i) ? "commanders" : section
          entries << Entry.new(m[2].strip, m[1].to_i, board)
        else
          raise Error, "cannot parse deck line: #{raw.strip.inspect}"
        end
      end
      new(entries, name: name)
    end

    def names = entries.map(&:name)
    def board_for(name) = entries.find { |e| e.name == name }&.board
    def size = entries.sum(&:quantity)
  end
end
