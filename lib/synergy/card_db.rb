# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "zlib"
require "fileutils"

module Synergy
  # Card data from MTGJSON's AtomicCards file: download, cache, and pull out the
  # cards of one deck. The extracted cards are stored next to the deck list so
  # that nobody needs the full file just to rebuild a matrix.
  class CardDb
    URL = "https://mtgjson.com/api/v5/AtomicCards.json.gz"

    attr_reader :cache_dir

    def initialize(cache_dir: CACHE_DIR, url: URL, io: $stderr)
      @cache_dir = cache_dir
      @url = url
      @io = io
    end

    def json_path = File.join(cache_dir, "AtomicCards.json")

    def ensure_downloaded(force: false)
      return json_path if File.exist?(json_path) && !force

      FileUtils.mkdir_p(cache_dir)
      gz = "#{json_path}.gz"
      @io.puts "downloading #{@url} ..."
      download(@url, gz)
      @io.puts "decompressing ..."
      Zlib::GzipReader.open(gz) { |r| File.open(json_path, "wb") { |w| IO.copy_stream(r, w) } }
      File.delete(gz)
      json_path
    end

    def data
      @data ||= JSON.parse(File.read(ensure_downloaded, encoding: "UTF-8"))
    end

    def version = data["meta"]["version"]

    # Returns a Card for +name+ on +board+, or nil when MTGJSON has no such card.
    def lookup(name, board: "mainboard")
      faces = data["data"][name]
      return nil unless faces

      front = faces.first
      multi = faces.size > 1
      Card.new(
        name: name,
        type_line: multi ? faces.map { |f| f["type"] }.join(" // ") : front["type"],
        oracle_text: multi ? nil : front["text"],
        mana_cost: front["manaCost"], mana_value: front["manaValue"],
        colors: front["colors"], board: board, power: front["power"], toughness: front["toughness"],
        faces: multi ? faces.map { |f| { "name" => f["faceName"] || f["name"], "type_line" => f["type"], "oracle_text" => f["text"], "mana_cost" => f["manaCost"] } } : []
      )
    end

    # [cards, missing_names]
    def extract(deck)
      cards = []
      missing = []
      deck.entries.each do |e|
        card = lookup(e.name, board: e.board)
        card ? cards << card : missing << e.name
      end
      [cards, missing]
    end

    def self.write_cards(cards, path, source:)
      File.write(path, JSON.pretty_generate(cards.map { |c| c.to_h.merge("source" => source) }))
    end

    def self.read_cards(path)
      JSON.parse(File.read(path, encoding: "UTF-8")).map { |h| Card.from_h(h) }
    end

    private

    def download(url, dest, limit = 5)
      raise Error, "too many redirects" if limit.zero?

      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request_get(uri.request_uri) do |res|
          case res
          when Net::HTTPRedirection then return download(res["location"], dest, limit - 1)
          when Net::HTTPSuccess then File.open(dest, "wb") { |f| res.read_body { |chunk| f.write(chunk) } }
          else raise Error, "download failed: #{res.code} #{res.message}"
          end
        end
      end
    end
  end
end
