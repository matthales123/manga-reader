from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from urllib import parse, request

from .library import MangaLibrary, MangaNotFoundError

RawArc = dict[str, object]
CHAPTER_BUCKET_SIZE = 25
WIKIPEDIA_API_ENDPOINT = "https://en.wikipedia.org/w/api.php"


TITLE_ALIASES: dict[str, str] = {
    "one piece": "one_piece",
    "attack on titan": "attack_on_titan",
    "shingeki no kyojin": "attack_on_titan",
    "demon slayer": "demon_slayer",
    "kimetsu no yaiba": "demon_slayer",
    "demon slayer kimetsu no yaiba": "demon_slayer",
    "kimetsu no yaiba demon slayer": "demon_slayer",
    "bleach": "bleach",
    "bleach color": "bleach",
    "chainsaw man": "chainsaw_man",
    "dandadan": "dandadan",
    "fire force": "fire_force",
    "frieren": "frieren",
    "frieren beyond journey s end": "frieren",
    "jujutsu kaisen": "jujutsu_kaisen",
    "one punch man": "one_punch_man",
    "sakamoto days": "sakamoto_days",
    "soul eater": "soul_eater",
    "gachiakuta": "gachiakuta",
    "chillin in another world with level 2 super cheat powers": "chillin_level2",
    "ore no level up ga okashi dekiru otoko no isekai tensei": "ore_no_level_up",
    "sword art online aincrad": "sao_aincrad",
    "sword art online fairy dance": "sao_fairy_dance",
    "sword art online phantom bullet": "sao_phantom_bullet",
    "sword art online mother s rosary": "sao_mothers_rosary",
    "sword art online ordinal scale": "sao_ordinal_scale",
    "sword art online lycoris": "sao_lycoris",
    "black clover": "black_clover",
    "fullmetal alchemist": "fullmetal_alchemist",
    "gosick": "gosick",
    "konosuba god s blessing on this wonderful world": "konosuba",
    "solo leveling": "solo_leveling",
    "the beginning after the end": "the_beginning_after_the_end",
}


