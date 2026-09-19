-- ===========================================================================
-- TRANSLATIONS (2026-09-18)
-- ===========================================================================
-- Every word PalBonds puts on screen, in the 16 languages Palworld ships
-- besides English (EPalLanguageType: JP, EN, ZH_HANS, ZH_HANT, FR, IT, DE, ES,
-- KO, PT_BR, RU, TH, VI, ID, TR, PL, ES_MX). Spanish is one neutral set for
-- Spain and Latin America, like Dragón's Workshop description. Wording follows
-- his Workshop translations where they already name the thing (the "tags",
-- the passive friendship gain, trust, giving up on you).
--
-- WHICH LANGUAGE: Dragón's rule, "follow the game's language automatically IF
-- WE CAN, if not then simply default it to English". The engine's current
-- language follows the in-game option (probe, 2026-09-18: "en" in English,
-- "es-MX" in Spanish), so "auto" reads it. The player can force one with
-- Language in the settings file. Anything unrecognised is English.
--
-- The engine is asked at most once every LANGUAGE_REFRESH_SECONDS, and only
-- from code that already runs on the game thread (tag refresh, toasts).
-- Palworld itself only changes language between launches (Dragón, 2026-09-18),
-- so in practice this settles on the first read; the refresh is just cheap.
local Locale = {}

local LANGUAGE_REFRESH_SECONDS = 10.0

-- Language names the settings file accepts, besides "auto".
Locale.LANGUAGES = { "en", "es", "fr", "de", "it", "pl", "pt", "ru", "tr", "vi", "th", "id", "ja", "ko", "zh-hans", "zh-hant" }

