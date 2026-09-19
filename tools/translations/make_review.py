import json, sys
src, out = sys.argv[1], sys.argv[2]
d = json.load(open(src, encoding='utf-8'))

ORDER = [
    ('tag_normal', 'Tag', 'Personality: behaves the way its species normally does.'),
    ('tag_curious', 'Tag', 'Personality: stops and looks at the player as they approach.'),
    ('tag_timid', 'Tag', 'Personality: shy, runs away and hides.'),
    ('tag_aloof', 'Tag', 'Personality: ignores the player almost completely.'),
    ('tag_grumpy', 'Tag', 'Personality: postures and grumbles; only attacks if the player looks like easy prey.'),
    ('tag_hostile', 'Tag', 'Personality: attacks the player on sight.'),
    ('tag_feral', 'Tag', 'Personality: attacks anything on sight, pure chaos. Must NOT be the word for "wild": every tagged Pal is already a wild Pal.'),
    ('tag_friendly', 'Tag', 'Replaces the personality once the Pal has 20% trust: it has forgiven the player and likes them.'),
    ('tag_bonding', 'Tag', 'Replaces it at 50% trust: the Pal is attached to the player and follows them around.'),
    ('tag_scarred', 'Tag', 'A Pal the player betrayed (hit it while it trusted them). An EMOTIONAL wound, not a physical one: the player should feel bad.'),
    ('tag_abandoned', 'Tag', 'A Pal the player left behind (walked too far away from it). It gave up on them.'),
    ('tag_wary', 'Tag', 'Rare fallback for a Pal that lost its trust for an unrecorded reason: distrustful, on guard.'),
    ('a_pal', 'Name', 'Used in place of {name} when the Pal\'s name cannot be read. Means "a Pal" (some Pal).'),
    ('following', 'Message', 'The Pal reached 50% trust: it has taken a liking to the player and now follows them around.'),
    ('joined', 'Message', 'The Pal reached 100% trust and joins the player\'s team on its own, without a sphere.'),
    ('joined_unnamed', 'Message', 'Same as "joined", when the name cannot be read.'),
    ('betrayed', 'Message', 'The player hit a bonded Pal twice: it lost all trust and will never bond with them again.'),
    ('fell', 'Message', 'A bonded Pal died fighting at the player\'s side.'),
    ('abandoned', 'Message', 'The player went too far away and left a bonded Pal behind; it gave up on them.'),
    ('shaken', 'Message', 'The player hit a bonded Pal once: it flinched away and its trust is damaged (a warning, not the end).'),
    ('tags_on', 'Toggle', 'The player pressed F9: the personality tags are now shown.'),
    ('tags_off', 'Toggle', 'The player pressed F9: the personality tags are now hidden.'),
    ('passive_on', 'Toggle', 'The player pressed F10: following Pals gain trust slowly over time again.'),
    ('passive_off', 'Toggle', 'The player pressed F10: following Pals stop gaining trust over time, but keep what they have.'),
]
assert sorted(k for k, _, _ in ORDER) == sorted(d.keys()), 'string list out of date'

LANGS = [
    ('es', 'Spanish (neutral, for Spain AND Latin America)'),
    ('pt', 'Portuguese (Brazil)'),
    ('fr', 'French'),
    ('it', 'Italian'),
    ('de', 'German'),
    ('pl', 'Polish'),
    ('ru', 'Russian'),
    ('tr', 'Turkish'),
    ('vi', 'Vietnamese'),
    ('th', 'Thai'),
    ('id', 'Indonesian'),
    ('ja', 'Japanese'),
    ('ko', 'Korean'),
    ('zh-hans', 'Chinese (Simplified)'),
    ('zh-hant', 'Chinese (Traditional)'),
]


def cell(s):
    return s.replace('|', '\\|')


