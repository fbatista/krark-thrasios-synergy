# frozen_string_literal: true

Encoding.default_external = Encoding::UTF_8

module Synergy
  ROOT = File.expand_path("..", __dir__)
  DATA_DIR = File.join(ROOT, "data")
  TAGS_DIR = File.join(DATA_DIR, "tags")
  CACHE_DIR = File.join(ROOT, "tmp")

  class Error < StandardError; end
end

require_relative "synergy/card"
require_relative "synergy/deck"
require_relative "synergy/card_db"
require_relative "synergy/tag_store"
require_relative "synergy/selector"
require_relative "synergy/rule"
require_relative "synergy/engine"
require_relative "synergy/matrix"
require_relative "synergy/attributes"
require_relative "synergy/comparison"
require_relative "synergy/cli"