-- {name} is replaced by the Pal's name (which the game already gives in its
-- own language). Where a word changes with the Pal's gender (Spanish,
-- Portuguese, French, Italian, Polish, Russian) the entry is { m = , f = };
-- Dragón caught a female Pal tagged "Curioso" (2026-09-18).
--
-- REVIEWED 2026-09-18 by ChatGPT and Gemini (docs/reveiw-chatgpt.txt,
-- docs/review-gemini.txt) plus a second pass of our own. Changed: tr Feral
-- (Azgın has a sexual meaning), pl Feral (Szalony = crazy), id Scarred
-- (Terluka is physical), ja/ko Curious (noun -> adjective), fr Scarred
-- (Trahi), fr/it shaken (keep the flinch), id abandoned, tr capitalisation,
-- fr idiom, es shaken ("flaquea", Dragón's pick), and Russian to informal ты
-- (Dragón wanted the mod to read casually). Kept on purpose: German neuter
-- "das Pal"/"Es", as in his German description, and the F10 system names,
-- which are his descriptions' own terms.
local S = {
    -- Personality tags
    tag_normal = {
        en = "Normal", es = "Normal", fr = { m = "Normal", f = "Normale" }, de = "Normal", it = "Normale", pl = { m = "Normalny", f = "Normalna" },
        pt = "Normal", ru = { m = "Обычный", f = "Обычная" }, tr = "Normal", vi = "Bình thường", th = "ปกติ", id = "Normal",
        ja = "普通", ko = "평범함", ["zh-hans"] = "普通", ["zh-hant"] = "普通",
    },
    tag_curious = {
        en = "Curious", es = { m = "Curioso", f = "Curiosa" }, fr = { m = "Curieux", f = "Curieuse" }, de = "Neugierig", it = { m = "Curioso", f = "Curiosa" }, pl = { m = "Ciekawski", f = "Ciekawska" },
        pt = { m = "Curioso", f = "Curiosa" }, ru = { m = "Любопытный", f = "Любопытная" }, tr = "Meraklı", vi = "Tò mò", th = "ขี้สงสัย", id = "Penasaran",
        ja = "好奇心旺盛", ko = "호기심 많음", ["zh-hans"] = "好奇", ["zh-hant"] = "好奇",
    },
    tag_timid = {
        en = "Timid", es = { m = "Tímido", f = "Tímida" }, fr = "Timide", de = "Scheu", it = { m = "Timido", f = "Timida" }, pl = { m = "Nieśmiały", f = "Nieśmiała" },
        pt = { m = "Tímido", f = "Tímida" }, ru = { m = "Робкий", f = "Робкая" }, tr = "Ürkek", vi = "Nhút nhát", th = "ขี้อาย", id = "Pemalu",
        ja = "臆病", ko = "소심함", ["zh-hans"] = "胆小", ["zh-hant"] = "膽小",
    },
    tag_aloof = {
        en = "Aloof", es = "Distante", fr = { m = "Distant", f = "Distante" }, de = "Distanziert", it = { m = "Distaccato", f = "Distaccata" }, pl = { m = "Obojętny", f = "Obojętna" },
        pt = "Distante", ru = { m = "Отстранённый", f = "Отстранённая" }, tr = "Mesafeli", vi = "Thờ ơ", th = "เมินเฉย", id = "Cuek",
        ja = "そっけない", ko = "무관심", ["zh-hans"] = "冷漠", ["zh-hant"] = "冷漠",
    },
    tag_grumpy = {
        en = "Grumpy", es = { m = "Gruñón", f = "Gruñona" }, fr = { m = "Grincheux", f = "Grincheuse" }, de = "Mürrisch", it = { m = "Scontroso", f = "Scontrosa" }, pl = { m = "Zrzędliwy", f = "Zrzędliwa" },
        pt = "Ranzinza", ru = { m = "Ворчливый", f = "Ворчливая" }, tr = "Huysuz", vi = "Cáu kỉnh", th = "ขี้หงุดหงิด", id = "Pemarah",
        ja = "不機嫌", ko = "심술궂음", ["zh-hans"] = "暴躁", ["zh-hant"] = "暴躁",
    },
    tag_hostile = {
        en = "Hostile", es = "Hostil", fr = "Hostile", de = "Feindselig", it = "Ostile", pl = { m = "Wrogi", f = "Wroga" },
        pt = "Hostil", ru = { m = "Враждебный", f = "Враждебная" }, tr = "Düşmanca", vi = "Thù địch", th = "ก้าวร้าว", id = "Bermusuhan",
        ja = "敵対的", ko = "적대적", ["zh-hans"] = "敌对", ["zh-hant"] = "敵對",
    },
    -- Not the word for "wild": every Pal the mod tags is a wild Pal, so
    -- Salvaje/Wild/Dziki/Vahşi would read as a description of all of them.
    tag_feral = {
        en = "Feral", es = "Feroz", fr = "Féroce", de = "Rasend", it = "Feroce", pl = { m = "Wściekły", f = "Wściekła" },
        pt = "Feroz", ru = { m = "Свирепый", f = "Свирепая" }, tr = "Gözü dönmüş", vi = "Hung dữ", th = "ดุร้าย", id = "Buas",
        ja = "凶暴", ko = "흉포함", ["zh-hans"] = "凶猛", ["zh-hant"] = "兇猛",
    },
    tag_friendly = {
        en = "Friendly", es = { m = "Amistoso", f = "Amistosa" }, fr = { m = "Amical", f = "Amicale" }, de = "Freundlich", it = "Amichevole", pl = { m = "Przyjazny", f = "Przyjazna" },
        pt = "Amigável", ru = { m = "Дружелюбный", f = "Дружелюбная" }, tr = "Dostça", vi = "Thân thiện", th = "เป็นมิตร", id = "Ramah",
        ja = "友好的", ko = "우호적", ["zh-hans"] = "友好", ["zh-hant"] = "友善",
    },
    tag_bonding = {
        en = "Bonding", es = { m = "Encariñado", f = "Encariñada" }, fr = { m = "Attaché", f = "Attachée" }, de = "Anhänglich", it = { m = "Affezionato", f = "Affezionata" }, pl = { m = "Przywiązany", f = "Przywiązana" },
        pt = { m = "Apegado", f = "Apegada" }, ru = { m = "Привязанный", f = "Привязанная" }, tr = "Bağlı", vi = "Gắn bó", th = "ผูกพัน", id = "Terikat",
        ja = "絆", ko = "유대", ["zh-hans"] = "亲近", ["zh-hant"] = "親近",
    },
    -- Dragón: "scarred for betrayed pals so players actually feel bad for what
    -- they did". An emotional wound, not a physical one.
    tag_scarred = {
        en = "Scarred", es = { m = "Resentido", f = "Resentida" }, fr = { m = "Trahi", f = "Trahie" }, de = "Verbittert", it = { m = "Rancoroso", f = "Rancorosa" }, pl = { m = "Urażony", f = "Urażona" },
        pt = { m = "Magoado", f = "Magoada" }, ru = { m = "Обиженный", f = "Обиженная" }, tr = "Kırgın", vi = "Tổn thương", th = "เจ็บใจ", id = "Sakit hati",
        ja = "傷心", ko = "상처받음", ["zh-hans"] = "心寒", ["zh-hant"] = "心寒",
    },
    tag_abandoned = {
        en = "Abandoned", es = { m = "Abandonado", f = "Abandonada" }, fr = { m = "Abandonné", f = "Abandonnée" }, de = "Verlassen", it = { m = "Abbandonato", f = "Abbandonata" }, pl = { m = "Porzucony", f = "Porzucona" },
        pt = { m = "Abandonado", f = "Abandonada" }, ru = { m = "Брошенный", f = "Брошенная" }, tr = "Terk edilmiş", vi = "Bị bỏ rơi", th = "ถูกทิ้ง", id = "Ditinggalkan",
        ja = "置き去り", ko = "버려짐", ["zh-hans"] = "被抛弃", ["zh-hant"] = "被拋棄",
    },
    tag_wary = {
        en = "Wary", es = { m = "Receloso", f = "Recelosa" }, fr = { m = "Méfiant", f = "Méfiante" }, de = "Misstrauisch", it = "Diffidente", pl = { m = "Nieufny", f = "Nieufna" },
        pt = { m = "Desconfiado", f = "Desconfiada" }, ru = { m = "Настороженный", f = "Настороженная" }, tr = "Temkinli", vi = "Dè chừng", th = "ระแวง", id = "Waspada",
        ja = "警戒", ko = "경계", ["zh-hans"] = "警惕", ["zh-hant"] = "警惕",
    },

    -- Messages
    a_pal = {
        en = "A Pal", es = "Un Pal", fr = "Un Pal", de = "Ein Pal", it = "Un Pal", pl = "Pal",
        pt = "Um Pal", ru = "Pal", tr = "Bir Pal", vi = "Một Pal", th = "Pal ตัวหนึ่ง", id = "Seekor Pal",
        ja = "Pal", ko = "Pal", ["zh-hans"] = "一只 Pal", ["zh-hant"] = "一隻 Pal",
    },
    joined = {
        en = "{name} has chosen to go with you. It trusts you completely.",
        es = "{name} decidió irse contigo. Confía plenamente en ti.",
        fr = { m = "{name} a choisi de partir avec toi. Il te fait entièrement confiance.", f = "{name} a choisi de partir avec toi. Elle te fait entièrement confiance." },
        de = "{name} hat sich entschieden, mit dir zu gehen. Es vertraut dir vollkommen.",
        it = "{name} ha scelto di venire con te. Si fida completamente di te.",
        pl = { m = "{name} postanowił pójść z tobą. Ufa ci całkowicie.", f = "{name} postanowiła pójść z tobą. Ufa ci całkowicie." },
        pt = { m = "{name} escolheu seguir com você. Ele confia completamente em você.", f = "{name} escolheu seguir com você. Ela confia completamente em você." },
        ru = { m = "{name} решил пойти с тобой. Он полностью тебе доверяет.", f = "{name} решила пойти с тобой. Она полностью тебе доверяет." },
        tr = "{name} seninle gelmeye karar verdi. Sana tamamen güveniyor.",
        vi = "{name} đã chọn đi cùng bạn. Nó hoàn toàn tin tưởng bạn.",
        th = "{name} เลือกที่จะไปกับคุณ มันไว้ใจคุณอย่างเต็มที่",
        id = "{name} memilih untuk ikut bersamamu. Dia sepenuhnya mempercayaimu.",
        ja = "{name}はあなたと一緒に行くことを選びました。あなたを完全に信頼しています。",
        ko = "{name}이(가) 당신과 함께하기로 했습니다. 당신을 완전히 믿습니다.",
        ["zh-hans"] = "{name}选择与你同行。它完全信任你。",
        ["zh-hant"] = "{name}選擇與你同行。牠完全信任你。",
    },
    -- 50%: the Pal starts following (Dragón's idea, 2026-09-18: "(palname)
    -- seems to like you"), with the second half saying what the player will
    -- now see it do.
    following = {
        en = "{name} seems to like you and starts following you.",
        es = "{name} parece tenerte cariño y empieza a seguirte.",
        fr = "{name} semble t'apprécier et commence à te suivre.",
        de = "{name} scheint dich zu mögen und folgt dir jetzt.",
        it = { m = "{name} sembra essersi affezionato a te e inizia a seguirti.", f = "{name} sembra essersi affezionata a te e inizia a seguirti." },
        pl = { m = "{name} chyba cię polubił i zaczyna za tobą chodzić.", f = "{name} chyba cię polubiła i zaczyna za tobą chodzić." },
        pt = "{name} parece gostar de você e começa a te seguir.",
        ru = { m = "{name}, похоже, привязался к тебе и теперь следует за тобой.", f = "{name}, похоже, привязалась к тебе и теперь следует за тобой." },
        tr = "{name} senden hoşlanmış gibi görünüyor ve seni takip etmeye başladı.",
        vi = "{name} có vẻ quý bạn và bắt đầu đi theo bạn.",
        th = "{name} ดูเหมือนจะชอบคุณ และเริ่มเดินตามคุณ",
        id = "{name} sepertinya menyukaimu dan mulai mengikutimu.",
        ja = "{name}はあなたを気に入ったようです。あなたについて来ます。",
        ko = "{name}이(가) 당신을 마음에 들어 하는 것 같습니다. 이제 당신을 따라옵니다.",
        ["zh-hans"] = "{name}似乎喜欢上你了，开始跟着你。",
        ["zh-hant"] = "{name}似乎喜歡上你了，開始跟著你。",
    },
    joined_unnamed = {
        en = "A wild Pal has chosen to go with you.",
        es = "Un Pal salvaje decidió irse contigo.",
        fr = "Un Pal sauvage a choisi de partir avec toi.",
        de = "Ein wildes Pal hat sich entschieden, mit dir zu gehen.",
        it = "Un Pal selvatico ha scelto di venire con te.",
        pl = "Dziki Pal postanowił pójść z tobą.",
        pt = "Um Pal selvagem escolheu seguir com você.",
        ru = "Дикий Pal решил пойти с тобой.",
        tr = "Vahşi bir Pal seninle gelmeye karar verdi.",
        vi = "Một Pal hoang dã đã chọn đi cùng bạn.",
        th = "Pal ป่าตัวหนึ่งเลือกที่จะไปกับคุณ",
        id = "Seekor Pal liar memilih untuk ikut bersamamu.",
        ja = "野生のPalがあなたと一緒に行くことを選びました。",
        ko = "야생 Pal이 당신과 함께하기로 했습니다.",
        ["zh-hans"] = "一只野生 Pal 选择与你同行。",
        ["zh-hant"] = "一隻野生 Pal 選擇與你同行。",
    },
    betrayed = {
        en = "{name} no longer trusts you. It will not bond with you again.",
        es = "{name} ya no confía en ti. No volverá a crear un vínculo contigo.",
        fr = { m = "{name} ne te fait plus confiance. Il ne se liera plus jamais à toi.", f = "{name} ne te fait plus confiance. Elle ne se liera plus jamais à toi." },
        de = "{name} vertraut dir nicht mehr. Es wird sich nie wieder an dich binden.",
        it = "{name} non si fida più di te. Non si legherà mai più a te.",
        pl = "{name} już ci nie ufa. Nigdy więcej się z tobą nie zwiąże.",
        pt = "{name} não confia mais em você. Nunca mais vai criar laços com você.",
        ru = { m = "{name} больше тебе не доверяет. Он больше никогда к тебе не привяжется.", f = "{name} больше тебе не доверяет. Она больше никогда к тебе не привяжется." },
        tr = "{name} artık sana güvenmiyor. Seninle bir daha asla bağ kurmayacak.",
        vi = "{name} không còn tin tưởng bạn nữa. Nó sẽ không bao giờ gắn bó với bạn nữa.",
        th = "{name} ไม่ไว้ใจคุณอีกต่อไป มันจะไม่ผูกพันกับคุณอีก",
        id = "{name} tidak lagi mempercayaimu. Dia tidak akan pernah terikat denganmu lagi.",
        ja = "{name}はもうあなたを信頼していません。二度と心を開くことはないでしょう。",
        ko = "{name}은(는) 더 이상 당신을 믿지 않습니다. 다시는 당신과 유대를 맺지 않을 것입니다.",
        ["zh-hans"] = "{name}不再信任你了。它再也不会与你建立羁绊。",
        ["zh-hant"] = "{name}不再信任你了。牠再也不會與你建立羈絆。",
    },
    fell = {
        en = "{name} fell while fighting alongside you.",
        es = "{name} cayó luchando a tu lado.",
        fr = { m = "{name} est tombé en combattant à tes côtés.", f = "{name} est tombée en combattant à tes côtés." },
        de = "{name} ist an deiner Seite im Kampf gefallen.",
        it = { m = "{name} è caduto combattendo al tuo fianco.", f = "{name} è caduta combattendo al tuo fianco." },
        pl = { m = "{name} poległ, walcząc u twojego boku.", f = "{name} poległa, walcząc u twojego boku." },
        pt = "{name} caiu lutando ao seu lado.",
        ru = { m = "{name} пал в бою рядом с тобой.", f = "{name} пала в бою рядом с тобой." },
        tr = "{name} senin yanında savaşırken düştü.",
        vi = "{name} đã ngã xuống khi chiến đấu bên cạnh bạn.",
        th = "{name} ล้มลงขณะต่อสู้เคียงข้างคุณ",
        id = "{name} gugur saat bertarung di sisimu.",
        ja = "{name}はあなたと共に戦い、倒れました。",
        ko = "{name}이(가) 당신 곁에서 싸우다 쓰러졌습니다.",
        ["zh-hans"] = "{name}在与你并肩作战时倒下了。",
        ["zh-hant"] = "{name}在與你並肩作戰時倒下了。",
    },
    abandoned = {
        en = "{name} was left behind and gave up on you.",
        es = { m = "{name} se quedó atrás y se dio por vencido contigo.", f = "{name} se quedó atrás y se dio por vencida contigo." },
        fr = { m = "{name} a été laissé en arrière et a renoncé à toi.", f = "{name} a été laissée en arrière et a renoncé à toi." },
        de = "{name} wurde zurückgelassen und hat dich aufgegeben.",
        it = { m = "{name} è stato lasciato indietro e ha perso fiducia in te.", f = "{name} è stata lasciata indietro e ha perso fiducia in te." },
        pl = { m = "{name} został w tyle i przestał na ciebie czekać.", f = "{name} została w tyle i przestała na ciebie czekać." },
        pt = { m = "{name} foi deixado para trás e desistiu de você.", f = "{name} foi deixada para trás e desistiu de você." },
        ru = { m = "{name} остался позади и перестал тебя ждать.", f = "{name} осталась позади и перестала тебя ждать." },
        tr = "{name} geride kaldı ve senden vazgeçti.",
        vi = "{name} đã bị bỏ lại phía sau và từ bỏ bạn.",
        th = "{name} ถูกทิ้งไว้ข้างหลังจึงยอมแพ้และจากคุณไป",
        id = "{name} tertinggal dan akhirnya berhenti menunggumu.",
        ja = "{name}は置き去りにされ、あなたを諦めました。",
        ko = "{name}이(가) 뒤에 남겨져 당신을 포기했습니다.",
        ["zh-hans"] = "{name}被你丢在身后，放弃了你。",
        ["zh-hant"] = "{name}被你留在身後，放棄了你。",
    },
    shaken = {
        en = "{name} flinched away from you. Its trust is shaken.",
        es = { m = "{name} se apartó de ti asustado. Su confianza en ti flaquea.", f = "{name} se apartó de ti asustada. Su confianza en ti flaquea." },
        fr = { m = "{name} s'est écarté de toi, effrayé. Sa confiance est ébranlée.", f = "{name} s'est écartée de toi, effrayée. Sa confiance est ébranlée." },
        de = "{name} ist vor dir zurückgeschreckt. Sein Vertrauen ist erschüttert.",
        it = { m = "{name} si è ritratto, spaventato. La sua fiducia è stata scossa.", f = "{name} si è ritratta, spaventata. La sua fiducia è stata scossa." },
        pl = { m = "{name} odskoczył od ciebie. Jego zaufanie zostało nadszarpnięte.", f = "{name} odskoczyła od ciebie. Jej zaufanie zostało nadszarpnięte." },
        pt = { m = "{name} se afastou assustado. A confiança dele foi abalada.", f = "{name} se afastou assustada. A confiança dela foi abalada." },
        ru = { m = "{name} отшатнулся от тебя. Его доверие пошатнулось.", f = "{name} отшатнулась от тебя. Её доверие пошатнулось." },
        tr = "{name} senden ürkerek uzaklaştı. Güveni sarsıldı.",
        vi = "{name} sợ hãi lùi lại. Niềm tin của nó đã bị lung lay.",
        th = "{name} ผงะถอยหนีคุณ ความไว้ใจของมันสั่นคลอน",
        id = "{name} mundur ketakutan darimu. Kepercayaannya terguncang.",
        ja = "{name}はあなたに怯えています。信頼が揺らいでいます。",
        ko = "{name}이(가) 겁을 먹고 물러섰습니다. 신뢰가 흔들렸습니다.",
        ["zh-hans"] = "{name}受到惊吓，躲开了你。它的信任动摇了。",
        ["zh-hant"] = "{name}受到驚嚇，躲開了你。牠的信任動搖了。",
    },
    tags_on = {
        en = "Personality tags: ON", es = "Etiquetas de personalidad: ACTIVADAS", fr = "Étiquettes de personnalité : ACTIVÉES",
        de = "Persönlichkeitstags: AN", it = "Etichette della personalità: ATTIVE", pl = "Etykiety osobowości: WŁĄCZONE",
        pt = "Etiquetas de personalidade: ATIVADAS", ru = "Метки характера: ВКЛ", tr = "Kişilik etiketleri: AÇIK",
        vi = "Nhãn tính cách: BẬT", th = "ป้ายบุคลิก: เปิด", id = "Label kepribadian: AKTIF",
        ja = "性格タグ：表示", ko = "성격 태그: 켜짐", ["zh-hans"] = "性格标签：开启", ["zh-hant"] = "性格標籤：開啟",
    },
    tags_off = {
        en = "Personality tags: OFF", es = "Etiquetas de personalidad: DESACTIVADAS", fr = "Étiquettes de personnalité : DÉSACTIVÉES",
        de = "Persönlichkeitstags: AUS", it = "Etichette della personalità: DISATTIVATE", pl = "Etykiety osobowości: WYŁĄCZONE",
        pt = "Etiquetas de personalidade: DESATIVADAS", ru = "Метки характера: ВЫКЛ", tr = "Kişilik etiketleri: KAPALI",
        vi = "Nhãn tính cách: TẮT", th = "ป้ายบุคลิก: ปิด", id = "Label kepribadian: NONAKTIF",
        ja = "性格タグ：非表示", ko = "성격 태그: 꺼짐", ["zh-hans"] = "性格标签：关闭", ["zh-hant"] = "性格標籤：關閉",
    },
    passive_on = {
        en = "Passive bonding: ON - your Pals grow closer over time.",
        es = "Ganancia pasiva de amistad: ACTIVADA - tus Pals se encariñan contigo con el tiempo.",
        fr = "Gain passif d'amitié : ACTIVÉ - tes Pals se rapprochent de toi avec le temps.",
        de = "Passive Freundschaftszunahme: AN - deine Pals kommen dir mit der Zeit näher.",
        it = "Aumento passivo dell'amicizia: ATTIVO - i tuoi Pals si affezionano a te col tempo.",
        pl = "Pasywne zdobywanie przyjaźni: WŁĄCZONE - twoje Pale z czasem się do ciebie zbliżają.",
        pt = "Ganho passivo de amizade: ATIVADO - seus Pals se aproximam de você com o tempo.",
        ru = "Пассивное получение дружбы: ВКЛ - твои Pals со временем сближаются с тобой.",
        tr = "Pasif dostluk kazanımı: AÇIK - Pal'ların zamanla sana daha çok yakınlaşır.",
        vi = "Tăng tình bạn thụ động: BẬT - các Pal của bạn sẽ thân thiết hơn theo thời gian.",
        th = "การเพิ่มค่ามิตรภาพแบบอัตโนมัติ: เปิด - Pal ของคุณจะสนิทกับคุณมากขึ้นเรื่อย ๆ",
        id = "Perolehan persahabatan pasif: AKTIF - Pal-mu makin dekat denganmu seiring waktu.",
        ja = "受動的な友情値の上昇：オン - Palたちは時間とともにあなたに懐いていきます。",
        ko = "수동적인 우정 상승: 켜짐 - Pal들이 시간이 지나며 당신과 가까워집니다.",
        ["zh-hans"] = "被动友情增长：开启 - 你的 Pal 会随着时间与你越来越亲近。",
        ["zh-hant"] = "被動友情值增加：開啟 - 你的 Pal 會隨著時間與你越來越親近。",
    },
    passive_off = {
        en = "Passive bonding: OFF - your Pals keep the trust they have.",
        es = "Ganancia pasiva de amistad: DESACTIVADA - tus Pals conservan la confianza que tienen.",
        fr = "Gain passif d'amitié : DÉSACTIVÉ - tes Pals gardent la confiance qu'ils ont.",
        de = "Passive Freundschaftszunahme: AUS - deine Pals behalten ihr bisheriges Vertrauen.",
        it = "Aumento passivo dell'amicizia: DISATTIVATO - i tuoi Pals mantengono la fiducia che hanno.",
        pl = "Pasywne zdobywanie przyjaźni: WYŁĄCZONE - twoje Pale zachowują obecne zaufanie.",
        pt = "Ganho passivo de amizade: DESATIVADO - seus Pals mantêm a confiança que já têm.",
        ru = "Пассивное получение дружбы: ВЫКЛ - твои Pals сохраняют текущее доверие.",
        tr = "Pasif dostluk kazanımı: KAPALI - Pal'ların mevcut güvenlerini korur.",
        vi = "Tăng tình bạn thụ động: TẮT - các Pal của bạn giữ nguyên niềm tin hiện có.",
        th = "การเพิ่มค่ามิตรภาพแบบอัตโนมัติ: ปิด - Pal ของคุณจะคงความไว้ใจที่มีอยู่",
        id = "Perolehan persahabatan pasif: NONAKTIF - Pal-mu tetap mempertahankan kepercayaan yang sudah ada.",
        ja = "受動的な友情値の上昇：オフ - Palたちは今の信頼を保ちます。",
        ko = "수동적인 우정 상승: 꺼짐 - Pal들이 지금의 신뢰를 유지합니다.",
        ["zh-hans"] = "被动友情增长：关闭 - 你的 Pal 会保持现有的信任。",
        ["zh-hant"] = "被動友情值增加：關閉 - 你的 Pal 會保持現有的信任。",
    },
}
Locale.STRINGS = S

-- Engine culture code -> our language key. Pure, so it can be tested.
-- "es-MX" -> "es", "pt-BR" -> "pt", "zh-Hans" / "zh-CN" -> "zh-hans",
-- "zh-Hant" / "zh-TW" / "zh-HK" -> "zh-hant", anything unknown -> "en".
local SUPPORTED = {}
for _, code in ipairs(Locale.LANGUAGES) do SUPPORTED[code] = true end

function Locale.FromCulture(culture)
    if type(culture) ~= "string" or culture == "" then return "en" end
    local c = culture:lower():gsub("_", "-")
    if c:find("^zh") then
        if c:find("hant") or c:find("%-tw") or c:find("%-hk") or c:find("%-mo") then return "zh-hant" end
        return "zh-hans"
    end
    if SUPPORTED[c] then return c end
    local base = c:match("^([a-z]+)")
    if base == "jp" then base = "ja" end
    if base and SUPPORTED[base] then return base end
    return "en"
end

local cached, cachedAt = nil, -1e9
local lib = nil

local function engine_culture()
    local okV, valid = false, false
    if lib ~= nil then okV, valid = pcall(function() return lib:IsValid() end) end
    if not (okV and valid) then
        lib = nil
        pcall(function() lib = StaticFindObject("/Script/Engine.Default__KismetInternationalizationLibrary") end)
    end
    if lib == nil then return nil end
    local ok, v = pcall(function() return lib:GetCurrentLanguage() end)
    if not ok or v == nil then return nil end
    if type(v) == "string" then return v end
    local okS, s = pcall(function() return v:ToString() end)
    if okS and type(s) == "string" then return s end
    return nil
end

-- The language in use right now.
function Locale.Current()
    local choice = "auto"
    pcall(function() choice = require("Settings").Get("Language") end)
    if choice ~= "auto" then return choice end
    local now = os.clock()
    if cached ~= nil and (now - cachedAt) < LANGUAGE_REFRESH_SECONDS then return cached end
    cachedAt = now
    local culture = engine_culture()
    local lang = Locale.FromCulture(culture)
    if lang ~= cached then
        pcall(function()
            require("Logger").log("[PalBonds/Locale] game language " .. tostring(culture) .. " -> " .. lang)
        end)
    end
    cached = lang
    return lang
end

-- Text for `key` in the current language, English if that one is missing.
-- `vars.name` fills {name}; `vars.female` picks the feminine form.
function Locale.T(key, vars)
    local entry = S[key]
    if entry == nil then return key end
    local text = entry[Locale.Current()] or entry.en
    -- Gendered languages hold { m = ..., f = ... }: the masculine form is also
    -- the neutral one, used for a Pal whose gender is None or unknown.
    if type(text) == "table" then
        text = (vars and vars.female) and text.f or text.m
    end
    if vars and vars.name ~= nil then
        local name = tostring(vars.name):gsub("%%", "%%%%")
        text = text:gsub("{name}", name)
    end
    return text
end

return Locale
