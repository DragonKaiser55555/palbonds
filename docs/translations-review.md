# PalBonds — translations for review

Every piece of text the PalBonds mod shows on screen, in English and in the 15 other languages it ships
with. Generated directly from the mod's `Locale.lua`, so this is exactly what players see.

**How to use this file:** each language has its own section below. Give a reviewer the "Context" and
"Rules" sections plus their language's section. Corrections are easiest to apply if they are sent back by
**ID** (for example: `es / tag_grumpy / feminine: ...`).

## Context

PalBonds is a mod for Palworld. Instead of catching wild Pals (creatures) with a sphere, the player earns
their trust by petting, feeding and playing with them. Every wild Pal gets a random **personality**,
shown as a short **tag** under its health bar. As trust grows, the tag changes to show the Pal forgiving the
player (20%), then following them (50%); at 100% the Pal joins the player's team on its own. Hurting a Pal
that trusts you, or leaving it behind, ends the bond. Short **messages** pop up on screen for these events,
and two keys (F9, F10) show a short on/off message.

The tone is warm and a little playful, like the mod's store page. It addresses the player informally
("you"), matching the store descriptions in each language.

## Rules for reviewers

- **`{name}`** is replaced by the Pal's name (for example "Lamball"), already in the game's language. It
  must stay exactly as `{name}`, but it can be moved anywhere in the sentence if the language needs it.
  In Korean, the particle after a name is written as 이(가) / 은(는) because the name is not known in
  advance; a reviewer may prefer a different convention.
- **Tags must be short**: ideally one word, two at most. They sit in a narrow line under the health bar.
- **Masculine / feminine**: in Spanish, Portuguese, French, Italian, Polish and Russian, some entries have
  two forms. The game knows each Pal's gender and picks the matching one. The masculine form is also used
  when the gender is unknown, so it should work as the neutral form. Entries shown with one form are the
  same for both genders; if a reviewer thinks one of those also needs two forms, say so.
- **Spanish** is a single neutral set used for both Spain and Latin America.
- **"Feral"** must not be translated as the word for "wild" (salvaje, wild, dziki, vahşi…), because every
  Pal that gets a tag is already a wild Pal.
- Do not use the `|` character: the game's font draws it as a quote mark.
- "Pal" is the game's own word for its creatures and stays as "Pal" (the game uses it in every language).

## The English text, with what each one means

| ID | Kind | English | What it is |
|---|---|---|---|
| `tag_normal` | Tag | Normal | Personality: behaves the way its species normally does. |
| `tag_curious` | Tag | Curious | Personality: stops and looks at the player as they approach. |
| `tag_timid` | Tag | Timid | Personality: shy, runs away and hides. |
| `tag_aloof` | Tag | Aloof | Personality: ignores the player almost completely. |
| `tag_grumpy` | Tag | Grumpy | Personality: postures and grumbles; only attacks if the player looks like easy prey. |
| `tag_hostile` | Tag | Hostile | Personality: attacks the player on sight. |
| `tag_feral` | Tag | Feral | Personality: attacks anything on sight, pure chaos. Must NOT be the word for "wild": every tagged Pal is already a wild Pal. |
| `tag_friendly` | Tag | Friendly | Replaces the personality once the Pal has 20% trust: it has forgiven the player and likes them. |
| `tag_bonding` | Tag | Bonding | Replaces it at 50% trust: the Pal is attached to the player and follows them around. |
| `tag_scarred` | Tag | Scarred | A Pal the player betrayed (hit it while it trusted them). An EMOTIONAL wound, not a physical one: the player should feel bad. |
| `tag_abandoned` | Tag | Abandoned | A Pal the player left behind (walked too far away from it). It gave up on them. |
| `tag_wary` | Tag | Wary | Rare fallback for a Pal that lost its trust for an unrecorded reason: distrustful, on guard. |
| `tag_claimed` | Tag | Claimed | MULTIPLAYER ONLY, and new: shown to OTHER players over a wild Pal that is already bonding with somebody else, so they know it will not respond to them. That Pal's own player never sees this word. The sense is taken / already has someone, not reserved in a technical or legal sense. Must be SHORT: it sits under the health bar where the personality tag normally is. |
| `a_pal` | Name | A Pal | Used in place of {name} when the Pal's name cannot be read. Means "a Pal" (some Pal). |
| `following` | Message | {name} seems to like you and starts following you. | The Pal reached 50% trust: it has taken a liking to the player and now follows them around. |
| `joined` | Message | {name} has chosen to go with you. It trusts you completely. | The Pal reached 100% trust and joins the player's team on its own, without a sphere. |
| `joined_unnamed` | Message | A wild Pal has chosen to go with you. | Same as "joined", when the name cannot be read. |
| `betrayed` | Message | {name} no longer trusts you. It will not bond with you again. | The player hit a bonded Pal twice: it lost all trust and will never bond with them again. |
| `fell` | Message | {name} fell while fighting alongside you. | A bonded Pal died fighting at the player's side. |
| `abandoned` | Message | {name} was left behind and gave up on you. | The player went too far away and left a bonded Pal behind; it gave up on them. |
| `shaken` | Message | {name} flinched away from you. Its trust is shaken. | The player hit a bonded Pal once: it flinched away and its trust is damaged (a warning, not the end). |
| `tags_on` | Toggle | Personality tags: ON | The player pressed F9: the personality tags are now shown. |
| `tags_off` | Toggle | Personality tags: OFF | The player pressed F9: the personality tags are now hidden. |
| `passive_on` | Toggle | Passive bonding: ON - your Pals grow closer over time. | The player pressed F10: following Pals gain trust slowly over time again. |
| `passive_off` | Toggle | Passive bonding: OFF - your Pals keep the trust they have. | The player pressed F10: following Pals stop gaining trust over time, but keep what they have. |