BUILTIN_ARCS: dict[str, list[RawArc]] = {
    "attack_on_titan": [
        {"id": "aot-fall-of-shiganshina", "name": "Fall of Shiganshina Arc", "start_chapter": 1, "end_chapter": 2, "order": 1},
        {"id": "aot-trost", "name": "Trost Arc", "start_chapter": 3, "end_chapter": 14, "order": 2},
        {"id": "aot-female-titan", "name": "Female Titan Arc", "start_chapter": 15, "end_chapter": 34, "order": 3},
        {"id": "aot-clash-of-the-titans", "name": "Clash of the Titans Arc", "start_chapter": 35, "end_chapter": 50, "order": 4},
        {"id": "aot-uprising", "name": "Uprising Arc", "start_chapter": 51, "end_chapter": 70, "order": 5},
        {"id": "aot-return-to-shiganshina", "name": "Return to Shiganshina Arc", "start_chapter": 71, "end_chapter": 90, "order": 6},
        {"id": "aot-marley", "name": "Marley Arc", "start_chapter": 91, "end_chapter": 106, "order": 7},
        {"id": "aot-war-for-paradis", "name": "War for Paradis Arc", "start_chapter": 107, "end_chapter": 139, "order": 8},
    ],
    "demon_slayer": [
        {"id": "ds-final-selection", "name": "Final Selection Arc", "start_chapter": 1, "end_chapter": 9, "order": 1},
        {"id": "ds-kidnappers-bog", "name": "Kidnapper's Bog Arc", "start_chapter": 10, "end_chapter": 13, "order": 2},
        {"id": "ds-asakusa", "name": "Asakusa Arc", "start_chapter": 14, "end_chapter": 19, "order": 3},
        {"id": "ds-tsuzumi-mansion", "name": "Tsuzumi Mansion Arc", "start_chapter": 20, "end_chapter": 27, "order": 4},
        {"id": "ds-natagumo-mountain", "name": "Natagumo Mountain Arc", "start_chapter": 28, "end_chapter": 44, "order": 5},
        {"id": "ds-rehabilitation-training", "name": "Rehabilitation Training Arc", "start_chapter": 45, "end_chapter": 53, "order": 6},
        {"id": "ds-mugen-train", "name": "Mugen Train Arc", "start_chapter": 54, "end_chapter": 66, "order": 7},
        {"id": "ds-entertainment-district", "name": "Entertainment District Arc", "start_chapter": 67, "end_chapter": 97, "order": 8},
        {"id": "ds-swordsmith-village", "name": "Swordsmith Village Arc", "start_chapter": 98, "end_chapter": 127, "order": 9},
        {"id": "ds-hashira-training", "name": "Hashira Training Arc", "start_chapter": 128, "end_chapter": 136, "order": 10},
        {"id": "ds-infinity-castle", "name": "Infinity Castle Arc", "start_chapter": 137, "end_chapter": 183, "order": 11},
        {"id": "ds-sunrise-countdown", "name": "Sunrise Countdown Arc", "start_chapter": 184, "end_chapter": 205, "order": 12},
    ],
    "one_piece": [
        {"id": "op-romance-dawn", "name": "Romance Dawn Arc", "start_chapter": 1, "end_chapter": 7, "order": 1},
        {"id": "op-orange-town", "name": "Orange Town Arc", "start_chapter": 8, "end_chapter": 21, "order": 2},
        {"id": "op-syrup-village", "name": "Syrup Village Arc", "start_chapter": 22, "end_chapter": 41, "order": 3},
        {"id": "op-baratie", "name": "Baratie Arc", "start_chapter": 42, "end_chapter": 68, "order": 4},
        {"id": "op-arlong-park", "name": "Arlong Park Arc", "start_chapter": 69, "end_chapter": 95, "order": 5},
        {"id": "op-loguetown", "name": "Loguetown Arc", "start_chapter": 96, "end_chapter": 100, "order": 6},
        {"id": "op-reverse-mountain", "name": "Reverse Mountain Arc", "start_chapter": 101, "end_chapter": 105, "order": 7},
        {"id": "op-whiskey-peak", "name": "Whiskey Peak Arc", "start_chapter": 106, "end_chapter": 114, "order": 8},
        {"id": "op-little-garden", "name": "Little Garden Arc", "start_chapter": 115, "end_chapter": 129, "order": 9},
        {"id": "op-drum-island", "name": "Drum Island Arc", "start_chapter": 130, "end_chapter": 154, "order": 10},
        {"id": "op-alabasta", "name": "Alabasta Arc", "start_chapter": 155, "end_chapter": 217, "order": 11},
        {"id": "op-jaya", "name": "Jaya Arc", "start_chapter": 218, "end_chapter": 236, "order": 12},
        {"id": "op-skypiea", "name": "Skypiea Arc", "start_chapter": 237, "end_chapter": 302, "order": 13},
        {"id": "op-long-ring-long-land", "name": "Long Ring Long Land Arc", "start_chapter": 303, "end_chapter": 321, "order": 14},
        {"id": "op-water-7", "name": "Water 7 Arc", "start_chapter": 322, "end_chapter": 374, "order": 15},
        {"id": "op-enies-lobby", "name": "Enies Lobby Arc", "start_chapter": 375, "end_chapter": 430, "order": 16},
        {"id": "op-post-enies-lobby", "name": "Post-Enies Lobby Arc", "start_chapter": 431, "end_chapter": 441, "order": 17},
        {"id": "op-thriller-bark", "name": "Thriller Bark Arc", "start_chapter": 442, "end_chapter": 489, "order": 18},
        {"id": "op-sabaody-archipelago", "name": "Sabaody Archipelago Arc", "start_chapter": 490, "end_chapter": 513, "order": 19},
        {"id": "op-amazon-lily", "name": "Amazon Lily Arc", "start_chapter": 514, "end_chapter": 524, "order": 20},
        {"id": "op-impel-down", "name": "Impel Down Arc", "start_chapter": 525, "end_chapter": 549, "order": 21},
        {"id": "op-marineford", "name": "Marineford Arc", "start_chapter": 550, "end_chapter": 580, "order": 22},
        {"id": "op-post-war", "name": "Post-War Arc", "start_chapter": 581, "end_chapter": 597, "order": 23},
        {"id": "op-return-to-sabaody", "name": "Return to Sabaody Arc", "start_chapter": 598, "end_chapter": 602, "order": 24},
        {"id": "op-fish-man-island", "name": "Fish-Man Island Arc", "start_chapter": 603, "end_chapter": 653, "order": 25},
        {"id": "op-punk-hazard", "name": "Punk Hazard Arc", "start_chapter": 654, "end_chapter": 699, "order": 26},
        {"id": "op-dressrosa", "name": "Dressrosa Arc", "start_chapter": 700, "end_chapter": 801, "order": 27},
        {"id": "op-zou", "name": "Zou Arc", "start_chapter": 802, "end_chapter": 824, "order": 28},
        {"id": "op-whole-cake-island", "name": "Whole Cake Island Arc", "start_chapter": 825, "end_chapter": 902, "order": 29},
        {"id": "op-reverie", "name": "Reverie Arc", "start_chapter": 903, "end_chapter": 908, "order": 30},
        {"id": "op-wano-country", "name": "Wano Country Arc", "start_chapter": 909, "end_chapter": 1057, "order": 31},
        {"id": "op-egghead", "name": "Egghead Arc", "start_chapter": 1058, "end_chapter": None, "order": 32},
    ],
    "bleach": [
        {"id": "bleach-substitute-shinigami", "name": "Substitute Shinigami Arc", "start_chapter": 1, "end_chapter": 70, "order": 1},
        {"id": "bleach-soul-society", "name": "Soul Society Arc", "start_chapter": 71, "end_chapter": 182, "order": 2},
        {"id": "bleach-arrancar", "name": "Arrancar Arc", "start_chapter": 183, "end_chapter": 423, "order": 3},
        {"id": "bleach-lost-agent", "name": "Lost Agent Arc", "start_chapter": 424, "end_chapter": 479, "order": 4},
        {"id": "bleach-thousand-year-blood-war", "name": "Thousand-Year Blood War Arc", "start_chapter": 480, "end_chapter": 686, "order": 5},
    ],
    "chainsaw_man": [
        {"id": "csm-introduction", "name": "Introduction Arc", "start_chapter": 1, "end_chapter": 4, "order": 1},
        {"id": "csm-bat-devil", "name": "Bat Devil Arc", "start_chapter": 5, "end_chapter": 12, "order": 2},
        {"id": "csm-eternity-devil", "name": "Eternity Devil Arc", "start_chapter": 13, "end_chapter": 21, "order": 3},
        {"id": "csm-katana-man", "name": "Katana Man Arc", "start_chapter": 22, "end_chapter": 39, "order": 4},
        {"id": "csm-bomb-girl", "name": "Bomb Girl Arc", "start_chapter": 40, "end_chapter": 52, "order": 5},
        {"id": "csm-international-assassins", "name": "International Assassins Arc", "start_chapter": 53, "end_chapter": 70, "order": 6},
        {"id": "csm-gun-devil", "name": "Gun Devil Arc", "start_chapter": 71, "end_chapter": 79, "order": 7},
        {"id": "csm-control-devil", "name": "Control Devil Arc", "start_chapter": 80, "end_chapter": 97, "order": 8},
        {"id": "csm-academy-saga", "name": "Academy Saga", "start_chapter": 98, "end_chapter": None, "order": 9},
    ],
    "dandadan": [
        {"id": "dnd-turbo-granny", "name": "Turbo Granny Arc", "start_chapter": 1, "end_chapter": 8, "order": 1},
        {"id": "dnd-acrobatic-silky", "name": "Acrobatic Silky Arc", "start_chapter": 9, "end_chapter": 17, "order": 2},
        {"id": "dnd-cursed-house", "name": "Cursed House Arc", "start_chapter": 18, "end_chapter": 50, "order": 3},
        {"id": "dnd-evil-eye", "name": "Evil Eye Arc", "start_chapter": 51, "end_chapter": 63, "order": 4},
        {"id": "dnd-kaiju", "name": "Kaiju Arc", "start_chapter": 64, "end_chapter": 73, "order": 5},
        {"id": "dnd-space-globalists", "name": "Space Globalists Arc", "start_chapter": 74, "end_chapter": 120, "order": 6},
        {"id": "dnd-danmara", "name": "Danmara Arc", "start_chapter": 121, "end_chapter": 165, "order": 7},
        {"id": "dnd-current", "name": "Current Arc", "start_chapter": 166, "end_chapter": None, "order": 8},
    ],
    "fire_force": [
        {"id": "ff-introduction", "name": "Introduction Arc", "start_chapter": 1, "end_chapter": 3, "order": 1},
        {"id": "ff-company-5", "name": "Company 5 Arc", "start_chapter": 4, "end_chapter": 10, "order": 2},
        {"id": "ff-company-1", "name": "Company 1 Arc", "start_chapter": 11, "end_chapter": 20, "order": 3},
        {"id": "ff-asakusa", "name": "Asakusa Arc", "start_chapter": 21, "end_chapter": 33, "order": 4},
        {"id": "ff-netherworld", "name": "Netherworld Arc", "start_chapter": 34, "end_chapter": 49, "order": 5},
        {"id": "ff-fifth-pillar", "name": "Fifth Pillar Arc", "start_chapter": 50, "end_chapter": 63, "order": 6},
        {"id": "ff-chinese-peninsula", "name": "Chinese Peninsula Arc", "start_chapter": 64, "end_chapter": 90, "order": 7},
        {"id": "ff-joint-investigation", "name": "Joint Investigation Arc", "start_chapter": 91, "end_chapter": 106, "order": 8},
        {"id": "ff-obis-rescue", "name": "Obi's Rescue Arc", "start_chapter": 107, "end_chapter": 138, "order": 9},
        {"id": "ff-stone-pillars", "name": "Stone Pillars Arc", "start_chapter": 139, "end_chapter": 174, "order": 10},
        {"id": "ff-stigma", "name": "Stigma Arc", "start_chapter": 175, "end_chapter": 197, "order": 11},
        {"id": "ff-final-pillar", "name": "Final Pillar Arc", "start_chapter": 198, "end_chapter": 239, "order": 12},
        {"id": "ff-great-cataclysm", "name": "Great Cataclysm Arc", "start_chapter": 240, "end_chapter": 304, "order": 13},
    ],
    "frieren": [
        {"id": "frieren-journeys-epilogue", "name": "Journey's Epilogue Arc", "start_chapter": 1, "end_chapter": 24, "order": 1},
        {"id": "frieren-aura-the-guillotine", "name": "Aura the Guillotine Arc", "start_chapter": 25, "end_chapter": 35, "order": 2},
        {"id": "frieren-first-class-mage-exam", "name": "First-Class Mage Exam Arc", "start_chapter": 36, "end_chapter": 60, "order": 3},
        {"id": "frieren-northern-expedition", "name": "Northern Expedition Arc", "start_chapter": 61, "end_chapter": 104, "order": 4},
        {"id": "frieren-golden-land", "name": "Golden Land Arc", "start_chapter": 105, "end_chapter": 124, "order": 5},
        {"id": "frieren-goddess-monument", "name": "Goddess Monument Arc", "start_chapter": 125, "end_chapter": None, "order": 6},
    ],
    "jujutsu_kaisen": [
        {"id": "jjk-fearsome-womb", "name": "Fearsome Womb Arc", "start_chapter": 1, "end_chapter": 9, "order": 1},
        {"id": "jjk-vs-mahito", "name": "Vs. Mahito Arc", "start_chapter": 10, "end_chapter": 31, "order": 2},
        {"id": "jjk-kyoto-goodwill-event", "name": "Kyoto Goodwill Event Arc", "start_chapter": 32, "end_chapter": 54, "order": 3},
        {"id": "jjk-death-painting", "name": "Death Painting Arc", "start_chapter": 55, "end_chapter": 64, "order": 4},
        {"id": "jjk-gojos-past", "name": "Gojo's Past Arc", "start_chapter": 65, "end_chapter": 79, "order": 5},
        {"id": "jjk-shibuya-incident", "name": "Shibuya Incident Arc", "start_chapter": 80, "end_chapter": 136, "order": 6},
        {"id": "jjk-itadoris-extermination", "name": "Itadori's Extermination Arc", "start_chapter": 137, "end_chapter": 143, "order": 7},
        {"id": "jjk-perfect-preparation", "name": "Perfect Preparation Arc", "start_chapter": 144, "end_chapter": 158, "order": 8},
        {"id": "jjk-culling-game", "name": "Culling Game Arc", "start_chapter": 159, "end_chapter": 221, "order": 9},
        {"id": "jjk-shinjuku-showdown", "name": "Shinjuku Showdown Arc", "start_chapter": 222, "end_chapter": 271, "order": 10},
    ],
    "one_punch_man": [
        {"id": "opm-introduction", "name": "Introduction Arc", "start_chapter": 1, "end_chapter": 7, "order": 1},
        {"id": "opm-house-of-evolution", "name": "House of Evolution Arc", "start_chapter": 8, "end_chapter": 11, "order": 2},
        {"id": "opm-paradise-group", "name": "Paradise Group Arc", "start_chapter": 12, "end_chapter": 15, "order": 3},
        {"id": "opm-deep-sea-king", "name": "Deep Sea King Arc", "start_chapter": 16, "end_chapter": 28, "order": 4},
        {"id": "opm-dark-matter-thieves", "name": "Dark Matter Thieves Arc", "start_chapter": 29, "end_chapter": 37, "order": 5},
        {"id": "opm-hero-hunt", "name": "Hero Hunt Arc", "start_chapter": 38, "end_chapter": 84, "order": 6},
        {"id": "opm-monster-association", "name": "Monster Association Arc", "start_chapter": 85, "end_chapter": 170, "order": 7},
        {"id": "opm-psychic-sisters", "name": "Psychic Sisters Arc", "start_chapter": 171, "end_chapter": 185, "order": 8},
        {"id": "opm-neo-heroes", "name": "Neo Heroes Arc", "start_chapter": 186, "end_chapter": None, "order": 9},
    ],
    "sakamoto_days": [
        {"id": "sd-introduction", "name": "Introduction Arc", "start_chapter": 1, "end_chapter": 13, "order": 1},
        {"id": "sd-lab", "name": "Lab Arc", "start_chapter": 14, "end_chapter": 31, "order": 2},
        {"id": "sd-death-row-prisoners", "name": "Death Row Prisoners Arc", "start_chapter": 32, "end_chapter": 55, "order": 3},
        {"id": "sd-jcc-transfer-exam", "name": "JCC Transfer Exam Arc", "start_chapter": 56, "end_chapter": 73, "order": 4},
        {"id": "sd-bangkok", "name": "Bangkok Arc", "start_chapter": 74, "end_chapter": 104, "order": 5},
        {"id": "sd-jaa-infiltration", "name": "JAA Infiltration Arc", "start_chapter": 105, "end_chapter": 137, "order": 6},
        {"id": "sd-assassin-exhibition", "name": "Assassin Exhibition Arc", "start_chapter": 138, "end_chapter": 168, "order": 7},
        {"id": "sd-jaa-headquarters", "name": "JAA Headquarters Arc", "start_chapter": 169, "end_chapter": 204, "order": 8},
        {"id": "sd-current", "name": "Current Arc", "start_chapter": 205, "end_chapter": None, "order": 9},
    ],
    "soul_eater": [
        {"id": "se-introduction", "name": "Introduction Arc", "start_chapter": 1, "end_chapter": 10, "order": 1},
        {"id": "se-medusa", "name": "Medusa Arc", "start_chapter": 11, "end_chapter": 21, "order": 2},
        {"id": "se-baba-yaga-castle", "name": "Baba Yaga Castle Arc", "start_chapter": 22, "end_chapter": 37, "order": 3},
        {"id": "se-arachnophobia", "name": "Arachnophobia Arc", "start_chapter": 38, "end_chapter": 61, "order": 4},
        {"id": "se-brew", "name": "Brew Arc", "start_chapter": 62, "end_chapter": 84, "order": 5},
        {"id": "se-book-of-eibon", "name": "Book of Eibon Arc", "start_chapter": 85, "end_chapter": 97, "order": 6},
        {"id": "se-final-battle", "name": "Final Battle Arc", "start_chapter": 98, "end_chapter": 113, "order": 7},
    ],
    "gachiakuta": [
        {"id": "gk-opening", "name": "Opening Arc", "start_chapter": 1, "end_chapter": 27, "order": 1},
        {"id": "gk-cleaners", "name": "Cleaners Arc", "start_chapter": 28, "end_chapter": 58, "order": 2},
        {"id": "gk-raiders", "name": "Raiders Arc", "start_chapter": 59, "end_chapter": 96, "order": 3},
        {"id": "gk-watchman", "name": "Watchman Arc", "start_chapter": 97, "end_chapter": 133, "order": 4},
        {"id": "gk-current", "name": "Current Arc", "start_chapter": 134, "end_chapter": None, "order": 5},
    ],
    "chillin_level2": [
        {"id": "lvl2-opening", "name": "Opening Arc", "start_chapter": 1, "end_chapter": 20, "order": 1},
        {"id": "lvl2-kingdom", "name": "Kingdom Arc", "start_chapter": 21, "end_chapter": 45, "order": 2},
        {"id": "lvl2-demon-realm", "name": "Demon Realm Arc", "start_chapter": 46, "end_chapter": None, "order": 3},
    ],
    "ore_no_level_up": [
        {"id": "onlu-awakening", "name": "Awakening Arc", "start_chapter": 1, "end_chapter": 12, "order": 1},
        {"id": "onlu-isekai-adventure", "name": "Isekai Adventure Arc", "start_chapter": 13, "end_chapter": 24, "order": 2},
        {"id": "onlu-frontier", "name": "Frontier Arc", "start_chapter": 25, "end_chapter": None, "order": 3},
    ],
    "sao_aincrad": [
        {"id": "sao-aincrad", "name": "Aincrad Arc", "start_chapter": 1, "end_chapter": 12, "order": 1},
    ],
    "sao_fairy_dance": [
        {"id": "sao-fairy-dance", "name": "Fairy Dance Arc", "start_chapter": 1, "end_chapter": 14, "order": 1},
    ],
    "sao_phantom_bullet": [
        {"id": "sao-phantom-bullet", "name": "Phantom Bullet Arc", "start_chapter": 1, "end_chapter": 20, "order": 1},
    ],
    "sao_mothers_rosary": [
        {"id": "sao-mothers-rosary", "name": "Mother's Rosary Arc", "start_chapter": 1, "end_chapter": 13, "order": 1},
    ],
    "sao_ordinal_scale": [
        {"id": "sao-ordinal-scale", "name": "Ordinal Scale Arc", "start_chapter": 1, "end_chapter": 17.6, "order": 1},
    ],
    "sao_lycoris": [
        {"id": "sao-lycoris", "name": "Lycoris Arc", "start_chapter": 1, "end_chapter": 16, "order": 1},
    ],
    "black_clover": [
        {"id": "bc-magic-knights-exam", "name": "Magic Knights Entrance Exam Arc", "start_chapter": 1, "end_chapter": 10, "order": 1},
        {"id": "bc-dungeon-exploration", "name": "Dungeon Exploration Arc", "start_chapter": 11, "end_chapter": 21, "order": 2},
        {"id": "bc-royal-capital-assault", "name": "Royal Capital Assault Arc", "start_chapter": 22, "end_chapter": 37, "order": 3},
        {"id": "bc-eye-of-midnight-sun", "name": "Eye of the Midnight Sun Arc", "start_chapter": 38, "end_chapter": 56, "order": 4},
        {"id": "bc-seabed-temple", "name": "Seabed Temple Arc", "start_chapter": 57, "end_chapter": 74, "order": 5},
        {"id": "bc-witches-forest", "name": "Witches' Forest Arc", "start_chapter": 75, "end_chapter": 101, "order": 6},
        {"id": "bc-royal-knights", "name": "Royal Knights Arc", "start_chapter": 102, "end_chapter": 149, "order": 7},
        {"id": "bc-elf-reincarnation", "name": "Elf Reincarnation Arc", "start_chapter": 150, "end_chapter": 228, "order": 8},
        {"id": "bc-heart-kingdom", "name": "Heart Kingdom Joint Struggle Arc", "start_chapter": 229, "end_chapter": 260, "order": 9},
        {"id": "bc-spade-kingdom-raid", "name": "Spade Kingdom Raid Arc", "start_chapter": 261, "end_chapter": 331, "order": 10},
        {"id": "bc-final-wizard-king", "name": "Final Wizard King Arc", "start_chapter": 332, "end_chapter": None, "order": 11},
    ],
    "fullmetal_alchemist": [
        {"id": "fma-city-of-heresy", "name": "City of Heresy Arc", "start_chapter": 1, "end_chapter": 4, "order": 1},
        {"id": "fma-battle-on-the-train", "name": "Battle on the Train Arc", "start_chapter": 5, "end_chapter": 9, "order": 2},
        {"id": "fma-laboratory-5", "name": "Laboratory 5 Arc", "start_chapter": 10, "end_chapter": 18, "order": 3},
        {"id": "fma-dublith", "name": "Dublith Arc", "start_chapter": 19, "end_chapter": 31, "order": 4},
        {"id": "fma-hughes-investigation", "name": "Hughes Investigation Arc", "start_chapter": 32, "end_chapter": 35, "order": 5},
        {"id": "fma-rush-valley", "name": "Rush Valley Arc", "start_chapter": 36, "end_chapter": 39, "order": 6},
        {"id": "fma-devils-nest", "name": "Devil's Nest Arc", "start_chapter": 40, "end_chapter": 52, "order": 7},
        {"id": "fma-briggs-fortress", "name": "Briggs Fortress Arc", "start_chapter": 53, "end_chapter": 64, "order": 8},
        {"id": "fma-promised-day", "name": "Promised Day Arc", "start_chapter": 65, "end_chapter": 108.5, "order": 9},
    ],
    "gosick": [
        {"id": "gosick-black-reaper", "name": "Black Reaper Arc", "start_chapter": 1, "end_chapter": 7, "order": 1},
        {"id": "gosick-queen-berry", "name": "Queen Berry Arc", "start_chapter": 8, "end_chapter": 14, "order": 2},
        {"id": "gosick-gray-wolf-village", "name": "Gray Wolf Village Arc", "start_chapter": 15, "end_chapter": 21, "order": 3},
        {"id": "gosick-summer-solstice", "name": "Summer Solstice Arc", "start_chapter": 22, "end_chapter": 28, "order": 4},
    ],
    "konosuba": [
        {"id": "kono-axel", "name": "Arrival in Axel Arc", "start_chapter": 1, "end_chapter": 8, "order": 1},
        {"id": "kono-kyouya", "name": "Kyouya Arc", "start_chapter": 9, "end_chapter": 20, "order": 2},
        {"id": "kono-destroyer", "name": "Destroyer Arc", "start_chapter": 21, "end_chapter": 33, "order": 3},
        {"id": "kono-wiz-vanir", "name": "Wiz and Vanir Arc", "start_chapter": 34, "end_chapter": 47, "order": 4},
        {"id": "kono-crimson-magic", "name": "Crimson Magic Clan Arc", "start_chapter": 48, "end_chapter": 71, "order": 5},
        {"id": "kono-alcanretia", "name": "Alcanretia Arc", "start_chapter": 72, "end_chapter": 95, "order": 6},
        {"id": "kono-royal-capital", "name": "Royal Capital Arc", "start_chapter": 96, "end_chapter": 114, "order": 7},
        {"id": "kono-current", "name": "Current Arc", "start_chapter": 115, "end_chapter": None, "order": 8},
    ],
    "solo_leveling": [
        {"id": "sl-d-rank-dungeon", "name": "D-Rank Dungeon Arc", "start_chapter": 1, "end_chapter": 10, "order": 1},
        {"id": "sl-reawakening", "name": "Reawakening Arc", "start_chapter": 11, "end_chapter": 17, "order": 2},
        {"id": "sl-instant-dungeon", "name": "Instant Dungeon Arc", "start_chapter": 18, "end_chapter": 24, "order": 3},
        {"id": "sl-job-change", "name": "Job Change Arc", "start_chapter": 25, "end_chapter": 45, "order": 4},
        {"id": "sl-red-gate", "name": "Red Gate Arc", "start_chapter": 46, "end_chapter": 55, "order": 5},
        {"id": "sl-demon-castle", "name": "Demon Castle Arc", "start_chapter": 56, "end_chapter": 75, "order": 6},
        {"id": "sl-retesting-rank", "name": "Retesting Rank Arc", "start_chapter": 76, "end_chapter": 85, "order": 7},
        {"id": "sl-hunters-guild-gate", "name": "Hunters Guild Gate Arc", "start_chapter": 86, "end_chapter": 100, "order": 8},
        {"id": "sl-jeju-island", "name": "Jeju Island Arc", "start_chapter": 101, "end_chapter": 110, "order": 9},
        {"id": "sl-recruitment", "name": "Recruitment Arc", "start_chapter": 111, "end_chapter": 131, "order": 10},
        {"id": "sl-double-dungeon", "name": "Double Dungeon Arc", "start_chapter": 132, "end_chapter": 139, "order": 11},
        {"id": "sl-japan-crisis", "name": "Japan Crisis Arc", "start_chapter": 140, "end_chapter": 149, "order": 12},
        {"id": "sl-international-guild", "name": "International Guild Conference Arc", "start_chapter": 150, "end_chapter": 166, "order": 13},
        {"id": "sl-monarchs-war", "name": "Monarchs War Arc", "start_chapter": 167, "end_chapter": 177, "order": 14},
        {"id": "sl-final-battle", "name": "Final Battle Arc", "start_chapter": 178, "end_chapter": 200, "order": 15},
    ],
    "the_beginning_after_the_end": [
        {"id": "tbate-reincarnation", "name": "King Grey's Reincarnation Arc", "start_chapter": 1, "end_chapter": 10, "order": 1},
        {"id": "tbate-twin-horns", "name": "Twin Horns Arc", "start_chapter": 11, "end_chapter": 24, "order": 2},
        {"id": "tbate-xyrus-academy", "name": "Xyrus Academy Arc", "start_chapter": 25, "end_chapter": 53, "order": 3},
        {"id": "tbate-lucas-wykes", "name": "Lucas Wykes Arc", "start_chapter": 54, "end_chapter": 74, "order": 4},
        {"id": "tbate-adventurer", "name": "Adventurer Arc", "start_chapter": 75, "end_chapter": 98, "order": 5},
        {"id": "tbate-war", "name": "Dicathen War Arc", "start_chapter": 99, "end_chapter": 138, "order": 6},
        {"id": "tbate-relictombs", "name": "Relictombs Arc", "start_chapter": 139, "end_chapter": 174, "order": 7},
        {"id": "tbate-victoriad", "name": "Victoriad Arc", "start_chapter": 175, "end_chapter": 207, "order": 8},
        {"id": "tbate-current", "name": "Current Arc", "start_chapter": 208, "end_chapter": None, "order": 9},
    ],
}


