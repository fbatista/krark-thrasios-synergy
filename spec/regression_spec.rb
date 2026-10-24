# frozen_string_literal: true

require "tmpdir"

# The shipped data must reproduce the reviewed matrices for the Krark/Thrasios deck.
# When you change a rule or a tag on purpose, rebuild and copy the new output into
# spec/fixtures/expected/<deck>/ (the diff of synergy_pairs.csv is your review).
RSpec.describe "regression against the reviewed outputs" do
  %w[krark-thrasios krark-thrasios-2026-09-30].each do |deck_name|
    context deck_name do
      let(:out) { Dir.mktmpdir }
      after { FileUtils.rm_rf(out) }

      before do
        deck_path = File.join(Synergy::ROOT, "decks", "#{deck_name}.txt")
        status = Synergy::CLI.new(["build", deck_path, "--out", out], out: StringIO.new, err: StringIO.new).run
        expect(status).to eq 0
      end

      it "reproduces synergy_matrix.csv" do
        expect(File.read(File.join(out, "synergy_matrix.csv"))).to eq File.read(File.join(FIXTURES, "expected", deck_name, "synergy_matrix.csv"))
      end

      it "reproduces attributes.csv" do
        expect(File.read(File.join(out, "attributes.csv"))).to eq File.read(File.join(FIXTURES, "expected", deck_name, "attributes.csv"))
      end
    end
  end
end