## Spanish (neutral, for Spain AND Latin America) (`es`)

| ID | English | Translation (masculine / neutral) | Feminine |
|---|---|---|---|
| `tag_normal` | Normal | Normal | (same) |
| `tag_curious` | Curious | Curioso | Curiosa |
| `tag_timid` | Timid | Tímido | Tímida |
| `tag_aloof` | Aloof | Distante | (same) |
| `tag_grumpy` | Grumpy | Gruñón | Gruñona |
| `tag_hostile` | Hostile | Hostil | (same) |
| `tag_feral` | Feral | Feroz | (same) |
| `tag_friendly` | Friendly | Amistoso | Amistosa |
| `tag_bonding` | Bonding | Encariñado | Encariñada |
| `tag_scarred` | Scarred | Resentido | Resentida |
| `tag_abandoned` | Abandoned | Abandonado | Abandonada |
| `tag_wary` | Wary | Receloso | Recelosa |
| `tag_claimed` | Claimed | Ocupado | Ocupada |
| `a_pal` | A Pal | Un Pal | (same) |
| `following` | {name} seems to like you and starts following you. | {name} parece tenerte cariño y empieza a seguirte. | (same) |
| `joined` | {name} has chosen to go with you. It trusts you completely. | {name} decidió irse contigo. Confía plenamente en ti. | (same) |
| `joined_unnamed` | A wild Pal has chosen to go with you. | Un Pal salvaje decidió irse contigo. | (same) |
| `betrayed` | {name} no longer trusts you. It will not bond with you again. | {name} ya no confía en ti. No volverá a crear un vínculo contigo. | (same) |
| `fell` | {name} fell while fighting alongside you. | {name} cayó luchando a tu lado. | (same) |
| `abandoned` | {name} was left behind and gave up on you. | {name} se quedó atrás y se dio por vencido contigo. | {name} se quedó atrás y se dio por vencida contigo. |
| `shaken` | {name} flinched away from you. Its trust is shaken. | {name} se apartó de ti asustado. Su confianza en ti flaquea. | {name} se apartó de ti asustada. Su confianza en ti flaquea. |
| `tags_on` | Personality tags: ON | Etiquetas de personalidad: ACTIVADAS | (same) |
| `tags_off` | Personality tags: OFF | Etiquetas de personalidad: DESACTIVADAS | (same) |
| `passive_on` | Passive bonding: ON - your Pals grow closer over time. | Ganancia pasiva de amistad: ACTIVADA - tus Pals se encariñan contigo con el tiempo. | (same) |
| `passive_off` | Passive bonding: OFF - your Pals keep the trust they have. | Ganancia pasiva de amistad: DESACTIVADA - tus Pals conservan la confianza que tienen. | (same) |

## Portuguese (Brazil) (`pt`)

| ID | English | Translation (masculine / neutral) | Feminine |
|---|---|---|---|
| `tag_normal` | Normal | Normal | (same) |
| `tag_curious` | Curious | Curioso | Curiosa |
| `tag_timid` | Timid | Tímido | Tímida |
| `tag_aloof` | Aloof | Distante | (same) |
| `tag_grumpy` | Grumpy | Ranzinza | (same) |
| `tag_hostile` | Hostile | Hostil | (same) |
| `tag_feral` | Feral | Feroz | (same) |
| `tag_friendly` | Friendly | Amigável | (same) |
| `tag_bonding` | Bonding | Apegado | Apegada |
| `tag_scarred` | Scarred | Magoado | Magoada |
| `tag_abandoned` | Abandoned | Abandonado | Abandonada |
| `tag_wary` | Wary | Desconfiado | Desconfiada |
| `tag_claimed` | Claimed | Ocupado | Ocupada |
| `a_pal` | A Pal | Um Pal | (same) |
| `following` | {name} seems to like you and starts following you. | {name} parece gostar de você e começa a te seguir. | (same) |
| `joined` | {name} has chosen to go with you. It trusts you completely. | {name} escolheu seguir com você. Ele confia completamente em você. | {name} escolheu seguir com você. Ela confia completamente em você. |
| `joined_unnamed` | A wild Pal has chosen to go with you. | Um Pal selvagem escolheu seguir com você. | (same) |
| `betrayed` | {name} no longer trusts you. It will not bond with you again. | {name} não confia mais em você. Nunca mais vai criar laços com você. | (same) |
| `fell` | {name} fell while fighting alongside you. | {name} caiu lutando ao seu lado. | (same) |
| `abandoned` | {name} was left behind and gave up on you. | {name} foi deixado para trás e desistiu de você. | {name} foi deixada para trás e desistiu de você. |
| `shaken` | {name} flinched away from you. Its trust is shaken. | {name} se afastou assustado. A confiança dele foi abalada. | {name} se afastou assustada. A confiança dela foi abalada. |
| `tags_on` | Personality tags: ON | Etiquetas de personalidade: ATIVADAS | (same) |
| `tags_off` | Personality tags: OFF | Etiquetas de personalidade: DESATIVADAS | (same) |
| `passive_on` | Passive bonding: ON - your Pals grow closer over time. | Ganho passivo de amizade: ATIVADO - seus Pals se aproximam de você com o tempo. | (same) |
| `passive_off` | Passive bonding: OFF - your Pals keep the trust they have. | Ganho passivo de amizade: DESATIVADO - seus Pals mantêm a confiança que já têm. | (same) |