class ArcExternalResolver:
    """Best-effort external arc resolver using Wikipedia search + plaintext extract parsing."""

    ARC_LINE_PATTERNS = [
        re.compile(
            r"(?P<name>[A-Z][A-Za-z0-9'’:\- ,/]+?(?:Arc|Saga|Part))\s*"
            r"\((?:chapters?|chapter|ch\.?)\s*"
            r"(?P<start>\d+(?:\.\d+)?)\s*(?:-|–|—|to)\s*(?P<end>\d+(?:\.\d+)?)\)",
            flags=re.IGNORECASE,
        ),
        re.compile(
            r"(?P<name>[A-Z][A-Za-z0-9'’:\- ,/]+?(?:Arc|Saga|Part))[^\n]{0,100}?"
            r"(?:chapters?|chapter|ch\.?)\s*(?P<start>\d+(?:\.\d+)?)\s*(?:-|–|—|to)\s*(?P<end>\d+(?:\.\d+)?)",
            flags=re.IGNORECASE,
        ),
    ]

    def __init__(
        self,
        *,
        enabled: bool = False,
        timeout_seconds: float = 8.0,
        max_search_results: int = 5,
    ) -> None:
        self.enabled = enabled
        self.timeout_seconds = timeout_seconds
        self.max_search_results = max(1, max_search_results)

    def resolve(self, series_title: str) -> tuple[list[dict], str] | None:
        if not self.enabled:
            return None

        candidate_queries = self._candidate_queries(series_title)
        checked_pages: set[str] = set()

        for query in candidate_queries:
            page_titles = self._search_wikipedia_pages(query)
            for page_title in page_titles:
                if page_title in checked_pages:
                    continue
                checked_pages.add(page_title)

                extract = self._fetch_page_extract(page_title)
                if not extract:
                    continue

                items = self._extract_arc_items(extract)
                if self._is_reasonable(items):
                    source = f"external:wikipedia:{self._slug(page_title)}"
                    return items, source

        return None

    def _candidate_queries(self, title: str) -> list[str]:
        cleaned = re.sub(r"\s*\((en|english)\)\s*$", "", title, flags=re.IGNORECASE).strip()
        normalized = re.sub(r"[_]+", " ", cleaned)
        canonical = re.sub(r"[^A-Za-z0-9 ]+", " ", normalized)
        canonical = re.sub(r"\s+", " ", canonical).strip()

        queries = [
            f"{normalized} manga story arcs",
            f"{canonical} manga story arcs" if canonical else normalized,
            f"{normalized} manga arcs chapters",
            f"{canonical} manga arcs chapters" if canonical else normalized,
            f"{normalized} manga",
        ]

        unique: list[str] = []
        seen: set[str] = set()
        for query in queries:
            q = query.strip()
            if not q or q in seen:
                continue
            seen.add(q)
            unique.append(q)
        return unique

    def _search_wikipedia_pages(self, query: str) -> list[str]:
        params = parse.urlencode(
            {
                "action": "query",
                "format": "json",
                "list": "search",
                "srsearch": query,
                "srlimit": self.max_search_results,
                "utf8": 1,
            }
        )
        url = f"{WIKIPEDIA_API_ENDPOINT}?{params}"
        data = self._fetch_json(url)
        if not isinstance(data, dict):
            return []

        results = data.get("query", {}).get("search", [])
        titles: list[str] = []
        if isinstance(results, list):
            for result in results:
                if not isinstance(result, dict):
                    continue
                title = result.get("title")
                if isinstance(title, str) and title.strip():
                    titles.append(title.strip())
        return titles

    def _fetch_page_extract(self, page_title: str) -> str:
        params = parse.urlencode(
            {
                "action": "query",
                "format": "json",
                "prop": "extracts",
                "explaintext": 1,
                "redirects": 1,
                "titles": page_title,
                "utf8": 1,
            }
        )
        url = f"{WIKIPEDIA_API_ENDPOINT}?{params}"
        data = self._fetch_json(url)
        if not isinstance(data, dict):
            return ""

        pages = data.get("query", {}).get("pages", {})
        if not isinstance(pages, dict):
            return ""

        for page_data in pages.values():
            if not isinstance(page_data, dict):
                continue
            extract = page_data.get("extract")
            if isinstance(extract, str) and extract.strip():
                return extract
        return ""

    def _fetch_json(self, url: str) -> dict | list | None:
        req = request.Request(
            url,
            headers={
                "Accept": "application/json",
                "User-Agent": "manga-reader-arc-resolver/1.0",
            },
        )
        try:
            with request.urlopen(req, timeout=self.timeout_seconds) as resp:
                payload = resp.read().decode("utf-8")
        except Exception:  # noqa: BLE001
            return None

        try:
            return json.loads(payload)
        except Exception:  # noqa: BLE001
            return None

    def _extract_arc_items(self, text: str) -> list[dict]:
        matches: list[tuple[str, float, float]] = []

        for pattern in self.ARC_LINE_PATTERNS:
            for match in pattern.finditer(text):
                name = self._clean_name(match.group("name"))
                start = ArcCatalog._coerce_number(match.group("start"))
                end = ArcCatalog._coerce_number(match.group("end"))
                if not name or start is None or end is None:
                    continue
                if end < start:
                    continue
                matches.append((name, start, end))

        if not matches:
            return []

        dedup: dict[str, tuple[str, float, float]] = {}
        for name, start, end in matches:
            key = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
            current = dedup.get(key)
            if current is None or start < current[1]:
                dedup[key] = (name, start, end)

        ordered = sorted(dedup.values(), key=lambda item: (item[1], item[2], item[0].lower()))
        items: list[dict] = []
        for idx, (name, start, end) in enumerate(ordered, start=1):
            items.append(
                {
                    "id": f"{self._slug(name)}-{idx:02d}",
                    "name": name,
                    "start_chapter": start,
                    "end_chapter": end,
                    "order": idx,
                }
            )

        return items

    @staticmethod
    def _clean_name(name: str) -> str:
        cleaned = re.sub(r"\s+", " ", name).strip(" -:\t")
        return cleaned

    @staticmethod
    def _is_reasonable(items: list[dict]) -> bool:
        if len(items) < 2:
            return False

        starts = [ArcCatalog._coerce_number(item.get("start_chapter")) for item in items]
        ends = [ArcCatalog._coerce_number(item.get("end_chapter")) for item in items]

        if any(value is None for value in starts) or any(value is None for value in ends):
            return False
        if any(float(s) <= 0 for s in starts if s is not None):
            return False
        if any(float(e) > 6000 for e in ends if e is not None):
            return False
        if starts != sorted(starts):
            return False
        return True

    @staticmethod
    def _slug(text: str) -> str:
        slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
        return slug or "arc"


