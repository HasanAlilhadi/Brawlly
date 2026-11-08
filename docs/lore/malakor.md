# Malakor, the Six-Armed Sovereign

The King of the Demon's Lair in **Conquest** (the middle of the map, zone 0). Story and design by the game's
author; "Mother Teresa" was renamed **Mother Tyressa** (a real person's name doesn't belong on a villain).

## القصة: «سقوط الملك مالاكور وولادة طاغية الأذرع الستة»

في العصور الغابرة، وقبل أن تتحول الأرض إلى مقابر موحشة يعلوها الضباب، كان **مالاكور** ملكاً بشرياً عظيماً
يحكم إمبراطورية الفرسان من قلعته العظيمة في «أطلال كراون».

عندما ضرب طاعون الفناء مملكته، وزحفت جيوش الهوردة اللانهائية من الأورك والموتى، أرسل الملك خيرة أبطال
المملكة الأربعة للدفاع عن أسوار العاصمة:

1. **السير إلدور** (بطل السيف الأعظم): يقطع بسيفه العظيم كتائب كاملة بضربات كاسحة.
2. **فايرا** (سيدة القوس الطيفي): تسقط الجيوش من أبعد مدى بمطر السهام الشبحية في مناطق (X) الحمراء.
3. **فاليندور** (مشعوذ السديم والظلال): كرات الفناء المظلمة والانتقال اللحظي (Phantom Blink) خلف خطوط العدو.
4. **الأم تيريسا** (Mother Tyressa، كاهنة الدماء): تسلب دماء الأعداء وتغذي بها جراح جيشها.

سقط الأبطال الأربعة واحداً تلو الآخر. وحوصر مالاكور في قاع سرداب تاجه الأخير، فرفض الركوع للموت وأقام
«طقس الالتحام المحرم»: قطع أذرع أبطاله الأربعة ونخبة قادة الأورك ومصاصي الدماء، ودمجها في جسده.

تحول إلى عملاق طوله **4.8 متر** بستة أذرع في ثلاثة مستويات:

* **الذراعان العلويان (السيف)**: سيف الفناء المسنن وشفرة البتر.
* **الذراعان الأوسطان (القوس)**: قوس من فقرات التنانين وسهم شبحي، لمطر من 40 سهماً.
* **الذراعان السفليان (السحر والعلاج)**: مخطوطة السحر الأسود وطلاسمها، وكأس الدماء الذي يمتص الأرواح.

## How it plays (what is built)

| Design | In the game |
|---|---|
| 4.8 m titan, crowned skull, ribcage + Soul Core, cape | `scenes/characters/enemies/malakor_model.gd` (built in code, ~3 m × the Lair's 1.6 boss size) |
| Six arms: greatsword + cleaver, bow + arrow, grimoire + chalice | shoulder / elbow / hand pivots per arm, each holding its item; own animation clips |
| Phase 1 (100–75 %) Sword Dominance: wide cleaves, red-lane charges | cleaving melee (both blades), Charge |
| Phase 2 (75–50 %) Phantom Hunter: backs off, 3 red X zones, 40-arrow rain | Kite movement, `ArrowRain` (BarrageAbility), arrow volleys |
| Phase 3 (50–25 %) Void Archmage: blinks behind archers, dark meteors | turns on a ranged foe near, Blink, `Meteors` (BarrageAbility), void bolts |
| Phase 4 (25–0 %) Apex Chimera: all classes at once, life-siphon aura | every action on, siphon aura (drains foes within 6 m, heals ×2), life steal 200 % |
| Blood Totems at 66 % and 33 % | `blood_totem.tscn`: 3 totems that heal him until broken |
| The four fallen heroes | the four lieutenants of the Lair, risen as his servants, each leading a strong army in zone 1 (Sir Eldor, Vaira, Valendor, Mother Tyressa); when the Lair is attacked they rush to defend him |

A modelled Malakor (a GLB with the same clip names) can replace the `Model` node of `malakor.tscn` later.