## French (`fr`)

| ID | English | Translation (masculine / neutral) | Feminine |
|---|---|---|---|
| `tag_normal` | Normal | Normal | Normale |
| `tag_curious` | Curious | Curieux | Curieuse |
| `tag_timid` | Timid | Timide | (same) |
| `tag_aloof` | Aloof | Distant | Distante |
| `tag_grumpy` | Grumpy | Grincheux | Grincheuse |
| `tag_hostile` | Hostile | Hostile | (same) |
| `tag_feral` | Feral | Féroce | (same) |
| `tag_friendly` | Friendly | Amical | Amicale |
| `tag_bonding` | Bonding | Attaché | Attachée |
| `tag_scarred` | Scarred | Trahi | Trahie |
| `tag_abandoned` | Abandoned | Abandonné | Abandonnée |
| `tag_wary` | Wary | Méfiant | Méfiante |
| `tag_claimed` | Claimed | Pris | Prise |
| `a_pal` | A Pal | Un Pal | (same) |
| `following` | {name} seems to like you and starts following you. | {name} semble t'apprécier et commence à te suivre. | (same) |
| `joined` | {name} has chosen to go with you. It trusts you completely. | {name} a choisi de partir avec toi. Il te fait entièrement confiance. | {name} a choisi de partir avec toi. Elle te fait entièrement confiance. |
| `joined_unnamed` | A wild Pal has chosen to go with you. | Un Pal sauvage a choisi de partir avec toi. | (same) |
| `betrayed` | {name} no longer trusts you. It will not bond with you again. | {name} ne te fait plus confiance. Il ne se liera plus jamais à toi. | {name} ne te fait plus confiance. Elle ne se liera plus jamais à toi. |
| `fell` | {name} fell while fighting alongside you. | {name} est tombé en combattant à tes côtés. | {name} est tombée en combattant à tes côtés. |
| `abandoned` | {name} was left behind and gave up on you. | {name} a été laissé en arrière et a renoncé à toi. | {name} a été laissée en arrière et a renoncé à toi. |
| `shaken` | {name} flinched away from you. Its trust is shaken. | {name} s'est écarté de toi, effrayé. Sa confiance est ébranlée. | {name} s'est écartée de toi, effrayée. Sa confiance est ébranlée. |
| `tags_on` | Personality tags: ON | Étiquettes de personnalité : ACTIVÉES | (same) |
| `tags_off` | Personality tags: OFF | Étiquettes de personnalité : DÉSACTIVÉES | (same) |
| `passive_on` | Passive bonding: ON - your Pals grow closer over time. | Gain passif d'amitié : ACTIVÉ - tes Pals se rapprochent de toi avec le temps. | (same) |
| `passive_off` | Passive bonding: OFF - your Pals keep the trust they have. | Gain passif d'amitié : DÉSACTIVÉ - tes Pals gardent la confiance qu'ils ont. | (same) |

## Italian (`it`)

| ID | English | Translation (masculine / neutral) | Feminine |
|---|---|---|---|
| `tag_normal` | Normal | Normale | (same) |
| `tag_curious` | Curious | Curioso | Curiosa |
| `tag_timid` | Timid | Timido | Timida |
| `tag_aloof` | Aloof | Distaccato | Distaccata |
| `tag_grumpy` | Grumpy | Scontroso | Scontrosa |
| `tag_hostile` | Hostile | Ostile | (same) |
| `tag_feral` | Feral | Feroce | (same) |
| `tag_friendly` | Friendly | Amichevole | (same) |
| `tag_bonding` | Bonding | Affezionato | Affezionata |
| `tag_scarred` | Scarred | Rancoroso | Rancorosa |
| `tag_abandoned` | Abandoned | Abbandonato | Abbandonata |
| `tag_wary` | Wary | Diffidente | (same) |
| `tag_claimed` | Claimed | Occupato | Occupata |
| `a_pal` | A Pal | Un Pal | (same) |
| `following` | {name} seems to like you and starts following you. | {name} sembra essersi affezionato a te e inizia a seguirti. | {name} sembra essersi affezionata a te e inizia a seguirti. |
| `joined` | {name} has chosen to go with you. It trusts you completely. | {name} ha scelto di venire con te. Si fida completamente di te. | (same) |
| `joined_unnamed` | A wild Pal has chosen to go with you. | Un Pal selvatico ha scelto di venire con te. | (same) |
| `betrayed` | {name} no longer trusts you. It will not bond with you again. | {name} non si fida più di te. Non si legherà mai più a te. | (same) |
| `fell` | {name} fell while fighting alongside you. | {name} è caduto combattendo al tuo fianco. | {name} è caduta combattendo al tuo fianco. |
| `abandoned` | {name} was left behind and gave up on you. | {name} è stato lasciato indietro e ha perso fiducia in te. | {name} è stata lasciata indietro e ha perso fiducia in te. |
| `shaken` | {name} flinched away from you. Its trust is shaken. | {name} si è ritratto, spaventato. La sua fiducia è stata scossa. | {name} si è ritratta, spaventata. La sua fiducia è stata scossa. |
| `tags_on` | Personality tags: ON | Etichette della personalità: ATTIVE | (same) |
| `tags_off` | Personality tags: OFF | Etichette della personalità: DISATTIVATE | (same) |
| `passive_on` | Passive bonding: ON - your Pals grow closer over time. | Aumento passivo dell'amicizia: ATTIVO - i tuoi Pals si affezionano a te col tempo. | (same) |
| `passive_off` | Passive bonding: OFF - your Pals keep the trust they have. | Aumento passivo dell'amicizia: DISATTIVATO - i tuoi Pals mantengono la fiducia che hanno. | (same) |