class ArcCatalog:
    def __init__(
        self,
        library: MangaLibrary,
        cache_root: Path,
        template_root: Path | None = None,
        external_resolver: ArcExternalResolver | None = None,
    ) -> None:
        self.library = library
        self.cache_root = cache_root.expanduser().resolve()
        if template_root is None:
            template_root = self.cache_root.parent / "arc_templates"
        self.template_root = template_root.expanduser().resolve()
        self.external_resolver = external_resolver or ArcExternalResolver(enabled=False)

    def list_arcs(self, series_id: str, *, force_refresh: bool = False) -> list[dict]:
        series = self._series_by_id(series_id)
        return self._list_arcs_for_series(series, force_refresh=force_refresh)

    def _list_arcs_for_series(self, series: dict, *, force_refresh: bool = False) -> list[dict]:
        series_id = series["id"]
        series_title = series["title"]

        # "Singles" does not represent a real named series.
        if series["relative_path"] == ".":
            return []

        volumes = self.library.list_volumes(series_id)
        signature = self._volumes_signature(volumes)

        source_key = self._resolve_source_key(series_title)
        template_payload = self._read_template_payload(series_id)
        template_items = self._normalize_items(template_payload["items"]) if template_payload is not None else None
        template_auto_generated = bool(template_payload.get("auto_generated")) if template_payload is not None else False

        if source_key is not None:
            builtin_source = f"builtin:{source_key}"
            builtin_items = self._normalize_items(BUILTIN_ARCS[source_key])

            # Replace prior auto-generated templates with deterministic builtin arc maps.
            if template_payload is not None and template_auto_generated:
                self._write_template(
                    series_id=series_id,
                    series_title=series_title,
                    auto_generated=False,
                    source=builtin_source,
                    items=builtin_items,
                )

            cached_builtin = None if force_refresh else self._read_cache_payload(series_id, signature)
            if cached_builtin is not None and str(cached_builtin.get("source") or "").startswith("builtin:"):
                return self._normalize_items(cached_builtin["items"])

            self._write_cache(
                series_id=series_id,
                series_title=series_title,
                source=builtin_source,
                series_signature=signature,
                items=builtin_items,
            )
            return builtin_items

        cached = None if force_refresh else self._read_cache_payload(series_id, signature)
        if cached is not None:
            cached_items = self._normalize_items(cached["items"])
            cached_source = str(cached.get("source") or "")

            # Migrate old inferred cache entries to template-based arcs so new
            # unknown series stop showing "Chapters 1-25" labels.
            if (
                cached_source == "inferred:chapter-buckets"
                and source_key is None
                and template_items is None
                and cached_items
            ):
                migrated_items = self._ensure_template_for_inferred(series_id, series_title, cached_items)
                self._write_cache(
                    series_id=series_id,
                    series_title=series_title,
                    source="generated:series-template",
                    series_signature=signature,
                    items=migrated_items,
                )
                return migrated_items

            # When template entries were auto-generated from inferred ranges,
            # try to upgrade them using external metadata during sync/read.
            if source_key is None and template_auto_generated:
                external = self._resolve_external_items(series_title)
                if external is not None:
                    external_items, external_source = external
                    self._write_template(
                        series_id=series_id,
                        series_title=series_title,
                        auto_generated=False,
                        source=external_source,
                        items=external_items,
                    )
                    self._write_cache(
                        series_id=series_id,
                        series_title=series_title,
                        source=external_source,
                        series_signature=signature,
                        items=external_items,
                    )
                    return external_items

            return cached_items

        if template_items is not None:
            if source_key is None and template_auto_generated and force_refresh:
                external = self._resolve_external_items(series_title)
                if external is not None:
                    items, source_name = external
                    self._write_template(
                        series_id=series_id,
                        series_title=series_title,
                        auto_generated=False,
                        source=source_name,
                        items=items,
                    )
                else:
                    items = template_items
                    source_name = str(template_payload.get("source") or "template:series-id") if template_payload is not None else "template:series-id"
            else:
                items = template_items
                source_name = str(template_payload.get("source") or "template:series-id") if template_payload is not None else "template:series-id"
        else:
            if source_key:
                items = self._normalize_items(BUILTIN_ARCS[source_key])
                source_name = f"builtin:{source_key}"
            else:
                external = self._resolve_external_items(series_title)
                if external is not None:
                    items, source_name = external
                    self._write_template(
                        series_id=series_id,
                        series_title=series_title,
                        auto_generated=False,
                        source=source_name,
                        items=items,
                    )
                else:
                    inferred_items = self._infer_items_from_volumes(series_title, volumes)
                    if inferred_items:
                        items = self._ensure_template_for_inferred(series_id, series_title, inferred_items)
                        source_name = "generated:series-template"
                    else:
                        items = []
                        source_name = "none"

        self._write_cache(
            series_id=series_id,
            series_title=series_title,
            source=source_name,
            series_signature=signature,
            items=items,
        )

        return items

    def sync_all_series(self, *, force_refresh: bool = False) -> dict:
        summary = {
            "series_total": 0,
            "created": 0,
            "refreshed": 0,
            "unchanged": 0,
            "errors": [],
        }

        for series in self.library.list_series():
            # Skip root-level "Singles" pseudo-series.
            if series.get("relative_path") == ".":
                continue

            series_id = series["id"]
            summary["series_total"] += 1

            cache_path = self._cache_path(series_id)
            before_mtime = cache_path.stat().st_mtime if cache_path.exists() else None

            try:
                self._list_arcs_for_series(series, force_refresh=force_refresh)
            except Exception as exc:  # noqa: BLE001
                summary["errors"].append({"series_id": series_id, "error": str(exc)})
                continue

            after_mtime = cache_path.stat().st_mtime if cache_path.exists() else None
            if before_mtime is None and after_mtime is not None:
                summary["created"] += 1
            elif before_mtime is not None and after_mtime is not None and after_mtime != before_mtime:
                summary["refreshed"] += 1
            else:
                summary["unchanged"] += 1

        return summary

    def _series_by_id(self, series_id: str) -> dict:
        for series in self.library.list_series():
            if series["id"] == series_id:
                return series
        raise MangaNotFoundError("Series not found")

    def _cache_path(self, series_id: str) -> Path:
        return self.cache_root / f"{series_id}.json"

    def _template_path(self, series_id: str) -> Path:
        return self.template_root / f"{series_id}.json"

    def _read_template_payload(self, series_id: str) -> dict | None:
        path = self._template_path(series_id)
        if not path.is_file():
            return None

        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001
            return None

        items = raw.get("items")
        if not isinstance(items, list):
            return None
        raw["items"] = self._normalize_items(items)
        return raw

    def _ensure_template_for_inferred(
        self,
        series_id: str,
        series_title: str,
        inferred_items: list[dict],
    ) -> list[dict]:
        existing = self._read_template_payload(series_id)
        if existing is not None:
            return self._normalize_items(existing.get("items", []))

        template_items = self._placeholder_items_from_inferred(series_title, inferred_items)
        self._write_template(
            series_id=series_id,
            series_title=series_title,
            auto_generated=True,
            source="generated:series-template",
            items=template_items,
        )
        return template_items

    def _write_template(
        self,
        series_id: str,
        series_title: str,
        auto_generated: bool,
        source: str,
        items: list[dict],
    ) -> None:
        self.template_root.mkdir(parents=True, exist_ok=True)
        payload = {
            "series_id": series_id,
            "series_title": series_title,
            "auto_generated": auto_generated,
            "source": source,
            "updated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "items": items,
        }
        self._template_path(series_id).write_text(
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    def _placeholder_items_from_inferred(self, series_title: str, inferred_items: list[dict]) -> list[dict]:
        series_slug = self._slug(series_title)
        normalized_inferred = self._normalize_items(inferred_items)
        placeholders: list[dict] = []
        for idx, item in enumerate(normalized_inferred, start=1):
            end = item["end_chapter"]
            if idx == len(normalized_inferred):
                # Keep latest arc open-ended so newly downloaded chapters continue
                # to map without requiring immediate template edits.
                end = None

            placeholders.append(
                {
                    "id": f"{series_slug}-arc-{idx:02d}",
                    "name": f"Arc {idx:02d}",
                    "start_chapter": item["start_chapter"],
                    "end_chapter": end,
                    "order": idx,
                }
            )

        return placeholders

    def _resolve_external_items(self, series_title: str) -> tuple[list[dict], str] | None:
        external = self.external_resolver.resolve(series_title)
        if external is None:
            return None

        items, source = external
        normalized = self._normalize_items(items)
        if len(normalized) < 2:
            return None
        return normalized, source

    def _read_cache_payload(self, series_id: str, signature: str) -> dict | None:
        path = self._cache_path(series_id)
        if not path.is_file():
            return None

        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001
            return None

        items = raw.get("items")
        if not isinstance(items, list):
            return None

        cached_signature = raw.get("series_signature")
        if cached_signature and isinstance(cached_signature, str) and cached_signature != signature:
            return None

        return raw

    def _write_cache(
        self,
        series_id: str,
        series_title: str,
        source: str,
        series_signature: str,
        items: list[dict],
    ) -> None:
        self.cache_root.mkdir(parents=True, exist_ok=True)
        payload = {
            "series_id": series_id,
            "series_title": series_title,
            "source": source,
            "updated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "series_signature": series_signature,
            "items": items,
        }
        self._cache_path(series_id).write_text(
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    def _infer_items_from_volumes(self, series_title: str, volumes: list[dict]) -> list[dict]:
        chapter_numbers: list[float] = []
        for volume in volumes:
            title = str(volume.get("title") or "")
            relative_path = str(volume.get("relative_path") or "")
            chapter = self._extract_chapter_number(title)
            if chapter is None:
                chapter = self._extract_chapter_number(relative_path)
            if chapter is not None:
                chapter_numbers.append(chapter)

        if not chapter_numbers:
            return []

        unique = sorted(set(chapter_numbers))
        if len(unique) < 3:
            return []

        min_chapter = min(unique)
        max_chapter = max(unique)

        bucket_start_to_values: dict[int, list[float]] = {}
        for chapter in unique:
            base = chapter if chapter > 0 else 1.0
            bucket_index = int((base - 1) // CHAPTER_BUCKET_SIZE)
            bucket_start = bucket_index * CHAPTER_BUCKET_SIZE + 1
            bucket_start_to_values.setdefault(bucket_start, []).append(chapter)

        series_slug = self._slug(series_title)
        items: list[dict] = []
        for order, bucket_start in enumerate(sorted(bucket_start_to_values.keys()), start=1):
            nominal_end = bucket_start + CHAPTER_BUCKET_SIZE - 1
            if nominal_end >= max_chapter:
                bucket_end = max_chapter
            else:
                bucket_end = float(nominal_end)

            start_value = float(bucket_start)
            if start_value < min_chapter:
                start_value = min_chapter

            start_label = self._format_number(start_value)
            end_label = self._format_number(bucket_end)
            items.append(
                {
                    "id": f"{series_slug}-chapters-{start_label}-to-{end_label}",
                    "name": f"Chapters {start_label}-{end_label}",
                    "start_chapter": start_value,
                    "end_chapter": bucket_end,
                    "order": order,
                }
            )

        return items

    @staticmethod
    def _extract_chapter_number(text: str) -> float | None:
        matches = re.findall(r"(\d+(?:\.\d+)?)", text)
        if not matches:
            return None

        # Use the last numeric token to support names like "Vol 01 Ch 005".
        candidate = matches[-1]
        try:
            return float(candidate)
        except ValueError:
            return None

    @staticmethod
    def _format_number(value: float) -> str:
        if float(value).is_integer():
            return str(int(value))
        return str(value).rstrip("0").rstrip(".")

    @staticmethod
    def _volumes_signature(volumes: list[dict]) -> str:
        parts = [str(v.get("relative_path") or v.get("title") or "") for v in volumes]
        payload = "\n".join(sorted(parts)).encode("utf-8")
        return hashlib.sha1(payload).hexdigest()

    @staticmethod
    def _normalize_items(items: list[object]) -> list[dict]:
        normalized: list[dict] = []
        for idx, raw in enumerate(items, start=1):
            if not isinstance(raw, dict):
                continue

            name = raw.get("name")
            if not isinstance(name, str) or not name.strip():
                continue

            arc_id = raw.get("id")
            if not isinstance(arc_id, str) or not arc_id.strip():
                arc_id = ArcCatalog._slug(name)

            start = ArcCatalog._coerce_number(raw.get("start_chapter"))
            end = ArcCatalog._coerce_number(raw.get("end_chapter"))
            order = ArcCatalog._coerce_int(raw.get("order"))
            if order is None:
                order = idx

            normalized.append(
                {
                    "id": arc_id,
                    "name": name.strip(),
                    "start_chapter": start,
                    "end_chapter": end,
                    "order": order,
                }
            )

        normalized.sort(key=lambda item: item["order"] if item["order"] is not None else 10**9)
        return normalized

    @staticmethod
    def _coerce_number(value: object) -> float | None:
        if value is None:
            return None
        if isinstance(value, (int, float)):
            return float(value)
        if isinstance(value, str):
            text = value.strip()
            if not text:
                return None
            try:
                return float(text)
            except ValueError:
                return None
        return None

    @staticmethod
    def _coerce_int(value: object) -> int | None:
        if value is None:
            return None
        if isinstance(value, int):
            return value
        if isinstance(value, float):
            return int(value)
        if isinstance(value, str):
            text = value.strip()
            if not text:
                return None
            try:
                return int(float(text))
            except ValueError:
                return None
        return None

    @staticmethod
    def _slug(text: str) -> str:
        slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
        return slug or "arc"

    @staticmethod
    def _resolve_source_key(title: str) -> str | None:
        cleaned = re.sub(r"\s*\((en|english)\)\s*$", "", title, flags=re.IGNORECASE).strip().lower()
        canonical = re.sub(r"[^a-z0-9]+", " ", cleaned).strip()
        return TITLE_ALIASES.get(cleaned) or TITLE_ALIASES.get(canonical)
