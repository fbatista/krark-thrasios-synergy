# frozen_string_literal: true

require "tmpdir"

RSpec.describe Synergy::TagStore do
  let(:root) { Dir.mktmpdir }
  let(:dir) { File.join(root, "tags").tap { |d| FileUtils.mkdir_p(d) } }
  let(:roles_path) { File.join(root, "roles.yml") }
  after { FileUtils.rm_rf(root) }

  let(:card) { Synergy::Card.new(name: "Sol Ring", type_line: "Artifact", oracle_text: "", mana_cost: "{1}", mana_value: 1, colors: [], board: "mainboard") }

  before { File.write(roles_path, { "fast_mana" => "cheap rock" }.to_yaml) }

  it "reports missing tag files, unknown roles and misplaced derived roles" do
    File.write(File.join(dir, "sol-ring.yml"), { "name" => "Sol Ring", "roles" => %w[fast_mana bogus artifact] }.to_yaml)
    other = Synergy::Card.new(name: "Mana Vault", type_line: "Artifact", oracle_text: "", mana_cost: "{1}", mana_value: 1, colors: [], board: "mainboard")
    errors, = described_class.new(tags_dir: dir, roles_path: roles_path).lint([card, other])
    expect(errors).to include(a_string_matching(/no tag file for "Mana Vault"/), a_string_matching(/unknown role "bogus"/), a_string_matching(/"artifact" is a derived role/))
  end

  it "passes a clean store and warns about tags outside the deck" do
    File.write(File.join(dir, "sol-ring.yml"), { "name" => "Sol Ring", "roles" => %w[fast_mana] }.to_yaml)
    File.write(File.join(dir, "mana-vault.yml"), { "name" => "Mana Vault", "roles" => [] }.to_yaml)
    errors, warnings = described_class.new(tags_dir: dir, roles_path: roles_path).lint([card])
    expect(errors).to be_empty
    expect(warnings).to include("Mana Vault is tagged but not in this deck")
  end

  it "writes stubs for untagged cards" do
    store = described_class.new(tags_dir: dir, roles_path: roles_path)
    path = store.write_stub(card)
    expect(YAML.safe_load_file(path)).to include("name" => "Sol Ring", "roles" => [])
  end
end
