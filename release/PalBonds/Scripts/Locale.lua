local Locale = {}

local LANGUAGE_REFRESH_SECONDS = 10.0

Locale.LANGUAGES = { "en", "es", "fr", "de", "it", "pl", "pt", "ru", "tr", "vi", "th", "id", "ja", "ko", "zh-hans", "zh-hant" }

local S = {

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

    tag_claimed = {
        en = "Claimed", es = { m = "Ocupado", f = "Ocupada" }, fr = { m = "Pris", f = "Prise" }, de = "Vergeben", it = { m = "Occupato", f = "Occupata" }, pl = { m = "Zajęty", f = "Zajęta" },
        pt = { m = "Ocupado", f = "Ocupada" }, ru = { m = "Занят", f = "Занята" }, tr = "Sahipli", vi = "Đã có chủ", th = "ถูกจอง", id = "Sudah diklaim",
        ja = "先約", ko = "선점됨", ["zh-hans"] = "已有主", ["zh-hant"] = "已有主",
    },

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

    menu_close = {
        en = "Close", es = "Cerrar", fr = "Fermer", de = "Schließen", it = "Chiudi", pl = "Zamknij",
        pt = "Fechar", ru = "Закрыть", tr = "Kapat", vi = "Đóng", th = "ปิด", id = "Tutup",
        ja = "閉じる", ko = "닫기", ["zh-hans"] = "关闭", ["zh-hant"] = "關閉",
    },

    sec_trust = {
        en = "Friendship points", es = "Puntos de amistad", fr = "Points d'amitié", de = "Freundschaftspunkte", it = "Punti amicizia", pl = "Punkty przyjaźni",
        pt = "Pontos de amizade", ru = "Очки дружбы", tr = "Dostluk puanları", vi = "Điểm tình bạn", th = "คะแนนมิตรภาพ", id = "Poin persahabatan", ja = "友情ポイント", ko = "우정 포인트", ["zh-hans"] = "友情点数", ["zh-hant"] = "友情點數",
    },
    sec_personality = {
        en = "Personality chances", es = "Probabilidades de personalidad", fr = "Chances de personnalité", de = "Persönlichkeits-Chancen", it = "Probabilità di personalità", pl = "Szanse osobowości",
        pt = "Chances de personalidade", ru = "Шансы характеров", tr = "Kişilik şansları", vi = "Tỉ lệ tính cách", th = "โอกาสของนิสัย", id = "Peluang kepribadian", ja = "性格の出現率", ko = "성격 확률", ["zh-hans"] = "性格出现概率", ["zh-hant"] = "性格出現機率",
    },
    sec_language = {
        en = "Language", es = "Idioma", fr = "Langue", de = "Sprache", it = "Lingua", pl = "Język",
        pt = "Idioma", ru = "Язык", tr = "Dil", vi = "Ngôn ngữ", th = "ภาษา", id = "Bahasa", ja = "言語", ko = "언어", ["zh-hans"] = "语言", ["zh-hant"] = "語言",
    },
    sec_display = {
        en = "Modules", es = "Módulos", fr = "Modules", de = "Module", it = "Moduli", pl = "Moduły",
        pt = "Módulos", ru = "Модули", tr = "Modüller", vi = "Mô-đun", th = "โมดูล", id = "Modul", ja = "モジュール", ko = "모듈", ["zh-hans"] = "模块", ["zh-hant"] = "模組",
    },
    sec_keys = {
        en = "Keys", es = "Teclas", fr = "Touches", de = "Tasten", it = "Tasti", pl = "Klawisze",
        pt = "Teclas", ru = "Клавиши", tr = "Tuşlar", vi = "Phím", th = "ปุ่ม", id = "Tombol", ja = "キー", ko = "키", ["zh-hans"] = "按键", ["zh-hant"] = "按鍵",
    },
    set_pet = {
        en = "Petting", es = "Acariciar", fr = "Caresser", de = "Streicheln", it = "Accarezzare", pl = "Głaskanie",
        pt = "Acariciar", ru = "Поглаживание", tr = "Sevmek", vi = "Vuốt ve", th = "การลูบ", id = "Membelai", ja = "なでる", ko = "쓰다듬기", ["zh-hans"] = "抚摸", ["zh-hant"] = "撫摸",
    },
    set_play = {
        en = "Playing", es = "Jugar", fr = "Jouer", de = "Spielen", it = "Giocare", pl = "Zabawa",
        pt = "Brincar", ru = "Игра", tr = "Oynamak", vi = "Chơi cùng", th = "การเล่น", id = "Bermain", ja = "あそぶ", ko = "놀아주기", ["zh-hans"] = "玩耍", ["zh-hant"] = "玩耍",
    },
    set_feed = {
        en = "Feeding", es = "Alimentar", fr = "Nourrir", de = "Füttern", it = "Nutrire", pl = "Karmienie",
        pt = "Alimentar", ru = "Кормление", tr = "Beslemek", vi = "Cho ăn", th = "การให้อาหาร", id = "Memberi makan", ja = "エサをあげる", ko = "먹이 주기", ["zh-hans"] = "喂食", ["zh-hant"] = "餵食",
    },
    set_feed_common = {
        en = "Extra for common food", es = "Extra por comida común", fr = "Bonus pour nourriture commune", de = "Extra für gewöhnliches Futter", it = "Extra per cibo comune", pl = "Dodatek za zwykłe jedzenie",
        pt = "Extra por comida comum", ru = "Бонус за обычную еду", tr = "Sıradan yemek için ek", vi = "Thêm cho thức ăn thường", th = "เพิ่มสำหรับอาหารธรรมดา", id = "Tambahan untuk makanan biasa", ja = "コモンのエサのボーナス", ko = "일반 먹이 보너스", ["zh-hans"] = "普通食物加成", ["zh-hant"] = "普通食物加成",
    },
    set_feed_uncommon = {
        en = "Extra for uncommon food", es = "Extra por comida poco común", fr = "Bonus pour nourriture peu commune", de = "Extra für ungewöhnliches Futter", it = "Extra per cibo non comune", pl = "Dodatek za niezwykłe jedzenie",
        pt = "Extra por comida incomum", ru = "Бонус за необычную еду", tr = "Az bulunan yemek için ek", vi = "Thêm cho thức ăn không phổ biến", th = "เพิ่มสำหรับอาหารไม่ธรรมดา", id = "Tambahan untuk makanan tidak biasa", ja = "アンコモンのエサのボーナス", ko = "고급 먹이 보너스", ["zh-hans"] = "罕见食物加成", ["zh-hant"] = "罕見食物加成",
    },
    set_feed_rare = {
        en = "Extra for rare food", es = "Extra por comida rara", fr = "Bonus pour nourriture rare", de = "Extra für seltenes Futter", it = "Extra per cibo raro", pl = "Dodatek za rzadkie jedzenie",
        pt = "Extra por comida rara", ru = "Бонус за редкую еду", tr = "Nadir yemek için ek", vi = "Thêm cho thức ăn hiếm", th = "เพิ่มสำหรับอาหารหายาก", id = "Tambahan untuk makanan langka", ja = "レアのエサのボーナス", ko = "희귀 먹이 보너스", ["zh-hans"] = "稀有食物加成", ["zh-hant"] = "稀有食物加成",
    },
    set_feed_epic = {
        en = "Extra for epic food", es = "Extra por comida épica", fr = "Bonus pour nourriture épique", de = "Extra für episches Futter", it = "Extra per cibo epico", pl = "Dodatek za epickie jedzenie",
        pt = "Extra por comida épica", ru = "Бонус за эпическую еду", tr = "Destansı yemek için ek", vi = "Thêm cho thức ăn sử thi", th = "เพิ่มสำหรับอาหารระดับเอปิก", id = "Tambahan untuk makanan epik", ja = "エピックのエサのボーナス", ko = "영웅 먹이 보너스", ["zh-hans"] = "史诗食物加成", ["zh-hant"] = "史詩食物加成",
    },
    set_feed_legendary = {
        en = "Extra for legendary food", es = "Extra por comida legendaria", fr = "Bonus pour nourriture légendaire", de = "Extra für legendäres Futter", it = "Extra per cibo leggendario", pl = "Dodatek za legendarne jedzenie",
        pt = "Extra por comida lendária", ru = "Бонус за легендарную еду", tr = "Efsanevi yemek için ek", vi = "Thêm cho thức ăn truyền thuyết", th = "เพิ่มสำหรับอาหารระดับตำนาน", id = "Tambahan untuk makanan legendaris", ja = "レジェンドのエサのボーナス", ko = "전설 먹이 보너스", ["zh-hans"] = "传说食物加成", ["zh-hant"] = "傳說食物加成",
    },

    set_peach_lesser = {
        en = "Little Kinship Peach", es = "Fruta de afecto pequeña (Little Kinship Peach)", fr = "Petit fruit d'affection (Little Kinship Peach)", de = "Kleine Zuneigungsfrucht (Little Kinship Peach)", it = "Piccolo frutto dell'affetto (Little Kinship Peach)", pl = "Mały owoc więzi (Little Kinship Peach)",
        pt = "Fruta de afeto pequena (Little Kinship Peach)", ru = "Малый плод привязанности (Little Kinship Peach)", tr = "Küçük bağ meyvesi (Little Kinship Peach)", vi = "Quả thân thiết nhỏ (Little Kinship Peach)", th = "ผลไม้ความผูกพันเล็ก (Little Kinship Peach)", id = "Buah kasih kecil (Little Kinship Peach)", ja = "小さな絆の実 (Little Kinship Peach)", ko = "작은 유대의 열매 (Little Kinship Peach)", ["zh-hans"] = "小型羁绊果实 (Little Kinship Peach)", ["zh-hant"] = "小型羈絆果實 (Little Kinship Peach)",
    },
    set_peach = {
        en = "Kinship Peach", es = "Fruta de afecto (Kinship Peach)", fr = "Fruit d'affection (Kinship Peach)", de = "Zuneigungsfrucht (Kinship Peach)", it = "Frutto dell'affetto (Kinship Peach)", pl = "Owoc więzi (Kinship Peach)",
        pt = "Fruta de afeto (Kinship Peach)", ru = "Плод привязанности (Kinship Peach)", tr = "Bağ meyvesi (Kinship Peach)", vi = "Quả thân thiết (Kinship Peach)", th = "ผลไม้ความผูกพัน (Kinship Peach)", id = "Buah kasih (Kinship Peach)", ja = "絆の実 (Kinship Peach)", ko = "유대의 열매 (Kinship Peach)", ["zh-hans"] = "羁绊果实 (Kinship Peach)", ["zh-hant"] = "羈絆果實 (Kinship Peach)",
    },
    set_passive = {
        en = "Passive friendship gain while following", es = "Ganancia pasiva de amistad al seguirte", fr = "Gain d'amitié passif en te suivant", de = "Passiver Freundschaftsgewinn beim Folgen", it = "Guadagno passivo di amicizia mentre ti segue", pl = "Pasywny przyrost przyjaźni podczas podążania",
        pt = "Ganho passivo de amizade ao te seguir", ru = "Пассивный рост дружбы, пока Pal следует", tr = "Takip ederken pasif dostluk kazanımı", vi = "Tăng tình bạn thụ động khi đi theo", th = "การเพิ่มมิตรภาพแบบอัตโนมัติขณะเดินตาม", id = "Perolehan persahabatan pasif saat mengikuti", ja = "ついてくる間の受動的な友情値上昇", ko = "따라올 때 수동 우정 상승", ["zh-hans"] = "跟随时的被动友情增长", ["zh-hant"] = "跟隨時的被動友情增加",
    },
    set_join = {
        en = "Friendship when a Pal joins you", es = "Amistad al unirse un Pal", fr = "Amitié quand un Pal te rejoint", de = "Freundschaft beim Beitritt eines Pals", it = "Amicizia quando un Pal si unisce", pl = "Przyjaźń przy dołączeniu Pala",
        pt = "Amizade quando um Pal se junta", ru = "Дружба при присоединении Pal", tr = "Bir Pal katıldığında dostluk", vi = "Tình bạn khi Pal gia nhập", th = "มิตรภาพเมื่อ Pal เข้าร่วม", id = "Persahabatan saat Pal bergabung", ja = "仲間になったときの友情値", ko = "합류할 때의 우정", ["zh-hans"] = "Pal 加入时的友情值", ["zh-hant"] = "Pal 加入時的友情值",
    },
    set_language = {
        en = "Language", es = "Idioma", fr = "Langue", de = "Sprache", it = "Lingua", pl = "Język",
        pt = "Idioma", ru = "Язык", tr = "Dil", vi = "Ngôn ngữ", th = "ภาษา", id = "Bahasa", ja = "言語", ko = "언어", ["zh-hans"] = "语言", ["zh-hant"] = "語言",
    },
    set_tags = {
        en = "Show personality tags", es = "Mostrar etiquetas de personalidad", fr = "Afficher les étiquettes de personnalité", de = "Persönlichkeits-Tags anzeigen", it = "Mostra le etichette di personalità", pl = "Pokaż etykiety osobowości",
        pt = "Mostrar etiquetas de personalidade", ru = "Показывать метки характера", tr = "Kişilik etiketlerini göster", vi = "Hiện thẻ tính cách", th = "แสดงป้ายนิสัย", id = "Tampilkan label kepribadian", ja = "性格タグを表示", ko = "성격 태그 표시", ["zh-hans"] = "显示性格标签", ["zh-hant"] = "顯示性格標籤",
    },
    set_key_play = {
        en = "Play key", es = "Tecla de jugar", fr = "Touche Jouer", de = "Taste für Spielen", it = "Tasto Gioca", pl = "Klawisz zabawy",
        pt = "Tecla de brincar", ru = "Клавиша игры", tr = "Oynama tuşu", vi = "Phím chơi cùng", th = "ปุ่มเล่น", id = "Tombol bermain", ja = "あそぶキー", ko = "놀아주기 키", ["zh-hans"] = "玩耍按键", ["zh-hant"] = "玩耍按鍵",
    },
    set_key_tags = {
        en = "Tags key", es = "Tecla de etiquetas", fr = "Touche Étiquettes", de = "Taste für Tags", it = "Tasto Etichette", pl = "Klawisz etykiet",
        pt = "Tecla de etiquetas", ru = "Клавиша меток", tr = "Etiket tuşu", vi = "Phím thẻ", th = "ปุ่มป้าย", id = "Tombol label", ja = "タグキー", ko = "태그 키", ["zh-hans"] = "标签按键", ["zh-hant"] = "標籤按鍵",
    },
    set_key_passive = {
        en = "Passive trust key", es = "Tecla de confianza pasiva", fr = "Touche confiance passive", de = "Taste für passives Vertrauen", it = "Tasto fiducia passiva", pl = "Klawisz pasywnego zaufania",
        pt = "Tecla de confiança passiva", ru = "Клавиша пассивного доверия", tr = "Pasif güven tuşu", vi = "Phím tin tưởng thụ động", th = "ปุ่มความไว้ใจแบบอัตโนมัติ", id = "Tombol kepercayaan pasif", ja = "受動的な信頼キー", ko = "수동 신뢰 키", ["zh-hans"] = "被动信任按键", ["zh-hant"] = "被動信任按鍵",
    },
    menu_press_key = {
        en = "Press a key", es = "Pulsa una tecla", fr = "Appuie sur une touche", de = "Drücke eine Taste", it = "Premi un tasto", pl = "Naciśnij klawisz",
        pt = "Pressione uma tecla", ru = "Нажми клавишу", tr = "Bir tuşa bas", vi = "Nhấn một phím", th = "กดปุ่ม", id = "Tekan sebuah tombol", ja = "キーを押してください", ko = "키를 누르세요", ["zh-hans"] = "请按一个键", ["zh-hant"] = "請按一個鍵",
    },

    menu_press_key_cancel = {
        en = "Esc to cancel", es = "Esc para cancelar", fr = "Échap pour annuler", de = "Esc zum Abbrechen", it = "Esc per annullare", pl = "Esc, aby anulować",
        pt = "Esc para cancelar", ru = "Esc — отмена", tr = "İptal için Esc", vi = "Esc để hủy", th = "กด Esc เพื่อยกเลิก", id = "Esc untuk membatalkan", ja = "Escでキャンセル", ko = "Esc로 취소", ["zh-hans"] = "按 Esc 取消", ["zh-hant"] = "按 Esc 取消",
    },
    menu_applies_now = {
        en = "Changes apply right away", es = "Los cambios se aplican al instante", fr = "Les changements s'appliquent aussitôt", de = "Änderungen gelten sofort", it = "Le modifiche si applicano subito", pl = "Zmiany działają od razu",
        pt = "As mudanças se aplicam na hora", ru = "Изменения применяются сразу", tr = "Değişiklikler hemen geçerli olur", vi = "Thay đổi áp dụng ngay", th = "การเปลี่ยนแปลงมีผลทันที", id = "Perubahan langsung berlaku", ja = "変更はすぐに反映されます", ko = "변경은 바로 적용됩니다", ["zh-hans"] = "更改立即生效", ["zh-hant"] = "更改立即生效",
    },

    menu_save = {
        en = "Save", es = "Guardar", fr = "Enregistrer", de = "Speichern", it = "Salva", pl = "Zapisz",
        pt = "Salvar", ru = "Сохранить", tr = "Kaydet", vi = "Lưu", th = "บันทึก", id = "Simpan", ja = "保存", ko = "저장", ["zh-hans"] = "保存", ["zh-hant"] = "儲存",
    },
    menu_cancel = {
        en = "Cancel", es = "Cancelar", fr = "Annuler", de = "Abbrechen", it = "Annulla", pl = "Anuluj",
        pt = "Cancelar", ru = "Отмена", tr = "İptal", vi = "Hủy", th = "ยกเลิก", id = "Batal", ja = "キャンセル", ko = "취소", ["zh-hans"] = "取消", ["zh-hant"] = "取消",
    },
    menu_defaults = {
        en = "Restore defaults", es = "Restaurar valores por defecto", fr = "Rétablir les valeurs par défaut", de = "Standardwerte wiederherstellen", it = "Ripristina i valori predefiniti", pl = "Przywróć domyślne",
        pt = "Restaurar padrões", ru = "Сбросить настройки", tr = "Varsayılanlara dön", vi = "Khôi phục mặc định", th = "คืนค่าเริ่มต้น", id = "Kembalikan ke bawaan", ja = "初期値に戻す", ko = "기본값으로 되돌리기", ["zh-hans"] = "恢复默认值", ["zh-hant"] = "恢復預設值",
    },
    menu_auto = {
        en = "Auto", es = "Automático", fr = "Auto", de = "Automatisch", it = "Automatico", pl = "Automatyczny",
        pt = "Automático", ru = "Авто", tr = "Otomatik", vi = "Tự động", th = "อัตโนมัติ", id = "Otomatis", ja = "自動", ko = "자동", ["zh-hans"] = "自动", ["zh-hant"] = "自動",
    },
    menu_saved = {
        en = "Saved", es = "Guardado", fr = "Enregistré", de = "Gespeichert", it = "Salvato", pl = "Zapisano",
        pt = "Salvo", ru = "Сохранено", tr = "Kaydedildi", vi = "Đã lưu", th = "บันทึกแล้ว", id = "Tersimpan", ja = "保存しました", ko = "저장했습니다", ["zh-hans"] = "已保存", ["zh-hant"] = "已儲存",
    },

    sec_accessibility = {
        en = "Accessibility", es = "Accesibilidad", fr = "Accessibilité", de = "Barrierefreiheit", it = "Accessibilità", pl = "Dostępność",
        pt = "Acessibilidade", ru = "Доступность", tr = "Erişilebilirlik", vi = "Trợ năng", th = "การช่วยการเข้าถึง", id = "Aksesibilitas", ja = "アクセシビリティ", ko = "접근성", ["zh-hans"] = "无障碍", ["zh-hant"] = "無障礙",
    },
    set_abandonment = {
        en = "A Pal left behind gives up on you", es = "Un Pal que dejas atrás se rinde contigo", fr = "Un Pal laissé derrière finit par renoncer", de = "Ein zurückgelassener Pal gibt dich auf", it = "Un Pal lasciato indietro rinuncia a te", pl = "Pal zostawiony z tyłu rezygnuje z ciebie",
        pt = "Um Pal deixado para trás desiste de você", ru = "Оставленный позади Pal перестаёт ждать", tr = "Geride bırakılan bir Pal senden vazgeçer", vi = "Pal bị bỏ lại sẽ từ bỏ bạn", th = "Pal ที่ถูกทิ้งไว้จะเลิกรอคุณ", id = "Pal yang ditinggal akan menyerah padamu", ja = "置いていかれたPalはあなたを諦める", ko = "두고 온 Pal은 당신을 포기합니다", ["zh-hans"] = "被留下的 Pal 会放弃你", ["zh-hant"] = "被留下的 Pal 會放棄你",
    },
    set_betrayal = {
        en = "Hitting a Pal can end the bond", es = "Golpear a un Pal puede romper el vínculo", fr = "Frapper un Pal peut briser le lien", de = "Ein Schlag kann die Bindung beenden", it = "Colpire un Pal può spezzare il legame", pl = "Uderzenie Pala może zerwać więź",
        pt = "Bater em um Pal pode romper o vínculo", ru = "Удар может разорвать связь", tr = "Bir Pal'a vurmak bağı koparabilir", vi = "Đánh một Pal có thể phá vỡ mối liên kết", th = "การตี Pal อาจทำให้สายสัมพันธ์ขาด", id = "Memukul Pal bisa memutus ikatan", ja = "Palを叩くと絆が切れることがある", ko = "Pal을 때리면 유대가 끊길 수 있습니다", ["zh-hans"] = "攻击 Pal 可能会断开羁绊", ["zh-hant"] = "攻擊 Pal 可能會斷開羈絆",
    },
    set_bar_color = {
        en = "Friendship bar colour", es = "Color de la barra de amistad", fr = "Couleur de la barre d'amitié", de = "Farbe der Freundschaftsleiste", it = "Colore della barra dell'amicizia", pl = "Kolor paska przyjaźni",
        pt = "Cor da barra de amizade", ru = "Цвет шкалы дружбы", tr = "Dostluk çubuğu rengi", vi = "Màu thanh tình bạn", th = "สีแถบมิตรภาพ", id = "Warna bilah persahabatan", ja = "友情バーの色", ko = "우정 바 색상", ["zh-hans"] = "友情条颜色", ["zh-hant"] = "友情條顏色",
    },
    set_tag_color = {
        en = "Personality tag colour", es = "Color de la etiqueta de personalidad", fr = "Couleur de l'étiquette de personnalité", de = "Farbe des Persönlichkeits-Tags", it = "Colore dell'etichetta di personalità", pl = "Kolor etykiety osobowości",
        pt = "Cor da etiqueta de personalidade", ru = "Цвет метки характера", tr = "Kişilik etiketi rengi", vi = "Màu thẻ tính cách", th = "สีป้ายนิสัย", id = "Warna label kepribadian", ja = "性格タグの色", ko = "성격 태그 색상", ["zh-hans"] = "性格标签颜色", ["zh-hant"] = "性格標籤顏色",
    },
    set_tag_size = {
        en = "Personality tag size", es = "Tamaño de la etiqueta de personalidad", fr = "Taille de l'étiquette de personnalité", de = "Größe des Persönlichkeits-Tags", it = "Dimensione dell'etichetta di personalità", pl = "Rozmiar etykiety osobowości",
        pt = "Tamanho da etiqueta de personalidade", ru = "Размер метки характера", tr = "Kişilik etiketi boyutu", vi = "Cỡ thẻ tính cách", th = "ขนาดป้ายนิสัย", id = "Ukuran label kepribadian", ja = "性格タグの大きさ", ko = "성격 태그 크기", ["zh-hans"] = "性格标签大小", ["zh-hant"] = "性格標籤大小",
    },
    opt_name = {
        en = "Same as the name", es = "Igual que el nombre", fr = "Comme le nom", de = "Wie der Name", it = "Come il nome", pl = "Tak jak nazwa",
        pt = "Igual ao nome", ru = "Как имя", tr = "İsimle aynı", vi = "Giống tên", th = "เหมือนชื่อ", id = "Sama seperti nama", ja = "名前と同じ", ko = "이름과 동일", ["zh-hans"] = "与名称相同", ["zh-hant"] = "與名稱相同",
    },
    opt_gold = {
        en = "Gold", es = "Dorado", fr = "Or", de = "Gold", it = "Oro", pl = "Złoty",
        pt = "Dourado", ru = "Золотой", tr = "Altın", vi = "Vàng kim", th = "ทอง", id = "Emas", ja = "ゴールド", ko = "금색", ["zh-hans"] = "金色", ["zh-hant"] = "金色",
    },
    opt_white = {
        en = "White", es = "Blanco", fr = "Blanc", de = "Weiß", it = "Bianco", pl = "Biały",
        pt = "Branco", ru = "Белый", tr = "Beyaz", vi = "Trắng", th = "ขาว", id = "Putih", ja = "ホワイト", ko = "흰색", ["zh-hans"] = "白色", ["zh-hant"] = "白色",
    },
    opt_red = {
        en = "Red", es = "Rojo", fr = "Rouge", de = "Rot", it = "Rosso", pl = "Czerwony",
        pt = "Vermelho", ru = "Красный", tr = "Kırmızı", vi = "Đỏ", th = "แดง", id = "Merah", ja = "レッド", ko = "빨간색", ["zh-hans"] = "红色", ["zh-hant"] = "紅色",
    },
    opt_green = {
        en = "Green", es = "Verde", fr = "Vert", de = "Grün", it = "Verde", pl = "Zielony",
        pt = "Verde", ru = "Зелёный", tr = "Yeşil", vi = "Xanh lá", th = "เขียว", id = "Hijau", ja = "グリーン", ko = "초록색", ["zh-hans"] = "绿色", ["zh-hant"] = "綠色",
    },
    opt_blue = {
        en = "Blue", es = "Azul", fr = "Bleu", de = "Blau", it = "Blu", pl = "Niebieski",
        pt = "Azul", ru = "Синий", tr = "Mavi", vi = "Xanh dương", th = "น้ำเงิน", id = "Biru", ja = "ブルー", ko = "파란색", ["zh-hans"] = "蓝色", ["zh-hant"] = "藍色",
    },
    opt_purple = {
        en = "Purple", es = "Morado", fr = "Violet", de = "Lila", it = "Viola", pl = "Fioletowy",
        pt = "Roxo", ru = "Фиолетовый", tr = "Mor", vi = "Tím", th = "ม่วง", id = "Ungu", ja = "パープル", ko = "보라색", ["zh-hans"] = "紫色", ["zh-hant"] = "紫色",
    },
    opt_small = {
        en = "Small", es = "Pequeño", fr = "Petite", de = "Klein", it = "Piccola", pl = "Mała",
        pt = "Pequeno", ru = "Маленький", tr = "Küçük", vi = "Nhỏ", th = "เล็ก", id = "Kecil", ja = "小", ko = "작게", ["zh-hans"] = "小", ["zh-hant"] = "小",
    },
    opt_normal = {
        en = "Normal", es = "Normal", fr = "Normale", de = "Normal", it = "Normale", pl = "Normalna",
        pt = "Normal", ru = "Обычный", tr = "Normal", vi = "Bình thường", th = "ปกติ", id = "Normal", ja = "標準", ko = "보통", ["zh-hans"] = "标准", ["zh-hant"] = "標準",
    },
    opt_large = {
        en = "Large", es = "Grande", fr = "Grande", de = "Groß", it = "Grande", pl = "Duża",
        pt = "Grande", ru = "Большой", tr = "Büyük", vi = "Lớn", th = "ใหญ่", id = "Besar", ja = "大", ko = "크게", ["zh-hans"] = "大", ["zh-hant"] = "大",
    },
    opt_huge = {
        en = "Very large", es = "Muy grande", fr = "Très grande", de = "Sehr groß", it = "Molto grande", pl = "Bardzo duża",
        pt = "Muito grande", ru = "Очень большой", tr = "Çok büyük", vi = "Rất lớn", th = "ใหญ่มาก", id = "Sangat besar", ja = "特大", ko = "아주 크게", ["zh-hans"] = "特大", ["zh-hant"] = "特大",
    },

    set_bondable = {
        en = "can be bonded", es = "puede vincularse", fr = "peut se lier", de = "kann sich binden", it = "può legarsi", pl = "może się związać",
        pt = "pode se vincular", ru = "может подружиться", tr = "bağ kurabilir", vi = "có thể kết bạn", th = "ผูกพันได้", id = "bisa menjalin ikatan", ja = "絆を結べる", ko = "유대를 맺을 수 있음", ["zh-hans"] = "可以建立羁绊", ["zh-hant"] = "可以建立羈絆",
    },

    set_passive_enabled = {
        en = "Passive friendship gain", es = "Ganancia pasiva de amistad", fr = "Gain d'amitié passif", de = "Passiver Freundschaftsgewinn", it = "Guadagno passivo di amicizia", pl = "Pasywny przyrost przyjaźni",
        pt = "Ganho passivo de amizade", ru = "Пассивный рост дружбы", tr = "Pasif dostluk kazanımı", vi = "Tăng tình bạn thụ động", th = "การเพิ่มมิตรภาพแบบอัตโนมัติ", id = "Perolehan persahabatan pasif", ja = "受動的な友情値の上昇", ko = "수동 우정 상승", ["zh-hans"] = "被动友情增长", ["zh-hant"] = "被動友情增加",
    },
}
Locale.STRINGS = S

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

function Locale.T(key, vars)
    local entry = S[key]
    if entry == nil then return key end
    local text = entry[Locale.Current()] or entry.en

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