## German (`de`)

| ID | English | Translation |
|---|---|---|
| `tag_normal` | Normal | Normal |
| `tag_curious` | Curious | Neugierig |
| `tag_timid` | Timid | Scheu |
| `tag_aloof` | Aloof | Distanziert |
| `tag_grumpy` | Grumpy | Mürrisch |
| `tag_hostile` | Hostile | Feindselig |
| `tag_feral` | Feral | Rasend |
| `tag_friendly` | Friendly | Freundlich |
| `tag_bonding` | Bonding | Anhänglich |
| `tag_scarred` | Scarred | Verbittert |
| `tag_abandoned` | Abandoned | Verlassen |
| `tag_wary` | Wary | Misstrauisch |
| `tag_claimed` | Claimed | Vergeben |
| `a_pal` | A Pal | Ein Pal |
| `following` | {name} seems to like you and starts following you. | {name} scheint dich zu mögen und folgt dir jetzt. |
| `joined` | {name} has chosen to go with you. It trusts you completely. | {name} hat sich entschieden, mit dir zu gehen. Es vertraut dir vollkommen. |
| `joined_unnamed` | A wild Pal has chosen to go with you. | Ein wildes Pal hat sich entschieden, mit dir zu gehen. |
| `betrayed` | {name} no longer trusts you. It will not bond with you again. | {name} vertraut dir nicht mehr. Es wird sich nie wieder an dich binden. |
| `fell` | {name} fell while fighting alongside you. | {name} ist an deiner Seite im Kampf gefallen. |
| `abandoned` | {name} was left behind and gave up on you. | {name} wurde zurückgelassen und hat dich aufgegeben. |
| `shaken` | {name} flinched away from you. Its trust is shaken. | {name} ist vor dir zurückgeschreckt. Sein Vertrauen ist erschüttert. |
| `tags_on` | Personality tags: ON | Persönlichkeitstags: AN |
| `tags_off` | Personality tags: OFF | Persönlichkeitstags: AUS |
| `passive_on` | Passive bonding: ON - your Pals grow closer over time. | Passive Freundschaftszunahme: AN - deine Pals kommen dir mit der Zeit näher. |
| `passive_off` | Passive bonding: OFF - your Pals keep the trust they have. | Passive Freundschaftszunahme: AUS - deine Pals behalten ihr bisheriges Vertrauen. |

## Polish (`pl`)

| ID | English | Translation (masculine / neutral) | Feminine |
|---|---|---|---|
| `tag_normal` | Normal | Normalny | Normalna |
| `tag_curious` | Curious | Ciekawski | Ciekawska |
| `tag_timid` | Timid | Nieśmiały | Nieśmiała |
| `tag_aloof` | Aloof | Obojętny | Obojętna |
| `tag_grumpy` | Grumpy | Zrzędliwy | Zrzędliwa |
| `tag_hostile` | Hostile | Wrogi | Wroga |
| `tag_feral` | Feral | Wściekły | Wściekła |
| `tag_friendly` | Friendly | Przyjazny | Przyjazna |
| `tag_bonding` | Bonding | Przywiązany | Przywiązana |
| `tag_scarred` | Scarred | Urażony | Urażona |
| `tag_abandoned` | Abandoned | Porzucony | Porzucona |
| `tag_wary` | Wary | Nieufny | Nieufna |
| `tag_claimed` | Claimed | Zajęty | Zajęta |
| `a_pal` | A Pal | Pal | (same) |
| `following` | {name} seems to like you and starts following you. | {name} chyba cię polubił i zaczyna za tobą chodzić. | {name} chyba cię polubiła i zaczyna za tobą chodzić. |
| `joined` | {name} has chosen to go with you. It trusts you completely. | {name} postanowił pójść z tobą. Ufa ci całkowicie. | {name} postanowiła pójść z tobą. Ufa ci całkowicie. |
| `joined_unnamed` | A wild Pal has chosen to go with you. | Dziki Pal postanowił pójść z tobą. | (same) |
| `betrayed` | {name} no longer trusts you. It will not bond with you again. | {name} już ci nie ufa. Nigdy więcej się z tobą nie zwiąże. | (same) |
| `fell` | {name} fell while fighting alongside you. | {name} poległ, walcząc u twojego boku. | {name} poległa, walcząc u twojego boku. |
| `abandoned` | {name} was left behind and gave up on you. | {name} został w tyle i przestał na ciebie czekać. | {name} została w tyle i przestała na ciebie czekać. |
| `shaken` | {name} flinched away from you. Its trust is shaken. | {name} odskoczył od ciebie. Jego zaufanie zostało nadszarpnięte. | {name} odskoczyła od ciebie. Jej zaufanie zostało nadszarpnięte. |
| `tags_on` | Personality tags: ON | Etykiety osobowości: WŁĄCZONE | (same) |
| `tags_off` | Personality tags: OFF | Etykiety osobowości: WYŁĄCZONE | (same) |
| `passive_on` | Passive bonding: ON - your Pals grow closer over time. | Pasywne zdobywanie przyjaźni: WŁĄCZONE - twoje Pale z czasem się do ciebie zbliżają. | (same) |
| `passive_off` | Passive bonding: OFF - your Pals keep the trust they have. | Pasywne zdobywanie przyjaźni: WYŁĄCZONE - twoje Pale zachowują obecne zaufanie. | (same) |

