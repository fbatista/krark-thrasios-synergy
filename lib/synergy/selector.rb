# frozen_string_literal: true

module Synergy
  # Matches a card's role set. In YAML a selector is a role name, a list of
  # roles (all required), or a hash with any of: all, any, none.
  class Selector
    attr_reader :all, :any, :none

    def initialize(all: [], any: [], none: [])
      @all = Array(all).map(&:to_s)
      @any = Array(any).map(&:to_s)
      @none = Array(none).map(&:to_s)
      raise Error, "empty selector" if @all.empty? && @any.empty?
    end

    def self.from_yaml(value)
      case value
      when String, Array then new(all: value)
      when Hash then new(all: value["all"], any: value["any"], none: value["none"])
      else raise Error, "bad selector: #{value.inspect}"
      end
    end

    def matches?(roles)
      all.all? { |r| roles.include?(r) } &&
        (any.empty? || any.any? { |r| roles.include?(r) }) &&
        none.none? { |r| roles.include?(r) }
    end

    def roles = all + any + none

    def to_s
      parts = []
      parts << all.join(" & ") unless all.empty?
      parts << "(#{any.join(' | ')})" unless any.empty?
      parts << "!#{none.join(' !')}" unless none.empty?
      parts.join(" ")
    end
  end
end
