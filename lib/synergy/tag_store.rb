# frozen_string_literal: true

require "yaml"

module Synergy
  # Curated roles: one YAML file per card in data/tags, plus the role registry
  # in data/roles.yml that documents every role a tag file or rule may use.
  class TagStore
    Tag = Struct.new(:name, :roles, :notes, :path)

    attr_reader :tags_dir, :roles_path

    def initialize(tags_dir: TAGS_DIR, roles_path: File.join(DATA_DIR, "roles.yml"))
      @tags_dir = tags_dir
      @roles_path = roles_path
    end

    # name => Tag
    def tags
      @tags ||= Dir.glob(File.join(tags_dir, "*.yml")).sort.each_with_object({}) do |path, h|
        y = YAML.safe_load_file(path) || {}
        raise Error, "#{path}: missing 'name'" unless y["name"]

        h[y["name"]] = Tag.new(y["name"], Array(y["roles"]).map(&:to_s), y["notes"], path)
      end
    end

    # role name => { "description" => ..., "derived" => bool }
    def registry
      @registry ||= (YAML.safe_load_file(roles_path) || {}).transform_values do |v|
        v.is_a?(Hash) ? v : { "description" => v.to_s }
      end
    end

    def role?(name) = registry.key?(name) || Card::DERIVED_ROLE_NAMES.include?(name)

    def roles_for(card_name) = tags[card_name]&.roles || []
    def tagged?(card_name) = tags.key?(card_name)

    # Problems a contributor should fix before building. Returns [errors, warnings].
    def lint(cards, rules: [])
      errors = []
      warnings = []
      names = cards.map(&:name)
      names.each do |n|
        errors << "no tag file for #{n.inspect} (expected #{File.join(tags_dir, "#{Card.slug(n)}.yml")})" unless tagged?(n)
      end
      tags.each_value do |tag|
        tag.roles.each { |r| errors << "#{File.basename(tag.path)}: unknown role #{r.inspect}" unless role?(r) }
        tag.roles.each { |r| errors << "#{File.basename(tag.path)}: #{r.inspect} is a derived role, remove it" if Card::DERIVED_ROLE_NAMES.include?(r) }
        expected = "#{Card.slug(tag.name)}.yml"
        warnings << "#{File.basename(tag.path)} should be named #{expected}" if File.basename(tag.path) != expected
        warnings << "#{tag.name} is tagged but not in this deck" unless names.include?(tag.name)
      end
      rules.each do |rule|
        rule.roles.each { |r| errors << "rule #{rule.reason.inspect}: unknown role #{r.inspect}" unless role?(r) }
      end
      used = (tags.values.flat_map(&:roles) + rules.flat_map(&:roles)).uniq
      registry.each do |r, info|
        next if info["derived"] || used.include?(r)

        warnings << "role #{r.inspect} is in roles.yml but never used"
      end
      [errors, warnings]
    end

    def write_stub(card)
      path = File.join(tags_dir, "#{card.slug}.yml")
      return path if File.exist?(path)

      File.write(path, { "name" => card.name, "roles" => [], "notes" => "TODO: review #{card.type_line}" }.to_yaml)
      path
    end
  end
end