## Russian (`ru`)

| ID | English | Translation (masculine / neutral) | Feminine |
|---|---|---|---|
| `tag_normal` | Normal | Обычный | Обычная |
| `tag_curious` | Curious | Любопытный | Любопытная |
| `tag_timid` | Timid | Робкий | Робкая |
| `tag_aloof` | Aloof | Отстранённый | Отстранённая |
| `tag_grumpy` | Grumpy | Ворчливый | Ворчливая |
| `tag_hostile` | Hostile | Враждебный | Враждебная |
| `tag_feral` | Feral | Свирепый | Свирепая |
| `tag_friendly` | Friendly | Дружелюбный | Дружелюбная |
| `tag_bonding` | Bonding | Привязанный | Привязанная |
| `tag_scarred` | Scarred | Обиженный | Обиженная |
| `tag_abandoned` | Abandoned | Брошенный | Брошенная |
| `tag_wary` | Wary | Настороженный | Настороженная |
| `tag_claimed` | Claimed | Занят | Занята |
| `a_pal` | A Pal | Pal | (same) |
| `following` | {name} seems to like you and starts following you. | {name}, похоже, привязался к тебе и теперь следует за тобой. | {name}, похоже, привязалась к тебе и теперь следует за тобой. |
| `joined` | {name} has chosen to go with you. It trusts you completely. | {name} решил пойти с тобой. Он полностью тебе доверяет. | {name} решила пойти с тобой. Она полностью тебе доверяет. |
| `joined_unnamed` | A wild Pal has chosen to go with you. | Дикий Pal решил пойти с тобой. | (same) |
| `betrayed` | {name} no longer trusts you. It will not bond with you again. | {name} больше тебе не доверяет. Он больше никогда к тебе не привяжется. | {name} больше тебе не доверяет. Она больше никогда к тебе не привяжется. |
| `fell` | {name} fell while fighting alongside you. | {name} пал в бою рядом с тобой. | {name} пала в бою рядом с тобой. |
| `abandoned` | {name} was left behind and gave up on you. | {name} остался позади и перестал тебя ждать. | {name} осталась позади и перестала тебя ждать. |
| `shaken` | {name} flinched away from you. Its trust is shaken. | {name} отшатнулся от тебя. Его доверие пошатнулось. | {name} отшатнулась от тебя. Её доверие пошатнулось. |
| `tags_on` | Personality tags: ON | Метки характера: ВКЛ | (same) |
| `tags_off` | Personality tags: OFF | Метки характера: ВЫКЛ | (same) |
| `passive_on` | Passive bonding: ON - your Pals grow closer over time. | Пассивное получение дружбы: ВКЛ - твои Pals со временем сближаются с тобой. | (same) |
| `passive_off` | Passive bonding: OFF - your Pals keep the trust they have. | Пассивное получение дружбы: ВЫКЛ - твои Pals сохраняют текущее доверие. | (same) |

## Turkish (`tr`)

| ID | English | Translation |
|---|---|---|
| `tag_normal` | Normal | Normal |
| `tag_curious` | Curious | Meraklı |
| `tag_timid` | Timid | Ürkek |
| `tag_aloof` | Aloof | Mesafeli |
| `tag_grumpy` | Grumpy | Huysuz |
| `tag_hostile` | Hostile | Düşmanca |
| `tag_feral` | Feral | Gözü dönmüş |
| `tag_friendly` | Friendly | Dostça |
| `tag_bonding` | Bonding | Bağlı |
| `tag_scarred` | Scarred | Kırgın |
| `tag_abandoned` | Abandoned | Terk edilmiş |
| `tag_wary` | Wary | Temkinli |
| `tag_claimed` | Claimed | Sahipli |
| `a_pal` | A Pal | Bir Pal |
| `following` | {name} seems to like you and starts following you. | {name} senden hoşlanmış gibi görünüyor ve seni takip etmeye başladı. |
| `joined` | {name} has chosen to go with you. It trusts you completely. | {name} seninle gelmeye karar verdi. Sana tamamen güveniyor. |
| `joined_unnamed` | A wild Pal has chosen to go with you. | Vahşi bir Pal seninle gelmeye karar verdi. |
| `betrayed` | {name} no longer trusts you. It will not bond with you again. | {name} artık sana güvenmiyor. Seninle bir daha asla bağ kurmayacak. |
| `fell` | {name} fell while fighting alongside you. | {name} senin yanında savaşırken düştü. |
| `abandoned` | {name} was left behind and gave up on you. | {name} geride kaldı ve senden vazgeçti. |
| `shaken` | {name} flinched away from you. Its trust is shaken. | {name} senden ürkerek uzaklaştı. Güveni sarsıldı. |
| `tags_on` | Personality tags: ON | Kişilik etiketleri: AÇIK |
| `tags_off` | Personality tags: OFF | Kişilik etiketleri: KAPALI |
| `passive_on` | Passive bonding: ON - your Pals grow closer over time. | Pasif dostluk kazanımı: AÇIK - Pal'ların zamanla sana daha çok yakınlaşır. |
| `passive_off` | Passive bonding: OFF - your Pals keep the trust they have. | Pasif dostluk kazanımı: KAPALI - Pal'ların mevcut güvenlerini korur. |

## Vietnamese (`vi`)

