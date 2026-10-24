# frozen_string_literal: true

require "optparse"
require "fileutils"

module Synergy
  # bin/synergy entry point.
  class CLI
    USAGE = <<~TXT
      usage: bin/synergy <command> [options]

        fetch   DECK            pull the deck's cards from MTGJSON into DECK.cards.json
        lint    DECK            check every card has a tag file and every role exists
        build   DECK            write synergy_matrix.csv, synergy_pairs.csv, attributes.csv, report.txt
        score   DECK...         build each deck in memory and print its synergy score
        compare OLD NEW         compare two deck lists (built in memory), output folders or synergy_matrix.csv files
        roles   DECK CARD...    show the derived + curated roles of cards (what the rules see)
        stub    DECK            create empty tag files for untagged cards

      DECK is a deck list file, e.g. decks/krark-thrasios.txt (see README for formats).
      Options: --out DIR (build/compare), --force (fetch), --cache DIR (fetch)
    TXT

    def initialize(argv, out: $stdout, err: $stderr)
      @argv = argv.dup
      @out = out
      @err = err
      @opts = { force: false, cache: CACHE_DIR }
    end

    def run
      parser.parse!(@argv)
      command = @argv.shift
      case command
      when "fetch" then fetch(*@argv)
      when "lint" then lint(*@argv)
      when "build" then build(*@argv)
      when "compare" then compare(*@argv)
      when "score" then score(*@argv)
      when "roles" then roles(*@argv)
      when "stub" then stub(*@argv)
      when nil, "help", "-h", "--help" then @out.puts USAGE
      else
        @err.puts "unknown command #{command.inspect}\n\n#{USAGE}"
        return 1
      end
      0
    rescue Error, Errno::ENOENT, ArgumentError => e
      @err.puts "error: #{e.message}"
      1
    end

    private

    def parser
      OptionParser.new do |o|
        o.on("--out DIR") { |v| @opts[:out] = v }
        o.on("--force") { @opts[:force] = true }
        o.on("--cache DIR") { |v| @opts[:cache] = v }
      end
    end

    def cards_path(deck_path) = deck_path.sub(/\.\w+\z/, "") + ".cards.json"

    def fetch(deck_path = nil)
      raise ArgumentError, "fetch needs a deck list" unless deck_path

      deck = Deck.load(deck_path)
      db = CardDb.new(cache_dir: @opts[:cache], io: @err)
      db.ensure_downloaded(force: @opts[:force])
      cards, missing = db.extract(deck)
      raise Error, "not found in MTGJSON: #{missing.join(', ')}" unless missing.empty?

      CardDb.write_cards(cards, cards_path(deck_path), source: "mtgjson #{db.version}")
      @out.puts "#{cards.size} cards written to #{cards_path(deck_path)} (MTGJSON #{db.version})"
    end

    # Card data comes from the deck's own DECK.cards.json first, then from every other
    # *.cards.json next to it and in the repo's decks/ folder, so a variant list that
    # reuses known cards needs no fetch.
    def card_pool(deck_path)
      own = File.expand_path(cards_path(deck_path))
      dirs = [File.dirname(File.expand_path(deck_path)), File.join(ROOT, "decks")].uniq
      others = dirs.flat_map { |d| Dir.glob(File.join(d, "*.cards.json")) }.sort.uniq - [own]
      ([own] + others).select { |f| File.exist?(f) }.each_with_object({}) do |file, pool|
        CardDb.read_cards(file).each { |c| pool[c.name] ||= c }
      end
    end

    def load(deck_path)
      raise ArgumentError, "command needs a deck list" unless deck_path

      deck = Deck.load(deck_path)
      pool = card_pool(deck_path)
      missing = deck.names - pool.keys
      raise Error, "no card data for: #{missing.join(', ')}\nrun: bin/synergy fetch #{deck_path}" unless missing.empty?

      cards = deck.entries.map { |e| pool[e.name].tap { |c| c.instance_variable_set(:@board, e.board) } }
      [deck, cards, TagStore.new, Rule.load]
    end

    def lint(deck_path = nil)
      _deck, cards, tags, rules = load(deck_path)
      errors, warnings = tags.lint(cards, rules: rules)
      warnings.each { |w| @out.puts "warning: #{w}" }
      errors.each { |e| @out.puts "error: #{e}" }
      @out.puts(errors.empty? ? "lint ok: #{cards.size} cards tagged, #{rules.size} rules" : "#{errors.size} error(s)")
      raise Error, "lint failed" unless errors.empty?
    end

    def build(deck_path = nil)
      deck, cards, tags, rules = load(deck_path)
      errors, = tags.lint(cards, rules: rules)
      raise Error, "lint failed, run: bin/synergy lint #{deck_path}" unless errors.empty?

      out = @opts[:out] || File.join(ROOT, "output", deck.name)
      FileUtils.mkdir_p(out)
      engine = Engine.new(cards: cards, tag_store: tags, rules: rules)
      Matrix.write_matrix(engine, File.join(out, "synergy_matrix.csv"))
      Matrix.write_pairs(engine, File.join(out, "synergy_pairs.csv"))
      Attributes.load.write(engine, File.join(out, "attributes.csv"))
      File.write(File.join(out, "report.txt"), engine.report + "\n")
      @out.puts engine.report
      @out.puts "written to #{out}/"
    end

    def engine_for(deck_path)
      deck, cards, tags, rules = load(deck_path)
      errors, = tags.lint(cards, rules: rules)
      raise Error, "lint failed for #{deck_path}, run: bin/synergy lint #{deck_path}" unless errors.empty?

      [deck, Engine.new(cards: cards, tag_store: tags, rules: rules)]
    end

    # A deck list is built in memory; a folder or CSV is read as a saved matrix.
    def side_for(path)
      if File.directory?(path)
        Comparison::Side.from_csv(File.join(path, "synergy_matrix.csv"))
      elsif path.end_with?(".csv")
        Comparison::Side.from_csv(path)
      else
        deck, engine = engine_for(path)
        Comparison::Side.from_engine(engine, label: deck.name)
      end
    end

    def score(*deck_paths)
      raise ArgumentError, "score needs at least one deck list" if deck_paths.empty?

      sides = deck_paths.map { |p| side_for(p) }
      width = sides.map { |s| s.label.to_s.size }.max
      @out.puts format("%-#{width}s  %5s  %5s  %s", "deck", "cards", "score", "avg/card")
      sides.each { |s| @out.puts format("%-#{width}s  %5d  %5d  %.1f", s.label, s.names.size, s.score, s.average) }
    end

    def compare(old_path = nil, new_path = nil)
      raise ArgumentError, "compare needs two deck lists, folders or matrices" unless old_path && new_path

      cmp = Comparison.new(side_for(old_path), side_for(new_path))
      @out.puts cmp.report
      return unless @opts[:out]

      cmp.write_csv(@opts[:out])
      @out.puts "written to #{@opts[:out]}"
    end

    def roles(deck_path = nil, *names)
      _deck, cards, tags, rules = load(deck_path)
      engine = Engine.new(cards: cards, tag_store: tags, rules: rules)
      names = cards.map(&:name) if names.empty?
      names.each do |n|
        card = cards.find { |c| c.name.casecmp?(n) } or raise Error, "#{n.inspect} is not in the deck"
        @out.puts "#{card.name}  (#{card.type_line}, #{card.mana_cost})"
        @out.puts "  derived: #{card.derived_roles.sort.join(', ')}"
        @out.puts "  curated: #{tags.roles_for(card.name).sort.join(', ')}"
        @out.puts "  synergies: #{engine.degree(card)}"
      end
    end

    def stub(deck_path = nil)
      _deck, cards, tags, = load(deck_path)
      created = cards.reject { |c| tags.tagged?(c.name) }.map { |c| tags.write_stub(c) }
      @out.puts(created.empty? ? "all cards already have tag files" : "created:\n  #{created.join("\n  ")}")
    end
  end
end