L = []
w = L.append
w('# PalBonds — translations for review')
w('')
w('Every piece of text the PalBonds mod shows on screen, in English and in the 15 other languages it ships')
w('with. Generated directly from the mod\'s `Locale.lua`, so this is exactly what players see.')
w('')
w('**How to use this file:** each language has its own section below. Give a reviewer the "Context" and')
w('"Rules" sections plus their language\'s section. Corrections are easiest to apply if they are sent back by')
w('**ID** (for example: `es / tag_grumpy / feminine: ...`).')
w('')
w('## Context')
w('')
w('PalBonds is a mod for Palworld. Instead of catching wild Pals (creatures) with a sphere, the player earns')
w('their trust by petting, feeding and playing with them. Every wild Pal gets a random **personality**,')
w('shown as a short **tag** under its health bar. As trust grows, the tag changes to show the Pal forgiving the')
w('player (20%), then following them (50%); at 100% the Pal joins the player\'s team on its own. Hurting a Pal')
w('that trusts you, or leaving it behind, ends the bond. Short **messages** pop up on screen for these events,')
w('and two keys (F9, F10) show a short on/off message.')
w('')
w('The tone is warm and a little playful, like the mod\'s store page. It addresses the player informally')
w('("you"), matching the store descriptions in each language.')
w('')
w('## Rules for reviewers')
w('')
w('- **`{name}`** is replaced by the Pal\'s name (for example "Lamball"), already in the game\'s language. It')
w('  must stay exactly as `{name}`, but it can be moved anywhere in the sentence if the language needs it.')
w('  In Korean, the particle after a name is written as 이(가) / 은(는) because the name is not known in')
w('  advance; a reviewer may prefer a different convention.')
w('- **Tags must be short**: ideally one word, two at most. They sit in a narrow line under the health bar.')
w('- **Masculine / feminine**: in Spanish, Portuguese, French, Italian, Polish and Russian, some entries have')
w('  two forms. The game knows each Pal\'s gender and picks the matching one. The masculine form is also used')
w('  when the gender is unknown, so it should work as the neutral form. Entries shown with one form are the')
w('  same for both genders; if a reviewer thinks one of those also needs two forms, say so.')
w('- **Spanish** is a single neutral set used for both Spain and Latin America.')
w('- **"Feral"** must not be translated as the word for "wild" (salvaje, wild, dziki, vahşi…), because every')
w('  Pal that gets a tag is already a wild Pal.')
w('- Do not use the `|` character: the game\'s font draws it as a quote mark.')
w('- "Pal" is the game\'s own word for its creatures and stays as "Pal" (the game uses it in every language).')
w('')
w('## The English text, with what each one means')
w('')
w('| ID | Kind | English | What it is |')
w('|---|---|---|---|')
for k, kind, meaning in ORDER:
    w('| `' + k + '` | ' + kind + ' | ' + cell(d[k]['en']) + ' | ' + cell(meaning) + ' |')
w('')

for code, name in LANGS:
    gendered = any(isinstance(d[k].get(code), dict) for k, _, _ in ORDER)
    w('## ' + name + ' (`' + code + '`)')
    w('')
    if gendered:
        w('| ID | English | Translation (masculine / neutral) | Feminine |')
        w('|---|---|---|---|')
    else:
        w('| ID | English | Translation |')
        w('|---|---|---|')
    for k, _, _ in ORDER:
        v = d[k][code]
        if gendered:
            if isinstance(v, dict):
                w('| `' + k + '` | ' + cell(d[k]['en']) + ' | ' + cell(v['m']) + ' | ' + cell(v['f']) + ' |')
            else:
                w('| `' + k + '` | ' + cell(d[k]['en']) + ' | ' + cell(v) + ' | (same) |')
        else:
            w('| `' + k + '` | ' + cell(d[k]['en']) + ' | ' + cell(v) + ' |')
    w('')

open(out, 'w', encoding='utf-8', newline='\n').write('\n'.join(L))
print('wrote', out, len(L), 'lines')