| ID | English | Translation |
|---|---|---|
| `tag_normal` | Normal | Bình thường |
| `tag_curious` | Curious | Tò mò |
| `tag_timid` | Timid | Nhút nhát |
| `tag_aloof` | Aloof | Thờ ơ |
| `tag_grumpy` | Grumpy | Cáu kỉnh |
| `tag_hostile` | Hostile | Thù địch |
| `tag_feral` | Feral | Hung dữ |
| `tag_friendly` | Friendly | Thân thiện |
| `tag_bonding` | Bonding | Gắn bó |
| `tag_scarred` | Scarred | Tổn thương |
| `tag_abandoned` | Abandoned | Bị bỏ rơi |
| `tag_wary` | Wary | Dè chừng |
| `tag_claimed` | Claimed | Đã có chủ |
| `a_pal` | A Pal | Một Pal |
| `following` | {name} seems to like you and starts following you. | {name} có vẻ quý bạn và bắt đầu đi theo bạn. |
| `joined` | {name} has chosen to go with you. It trusts you completely. | {name} đã chọn đi cùng bạn. Nó hoàn toàn tin tưởng bạn. |
| `joined_unnamed` | A wild Pal has chosen to go with you. | Một Pal hoang dã đã chọn đi cùng bạn. |
| `betrayed` | {name} no longer trusts you. It will not bond with you again. | {name} không còn tin tưởng bạn nữa. Nó sẽ không bao giờ gắn bó với bạn nữa. |
| `fell` | {name} fell while fighting alongside you. | {name} đã ngã xuống khi chiến đấu bên cạnh bạn. |
| `abandoned` | {name} was left behind and gave up on you. | {name} đã bị bỏ lại phía sau và từ bỏ bạn. |
| `shaken` | {name} flinched away from you. Its trust is shaken. | {name} sợ hãi lùi lại. Niềm tin của nó đã bị lung lay. |
| `tags_on` | Personality tags: ON | Nhãn tính cách: BẬT |
| `tags_off` | Personality tags: OFF | Nhãn tính cách: TẮT |
| `passive_on` | Passive bonding: ON - your Pals grow closer over time. | Tăng tình bạn thụ động: BẬT - các Pal của bạn sẽ thân thiết hơn theo thời gian. |
| `passive_off` | Passive bonding: OFF - your Pals keep the trust they have. | Tăng tình bạn thụ động: TẮT - các Pal của bạn giữ nguyên niềm tin hiện có. |

## Thai (`th`)

| ID | English | Translation |
|---|---|---|
| `tag_normal` | Normal | ปกติ |
| `tag_curious` | Curious | ขี้สงสัย |
| `tag_timid` | Timid | ขี้อาย |
| `tag_aloof` | Aloof | เมินเฉย |
| `tag_grumpy` | Grumpy | ขี้หงุดหงิด |
| `tag_hostile` | Hostile | ก้าวร้าว |
| `tag_feral` | Feral | ดุร้าย |
| `tag_friendly` | Friendly | เป็นมิตร |
| `tag_bonding` | Bonding | ผูกพัน |
| `tag_scarred` | Scarred | เจ็บใจ |
| `tag_abandoned` | Abandoned | ถูกทิ้ง |
| `tag_wary` | Wary | ระแวง |
| `tag_claimed` | Claimed | ถูกจอง |
| `a_pal` | A Pal | Pal ตัวหนึ่ง |
| `following` | {name} seems to like you and starts following you. | {name} ดูเหมือนจะชอบคุณ และเริ่มเดินตามคุณ |
| `joined` | {name} has chosen to go with you. It trusts you completely. | {name} เลือกที่จะไปกับคุณ มันไว้ใจคุณอย่างเต็มที่ |
| `joined_unnamed` | A wild Pal has chosen to go with you. | Pal ป่าตัวหนึ่งเลือกที่จะไปกับคุณ |
| `betrayed` | {name} no longer trusts you. It will not bond with you again. | {name} ไม่ไว้ใจคุณอีกต่อไป มันจะไม่ผูกพันกับคุณอีก |
| `fell` | {name} fell while fighting alongside you. | {name} ล้มลงขณะต่อสู้เคียงข้างคุณ |
| `abandoned` | {name} was left behind and gave up on you. | {name} ถูกทิ้งไว้ข้างหลังจึงยอมแพ้และจากคุณไป |
| `shaken` | {name} flinched away from you. Its trust is shaken. | {name} ผงะถอยหนีคุณ ความไว้ใจของมันสั่นคลอน |
| `tags_on` | Personality tags: ON | ป้ายบุคลิก: เปิด |
| `tags_off` | Personality tags: OFF | ป้ายบุคลิก: ปิด |
| `passive_on` | Passive bonding: ON - your Pals grow closer over time. | การเพิ่มค่ามิตรภาพแบบอัตโนมัติ: เปิด - Pal ของคุณจะสนิทกับคุณมากขึ้นเรื่อย ๆ |
| `passive_off` | Passive bonding: OFF - your Pals keep the trust they have. | การเพิ่มค่ามิตรภาพแบบอัตโนมัติ: ปิด - Pal ของคุณจะคงความไว้ใจที่มีอยู่ |

## Indonesian (`id`)

