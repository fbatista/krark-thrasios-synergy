# Krark / Thrasios synergy matrix

A small Ruby tool that turns a Commander deck list into:

- `synergy_matrix.csv`: a card x card matrix, `1` where two cards have synergy, `0` otherwise, diagonal empty
- `synergy_pairs.csv`: every synergistic pair with the reason(s) it was linked
- `attributes.csv`: one row per card with attribute flags (anti_stack, anti_permanent, draw, mana, tutor, ...)

Card data (types, mana cost, rules text) comes from [MTGJSON](https://mtgjson.com). The deck list comes
from you, for example Moxfield's text export. The reference deck is
[Thumbless kitten plays with fish](https://moxfield.com/decks/I4JbQfOqskG3emXagxm6aA)
(Thrasios, Triton Hero / Krark, the Thumbless).

Only Ruby 3.2+ is required. No gems are needed to run it; `rspec` is only for the test suite.

## Quick start

```bash
bin/synergy build decks/krark-thrasios.txt                                   # -> output/krark-thrasios/
bin/synergy score decks/krark-thrasios-2026-09-30.txt decks/krark-thrasios.txt
bin/synergy compare decks/krark-thrasios-2026-09-30.txt decks/krark-thrasios.txt --out output/compare.csv
```

## Comparing two versions of a deck

`compare` builds both lists in memory and reports the **synergy score** of each (the number of
synergistic pairs, which is the sum of the matrix divided by two), the average per card, the cards
that went in and out with their synergy counts, and every kept card whose count changed:

```
krark-thrasios-2026-09-30 -> krark-thrasios
synergy score (pairs): 1135 -> 1147 (+12)
avg synergies per card: 22.7 -> 22.9

removed (synergies in old version):
   40  Narset's Reversal
   ...
added (synergies in new version):
   38  The Unbeatable Squirrel Girl
   ...
kept cards that changed:
  +4  Goblin Anarchomancer  (28 -> 32)
```

Either side can be a deck list, an output folder or a `synergy_matrix.csv`. `score` prints the same
numbers for any number of lists. To try a swap, copy the list, edit it and compare; card data is looked
up in every `decks/*.cards.json`, so a swap that only uses cards from the reference deck or the
Considering list needs no fetch.

## Your own version of the deck

1. Export the deck as text from Moxfield (or write the list by hand) into `decks/my-deck.txt`. Supported line formats:

   ```
   Commander:
   1 Krark, the Thumbless (CMR) 500          # Moxfield / Archidekt export, set code optional
   Mainboard:
   1 Sol Ring
   c|1|Thrasios, Triton Hero                  # or the pipe format: c = commander, m = mainboard
   ```

   Section headers (`Commander`, `Mainboard`, `Sideboard`, `Maybeboard`) are recognised; sideboard and
   maybeboard lines are skipped. `*CMDR*` or `[Commander]` after a name also marks a commander.

2. Fetch the card data, unless every card is already in a `decks/*.cards.json`. This downloads MTGJSON's
   AtomicCards (about 50 MB, cached in `tmp/`) and writes `decks/my-deck.cards.json` with just your
   cards, so the download happens once:

   ```bash
   bin/synergy fetch decks/my-deck.txt
   ```

3. Lint. Every card needs a tag file in `data/tags/`. Cards already in the reference deck are covered;
   the lint lists the ones that are not:

   ```bash
   bin/synergy lint decks/my-deck.txt
   bin/synergy stub decks/my-deck.txt     # creates empty tag files for the missing cards
   ```

4. Tag the new cards (see below), then build:

   ```bash
   bin/synergy build decks/my-deck.txt
   ```

## How synergy is decided

The engine knows nothing about specific cards. Each card has **roles**, and `data/rules.yml` says which
role pairs count as synergy:

```yaml
- reason: copies instants/sorceries
  a: copies_spells
  b: instant_sorcery
- reason: finds a creature
  a: finds_creature
  b: { all: creature, none: commander }
```

Every card matching `a` is linked to every card matching `b`. The matrix is symmetric. A selector is a
role, a list of roles (all required), or a hash with `all` / `any` / `none`.

Roles come from two places:

- **Derived roles** are computed from the card data: `land`, `creature`, `instant_sorcery`, `legendary`,
  `wizard`, `forest_land`, `fetchland`, `fetches_island`, `mv_le_1`, `generic_in_cost`, `green`,
  `power_le_2`, ... A new card gets these for free. The full list is at the bottom of `data/roles.yml`.
  Type-based roles use the front face of a double-faced card, since that is what sits in your library.
- **Curated roles** are judgment calls written by a human in `data/tags/<card>.yml`:

  ```yaml
  name: Dualcaster Mage
  roles:
  - copies_spells
  - etb_creature
  - etb_spell_copier
  - wizard_shaman_trigger
  ```

Every role is documented in `data/roles.yml`; `bin/synergy lint` rejects unknown roles and derived roles
placed in tag files. To see what the rules see for a card:

```bash
bin/synergy roles decks/krark-thrasios.txt "Shang-Chi, Master of Kung Fu"
```

### Tagging a new card

1. Read the card's rules text and skim `data/roles.yml`.
2. Add the roles that apply to `data/tags/<slug>.yml`. If the card does something no role describes,
   add the role to `roles.yml` and a rule to `rules.yml` that uses it. Prefer roles that describe a
   mechanic ("creates Treasure tokens for you") over roles that name a card.
3. `bin/synergy build` and read the card's rows in `synergy_pairs.csv`. If a link is wrong, the reason
   column tells you which rule and therefore which role to fix.

Cells are binary, so a game-winning combo and a mild convenience both read as `1`. The pairs file is
where the nuance lives.

## Attribute columns

Defined in `data/attributes.yml`. Each column is a regex on the rules text, a regex on the mana cost,
and/or a list of roles.

| Column | Meaning |
|---|---|
| `anti_stack` | counters or exiles target spell, or changes targets / returns a spell |
| `anti_permanent` | targeted removal of a creature, land, artifact, enchantment, battle or planeswalker (destroy, bounce, tuck, damage to any target). Untap effects don't count. |
| `draw` | draws cards, including conditional draw and looting; impulse "exile and play" does not count |
| `mana` | adds mana or creates Treasures for you (An Offer You Can't Refuse counts: aimed at your own spell or a copy it makes you two Treasures) |
| `tutor` | searches your library |
| `recursion` | uses cards from a graveyard |
| `untap` | untaps other permanents |
| `copy` | copies spells or permanents |
| `storm` | has storm |
| `free_cast` | castable for {0}: zero cost, phyrexian mana, or a free alternative cost |
| `trigger_doubler` | makes triggered abilities trigger an additional time |
| `mana_sink` | repeatable activated ability with a generic mana cost |
| `land`, `creature`, `instant_sorcery`, `legendary` | type flags |

## Repository layout

```
bin/synergy              CLI: fetch | lint | build | score | compare | roles | stub
lib/synergy/             engine (card, deck, card_db, tag_store, selector, rule, engine, matrix, attributes, comparison, cli)
data/roles.yml           role registry (documentation + lint)
data/rules.yml           the synergy rules
data/attributes.yml      attribute columns
data/tags/*.yml          one file per card: curated roles
decks/*.txt              deck lists; decks/*.cards.json is the MTGJSON data for each (committed, so no download needed)
                         krark-thrasios-considering.txt is the deck's Moxfield "Considering" list: tagged, not a deck
output/<deck>/           generated CSVs and report.txt
spec/                    rspec suite; spec/fixtures/expected holds the reviewed matrices (regression test)
```

## Development

```bash
rspec                                   # unit tests + regression against the reviewed matrices
bin/synergy lint decks/krark-thrasios.txt
```

The regression spec rebuilds the two reference deck versions and compares them to
`spec/fixtures/expected/`. When you change a rule or tag on purpose, rebuild, review the diff of
`synergy_pairs.csv`, and copy the new `synergy_matrix.csv` / `attributes.csv` into the fixtures folder.

## Reference deck history

| Version | Deck list | Pairs |
|---|---|---|
| 2026-09-30 | `decks/krark-thrasios-2026-09-30.txt` | 1135 |
| 2026-10-10 (current) | `decks/krark-thrasios.txt` | 1147 |

Change between them: out Narset's Reversal, Ragavan, Tinder Wall, Wizard's Staff; in Pia Aether Ascetic,
Shang-Chi, The Unbeatable Squirrel Girl, Vibrance. `bin/synergy compare` shows the per-card effect.

All 55 cards of the deck's Considering list are tagged as well (`decks/krark-thrasios-considering.txt`),
so swapping any of them in is a two-line edit and a `compare`.