| ID | English | Translation |
|---|---|---|
| `tag_normal` | Normal | Normal |
| `tag_curious` | Curious | Penasaran |
| `tag_timid` | Timid | Pemalu |
| `tag_aloof` | Aloof | Cuek |
| `tag_grumpy` | Grumpy | Pemarah |
| `tag_hostile` | Hostile | Bermusuhan |
| `tag_feral` | Feral | Buas |
| `tag_friendly` | Friendly | Ramah |
| `tag_bonding` | Bonding | Terikat |
| `tag_scarred` | Scarred | Sakit hati |
| `tag_abandoned` | Abandoned | Ditinggalkan |
| `tag_wary` | Wary | Waspada |
| `tag_claimed` | Claimed | Sudah diklaim |
| `a_pal` | A Pal | Seekor Pal |
| `following` | {name} seems to like you and starts following you. | {name} sepertinya menyukaimu dan mulai mengikutimu. |
| `joined` | {name} has chosen to go with you. It trusts you completely. | {name} memilih untuk ikut bersamamu. Dia sepenuhnya mempercayaimu. |
| `joined_unnamed` | A wild Pal has chosen to go with you. | Seekor Pal liar memilih untuk ikut bersamamu. |
| `betrayed` | {name} no longer trusts you. It will not bond with you again. | {name} tidak lagi mempercayaimu. Dia tidak akan pernah terikat denganmu lagi. |
| `fell` | {name} fell while fighting alongside you. | {name} gugur saat bertarung di sisimu. |
| `abandoned` | {name} was left behind and gave up on you. | {name} tertinggal dan akhirnya berhenti menunggumu. |
| `shaken` | {name} flinched away from you. Its trust is shaken. | {name} mundur ketakutan darimu. Kepercayaannya terguncang. |
| `tags_on` | Personality tags: ON | Label kepribadian: AKTIF |
| `tags_off` | Personality tags: OFF | Label kepribadian: NONAKTIF |
| `passive_on` | Passive bonding: ON - your Pals grow closer over time. | Perolehan persahabatan pasif: AKTIF - Pal-mu makin dekat denganmu seiring waktu. |
| `passive_off` | Passive bonding: OFF - your Pals keep the trust they have. | Perolehan persahabatan pasif: NONAKTIF - Pal-mu tetap mempertahankan kepercayaan yang sudah ada. |

## Japanese (`ja`)

| ID | English | Translation |
|---|---|---|
| `tag_normal` | Normal | 普通 |
| `tag_curious` | Curious | 好奇心旺盛 |
| `tag_timid` | Timid | 臆病 |
| `tag_aloof` | Aloof | そっけない |
| `tag_grumpy` | Grumpy | 不機嫌 |
| `tag_hostile` | Hostile | 敵対的 |
| `tag_feral` | Feral | 凶暴 |
| `tag_friendly` | Friendly | 友好的 |
| `tag_bonding` | Bonding | 絆 |
| `tag_scarred` | Scarred | 傷心 |
| `tag_abandoned` | Abandoned | 置き去り |
| `tag_wary` | Wary | 警戒 |
| `tag_claimed` | Claimed | 先約 |
| `a_pal` | A Pal | Pal |
| `following` | {name} seems to like you and starts following you. | {name}はあなたを気に入ったようです。あなたについて来ます。 |
| `joined` | {name} has chosen to go with you. It trusts you completely. | {name}はあなたと一緒に行くことを選びました。あなたを完全に信頼しています。 |
| `joined_unnamed` | A wild Pal has chosen to go with you. | 野生のPalがあなたと一緒に行くことを選びました。 |
| `betrayed` | {name} no longer trusts you. It will not bond with you again. | {name}はもうあなたを信頼していません。二度と心を開くことはないでしょう。 |
| `fell` | {name} fell while fighting alongside you. | {name}はあなたと共に戦い、倒れました。 |
| `abandoned` | {name} was left behind and gave up on you. | {name}は置き去りにされ、あなたを諦めました。 |
| `shaken` | {name} flinched away from you. Its trust is shaken. | {name}はあなたに怯えています。信頼が揺らいでいます。 |
| `tags_on` | Personality tags: ON | 性格タグ：表示 |
| `tags_off` | Personality tags: OFF | 性格タグ：非表示 |
| `passive_on` | Passive bonding: ON - your Pals grow closer over time. | 受動的な友情値の上昇：オン - Palたちは時間とともにあなたに懐いていきます。 |
| `passive_off` | Passive bonding: OFF - your Pals keep the trust they have. | 受動的な友情値の上昇：オフ - Palたちは今の信頼を保ちます。 |

## Korean (`ko`)

| ID | English | Translation |
|---|---|---|
| `tag_normal` | Normal | 평범함 |
| `tag_curious` | Curious | 호기심 많음 |
| `tag_timid` | Timid | 소심함 |
| `tag_aloof` | Aloof | 무관심 |
| `tag_grumpy` | Grumpy | 심술궂음 |
| `tag_hostile` | Hostile | 적대적 |
| `tag_feral` | Feral | 흉포함 |
| `tag_friendly` | Friendly | 우호적 |
| `tag_bonding` | Bonding | 유대 |
| `tag_scarred` | Scarred | 상처받음 |
| `tag_abandoned` | Abandoned | 버려짐 |
| `tag_wary` | Wary | 경계 |
| `tag_claimed` | Claimed | 선점됨 |
| `a_pal` | A Pal | Pal |
| `following` | {name} seems to like you and starts following you. | {name}이(가) 당신을 마음에 들어 하는 것 같습니다. 이제 당신을 따라옵니다. |
| `joined` | {name} has chosen to go with you. It trusts you completely. | {name}이(가) 당신과 함께하기로 했습니다. 당신을 완전히 믿습니다. |
| `joined_unnamed` | A wild Pal has chosen to go with you. | 야생 Pal이 당신과 함께하기로 했습니다. |
| `betrayed` | {name} no longer trusts you. It will not bond with you again. | {name}은(는) 더 이상 당신을 믿지 않습니다. 다시는 당신과 유대를 맺지 않을 것입니다. |
| `fell` | {name} fell while fighting alongside you. | {name}이(가) 당신 곁에서 싸우다 쓰러졌습니다. |
| `abandoned` | {name} was left behind and gave up on you. | {name}이(가) 뒤에 남겨져 당신을 포기했습니다. |
| `shaken` | {name} flinched away from you. Its trust is shaken. | {name}이(가) 겁을 먹고 물러섰습니다. 신뢰가 흔들렸습니다. |
| `tags_on` | Personality tags: ON | 성격 태그: 켜짐 |
| `tags_off` | Personality tags: OFF | 성격 태그: 꺼짐 |
| `passive_on` | Passive bonding: ON - your Pals grow closer over time. | 수동적인 우정 상승: 켜짐 - Pal들이 시간이 지나며 당신과 가까워집니다. |
| `passive_off` | Passive bonding: OFF - your Pals keep the trust they have. | 수동적인 우정 상승: 꺼짐 - Pal들이 지금의 신뢰를 유지합니다. |

## Chinese (Simplified) (`zh-hans`)

| ID | English | Translation |
|---|---|---|
| `tag_normal` | Normal | 普通 |
| `tag_curious` | Curious | 好奇 |
| `tag_timid` | Timid | 胆小 |
| `tag_aloof` | Aloof | 冷漠 |
| `tag_grumpy` | Grumpy | 暴躁 |
| `tag_hostile` | Hostile | 敌对 |
| `tag_feral` | Feral | 凶猛 |
| `tag_friendly` | Friendly | 友好 |
| `tag_bonding` | Bonding | 亲近 |
| `tag_scarred` | Scarred | 心寒 |
| `tag_abandoned` | Abandoned | 被抛弃 |
| `tag_wary` | Wary | 警惕 |
| `tag_claimed` | Claimed | 已有主 |
| `a_pal` | A Pal | 一只 Pal |
| `following` | {name} seems to like you and starts following you. | {name}似乎喜欢上你了，开始跟着你。 |
| `joined` | {name} has chosen to go with you. It trusts you completely. | {name}选择与你同行。它完全信任你。 |
| `joined_unnamed` | A wild Pal has chosen to go with you. | 一只野生 Pal 选择与你同行。 |
| `betrayed` | {name} no longer trusts you. It will not bond with you again. | {name}不再信任你了。它再也不会与你建立羁绊。 |
| `fell` | {name} fell while fighting alongside you. | {name}在与你并肩作战时倒下了。 |
| `abandoned` | {name} was left behind and gave up on you. | {name}被你丢在身后，放弃了你。 |
| `shaken` | {name} flinched away from you. Its trust is shaken. | {name}受到惊吓，躲开了你。它的信任动摇了。 |
| `tags_on` | Personality tags: ON | 性格标签：开启 |
| `tags_off` | Personality tags: OFF | 性格标签：关闭 |
| `passive_on` | Passive bonding: ON - your Pals grow closer over time. | 被动友情增长：开启 - 你的 Pal 会随着时间与你越来越亲近。 |
| `passive_off` | Passive bonding: OFF - your Pals keep the trust they have. | 被动友情增长：关闭 - 你的 Pal 会保持现有的信任。 |

## Chinese (Traditional) (`zh-hant`)

| ID | English | Translation |
|---|---|---|
| `tag_normal` | Normal | 普通 |
| `tag_curious` | Curious | 好奇 |
| `tag_timid` | Timid | 膽小 |
| `tag_aloof` | Aloof | 冷漠 |
| `tag_grumpy` | Grumpy | 暴躁 |
| `tag_hostile` | Hostile | 敵對 |
| `tag_feral` | Feral | 兇猛 |
| `tag_friendly` | Friendly | 友善 |
| `tag_bonding` | Bonding | 親近 |
| `tag_scarred` | Scarred | 心寒 |
| `tag_abandoned` | Abandoned | 被拋棄 |
| `tag_wary` | Wary | 警惕 |
| `tag_claimed` | Claimed | 已有主 |
| `a_pal` | A Pal | 一隻 Pal |
| `following` | {name} seems to like you and starts following you. | {name}似乎喜歡上你了，開始跟著你。 |
| `joined` | {name} has chosen to go with you. It trusts you completely. | {name}選擇與你同行。牠完全信任你。 |
| `joined_unnamed` | A wild Pal has chosen to go with you. | 一隻野生 Pal 選擇與你同行。 |
| `betrayed` | {name} no longer trusts you. It will not bond with you again. | {name}不再信任你了。牠再也不會與你建立羈絆。 |
| `fell` | {name} fell while fighting alongside you. | {name}在與你並肩作戰時倒下了。 |
| `abandoned` | {name} was left behind and gave up on you. | {name}被你留在身後，放棄了你。 |
| `shaken` | {name} flinched away from you. Its trust is shaken. | {name}受到驚嚇，躲開了你。牠的信任動搖了。 |
| `tags_on` | Personality tags: ON | 性格標籤：開啟 |
| `tags_off` | Personality tags: OFF | 性格標籤：關閉 |
| `passive_on` | Passive bonding: ON - your Pals grow closer over time. | 被動友情值增加：開啟 - 你的 Pal 會隨著時間與你越來越親近。 |
| `passive_off` | Passive bonding: OFF - your Pals keep the trust they have. | 被動友情值增加：關閉 - 你的 Pal 會保持現有的信任。 |
