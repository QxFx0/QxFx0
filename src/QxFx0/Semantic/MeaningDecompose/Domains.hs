{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Semantic.MeaningDecompose.Domains
  ( heartPump
  , aorta
  , vessels
  , bloodGroups
  , bloodVolume
  , decomposedFacts
  , heartFacts
  , bloodFacts
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)

import QxFx0.Semantic.MeaningAtom

heartPump :: FactAtoms
heartPump = FactAtoms (M.fromListWith (++)
  [ (AtomSubject,   [nounSlot AtomSubject
                      "сердце" "сердца" "сердце" "сердце" "сердцем" "сердца"])
  , (AtomProperty,  [plainSlot TModifier "полый"
                    ,plainSlot TModifier "мышечный"])
  , (AtomPredicate, [nounSlot AtomPredicate
                      "сокращается" "сокращения" "сокращении" "сокращение" "сокращением" "сокращения"])
  , (AtomQuantity,  [plainSlot AtomQuantity "100 000"
                    ,plainSlot AtomQuantity "7 000"
                    ,plainSlot AtomQuantity "≈ 7 000"])
  , (AtomUnit,      [nounSlot AtomUnit
                       "сокращение" "сокращения" "сокращении" "сокращение" "сокращением" "сокращения"
                     ,nounSlot AtomUnit
                       "литр" "литра" "литре" "литр" "литром" "литры"])
  , (AtomPeriod,    [nounSlot AtomPeriod
                       "сутки" "суток" "сутках" "сутки" "сутками" "сутки"])
  , (TVerb,         [nounSlot TVerb
                       "перекачивать" "перекачивание" "перекачивания" "перекачивании" "перекачивание" "перекачиванием"])
  , (TObject,       [nounSlot TObject
                      "кровь" "крови" "крови" "кровь" "кровью" ""])
  , (AtomAnalogy,   [plainSlot AtomAnalogy "насос"])
  -- [decomposed] -- , (AtomScale,     [plainSlot AtomScale "35 полных ванн за день"])
  , (AtomQuantity,      [plainSlot AtomQuantity "35"])
  , (AtomAnalogy,       [plainSlot AtomAnalogy "35 полных ванн за день"])
  , (AtomContext,   [nounSlot AtomContext
                      "кровеносная система" "кровеносной системы" "кровеносной системе"
                      "кровеносную систему" "кровеносной системой" "кровеносные системы"])
  , (AtomRelation,  [plainSlot TModifier "центральный"
                    ,nounSlot AtomRelation "орган" "органа" "органе" "орган" "органом" "органы"])
  , (TVerbReason,   [nounSlot TVerbReason
                      "доставлять" "доставления" "доставлении" "доставление" "доставлением" ""])
  , (TObjectReason,  [nounSlot TObjectReason
                      "кислород" "кислорода" "кислороде" "кислород" "кислородом" ""])
  -- [decomposed] -- , (AtomReason,    [plainSlot AtomReason "доставлять кислород всем клеткам"])

  ])
aorta :: FactAtoms
aorta = FactAtoms (M.fromListWith (++)
  [ (AtomSubject,   [nounSlot AtomSubject
                      "аорта" "аорты" "аорте" "аорту" "аортой" "аорты"])
  , (AtomProperty,  [plainSlot TModifier "крупнейший"
                    ,nounSlot AtomProperty "артерия" "артерии" "артерии" "артерию" "артерией" "артерии"
                    ,plainSlot TModifier "эластичный"
                    ,plainSlot TModifier "насыщенный"
                    ,nounSlot AtomProperty "кислород" "кислорода" "кислороде" "кислород" "кислородом" "кислороды"])
  , (AtomQuantity,  [plainSlot AtomQuantity "2,5–3,5"])
  , (AtomUnit,      [nounSlot AtomUnit
                       "сантиметр" "сантиметра" "сантиметре" "сантиметр" "сантиметром" "сантиметры"])
  , (AtomContext,   [nounSlot AtomContext
                      "взрослый человек" "взрослого человека" "взрослом человеке"
                      "взрослого человека" "взрослым человеком" "взрослые люди"
                    ,nounSlot AtomContext
                      "левый желудочек" "левого желудочка" "левом желудочке"
                      "левый желудочек" "левым желудочком" "левые желудочки"])
  , (TVerb,         [nounSlot TVerb
                       "распределять" "распределение" "распределения" "распределении" "распределение" "распределением"])
  , (TObject,       [nounSlot TObject
                      "кровь" "крови" "крови" "кровь" "кровью" ""
                    ,nounSlot TObject
                      "орган" "органа" "органе" "орган" "органом" "органы"])
  , (AtomProperty,      [plainSlot TModifier "главный"])
  , (AtomProperty,      [nounSlot AtomProperty "магистраль" "магистрали" "магистрали" "магистраль" "магистралью" "магистрали"])
  , (TCondition,    [nounSlot TCondition
                       "выход" "выхода" "выходе" "выход" "выходом" "выходы"])
  -- [decomposed] -- , (AtomScale,     [plainSlot AtomScale "в 5 раз выше атмосферного"])
  , (AtomQuantity,      [plainSlot AtomQuantity "5"])
  , (AtomRelation,      [plainSlot AtomRelation "выше атмосферного"])
  -- [decomposed reason] -- (AtomReason,    [plainSlot AtomReason "главная магистраль кровеносной системы"

  ])
vessels :: FactAtoms
vessels = FactAtoms (M.fromListWith (++)
  [ (AtomSubject,   [nounSlot AtomSubject
                      "кровеносные сосуды" "кровеносных сосудов" "кровеносных сосудах"
                      "кровеносные сосуды" "кровеносными сосудами" "кровеносные сосуды"])
  , (AtomProperty,  [plainSlot TModifier "эластичный"
                     ,nounSlot AtomProperty "трубки" "трубок" "трубках" "трубки" "трубками" "трубки"])
  , (AtomQuantity,  [plainSlot AtomQuantity "100 000"])
  , (AtomUnit,      [nounSlot AtomUnit
                       "километр" "километра" "километре" "километр" "километром" "километры"])
  , (AtomQuantity,     [plainSlot AtomQuantity "2,5"])
  , (AtomRelation,     [plainSlot AtomRelation "длиннее экватора Земли"])
  , (AtomAnalogy,      [plainSlot AtomAnalogy "дважды обмотать Землю"])
  , (AtomContext,   [nounSlot AtomContext
                      "человек" "человека" "человеке" "человека" "человеком" "люди"])
  , (TVerb,         [nounSlot TVerb
                       "включать" "включение" "включения" "включении" "включение" "включением"])
  , (TObject,       [nounSlot TObject
                      "артерия" "артерии" "артерии" "артерию" "артерией" "артерии"
                    ,nounSlot TObject
                      "вена" "вены" "вене" "вену" "веной" "вены"
                    ,nounSlot TObject "клетка" "клетки" "клетке" "клетку" "клеткой" "клетки"
                    ,nounSlot TObject "кровь" "крови" "крови" "кровь" "кровью" "крови"])

  ])

bloodGroups :: FactAtoms
bloodGroups = FactAtoms (M.fromListWith (++)
  [ (AtomSubject,   [nounSlot AtomSubject
                      "группы крови" "групп крови" "группах крови"
                      "группы крови" "группами крови" "группы крови"])
  , (AtomContext,   [nounSlot AtomContext
                      "система AB0" "системы AB0" "системе AB0"
                      "систему AB0" "системой AB0" "системы AB0"])
  , (AtomDiscoverer,[nounSlot AtomDiscoverer
                      "Карл Ландштейнер" "Карла Ландштейнера" "Карле Ландштейнере"
                      "Карла Ландштейнера" "Карлом Ландштейнером" ""])
  , (AtomYear,      [plainSlot AtomYear "1901"])
  , (TVerb,         [nounSlot TVerb
                       "основываться" "основание" "основания" "основании" "основание" "основанием"])
  , (TObject,       [nounSlot TObject
                      "антиген" "антигена" "антигене" "антиген" "антигеном" "антигены"
                    ,nounSlot TObject
                      "эритроцит" "эритроцита" "эритроците" "эритроцит" "эритроцитом" "эритроциты"])
  -- [decomposed] -- , (AtomRelation,  [plainSlot AtomRelation "универсальный донор — группа 0(I)"
  , (AtomProperty,      [plainSlot TModifier "универсальный"])
  , (TObject,        [nounSlot TObject "донор" "донора" "доноре" "донора" "донором" "доноры"])
  -- [decomposed] -- ,plainSlot AtomRelation "универсальный реципиент — AB(IV)"])
  , (TObject,        [nounSlot TObject "реципиент" "реципиента" "реципиенте" "реципиента" "реципиентом" "реципиенты"])
  , (TCondition,    [nounSlot TCondition
                       "учёт" "учёта" "учёте" "учёт" "учётом" "учёты"])
  , (TVerbReason,   [nounSlot TVerbReason
                      "требовать" "требования" "требовании" "требование" "требованием" ""])
  , (TObjectReason,  [nounSlot TObjectReason
                      "совместимость" "совместимости" "совместимости" "совместимость" "совместимостью" "совместимости"])
  -- [decomposed] -- , (AtomReason,    [plainSlot AtomReason "переливание требует совместимости"])

  ])
bloodVolume :: FactAtoms
bloodVolume = FactAtoms (M.fromListWith (++)
  [ (AtomSubject,   [nounSlot AtomSubject
                      "кровь" "крови" "крови" "кровь" "кровью" ""])
  , (AtomQuantity,  [plainSlot AtomQuantity "5"])
  , (AtomUnit,      [nounSlot AtomUnit
                       "литр" "литра" "литре" "литр" "литром" "литры"])
  , (AtomContext,   [nounSlot AtomContext
                      "взрослый человек" "взрослого человека" "взрослом человеке"
                      "взрослого человека" "взрослым человеком" "взрослые люди"])  , (AtomProperty,  [plainSlot TModifier "красный"])
  , (TVerb,         [nounSlot TVerb
                       "доставлять" "доставление" "доставления" "доставлении" "доставление" "доставлением"])
  , (TObject,       [nounSlot TObject
                      "кислород" "кислорода" "кислороде" "кислород" "кислородом" ""
                    ,nounSlot TObject
                      "вещество" "вещества" "веществе" "вещество" "веществом" "вещества"
                    ,nounSlot TObject "кровь" "крови" "крови" "кровь" "кровью" "крови"])
  -- [decomposed] -- , (AtomScale,     [plainSlot AtomScale "примерно 7–8% массы тела"])
  , (AtomQuantity,      [plainSlot AtomQuantity "7–8%"])
  , (AtomRelation,      [nounSlot AtomRelation "масса тела" "массы тела" "массе тела" "массу тела" "массой тела" "массы тела"])
  , (AtomQuantity,       [plainSlot AtomQuantity "3–5"])

  ])

medicine_fact0 :: FactAtoms
medicine_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "сердце" "сердца" "сердце" "сердце" "сердцем" "сердца"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "100 000"])
  , (TVerb,         [nounSlot TVerb
                       "совершать" "совершение" "совершения" "совершении" "совершение" "совершением"
                    ,nounSlot TVerb
                       "перекачивать" "перекачивание" "перекачивания" "перекачивании" "перекачивание" "перекачиванием"])
  , (TObject,       [nounSlot TObject "сердце" "сердца" "сердце" "сердце" "сердцем" "сердца"
                    ,nounSlot TObject "сокращение" "сокращения" "сокращении" "сокращение" "сокращением" "сокращения"])
  , (AtomQuantity,       [plainSlot AtomQuantity "100 000"])

  ])
medicine_fact1 :: FactAtoms
medicine_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "артерия" "артерии" "артерии" "артерию" "артерией" "артерии"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "2,5"])
  , (TVerb,         [nounSlot TVerb
                       "составлять" "составление" "составления" "составлении" "составление" "составлением"])
  , (TObject,       [nounSlot TObject "артерия" "артерии" "артерии" "артерию" "артерией" "артерии"
                    ,nounSlot TObject "аорта" "аорты" "аорте" "аорту" "аортой" "аорты"])
  , (AtomProperty,       [plainSlot TModifier "крупный"])

  ])
medicine_fact2 :: FactAtoms
medicine_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "печень" "печени" "печени" "печень" "печенью" "печени"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "75"])
  , (TVerb,         [nounSlot TVerb
                       "регенерировать" "регенерирование" "регенерирования" "регенерировании" "регенерирование" "регенерированием"])
  , (TObject,       [nounSlot TObject "печень" "печени" "печени" "печень" "печенью" "печени"
                    ,nounSlot TObject "орган" "органа" "органе" "орган" "органом" "органы"])
  ,   (AtomContext,   [nounSlot AtomContext "орган" "органа" "органе" "орган" "органом" "органы"])

  ])
physics_fact0 :: FactAtoms
physics_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "скорость" "скорости" "скорости" "скорость" "скоростью" "скорости"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "299 792 458"])
  , (TVerb,         [nounSlot TVerb
                       "составлять" "составление" "составления" "составлении" "составление" "составлением"
                    ,nounSlot TVerb
                       "являться" "явление" "явления" "явлении" "явление" "явлением"])
  , (TObject,       [nounSlot TObject "скорость" "скорости" "скорости" "скорость" "скоростью" "скорости"])
  , (AtomQuantity,       [plainSlot AtomQuantity "299 792 458"])

  ])
physics_fact1 :: FactAtoms
physics_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "закон" "закона" "законе" "закон" "законом" "законы"])
  , (TVerb,         [nounSlot TVerb
                       "утверждать" "утверждение" "утверждения" "утверждении" "утверждение" "утверждением"])
  , (TObject,       [nounSlot TObject "закон" "закона" "законе" "закон" "законом" "законы"])
  ,   (AtomContext,   [nounSlot AtomContext "Закон" "Закона" "Законе" "Закон" "Законом" "Законы"])

  ])
physics_fact2 :: FactAtoms
physics_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "атом" "атома" "атоме" "атом" "атомом" "атомы"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "99,9"])
  , (TVerb,         [nounSlot TVerb
                       "состоять" "состояние" "состояния" "состоянии" "состояние" "состоянием"
                    ,nounSlot TVerb
                       "сосредотачивать" "сосредоточение" "сосредоточения" "сосредоточении" "сосредоточение" "сосредоточением"])
  , (TObject,       [nounSlot TObject "атом" "атома" "атоме" "атом" "атомом" "атомы"])
  , (AtomQuantity,       [plainSlot AtomQuantity "99,9"])

  ])
chemistry_fact0 :: FactAtoms
chemistry_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "вода" "воды" "воде" "воду" "водой" "воды"])
  , (TVerb,            [nounSlot TVerb
                       "реагировать" "реагирование" "реагирования" "реагировании" "реагирование" "реагированием"])
  , (TObject,            [nounSlot TObject "вещество" "вещества" "веществе" "вещество" "веществом" "вещества"])
  , (AtomProperty,            [plainSlot TModifier "химический"])

  ])
chemistry_fact1 :: FactAtoms
chemistry_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "таблица" "таблицы" "таблице" "таблицу" "таблицей" "таблицы"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1869"])
  ,   (AtomYear,      [plainSlot AtomYear "1869"])
  ,   (AtomDiscoverer,[nounSlot AtomDiscoverer "Дмитрий Менделеев" "Дмитрия Менделеева" "Дмитрии Менделееве" "Дмитрия Менделеева" "Дмитрием Менделеевым" ""])
  -- [decomposed AtomScale] -- ,   (AtomScale,     [plainSlot AtomScale "в 1869 году"])
  , (TQuantity,            [plainSlot TQuantity "1869"])

  ])
chemistry_fact2 :: FactAtoms
chemistry_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "элемент" "элемента" "элементе" "элемент" "элементом" "элементы"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "75"])
  , (TVerb,            [nounSlot TVerb
                       "реагировать" "реагирование" "реагирования" "реагировании" "реагирование" "реагированием"])
  , (TObject,            [nounSlot TObject "вещество" "вещества" "веществе" "вещество" "веществом" "вещества"])
  , (AtomProperty,            [plainSlot TModifier "химический"])

  ])
biology_fact0 :: FactAtoms
biology_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "теория" "теории" "теории" "теорию" "теорией" "теории"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1859"])
  ,   (AtomYear,      [plainSlot AtomYear "1859"])
  , (TVerb,         [nounSlot TVerb
                       "формулировать" "формулирование" "формулирования" "формулировании" "формулирование" "формулированием"])
  , (TObject,       [nounSlot TObject "теория" "теории" "теории" "теорию" "теорией" "теории"])
  ,   (AtomContext,   [nounSlot AtomContext "Теория" "Теории" "Теории" "Теорию" "Теорией" "Теории"])

  ])
biology_fact1 :: FactAtoms
biology_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "клетка" "клетки" "клетке" "клетку" "клеткой" "клетки"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1838"])
  ,   (AtomYear,      [plainSlot AtomYear "1838"])
  ,   (AtomDiscoverer,[nounSlot AtomDiscoverer "Шванн" "Шванна" "Шванне" "Шванна" "Шванном" ""])
  , (TObject,       [nounSlot TObject "клетка" "клетки" "клетке" "клетку" "клеткой" "клетки"
                    ,nounSlot TObject "теория" "теории" "теории" "теорию" "теорией" "теории"])
  , (AtomProperty,       [plainSlot TModifier "базовый"])
  , (TVerb,         [nounSlot TVerb
                       "формулировать" "формулирование" "формулирования" "формулировании" "формулирование" "формулированием"])
  , (AtomQuantity,       [plainSlot AtomQuantity "1838–1839"])
  ,   (AtomContext,   [nounSlot AtomContext "орган" "органа" "органе" "орган" "органом" "органы"])

  ])
biology_fact2 :: FactAtoms
biology_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "митохондрия" "митохондрии" "митохондрии" "митохондрию" "митохондрией" "митохондрии"])
  , (TVerb,         [nounSlot TVerb
                       "производить" "производство" "производства" "производстве" "производство" "производством"])
  , (TObject,       [nounSlot TObject "энергия" "энергии" "энергии" "энергию" "энергией" ""])
  , (AtomProperty,     [plainSlot TModifier "клеточный"
                       ,nounSlot AtomProperty "станция" "станции" "станции" "станцию" "станцией" "станции"])
  , (AtomAnalogy,      [plainSlot AtomAnalogy "энергетическая станция"])

  ])
mathematics_fact0 :: FactAtoms
mathematics_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "число" "числа" "числе" "число" "числом" "числа"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "3,1415926535"])
  ,   (AtomYear,      [plainSlot AtomYear "1415"])
  , (TObject,       [nounSlot TObject "число" "числа" "числе" "число" "числом" "числа"])
  , (AtomProperty,       [plainSlot TModifier "иррациональный"])
  -- [decomposed] -- ,   (AtomProperty,  [plainSlot TModifier "первые несколько знаков: 3,1415926535"])
  , (AtomProperty,      [plainSlot TModifier "иррациональный"])
  , (AtomQuantity,      [plainSlot AtomQuantity "3,1415926535"])

  ])
mathematics_fact1 :: FactAtoms
mathematics_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "теорема" "теоремы" "теореме" "теорему" "теоремой" "теоремы"])
  , (TVerb,         [nounSlot TVerb
                       "утверждать" "утверждение" "утверждения" "утверждении" "утверждение" "утверждением"])
  , (TObject,       [nounSlot TObject "теорема" "теоремы" "теореме" "теорему" "теоремой" "теоремы"])

  ])
mathematics_fact2 :: FactAtoms
mathematics_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "теорема" "теоремы" "теореме" "теорему" "теоремой" "теоремы"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1637"])
  ,   (AtomYear,      [plainSlot AtomYear "1637"])
  , (TVerb,         [nounSlot TVerb
                       "доказывать" "доказывание" "доказывания" "доказывании" "доказывание" "доказыванием"])
  , (TObject,       [nounSlot TObject "теорема" "теоремы" "теореме" "теорему" "теоремой" "теоремы"])
  , (AtomQuantity,       [plainSlot AtomQuantity "1637"])
  -- [decomposed AtomScale] -- ,   (AtomScale,     [plainSlot AtomScale "в 1637 году"])
  , (TQuantity,            [plainSlot TQuantity "1637"])

  ])
astronomy_fact0 :: FactAtoms
astronomy_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "возраст" "возраста" "возрасте" "возраст" "возрастом" "возрасты"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "13,8"])
  , (TVerb,            [nounSlot TVerb
                       "вращаться" "вращение" "вращения" "вращении" "вращение" "вращением"])
  , (TObject,            [nounSlot TObject "звезда" "звезды" "звезде" "звезду" "звездой" "звёзды"])
  , (AtomProperty,            [plainSlot TModifier "астрономический"])
  -- [decomposed AtomScale] -- ,   (AtomScale,     [plainSlot AtomScale "в 13,8 миллиарда"])
  , (TQuantity,            [plainSlot TQuantity "13,8"])

  ])
astronomy_fact1 :: FactAtoms
astronomy_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "солнце" "солнца" "солнце" "солнце" "солнцем" "солнца"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "2"])
  , (TObject,       [nounSlot TObject "солнце" "солнца" "солнце" "солнце" "солнцем" "солнца"])
  , (AtomQuantity,       [plainSlot AtomQuantity "2"
                      ,plainSlot AtomQuantity "150"])
  -- [decomposed AtomScale] -- ,   (AtomScale,     [plainSlot AtomScale "в 330 000"])
  , (TQuantity,            [plainSlot TQuantity "330 000"])
  ,   (AtomContext,   [nounSlot AtomContext "звезда" "звезды" "звезде" "звезду" "звездой" "звёзды"])

  ])
astronomy_fact2 :: FactAtoms
astronomy_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "дыра" "дыры" "дыре" "дыру" "дырой" "дыры"])
  , (TVerb,            [nounSlot TVerb
                       "вращаться" "вращение" "вращения" "вращении" "вращение" "вращением"
                      ,nounSlot TVerb
                       "называться" "название" "названия" "названии" "название" "названием"])
  , (TObject,            [nounSlot TObject "звезда" "звезды" "звезде" "звезду" "звездой" "звёзды"
                      ,nounSlot TObject "дыра" "дыры" "дыре" "дыру" "дырой" "дыры"])
  , (AtomProperty,            [plainSlot TModifier "астрономический"])

  ])
geography_fact0 :: FactAtoms
geography_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "гора" "горы" "горе" "гору" "горой" "горы"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "8 848,86"])
  , (TVerb,         [nounSlot TVerb
                       "составлять" "составление" "составления" "составлении" "составление" "составлением"])
  , (TObject,       [nounSlot TObject "гора" "горы" "горе" "гору" "горой" "горы"])
  , (AtomProperty,       [plainSlot TModifier "крупный"])
  , (AtomQuantity,       [plainSlot AtomQuantity "8"])

  ])
geography_fact1 :: FactAtoms
geography_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "точка" "точки" "точке" "точку" "точкой" "точки"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "10 994"])
  , (TVerb,            [nounSlot TVerb
                       "располагаться" "расположение" "расположения" "расположении" "расположение" "расположением"])
  , (TObject,            [nounSlot TObject "территория" "территории" "территории" "территорию" "территорией" "территории"])
  , (AtomProperty,            [plainSlot TModifier "географический"])

  ])
geography_fact2 :: FactAtoms
geography_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "озеро" "озера" "озере" "озеро" "озером" "озёра"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "371 000"])
  , (TObject,       [nounSlot TObject "озеро" "озера" "озере" "озеро" "озером" "озёра"])
  , (AtomQuantity,       [plainSlot AtomQuantity "371 000"])

  ])
history_fact0 :: FactAtoms
history_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "римская" "римской" "римской" "римскую" "римской" "римские"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "70"])
  , (TVerb,            [nounSlot TVerb
                       "происходить" "происхождение" "происхождения" "происхождении" "происхождение" "происхождением"])
  , (TObject,            [nounSlot TObject "событие" "события" "событии" "событие" "событием" "события"])
  , (AtomProperty,            [plainSlot TModifier "исторический"])

  ])
history_fact1 :: FactAtoms
history_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "революция" "революции" "революции" "революцию" "революцией" "революции"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1789"])
  ,   (AtomYear,      [plainSlot AtomYear "1789"])
  , (TVerb,            [nounSlot TVerb
                       "происходить" "происхождение" "происхождения" "происхождении" "происхождение" "происхождением"])
  , (TObject,            [nounSlot TObject "событие" "события" "событии" "событие" "событием" "события"])
  , (AtomProperty,            [plainSlot TModifier "исторический"])

  ])
history_fact2 :: FactAtoms
history_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "война" "войны" "войне" "войну" "войной" "войны"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1914"])
  ,   (AtomYear,      [plainSlot AtomYear "1914"])
  , (TVerb,         [nounSlot TVerb
                       "становиться" "становление" "становления" "становлении" "становление" "становлением"])
  , (TObject,       [nounSlot TObject "война" "войны" "войне" "войну" "войной" "войны"])
  , (AtomQuantity,       [plainSlot AtomQuantity "1914–1918"])

  ])
law_fact0 :: FactAtoms
law_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "право" "права" "праве" "право" "правом" "права"])
  , (TVerb,            [nounSlot TVerb
                       "регулировать" "регулирование" "регулирования" "регулировании" "регулирование" "регулированием"])
  , (TObject,            [nounSlot TObject "норма" "нормы" "норме" "норму" "нормой" "нормы"])
  , (AtomProperty,            [plainSlot TModifier "юридический"])
  ,   (AtomContext,   [nounSlot AtomContext "система" "системы" "системе" "систему" "системой" "системы"])

  ])
law_fact1 :: FactAtoms
law_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "хартия" "хартии" "хартии" "хартию" "хартией" "хартии"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1215"])
  ,   (AtomYear,      [plainSlot AtomYear "1215"])
  , (TVerb,         [nounSlot TVerb
                       "ограничивать" "ограничение" "ограничения" "ограничении" "ограничение" "ограничением"])
  , (AtomQuantity,       [plainSlot AtomQuantity "1215"])
  ,   (AtomContext,   [nounSlot AtomContext "закон" "закона" "законе" "закон" "законом" "законы"])

  ])
law_fact2 :: FactAtoms
law_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "презумпция" "презумпции" "презумпции" "презумпцию" "презумпцией" "презумпции"])
  , (TVerb,            [nounSlot TVerb
                       "регулировать" "регулирование" "регулирования" "регулировании" "регулирование" "регулированием"])
  , (TObject,            [nounSlot TObject "норма" "нормы" "норме" "норму" "нормой" "нормы"])
  , (AtomProperty,            [plainSlot TModifier "юридический"])

  ])
economics_fact0 :: FactAtoms
economics_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "адам" "адама" "адаме" "адама" "адамом" "адамы"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1776"])
  ,   (AtomYear,      [plainSlot AtomYear "1776"])
  , (TVerb,            [nounSlot TVerb
                       "производить" "производство" "производства" "производстве" "производство" "производством"])
  , (TObject,            [nounSlot TObject "товар" "товара" "товаре" "товар" "товаром" "товары"])
  , (AtomProperty,            [plainSlot TModifier "экономический"])
  ,   (AtomContext,   [nounSlot AtomContext "класс" "класса" "классе" "класс" "классом" "классы"])

  ])
economics_fact1 :: FactAtoms
economics_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "валова" "валовой" "валовой" "валову" "валовой" "валовы"])
  , (TVerb,            [nounSlot TVerb
                       "производить" "производство" "производства" "производстве" "производство" "производством"])
  , (TObject,            [nounSlot TObject "товар" "товара" "товаре" "товар" "товаром" "товары"])
  , (AtomProperty,            [plainSlot TModifier "экономический"])
  ,   (AtomContext,   [nounSlot AtomContext "экономика" "экономики" "экономике" "экономику" "экономикой" "экономики"])

  ])
economics_fact2 :: FactAtoms
economics_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "инфляция" "инфляции" "инфляции" "инфляцию" "инфляцией" "инфляции"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "2"])
  , (TVerb,            [nounSlot TVerb
                       "производить" "производство" "производства" "производстве" "производство" "производством"
                      ,nounSlot TVerb
                       "считаться" "считание" "считания" "считании" "считание" "считанием"])
  , (TObject,            [nounSlot TObject "товар" "товара" "товаре" "товар" "товаром" "товары"
                      ,nounSlot TObject "инфляция" "инфляции" "инфляции" "инфляцию" "инфляцией" "инфляции"])
  , (AtomProperty,            [plainSlot TModifier "экономический"])
  , (AtomQuantity,       [plainSlot AtomQuantity "2–3"])

  ])
computer_science_fact0 :: FactAtoms
computer_science_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "алан" "алана" "алане" "алана" "аланом" "аланы"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1936"])
  ,   (AtomYear,      [plainSlot AtomYear "1936"])
  ,   (AtomDiscoverer,[nounSlot AtomDiscoverer "Алан Тьюринг" "Алана Тьюринга" "Алане Тьюринге" "Алана Тьюринга" "Аланом Тьюрингом" ""])
  , (TVerb,         [nounSlot TVerb
                       "описывать" "описание" "описания" "описании" "описание" "описанием"])
  , (AtomQuantity,       [plainSlot AtomQuantity "1936"])

  ])
computer_science_fact1 :: FactAtoms
computer_science_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "компьютер" "компьютера" "компьютере" "компьютер" "компьютером" "компьютеры"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1945"])
  ,   (AtomYear,      [plainSlot AtomYear "1945"])
  , (TVerb,         [nounSlot TVerb
                       "создавать" "создание" "создания" "создании" "создание" "созданием"])
  , (TObject,       [nounSlot TObject "компьютер" "компьютера" "компьютере" "компьютер" "компьютером" "компьютеры"])
  , (AtomProperty,       [plainSlot TModifier "первый"])
  , (AtomQuantity,       [plainSlot AtomQuantity "1945"
                      ,plainSlot AtomQuantity "27"
                      ,plainSlot AtomQuantity "167"])
  -- [decomposed AtomScale] -- ,   (AtomScale,     [plainSlot AtomScale "в 1945 году"])
  , (TQuantity,            [plainSlot TQuantity "1945"])

  ])
computer_science_fact2 :: FactAtoms
computer_science_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "интернет" "интернета" "интернете" "интернет" "интернетом" "интернеты"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1969"])
  ,   (AtomYear,      [plainSlot AtomYear "1969"])
  , (TVerb,         [nounSlot TVerb
                       "возникать" "возникновение" "возникновения" "возникновении" "возникновение" "возникновением"])
  , (TObject,       [nounSlot TObject "интернет" "интернета" "интернете" "интернет" "интернетом" "интернеты"])
  , (AtomQuantity,       [plainSlot AtomQuantity "29"
                      ,plainSlot AtomQuantity "1969"])
  -- [decomposed AtomScale] -- ,   (AtomScale,     [plainSlot AtomScale "в 1969 году"])
  , (TQuantity,            [plainSlot TQuantity "1969"])

  ])
linguistics_fact0 :: FactAtoms
linguistics_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "мир" "мира" "мире" "мир" "миром" "миры"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "6 000"])
  , (AtomQuantity,       [plainSlot AtomQuantity "6 000"
                      ,plainSlot AtomQuantity "7 000"
                      ,plainSlot AtomQuantity "20"])
  , (TVerb,         [nounSlot TVerb
                       "говорить" "говорение" "говорения" "говорении" "говорение" "говорением"])
  ,   (AtomContext,   [nounSlot AtomContext "язык" "языка" "языке" "язык" "языком" "языки"])

  ])
linguistics_fact1 :: FactAtoms
linguistics_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "язык" "языка" "языке" "язык" "языком" "языки"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "920"])
  , (TVerb,            [nounSlot TVerb
                       "выражать" "выражение" "выражения" "выражении" "выражение" "выражением"])
  , (TObject,            [nounSlot TObject "знак" "знака" "знаке" "знак" "знаком" "знаки"])
  , (AtomProperty,            [plainSlot TModifier "лингвистический"])
  ,   (AtomContext,   [nounSlot AtomContext "язык" "языка" "языке" "язык" "языком" "языки"])

  ])
linguistics_fact2 :: FactAtoms
linguistics_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "санскрит" "санскрита" "санскрите" "санскрит" "санскритом" "санскриты"])
  , (TObject,       [nounSlot TObject "язык" "языка" "языке" "язык" "языком" "языки"])
  , (AtomProperty,       [plainSlot TModifier "древний"])
  ,   (AtomContext,   [nounSlot AtomContext "язык" "языка" "языке" "язык" "языком" "языки"])

  ])
psychology_fact0 :: FactAtoms
psychology_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "зигмунд" "зигмунда" "зигмунде" "зигмунда" "зигмундом" "зигмунды"])
  ,   (AtomDiscoverer,[nounSlot AtomDiscoverer "Зигмунд Фрейд" "Зигмунда Фрейда" "Зигмунде Фрейде" "Зигмунда Фрейда" "Зигмундом Фрейдом" ""])
  , (TVerb,            [nounSlot TVerb
                       "воспринимать" "восприятие" "восприятия" "восприятии" "восприятие" "восприятием"])
  , (TObject,            [nounSlot TObject "стимул" "стимула" "стимуле" "стимул" "стимулом" "стимулы"])
  , (AtomProperty,            [plainSlot TModifier "психологический"])
  ,   (AtomContext,   [nounSlot AtomContext "механизм" "механизма" "механизме" "механизм" "механизмом" "механизмы"])

  ])
psychology_fact1 :: FactAtoms
psychology_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "эксперимент" "эксперимента" "эксперименте" "эксперимент" "экспериментом" "эксперименты"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1961"])
  ,   (AtomYear,      [plainSlot AtomYear "1961"])
  , (TVerb,         [nounSlot TVerb
                       "показывать" "показание" "показания" "показании" "показание" "показанием"])
  , (AtomQuantity,       [plainSlot AtomQuantity "1961"])

  ])
psychology_fact2 :: FactAtoms
psychology_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "диссонанс" "диссонанса" "диссонансе" "диссонанс" "диссонансом" "диссонансы"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1957"])
  ,   (AtomYear,      [plainSlot AtomYear "1957"])
  ,   (AtomDiscoverer,[nounSlot AtomDiscoverer "Леон Фестингер" "Леона Фестингера" "Леоне Фестингере" "Леона Фестингера" "Леоном Фестингером" ""])
  , (TObject,       [nounSlot TObject "теория" "теории" "теории" "теорию" "теорией" "теории"])
  , (AtomQuantity,       [plainSlot AtomQuantity "1957"])
  -- [decomposed AtomScale] -- ,   (AtomScale,     [plainSlot AtomScale "в 1957 году"])
  , (TQuantity,            [plainSlot TQuantity "1957"])
  ,   (AtomContext,   [nounSlot AtomContext "теория" "теории" "теории" "теорию" "теорией" "теории"])

  ])
literature_fact0 :: FactAtoms
literature_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "роман" "романа" "романе" "роман" "романом" "романы"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1869"])
  ,   (AtomYear,      [plainSlot AtomYear "1869"])
  , (TVerb,         [nounSlot TVerb
                       "повествовать" "повествование" "повествования" "повествовании" "повествование" "повествованием"])
  , (TObject,       [nounSlot TObject "событие" "события" "событии" "событие" "событием" "события"])
  , (AtomProperty,     [plainSlot TModifier "эпический"])
  , (AtomProperty,     [plainSlot TModifier "великий"])
  , (AtomProperty,      [plainSlot TModifier "многоперсонажный"])
  , (AtomQuantity,      [plainSlot AtomQuantity "580"])

  ])
literature_fact1 :: FactAtoms
literature_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "комедия" "комедии" "комедии" "комедию" "комедией" "комедии"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1321"])
  ,   (AtomYear,      [plainSlot AtomYear "1321"])
  , (TVerb,         [nounSlot TVerb
                       "описывать" "описание" "описания" "описании" "описание" "описанием"])
  , (TObject,       [nounSlot TObject "путешествие" "путешествия" "путешествии" "путешествие" "путешествием" "путешествия"])
  , (AtomProperty,     [plainSlot TModifier "аллегорический"])

  ])
literature_fact2 :: FactAtoms
literature_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "мигель" "мигеля" "мигеле" "мигель" "мигелем" "мигели"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1605"])
  ,   (AtomYear,      [plainSlot AtomYear "1605"])
  ,   (AtomDiscoverer,[nounSlot AtomDiscoverer "Сервантес" "Сервантеса" "Сервантесе" "Сервантеса" "Сервантесом" ""])
  , (TVerb,         [nounSlot TVerb
                       "считаться" "считание" "считания" "считании" "считание" "считанием"])
  , (TObject,       [nounSlot TObject "роман" "романа" "романе" "роман" "романом" "романы"])

  ])
art_fact0 :: FactAtoms
art_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "леонардо" "леонардо" "леонардо" "леонардо" "леонардо" "леонардо"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1503"])
  ,   (AtomYear,      [plainSlot AtomYear "1503"])
  ,   (AtomDiscoverer,[nounSlot AtomDiscoverer "Винчи" "Винчи" "Винчи" "Винчи" "Винчи" ""])

  ])
art_fact1 :: FactAtoms
art_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "импрессионизм" "импрессионизма" "импрессионизме" "импрессионизм" "импрессионизмом" "импрессионизмы"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1870"])
  ,   (AtomYear,      [plainSlot AtomYear "1870"])
  ,   (AtomDiscoverer,[nounSlot AtomDiscoverer "Франция" "Франции" "Франции" "Францию" "Францией" ""])
  , (TVerb,         [nounSlot TVerb
                       "возникать" "возникновение" "возникновения" "возникновении" "возникновение" "возникновением"])
  , (AtomQuantity,       [plainSlot AtomQuantity "1870"])

  ])
art_fact2 :: FactAtoms
art_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "пабло" "пабло" "пабло" "пабло" "пабло" "пабло"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1937"])
  ,   (AtomYear,      [plainSlot AtomYear "1937"])
  , (TVerb,            [nounSlot TVerb
                       "изображать" "изображение" "изображения" "изображении" "изображение" "изображением"])
  , (TObject,            [nounSlot TObject "образ" "образа" "образе" "образ" "образом" "образы"])
  , (AtomProperty,            [plainSlot TModifier "художественный"])
  -- [decomposed] -- ,   (AtomProperty,  [plainSlot TModifier "его картина \"Герника\" (1937) стала антивоенным символом"])

  ])
music_fact0 :: FactAtoms
music_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "иоганн" "иоганна" "иоганне" "иоганна" "иоганном" "иоганны"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1685"])
  ,   (AtomYear,      [plainSlot AtomYear "1685"])
  , (TVerb,            [nounSlot TVerb
                       "исполнять" "исполнение" "исполнения" "исполнении" "исполнение" "исполнением"])
  , (TObject,            [nounSlot TObject "мелодия" "мелодии" "мелодии" "мелодию" "мелодией" "мелодии"])
  , (AtomProperty,            [plainSlot TModifier "музыкальный"])

  ])
music_fact1 :: FactAtoms
music_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "вольфганг" "вольфганга" "вольфганге" "вольфганга" "вольфгангом" "вольфганги"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "5"])
  , (TVerb,            [nounSlot TVerb
                       "исполнять" "исполнение" "исполнения" "исполнении" "исполнение" "исполнением"])
  , (TObject,            [nounSlot TObject "мелодия" "мелодии" "мелодии" "мелодию" "мелодией" "мелодии"])
  , (AtomProperty,            [plainSlot TModifier "музыкальный"])
  -- [converted AtomScale→AtomRelation] -- ,   (AtomScale,     [plainSlot AtomScale "в 5 лет"])
  ,   (AtomRelation,     [plainSlot AtomRelation "в 5 лет"])

  ])
music_fact2 :: FactAtoms
music_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "людвиг" "людвига" "людвиге" "людвига" "людвигом" "людвиги"])
  , (TVerb,            [nounSlot TVerb
                       "исполнять" "исполнение" "исполнения" "исполнении" "исполнение" "исполнением"])
  , (TObject,            [nounSlot TObject "мелодия" "мелодии" "мелодии" "мелодию" "мелодией" "мелодии"])
  , (AtomProperty,            [plainSlot TModifier "музыкальный"])

  ])
philosophy_fact0 :: FactAtoms
philosophy_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "сократ" "сократа" "сократе" "сократа" "сократом" "сократы"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "469"])
  , (TVerb,            [nounSlot TVerb
                       "осмысливать" "осмысливание" "осмысливания" "осмысливании" "осмысливание" "осмысливанием"])
  , (TObject,            [nounSlot TObject "категория" "категории" "категории" "категорию" "категорией" "категории"])
  , (AtomProperty,            [plainSlot TModifier "философский"])

  ])
philosophy_fact1 :: FactAtoms
philosophy_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "критика" "критики" "критике" "критику" "критикой" "критики"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1781"])
  ,   (AtomYear,      [plainSlot AtomYear "1781"])
  , (TVerb,         [nounSlot TVerb "исследовать" "исследования" "исследовании" "исследование" "исследованием" ""])
  , (TObject,       [nounSlot TObject "разум" "разума" "разуме" "разум" "разумом" ""])
  , (TObject,       [nounSlot TObject "познание" "познания" "познании" "познание" "познанием" "познания"])
  , (AtomProperty,     [plainSlot TModifier "критический"])
  , (AtomProperty,     [plainSlot TModifier "философский"])
  ,   (AtomContext,   [nounSlot AtomContext "явление" "явления" "явлении" "явление" "явлением" "явления"])

  ])
philosophy_fact2 :: FactAtoms
philosophy_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "аристотель" "аристотеля" "аристотеле" "аристотеля" "аристотелем" "аристотели"])
  , (TVerb,            [nounSlot TVerb
                       "осмысливать" "осмысливание" "осмысливания" "осмысливании" "осмысливание" "осмысливанием"])
  , (TObject,            [nounSlot TObject "категория" "категории" "категории" "категорию" "категорией" "категории"])
  , (AtomProperty,            [plainSlot TModifier "философский"])
  ,   (AtomContext,   [nounSlot AtomContext "Орган" "Органа" "Органе" "Орган" "Органом" "Органы"])

  ])
religion_fact0 :: FactAtoms
religion_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "христианство" "христианства" "христианстве" "христианство" "христианством" "христианства"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "2,4"])
  , (AtomProperty,       [plainSlot TModifier "крупный"])
  , (AtomQuantity,       [plainSlot AtomQuantity "2,4"])
  ,   (AtomContext,   [nounSlot AtomContext "религия" "религии" "религии" "религию" "религией" "религии"])

  ])
religion_fact1 :: FactAtoms
religion_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "ислам" "ислама" "исламе" "ислам" "исламом" "исламы"])
  , (TVerb,            [nounSlot TVerb "исповедовать" "исповедования" "исповедовании" "исповедование" "исповедованием" ""])
  , (TObject,            [nounSlot TObject "учение" "учения" "учении" "учение" "учением" "учения"])
  , (AtomProperty,            [plainSlot TModifier "религиозный"])
  -- [decomposed] -- ,   (AtomProperty,  [plainSlot TModifier "основатель — пророк Мухаммед"])
  , (AtomSubject,       [nounSlot AtomSubject "основатель" "основателя" "основателе" "основателя" "основателем" "основатели"])

  ])
religion_fact2 :: FactAtoms
religion_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "индуизм" "индуизма" "индуизме" "индуизм" "индуизмом" "индуизмы"])
  , (TVerb,            [nounSlot TVerb "исповедовать" "исповедования" "исповедовании" "исповедование" "исповедованием" ""])
  , (TObject,            [nounSlot TObject "учение" "учения" "учении" "учение" "учением" "учения"])
  , (AtomProperty,            [plainSlot TModifier "религиозный"])

  ])
politics_fact0 :: FactAtoms
politics_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "демократия" "демократии" "демократии" "демократию" "демократией" "демократии"])
  , (TVerb,            [nounSlot TVerb
                       "управлять" "управление" "управления" "управлении" "управление" "управлением"])
  , (TObject,            [nounSlot TObject "государство" "государства" "государстве" "государство" "государством" "государства"])
  , (AtomProperty,            [plainSlot TModifier "политический"])

  ])
politics_fact1 :: FactAtoms
politics_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "организация" "организации" "организации" "организацию" "организацией" "организации"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1945"])
  ,   (AtomYear,      [plainSlot AtomYear "1945"])
  , (TVerb,         [nounSlot TVerb
                       "создавать" "создание" "создания" "создании" "создание" "созданием"
                    ,nounSlot TVerb
                       "включать" "включение" "включения" "включении" "включение" "включением"])
  , (AtomQuantity,       [plainSlot AtomQuantity "1945"
                      ,plainSlot AtomQuantity "193"])
  -- [decomposed AtomScale] -- ,   (AtomScale,     [plainSlot AtomScale "в 1945 году"])
  , (TQuantity,            [plainSlot TQuantity "1945"])
  ,   (AtomContext,   [nounSlot AtomContext "Орган" "Органа" "Органе" "Орган" "Органом" "Органы"])

  ])
politics_fact2 :: FactAtoms
politics_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "разделение" "разделения" "разделении" "разделение" "разделением" "разделения"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1748"])
  ,   (AtomYear,      [plainSlot AtomYear "1748"])
  , (TVerb,            [nounSlot TVerb
                       "управлять" "управление" "управления" "управлении" "управление" "управлением"])
  , (TObject,            [nounSlot TObject "государство" "государства" "государстве" "государство" "государством" "государства"])
  , (AtomProperty,            [plainSlot TModifier "политический"])
  ,   (AtomContext,   [nounSlot AtomContext "закон" "закона" "законе" "закон" "законом" "законы"])

  ])
sociology_fact0 :: FactAtoms
sociology_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "огюст" "огюста" "огюсте" "огюста" "огюстом" "огюсты"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1830"])
  ,   (AtomYear,      [plainSlot AtomYear "1830"])
  , (TVerb,            [nounSlot TVerb "взаимодействовать" "взаимодействования" "взаимодействовании" "взаимодействование" "взаимодействованием" ""])
  , (TObject,            [nounSlot TObject "группа" "группы" "группе" "группу" "группой" "группы"])
  , (AtomProperty,            [plainSlot TModifier "социальный"])

  ])
sociology_fact1 :: FactAtoms
sociology_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "макс" "макса" "максе" "макса" "максом" "максы"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1905"])
  ,   (AtomYear,      [plainSlot AtomYear "1905"])
  , (TVerb,            [nounSlot TVerb "взаимодействовать" "взаимодействования" "взаимодействовании" "взаимодействование" "взаимодействованием" ""])
  , (TObject,            [nounSlot TObject "группа" "группы" "группе" "группу" "группой" "группы"])
  , (AtomProperty,            [plainSlot TModifier "социальный"])

  ])
sociology_fact2 :: FactAtoms
sociology_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "эмиль" "эмиля" "эмиле" "эмиля" "эмилем" "эмили"])
  ,   (AtomQuantity,  [plainSlot AtomQuantity "1897"])
  ,   (AtomYear,      [plainSlot AtomYear "1897"])
  , (TVerb,            [nounSlot TVerb "взаимодействовать" "взаимодействования" "взаимодействовании" "взаимодействование" "взаимодействованием" ""])
  , (TObject,            [nounSlot TObject "группа" "группы" "группе" "группу" "группой" "группы"])
  , (AtomProperty,            [plainSlot TModifier "социальный"])
  ,   (AtomContext,   [nounSlot AtomContext "закон" "закона" "законе" "закон" "законом" "законы"])


  ])


gen_medicine_fact0 :: FactAtoms
gen_medicine_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "сердце" "сердца" "сердце" "сердце" "сердцем" "сердца"])
  , (AtomProperty, [plainSlot TModifier "мышечный"
                    ,nounSlot AtomProperty "орган" "органа" "органе" "орган" "органом" "органы"])
  , (AtomContext,  [plainSlot TModifier "кровеносный"
                    ,nounSlot AtomContext "система" "системы" "системе" "систему" "системой" "системы"])
  ])

gen_medicine_fact1 :: FactAtoms
gen_medicine_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "артерия" "артерии" "артерии" "артерию" "артерией" "артерии"])
  , (AtomProperty, [plainSlot TModifier "кровеносный"
                    ,nounSlot AtomProperty "сосуд" "сосуда" "сосуде" "сосуд" "сосудом" "сосуды"])
  , (AtomContext,  [plainSlot TModifier "кровеносный"
                    ,nounSlot AtomContext "система" "системы" "системе" "систему" "системой" "системы"])
  ])

gen_medicine_fact2 :: FactAtoms
gen_medicine_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "печень" "печени" "печени" "печень" "печенью" "печени"])
  , (AtomProperty, [plainSlot TModifier "фильтрующий"
                    ,nounSlot AtomProperty "орган" "органа" "органе" "орган" "органом" "органы"])
  , (AtomContext,  [plainSlot TModifier "пищеварительный"
                    ,nounSlot AtomContext "система" "системы" "системе" "систему" "системой" "системы"])
  ])

gen_medicine_fact3 :: FactAtoms
gen_medicine_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "тело" "тела" "теле" "тело" "телом" "тела"])
  , (AtomProperty, [plainSlot TModifier "физический"
                    ,nounSlot AtomProperty "объект" "объекта" "объекте" "объект" "объектом" "объекты"])
  , (AtomContext,  [nounSlot AtomContext "анатомия" "анатомии" "анатомии" "анатомию" "анатомией" "анатомии"])
  ])

gen_medicine_fact4 :: FactAtoms
gen_medicine_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "группа" "группы" "группе" "группу" "группой" "группы"])
  , (AtomProperty, [nounSlot AtomProperty "категоризация" "категоризации" "категоризации" "категоризацию" "категоризацией" "категоризации"])
  , (AtomContext,  [nounSlot AtomContext "классификация" "классификации" "классификации" "классификацию" "классификацией" "классификации"])
  ])

gen_physics_fact0 :: FactAtoms
gen_physics_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "скорость" "скорости" "скорости" "скорость" "скоростью" "скорости"])
  , (AtomProperty, [plainSlot TModifier "физический"
                    ,nounSlot AtomProperty "величина" "величины" "величине" "величину" "величиной" "величины"])
  , (AtomContext,  [nounSlot AtomContext "механика" "механики" "механике" "механику" "механикой" "механики"])
  ])

gen_physics_fact1 :: FactAtoms
gen_physics_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "закон" "закона" "законе" "закон" "законом" "законы"])
  , (AtomProperty, [plainSlot TModifier "нормативный"
                    ,nounSlot AtomProperty "правило" "правила" "правиле" "правило" "правилом" "правила"])
  , (AtomContext,  [nounSlot AtomContext "юриспруденция" "юриспруденции" "юриспруденции" "юриспруденцию" "юриспруденцией" "юриспруденции"])
  ])

gen_physics_fact2 :: FactAtoms
gen_physics_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "атом" "атома" "атоме" "атом" "атомом" "атомы"])
  , (AtomProperty, [plainSlot TModifier "мельчайший"
                    ,nounSlot AtomProperty "частица" "частицы" "частице" "частицу" "частицей" "частицы"])
  , (AtomContext,  [nounSlot AtomContext "физика" "физики" "физике" "физику" "физикой" "физики"])
  ])

gen_physics_fact3 :: FactAtoms
gen_physics_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "теория" "теории" "теории" "теорию" "теорией" "теории"])
  -- [decomposed] -- , (AtomProperty, [plainSlot TModifier "система идей"])
  , (AtomContext,  [nounSlot AtomContext "наука" "науки" "науке" "науку" "наукой" "науки"])
  ])

gen_physics_fact4 :: FactAtoms
gen_physics_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "механика" "механики" "механике" "механику" "механикой" "механики"])
  -- [decomposed] -- , (AtomProperty, [plainSlot TModifier "раздел физики"])
  , (AtomContext,  [nounSlot AtomContext "физика" "физики" "физике" "физику" "физикой" "физики"])
  ])

gen_chemistry_fact0 :: FactAtoms
gen_chemistry_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "вода" "воды" "воде" "воду" "водой" "воды"])
  , (AtomProperty, [nounSlot AtomProperty "жидкость" "жидкости" "жидкости" "жидкость" "жидкостью" "жидкости"])
  , (AtomContext,  [nounSlot AtomContext "химия" "химии" "химии" "химию" "химией" "химии"])
  ])

gen_chemistry_fact1 :: FactAtoms
gen_chemistry_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "таблица" "таблицы" "таблице" "таблицу" "таблицей" "таблицы"])
  -- [decomposed] -- , (AtomProperty, [plainSlot TModifier "структура данных"])
  , (AtomContext,  [nounSlot AtomContext "информация" "информации" "информации" "информацию" "информацией" "информации"])
  ])

gen_chemistry_fact2 :: FactAtoms
gen_chemistry_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "элемент" "элемента" "элементе" "элемент" "элементом" "элементы"])
  , (AtomProperty, [plainSlot TModifier "составной"
                    ,nounSlot AtomProperty "часть" "части" "части" "часть" "частью" "части"])
  , (AtomContext,  [nounSlot AtomContext "химия" "химии" "химии" "химию" "химией" "химии"])
  ])

gen_chemistry_fact3 :: FactAtoms
gen_chemistry_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "углерод" "углерода" "углероде" "углерод" "углеродом" "углероды"])
  , (AtomProperty, [plainSlot TModifier "химический"
                    ,nounSlot AtomProperty "элемент" "элемента" "элементе" "элемент" "элементом" "элементы"])
  , (AtomContext,  [plainSlot TModifier "органический"
                    ,nounSlot AtomContext "химия" "химии" "химии" "химию" "химией" "химии"])
  ])

gen_chemistry_fact4 :: FactAtoms
gen_chemistry_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "реакция" "реакции" "реакции" "реакцию" "реакцией" "реакции"])
  -- [decomposed] -- , (AtomProperty, [plainSlot TModifier "процесс превращения"])
  , (AtomContext,  [nounSlot AtomContext "химия" "химии" "химии" "химию" "химией" "химии"])
  ])

gen_biology_fact0 :: FactAtoms
gen_biology_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "теория" "теории" "теории" "теорию" "теорией" "теории"])
  -- [decomposed] -- , (AtomProperty, [plainSlot TModifier "система идей"])
  , (AtomContext,  [nounSlot AtomContext "наука" "науки" "науке" "науку" "наукой" "науки"])
  ])

gen_biology_fact1 :: FactAtoms
gen_biology_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "клетка" "клетки" "клетке" "клетку" "клеткой" "клетки"])
  , (AtomProperty, [plainSlot TModifier "структурный"
                    ,nounSlot AtomProperty "единица" "единицы" "единице" "единицу" "единицей" "единицы"])
  , (AtomContext,  [nounSlot AtomContext "биология" "биологии" "биологии" "биологию" "биологией" "биологии"])
  ])

gen_biology_fact2 :: FactAtoms
gen_biology_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "митохондрия" "митохондрии" "митохондрии" "митохондрию" "митохондрией" "митохондрии"])
  , (AtomProperty, [plainSlot TModifier "клеточный"
                    ,nounSlot AtomProperty "органелла" "органеллы" "органелле" "органеллу" "органеллой" "органеллы"])
  , (AtomContext,  [nounSlot AtomContext "биология" "биологии" "биологии" "биологию" "биологией" "биологии"])
  ])

gen_biology_fact3 :: FactAtoms
gen_biology_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "геном" "генома" "геноме" "геном" "геномом" "геномы"])
  , (AtomProperty, [plainSlot TModifier "генетический"
                    ,nounSlot AtomProperty "информация" "информации" "информации" "информацию" "информацией" "информации"])
  , (AtomContext,  [nounSlot AtomContext "биология" "биологии" "биологии" "биологию" "биологией" "биологии"])
  ])

gen_biology_fact4 :: FactAtoms
gen_biology_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "существо" "существа" "существе" "существо" "существом" "существа"])
  , (AtomProperty, [plainSlot TModifier "живой"
                    ,nounSlot AtomProperty "организм" "организма" "организме" "организм" "организмом" "организмы"])
  , (AtomContext,  [nounSlot AtomContext "биология" "биологии" "биологии" "биологию" "биологией" "биологии"])
  ])

gen_mathematics_fact0 :: FactAtoms
gen_mathematics_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "число" "числа" "числе" "число" "числом" "числа"])
  , (AtomProperty, [plainSlot TModifier "математический"
                    ,nounSlot AtomProperty "абстракция" "абстракции" "абстракции" "абстракцию" "абстракцией" "абстракции"])
  , (AtomContext,  [nounSlot AtomContext "математика" "математики" "математике" "математику" "математикой" "математики"])
  ])

gen_mathematics_fact1 :: FactAtoms
gen_mathematics_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "теорема" "теоремы" "теореме" "теорему" "теоремой" "теоремы"])
  , (AtomProperty, [plainSlot TModifier "доказанный"
                    ,nounSlot AtomProperty "утверждение" "утверждения" "утверждении" "утверждение" "утверждением" "утверждения"])
  , (AtomContext,  [nounSlot AtomContext "математика" "математики" "математике" "математику" "математикой" "математики"])
  ])

gen_mathematics_fact2 :: FactAtoms
gen_mathematics_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "теорема" "теоремы" "теореме" "теорему" "теоремой" "теоремы"])
  , (AtomProperty, [plainSlot TModifier "доказанный"
                    ,nounSlot AtomProperty "утверждение" "утверждения" "утверждении" "утверждение" "утверждением" "утверждения"])
  , (AtomContext,  [nounSlot AtomContext "математика" "математики" "математике" "математику" "математикой" "математики"])
  ])

gen_mathematics_fact3 :: FactAtoms
gen_mathematics_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "ноль" "ноля" "ноле" "ноль" "нолём" "ноли"])
  , (AtomProperty, [plainSlot TModifier "нулевый"
                    ,nounSlot AtomProperty "значение" "значения" "значении" "значение" "значением" "значения"])
  , (AtomContext,  [nounSlot AtomContext "математика" "математики" "математике" "математику" "математикой" "математики"])
  ])

gen_mathematics_fact4 :: FactAtoms
gen_mathematics_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "сечение" "сечения" "сечении" "сечение" "сечением" "сечения"])
  , (AtomProperty, [plainSlot TModifier "геометрический"
                    ,nounSlot AtomProperty "операция" "операции" "операции" "операцию" "операцией" "операции"])
  , (AtomContext,  [nounSlot AtomContext "математика" "математики" "математике" "математику" "математикой" "математики"])
  ])

gen_astronomy_fact0 :: FactAtoms
gen_astronomy_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "возраст" "возраста" "возрасте" "возраст" "возрастом" "возрасты"])
  , (AtomProperty, [plainSlot TModifier "временной"
                    ,nounSlot AtomProperty "параметр" "параметра" "параметре" "параметр" "параметром" "параметры"])
  , (AtomContext,  [nounSlot AtomContext "хронология" "хронологии" "хронологии" "хронологию" "хронологией" "хронологии"])
  ])

gen_astronomy_fact1 :: FactAtoms
gen_astronomy_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "солнце" "солнца" "солнце" "солнце" "солнцем" "солнца"])
  , (AtomProperty, [nounSlot AtomProperty "звезда" "звезды" "звезде" "звезду" "звездой" "звёзды"])
  , (AtomContext,  [nounSlot AtomContext "астрономия" "астрономии" "астрономии" "астрономию" "астрономией" "астрономии"])
  ])

gen_astronomy_fact2 :: FactAtoms
gen_astronomy_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "дыра" "дыры" "дыре" "дыру" "дырой" "дыры"])
  -- [decomposed] -- , (AtomProperty, [plainSlot TModifier "область пространства"])
  , (AtomContext,  [nounSlot AtomContext "астрофизика" "астрофизики" "астрофизике" "астрофизику" "астрофизикой" "астрофизики"])
  ])

gen_astronomy_fact3 :: FactAtoms
gen_astronomy_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "планета" "планеты" "планете" "планету" "планетой" "планеты"])
  , (AtomProperty, [plainSlot TModifier "небесный"
                    ,nounSlot AtomProperty "тело" "тела" "теле" "тело" "телом" "тела"])
  , (AtomContext,  [nounSlot AtomContext "астрономия" "астрономии" "астрономии" "астрономию" "астрономией" "астрономии"])
  ])

gen_astronomy_fact4 :: FactAtoms
gen_astronomy_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "свет" "света" "свете" "свет" "светом" "свет"])
  , (AtomProperty, [plainSlot TModifier "электромагнитный"
                    ,nounSlot AtomProperty "излучение" "излучения" "излучении" "излучение" "излучением" "излучения"])
  , (AtomContext,  [nounSlot AtomContext "физика" "физики" "физике" "физику" "физикой" "физики"])
  ])

gen_geography_fact0 :: FactAtoms
gen_geography_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "гора" "горы" "горе" "гору" "горой" "горы"])
  , (AtomProperty, [nounSlot AtomProperty "возвышенность" "возвышенности" "возвышенности" "возвышенность" "возвышенностью" "возвышенности"])
  , (AtomContext,  [nounSlot AtomContext "география" "географии" "географии" "географию" "географией" "географии"])
  ])

gen_geography_fact1 :: FactAtoms
gen_geography_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "точка" "точки" "точке" "точку" "точкой" "точки"])
  , (AtomProperty, [plainSlot TModifier "геометрический"
                    ,nounSlot AtomProperty "локальность" "локальности" "локальности" "локальность" "локальностью" "локальности"])
  , (AtomContext,  [nounSlot AtomContext "математика" "математики" "математике" "математику" "математикой" "математики"])
  ])

gen_geography_fact2 :: FactAtoms
gen_geography_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "озеро" "озера" "озере" "озеро" "озером" "озёра"])
  , (AtomProperty, [nounSlot AtomProperty "водоём" "водоёма" "водоёме" "водоём" "водоёмом" "водоёмы"])
  , (AtomContext,  [nounSlot AtomContext "география" "географии" "географии" "географию" "географией" "географии"])
  ])

gen_geography_fact3 :: FactAtoms
gen_geography_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "река" "реки" "реке" "реку" "рекой" "реки"])
  , (AtomProperty, [nounSlot AtomProperty "ландшафт" "ландшафта" "ландшафте" "ландшафт" "ландшафтом" "ландшафты"])
  , (AtomContext,  [nounSlot AtomContext "география" "географии" "географии" "географию" "географией" "географии"])
  ])

gen_geography_fact4 :: FactAtoms
gen_geography_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "сахар" "сахара" "сахаре" "сахар" "сахаром" "сахара"])
  , (AtomProperty, [nounSlot AtomProperty "почва" "почвы" "почве" "почву" "почвой" "почвы"])
  , (AtomContext,  [nounSlot AtomContext "география" "географии" "географии" "географию" "географией" "географии"])
  ])

gen_history_fact0 :: FactAtoms
gen_history_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "римская" "римской" "римской" "римскую" "римской" "римские"])
  , (AtomProperty, [plainSlot TModifier "исторический"
                    ,nounSlot AtomProperty "эпоха" "эпохи" "эпохе" "эпоху" "эпохой" "эпохи"])
  , (AtomContext,  [nounSlot AtomContext "история" "истории" "истории" "историю" "историей" "истории"])
  ])

gen_history_fact1 :: FactAtoms
gen_history_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "революция" "революции" "революции" "революцию" "революцией" "революции"])
  , (AtomProperty, [plainSlot TModifier "радикальный"
                    ,nounSlot AtomProperty "изменение" "изменения" "изменении" "изменение" "изменением" "изменения"])
  , (AtomContext,  [nounSlot AtomContext "история" "истории" "истории" "историю" "историей" "истории"])
  ])

gen_history_fact2 :: FactAtoms
gen_history_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "война" "войны" "войне" "войну" "войной" "войны"])
  , (AtomProperty, [plainSlot TModifier "вооружённый"
                    ,nounSlot AtomProperty "конфликт" "конфликта" "конфликте" "конфликт" "конфликтом" "конфликты"])
  , (AtomContext,  [nounSlot AtomContext "история" "истории" "истории" "историю" "историей" "истории"])
  ])

gen_history_fact3 :: FactAtoms
gen_history_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "великое" "великого" "великом" "великое" "великим" "великие"])
  , (AtomProperty, [nounSlot AtomProperty "реформа" "реформы" "реформе" "реформу" "реформой" "реформы"])
  , (AtomContext,  [nounSlot AtomContext "история" "истории" "истории" "историю" "историей" "истории"])
  ])

gen_history_fact4 :: FactAtoms
gen_history_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "эпоха" "эпохи" "эпохе" "эпоху" "эпохой" "эпохи"])
  , (AtomProperty, [nounSlot AtomProperty "памятник" "памятника" "памятнике" "памятник" "памятником" "памятники"])
  , (AtomContext,  [nounSlot AtomContext "история" "истории" "истории" "историю" "историей" "истории"])
  ])

gen_law_fact0 :: FactAtoms
gen_law_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "право" "права" "праве" "право" "правом" "права"])
  , (AtomProperty, [plainSlot TModifier "нормативный"
                    ,nounSlot AtomProperty "система" "системы" "системе" "систему" "системой" "системы"])
  , (AtomContext,  [nounSlot AtomContext "юриспруденция" "юриспруденции" "юриспруденции" "юриспруденцию" "юриспруденцией" "юриспруденции"])
  ])

gen_law_fact1 :: FactAtoms
gen_law_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "хартия" "хартии" "хартии" "хартию" "хартией" "хартии"])
  , (AtomProperty, [plainSlot TModifier "исторический"
                    ,nounSlot AtomProperty "документ" "документа" "документе" "документ" "документом" "документы"])
  , (AtomContext,  [nounSlot AtomContext "история права" "истории права" "истории права" "историю права" "историей права" "истории права"])
  ])

gen_law_fact2 :: FactAtoms
gen_law_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "презумпция" "презумпции" "презумпции" "презумпцию" "презумпцией" "презумпции"])
  , (AtomProperty, [plainSlot TModifier "правовой"
                    ,nounSlot AtomProperty "принцип" "принципа" "принципе" "принцип" "принципом" "принципы"])
  , (AtomContext,  [nounSlot AtomContext "юриспруденция" "юриспруденции" "юриспруденции" "юриспруденцию" "юриспруденцией" "юриспруденции"])
  ])

gen_law_fact3 :: FactAtoms
gen_law_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "декларация" "декларации" "декларации" "декларацию" "декларацией" "декларации"])
  , (AtomProperty, [nounSlot AtomProperty "санкция" "санкции" "санкции" "санкцию" "санкцией" "санкции"])
  , (AtomContext,  [nounSlot AtomContext "юриспруденция" "юриспруденции" "юриспруденции" "юриспруденцию" "юриспруденцией" "юриспруденции"])
  ])

gen_law_fact4 :: FactAtoms
gen_law_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "конституция" "конституции" "конституции" "конституцию" "конституцией" "конституции"])
  , (AtomProperty, [nounSlot AtomProperty "апелляция" "апелляции" "апелляции" "апелляцию" "апелляцией" "апелляции"])
  , (AtomContext,  [nounSlot AtomContext "юриспруденция" "юриспруденции" "юриспруденции" "юриспруденцию" "юриспруденцией" "юриспруденции"])
  ])

gen_economics_fact0 :: FactAtoms
gen_economics_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "адам" "адама" "адаме" "адама" "адамом" "адамы"])
  , (AtomProperty, [nounSlot AtomProperty "экономист" "экономиста" "экономисте" "экономиста" "экономистом" "экономисты"])
  , (AtomContext,  [nounSlot AtomContext "экономика" "экономики" "экономике" "экономику" "экономикой" "экономики"])
  ])

gen_economics_fact1 :: FactAtoms
gen_economics_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "валова" "валовой" "валовой" "валову" "валовой" "валовы"])
  , (AtomProperty, [plainSlot TModifier "макроэкономический"
                    ,nounSlot AtomProperty "показатель" "показателя" "показателе" "показатель" "показателем" "показатели"])
  , (AtomContext,  [nounSlot AtomContext "экономика" "экономики" "экономике" "экономику" "экономикой" "экономики"])
  ])

gen_economics_fact2 :: FactAtoms
gen_economics_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "инфляция" "инфляции" "инфляции" "инфляцию" "инфляцией" "инфляции"])
  -- [decomposed] -- , (AtomProperty, [plainSlot TModifier "рост цен"])
  , (AtomContext,  [nounSlot AtomContext "экономика" "экономики" "экономике" "экономику" "экономикой" "экономики"])
  ])

gen_economics_fact3 :: FactAtoms
gen_economics_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "закон" "закона" "законе" "закон" "законом" "законы"])
  , (AtomProperty, [plainSlot TModifier "нормативный"
                    ,nounSlot AtomProperty "правило" "правила" "правиле" "правило" "правилом" "правила"])
  , (AtomContext,  [nounSlot AtomContext "юриспруденция" "юриспруденции" "юриспруденции" "юриспруденцию" "юриспруденцией" "юриспруденции"])
  ])

gen_economics_fact4 :: FactAtoms
gen_economics_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "депрессия" "депрессии" "депрессии" "депрессию" "депрессией" "депрессии"])
  , (AtomProperty, [nounSlot AtomProperty "капитал" "капитала" "капитале" "капитал" "капиталом" "капиталы"])
  , (AtomContext,  [nounSlot AtomContext "экономика" "экономики" "экономике" "экономику" "экономикой" "экономики"])
  ])

gen_computer_science_fact0 :: FactAtoms
gen_computer_science_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "алан" "алана" "алане" "алана" "аланом" "аланы"])
  , (AtomProperty, [nounSlot AtomProperty "учёный" "учёного" "учёном" "учёного" "учёным" "учёные"])
  , (AtomContext,  [nounSlot AtomContext "информатика" "информатики" "информатике" "информатику" "информатикой" "информатики"])
  ])

gen_computer_science_fact1 :: FactAtoms
gen_computer_science_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "компьютер" "компьютера" "компьютере" "компьютер" "компьютером" "компьютеры"])
  , (AtomProperty, [plainSlot TModifier "вычислительный"
                    ,nounSlot AtomProperty "машина" "машины" "машине" "машину" "машиной" "машины"])
  , (AtomContext,  [nounSlot AtomContext "информатика" "информатики" "информатике" "информатику" "информатикой" "информатики"])
  ])

gen_computer_science_fact2 :: FactAtoms
gen_computer_science_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "интернет" "интернета" "интернете" "интернет" "интернетом" "интернеты"])
  , (AtomProperty, [plainSlot TModifier "глобальный"
                    ,nounSlot AtomProperty "сеть" "сети" "сети" "сеть" "сетью" "сети"])
  , (AtomContext,  [plainSlot TModifier "информационный"
                    ,nounSlot AtomContext "технология" "технологии" "технологии" "технологию" "технологией" "технологии"])
  ])

gen_computer_science_fact3 :: FactAtoms
gen_computer_science_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "язык" "языка" "языке" "язык" "языком" "языки"])
  , (AtomProperty, [plainSlot TModifier "знаковый"
                    ,nounSlot AtomProperty "система" "системы" "системе" "систему" "системой" "системы"])
  , (AtomContext,  [nounSlot AtomContext "лингвистика" "лингвистики" "лингвистике" "лингвистику" "лингвистикой" "лингвистики"])
  ])

gen_computer_science_fact4 :: FactAtoms
gen_computer_science_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "сложность" "сложности" "сложности" "сложность" "сложностью" "сложности"])
  , (AtomProperty, [nounSlot AtomProperty "алгоритм" "алгоритма" "алгоритме" "алгоритм" "алгоритмом" "алгоритмы"])
  , (AtomContext,  [nounSlot AtomContext "информатика" "информатики" "информатике" "информатику" "информатикой" "информатики"])
  ])

gen_linguistics_fact0 :: FactAtoms
gen_linguistics_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "мир" "мира" "мире" "мир" "миром" "миры"])
  , (AtomProperty, [plainSlot TModifier "социальный"
                    ,nounSlot AtomProperty "пространство" "пространства" "пространстве" "пространство" "пространством" "пространства"])
  , (AtomContext,  [nounSlot AtomContext "социология" "социологии" "социологии" "социологию" "социологией" "социологии"])
  ])

gen_linguistics_fact1 :: FactAtoms
gen_linguistics_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "язык" "языка" "языке" "язык" "языком" "языки"])
  , (AtomProperty, [plainSlot TModifier "знаковый"
                    ,nounSlot AtomProperty "система" "системы" "системе" "систему" "системой" "системы"])
  , (AtomContext,  [nounSlot AtomContext "лингвистика" "лингвистики" "лингвистике" "лингвистику" "лингвистикой" "лингвистики"])
  ])

gen_linguistics_fact2 :: FactAtoms
gen_linguistics_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "санскрит" "санскрита" "санскрите" "санскрит" "санскритом" "санскриты"])
  , (AtomProperty, [plainSlot TModifier "древний"
                    ,nounSlot AtomProperty "язык" "языка" "языке" "язык" "языком" "языки"])
  , (AtomContext,  [nounSlot AtomContext "лингвистика" "лингвистики" "лингвистике" "лингвистику" "лингвистикой" "лингвистики"])
  ])

gen_linguistics_fact3 :: FactAtoms
gen_linguistics_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "фердинанд" "фердинанда" "фердинанде" "фердинанда" "фердинандом" "фердинанды"])
  , (AtomProperty, [nounSlot AtomProperty "диалект" "диалекта" "диалекте" "диалект" "диалектом" "диалекты"])
  , (AtomContext,  [nounSlot AtomContext "лингвистика" "лингвистики" "лингвистике" "лингвистику" "лингвистикой" "лингвистики"])
  ])

gen_linguistics_fact4 :: FactAtoms
gen_linguistics_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "язык" "языка" "языке" "язык" "языком" "языки"])
  , (AtomProperty, [plainSlot TModifier "знаковый"
                    ,nounSlot AtomProperty "система" "системы" "системе" "систему" "системой" "системы"])
  , (AtomContext,  [nounSlot AtomContext "лингвистика" "лингвистики" "лингвистике" "лингвистику" "лингвистикой" "лингвистики"])
  ])

gen_psychology_fact0 :: FactAtoms
gen_psychology_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "зигмунд" "зигмунда" "зигмунде" "зигмунда" "зигмундом" "зигмунды"])
  , (AtomProperty, [nounSlot AtomProperty "психолог" "психолога" "психологе" "психолога" "психологом" "психологи"])
  , (AtomContext,  [nounSlot AtomContext "психология" "психологии" "психологии" "психологию" "психологией" "психологии"])
  ])

gen_psychology_fact1 :: FactAtoms
gen_psychology_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "эксперимент" "эксперимента" "эксперименте" "эксперимент" "экспериментом" "эксперименты"])
  , (AtomProperty, [plainSlot TModifier "научный"
                    ,nounSlot AtomProperty "метод" "метода" "методе" "метод" "методом" "методы"])
  , (AtomContext,  [nounSlot AtomContext "психология" "психологии" "психологии" "психологию" "психологией" "психологии"])
  ])

gen_psychology_fact2 :: FactAtoms
gen_psychology_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "диссонанс" "диссонанса" "диссонансе" "диссонанс" "диссонансом" "диссонансы"])
  , (AtomProperty, [plainSlot TModifier "психический"
                    ,nounSlot AtomProperty "состояние" "состояния" "состоянии" "состояние" "состоянием" "состояния"])
  , (AtomContext,  [nounSlot AtomContext "психология" "психологии" "психологии" "психологию" "психологией" "психологии"])
  ])

gen_psychology_fact3 :: FactAtoms
gen_psychology_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "пирамида" "пирамиды" "пирамиде" "пирамиду" "пирамидой" "пирамиды"])
  , (AtomProperty, [nounSlot AtomProperty "поведение" "поведения" "поведении" "поведение" "поведением" "поведения"])
  , (AtomContext,  [nounSlot AtomContext "психология" "психологии" "психологии" "психологию" "психологией" "психологии"])
  ])

gen_psychology_fact4 :: FactAtoms
gen_psychology_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "эффект" "эффекта" "эффекте" "эффект" "эффектом" "эффекты"])
  , (AtomProperty, [nounSlot AtomProperty "сознание" "сознания" "сознании" "сознание" "сознанием" "сознания"])
  , (AtomContext,  [nounSlot AtomContext "психология" "психологии" "психологии" "психологию" "психологией" "психологии"])
  ])

gen_literature_fact0 :: FactAtoms
gen_literature_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "роман" "романа" "романе" "роман" "романом" "романы"])
  , (AtomProperty, [plainSlot TModifier "литературный"
                    ,nounSlot AtomProperty "жанр" "жанра" "жанре" "жанр" "жанром" "жанры"])
  , (AtomContext,  [nounSlot AtomContext "литература" "литературы" "литературе" "литературу" "литературой" "литературы"])
  ])

gen_literature_fact1 :: FactAtoms
gen_literature_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "комедия" "комедии" "комедии" "комедию" "комедией" "комедии"])
  , (AtomProperty, [plainSlot TModifier "драматический"
                    ,nounSlot AtomProperty "жанр" "жанра" "жанре" "жанр" "жанром" "жанры"])
  , (AtomContext,  [nounSlot AtomContext "литература" "литературы" "литературе" "литературу" "литературой" "литературы"])
  ])

gen_literature_fact2 :: FactAtoms
gen_literature_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "мигель" "мигеля" "мигеле" "мигель" "мигелем" "мигели"])
  , (AtomProperty, [plainSlot TModifier "испанский"
                    ,nounSlot AtomProperty "писатель" "писателя" "писателе" "писателя" "писателем" "писатели"])
  , (AtomContext,  [nounSlot AtomContext "литература" "литературы" "литературе" "литературу" "литературой" "литературы"])
  ])

gen_literature_fact3 :: FactAtoms
gen_literature_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "уильям" "уильяма" "уильяме" "уильяма" "уильямом" "уильямы"])
  , (AtomProperty, [nounSlot AtomProperty "рассказ" "рассказа" "рассказе" "рассказ" "рассказом" "рассказы"])
  , (AtomContext,  [nounSlot AtomContext "литература" "литературы" "литературе" "литературу" "литературой" "литературы"])
  ])

gen_literature_fact4 :: FactAtoms
gen_literature_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "фёдор" "фёдора" "фёдоре" "фёдора" "фёдором" "фёдоры"])
  , (AtomProperty, [nounSlot AtomProperty "поэзия" "поэзии" "поэзии" "поэзию" "поэзией" "поэзии"])
  , (AtomContext,  [nounSlot AtomContext "литература" "литературы" "литературе" "литературу" "литературой" "литературы"])
  ])

gen_art_fact0 :: FactAtoms
gen_art_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "леонардо" "леонардо" "леонардо" "леонардо" "леонардо" "леонардо"])
  , (AtomProperty, [plainSlot TModifier "итальянский"
                    ,nounSlot AtomProperty "художник" "художника" "художнике" "художника" "художником" "художники"])
  , (AtomContext,  [nounSlot AtomContext "искусство" "искусства" "искусстве" "искусство" "искусством" "искусства"])
  ])

gen_art_fact1 :: FactAtoms
gen_art_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "импрессионизм" "импрессионизма" "импрессионизме" "импрессионизм" "импрессионизмом" "импрессионизмы"])
  , (AtomProperty, [plainSlot TModifier "художественный"
                    ,nounSlot AtomProperty "направление" "направления" "направлении" "направление" "направлением" "направления"])
  , (AtomContext,  [nounSlot AtomContext "искусство" "искусства" "искусстве" "искусство" "искусством" "искусства"])
  ])

gen_art_fact2 :: FactAtoms
gen_art_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "пабло" "пабло" "пабло" "пабло" "пабло" "пабло"])
  , (AtomProperty, [plainSlot TModifier "испанский"
                    ,nounSlot AtomProperty "художник" "художника" "художнике" "художника" "художником" "художники"])
  , (AtomContext,  [nounSlot AtomContext "искусство" "искусства" "искусстве" "искусство" "искусством" "искусства"])
  ])

gen_art_fact3 :: FactAtoms
gen_art_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "капелла" "капеллы" "капелле" "капеллу" "капеллой" "капеллы"])
  , (AtomProperty, [plainSlot TModifier "архитектурный"
                    ,nounSlot AtomProperty "сооружение" "сооружения" "сооружении" "сооружение" "сооружением" "сооружения"])
  , (AtomContext,  [nounSlot AtomContext "искусство" "искусства" "искусстве" "искусство" "искусством" "искусства"])
  ])

gen_art_fact4 :: FactAtoms
gen_art_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "винсент" "винсента" "винсенте" "винсента" "винсентом" "винсенты"])
  , (AtomProperty, [plainSlot TModifier "голландский"
                    ,nounSlot AtomProperty "художник" "художника" "художнике" "художника" "художником" "художники"])
  , (AtomContext,  [nounSlot AtomContext "искусство" "искусства" "искусстве" "искусство" "искусством" "искусства"])
  ])

gen_music_fact0 :: FactAtoms
gen_music_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "иоганн" "иоганна" "иоганне" "иоганна" "иоганном" "иоганны"])
  , (AtomProperty, [plainSlot TModifier "немецкий"
                    ,nounSlot AtomProperty "композитор" "композитора" "композиторе" "композитора" "композитором" "композиторы"])
  , (AtomContext,  [nounSlot AtomContext "музыка" "музыки" "музыке" "музыку" "музыкой" "музыки"])
  ])

gen_music_fact1 :: FactAtoms
gen_music_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "вольфганг" "вольфганга" "вольфганге" "вольфганга" "вольфгангом" "вольфганги"])
  , (AtomProperty, [plainSlot TModifier "австрийский"
                    ,nounSlot AtomProperty "композитор" "композитора" "композиторе" "композитора" "композитором" "композиторы"])
  , (AtomContext,  [nounSlot AtomContext "музыка" "музыки" "музыке" "музыку" "музыкой" "музыки"])
  ])

gen_music_fact2 :: FactAtoms
gen_music_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "людвиг" "людвига" "людвиге" "людвига" "людвигом" "людвиги"])
  , (AtomProperty, [plainSlot TModifier "немецкий"
                    ,nounSlot AtomProperty "композитор" "композитора" "композиторе" "композитора" "композитором" "композиторы"])
  , (AtomContext,  [nounSlot AtomContext "музыка" "музыки" "музыке" "музыку" "музыкой" "музыки"])
  ])

gen_music_fact3 :: FactAtoms
gen_music_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "джаз" "джаза" "джазе" "джаз" "джазом" "джазы"])
  , (AtomProperty, [plainSlot TModifier "музыкальный"
                    ,nounSlot AtomProperty "направление" "направления" "направлении" "направление" "направлением" "направления"])
  , (AtomContext,  [nounSlot AtomContext "музыка" "музыки" "музыке" "музыку" "музыкой" "музыки"])
  ])

gen_music_fact4 :: FactAtoms
gen_music_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "рок" "рока" "роке" "рок" "роком" "роки"])
  , (AtomProperty, [plainSlot TModifier "музыкальный"
                    ,nounSlot AtomProperty "жанр" "жанра" "жанре" "жанр" "жанром" "жанры"])
  , (AtomContext,  [nounSlot AtomContext "музыка" "музыки" "музыке" "музыку" "музыкой" "музыки"])
  ])

gen_philosophy_fact0 :: FactAtoms
gen_philosophy_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "сократ" "сократа" "сократе" "сократа" "сократом" "сократы"])
  , (AtomProperty, [plainSlot TModifier "древнегреческий"
                    ,nounSlot AtomProperty "философ" "философа" "философе" "философа" "философом" "философы"])
  , (AtomContext,  [nounSlot AtomContext "философия" "философии" "философии" "философию" "философией" "философии"])
  ])

gen_philosophy_fact1 :: FactAtoms
gen_philosophy_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "критика" "критики" "критике" "критику" "критикой" "критики"])
  , (AtomProperty, [plainSlot TModifier "аналитический"
                    ,nounSlot AtomProperty "метод" "метода" "методе" "метод" "методом" "методы"])
  , (AtomContext,  [nounSlot AtomContext "философия" "философии" "философии" "философию" "философией" "философии"])
  ])

gen_philosophy_fact2 :: FactAtoms
gen_philosophy_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "аристотель" "аристотеля" "аристотеле" "аристотеля" "аристотелем" "аристотели"])
  , (AtomProperty, [plainSlot TModifier "древнегреческий"
                    ,nounSlot AtomProperty "философ" "философа" "философе" "философа" "философом" "философы"])
  , (AtomContext,  [nounSlot AtomContext "философия" "философии" "философии" "философию" "философией" "философии"])
  ])

gen_philosophy_fact3 :: FactAtoms
gen_philosophy_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "экзистенциализм" "экзистенциализма" "экзистенциализме" "экзистенциализм" "экзистенциализмом" "экзистенциализмы"])
  , (AtomProperty, [plainSlot TModifier "философский"
                    ,nounSlot AtomProperty "направление" "направления" "направлении" "направление" "направлением" "направления"])
  , (AtomContext,  [nounSlot AtomContext "философия" "философии" "философии" "философию" "философией" "философии"])
  ])

gen_philosophy_fact4 :: FactAtoms
gen_philosophy_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "заратустра" "заратустры" "заратустре" "заратустру" "заратустрой" "заратустры"])
  , (AtomProperty, [plainSlot TModifier "древнеиранский"
                    ,nounSlot AtomProperty "пророк" "пророка" "пророке" "пророка" "пророком" "пророки"])
  , (AtomContext,  [nounSlot AtomContext "философия" "философии" "философии" "философию" "философией" "философии"])
  ])

gen_religion_fact0 :: FactAtoms
gen_religion_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "христианство" "христианства" "христианстве" "христианство" "христианством" "христианства"])
  , (AtomProperty, [plainSlot TModifier "мировой"
                    ,nounSlot AtomProperty "религия" "религии" "религии" "религию" "религией" "религии"])
  , (AtomContext,  [nounSlot AtomContext "религия" "религии" "религии" "религию" "религией" "религии"])
  ])

gen_religion_fact1 :: FactAtoms
gen_religion_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "ислам" "ислама" "исламе" "ислам" "исламом" "исламы"])
  , (AtomProperty, [plainSlot TModifier "мировой"
                    ,nounSlot AtomProperty "религия" "религии" "религии" "религию" "религией" "религии"])
  , (AtomContext,  [nounSlot AtomContext "религия" "религии" "религии" "религию" "религией" "религии"])
  ])

gen_religion_fact2 :: FactAtoms
gen_religion_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "индуизм" "индуизма" "индуизме" "индуизм" "индуизмом" "индуизмы"])
  , (AtomProperty, [plainSlot TModifier "национальный"
                    ,nounSlot AtomProperty "религия" "религии" "религии" "религию" "религией" "религии"])
  , (AtomContext,  [nounSlot AtomContext "религия" "религии" "религии" "религию" "религией" "религии"])
  ])

gen_religion_fact3 :: FactAtoms
gen_religion_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "буддизм" "буддизма" "буддизме" "буддизм" "буддизмом" "буддизмы"])
  , (AtomProperty, [plainSlot TModifier "мировой"
                    ,nounSlot AtomProperty "религия" "религии" "религии" "религию" "религией" "религии"])
  , (AtomContext,  [nounSlot AtomContext "религия" "религии" "религии" "религию" "религией" "религии"])
  ])

gen_religion_fact4 :: FactAtoms
gen_religion_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "иудаизм" "иудаизма" "иудаизме" "иудаизм" "иудаизмом" "иудаизмы"])
  , (AtomProperty, [plainSlot TModifier "национальный"
                    ,nounSlot AtomProperty "религия" "религии" "религии" "религию" "религией" "религии"])
  , (AtomContext,  [nounSlot AtomContext "религия" "религии" "религии" "религию" "религией" "религии"])
  ])

gen_politics_fact0 :: FactAtoms
gen_politics_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "демократия" "демократии" "демократии" "демократию" "демократией" "демократии"])
  -- [decomposed] -- , (AtomProperty, [plainSlot TModifier "форма правления"])
  , (AtomContext,  [nounSlot AtomContext "политология" "политологии" "политологии" "политологию" "политологией" "политологии"])
  ])

gen_politics_fact1 :: FactAtoms
gen_politics_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "организация" "организации" "организации" "организацию" "организацией" "организации"])
  , (AtomProperty, [plainSlot TModifier "социальный"
                    ,nounSlot AtomProperty "структура" "структуры" "структуре" "структуру" "структурой" "структуры"])
  , (AtomContext,  [nounSlot AtomContext "социология" "социологии" "социологии" "социологию" "социологией" "социологии"])
  ])

gen_politics_fact2 :: FactAtoms
gen_politics_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "разделение" "разделения" "разделении" "разделение" "разделением" "разделения"])
  , (AtomProperty, [nounSlot AtomProperty "дифференциация" "дифференциации" "дифференциации" "дифференциацию" "дифференциацией" "дифференциации"])
  , (AtomContext,  [nounSlot AtomContext "политология" "политологии" "политологии" "политологию" "политологией" "политологии"])
  ])

gen_politics_fact3 :: FactAtoms
gen_politics_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "союз" "союза" "союзе" "союз" "союзом" "союзы"])
  , (AtomProperty, [nounSlot AtomProperty "объединение" "объединения" "объединении" "объединение" "объединением" "объединения"])
  , (AtomContext,  [nounSlot AtomContext "политология" "политологии" "политологии" "политологию" "политологией" "политологии"])
  ])

gen_politics_fact4 :: FactAtoms
gen_politics_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "война" "войны" "войне" "войну" "войной" "войны"])
  , (AtomProperty, [plainSlot TModifier "вооружённый"
                    ,nounSlot AtomProperty "конфликт" "конфликта" "конфликте" "конфликт" "конфликтом" "конфликты"])
  , (AtomContext,  [nounSlot AtomContext "история" "истории" "истории" "историю" "историей" "истории"])
  ])

gen_sociology_fact0 :: FactAtoms
gen_sociology_fact0 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "огюст" "огюста" "огюсте" "огюста" "огюстом" "огюсты"])
  , (AtomProperty, [plainSlot TModifier "французский"
                    ,nounSlot AtomProperty "социолог" "социолога" "социологе" "социолога" "социологом" "социологи"])
  , (AtomContext,  [nounSlot AtomContext "социология" "социологии" "социологии" "социологию" "социологией" "социологии"])
  ])

gen_sociology_fact1 :: FactAtoms
gen_sociology_fact1 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "макс" "макса" "максе" "макса" "максом" "максы"])
  , (AtomProperty, [plainSlot TModifier "немецкий"
                    ,nounSlot AtomProperty "социолог" "социолога" "социологе" "социолога" "социологом" "социологи"])
  , (AtomContext,  [nounSlot AtomContext "социология" "социологии" "социологии" "социологию" "социологией" "социологии"])
  ])

gen_sociology_fact2 :: FactAtoms
gen_sociology_fact2 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "эмиль" "эмиля" "эмиле" "эмиля" "эмилем" "эмили"])
  , (AtomProperty, [plainSlot TModifier "французский"
                    ,nounSlot AtomProperty "социолог" "социолога" "социологе" "социолога" "социологом" "социологи"])
  , (AtomContext,  [nounSlot AtomContext "социология" "социологии" "социологии" "социологию" "социологией" "социологии"])
  ])

gen_sociology_fact3 :: FactAtoms
gen_sociology_fact3 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "стратификация" "стратификации" "стратификации" "стратификацию" "стратификацией" "стратификации"])
  , (AtomProperty, [plainSlot TModifier "социальный"
                    ,nounSlot AtomProperty "расслоение" "расслоения" "расслоении" "расслоение" "расслоением" "расслоения"])
  , (AtomContext,  [nounSlot AtomContext "социология" "социологии" "социологии" "социологию" "социологией" "социологии"])
  ])

gen_sociology_fact4 :: FactAtoms
gen_sociology_fact4 = FactAtoms (M.fromListWith (++)
  [   (AtomSubject,   [nounSlot AtomSubject "урбанизация" "урбанизации" "урбанизации" "урбанизацию" "урбанизацией" "урбанизации"])
  -- [decomposed] -- , (AtomProperty, [plainSlot TModifier "рост городов"])
  , (AtomContext,  [nounSlot AtomContext "социология" "социологии" "социологии" "социологию" "социологией" "социологии"])
  ])

{-| All decomposed facts indexed by subject keyword. -}
decomposedFacts :: Map Text FactAtoms
decomposedFacts = M.fromListWith (flip const)
  [ ("сердце", heartPump)
  , ("аорта", aorta)
  , ("сосуды", vessels)
  , ("кровеносные сосуды", vessels)
  , ("группы крови", bloodGroups)
  , ("кровь", bloodVolume)
  , ("сердце", medicine_fact0)
  , ("артерия", medicine_fact1)
  , ("печень", medicine_fact2)
  , ("скорость", physics_fact0)
  , ("закон", physics_fact1)
  , ("атом", physics_fact2)
  , ("вода", chemistry_fact0)
  , ("таблица", chemistry_fact1)
  , ("элемент", chemistry_fact2)
  , ("теория", biology_fact0)
  , ("клетка", biology_fact1)
  , ("митохондрия", biology_fact2)
  , ("число", mathematics_fact0)
  , ("теорема", mathematics_fact1)
  , ("возраст", astronomy_fact0)
  , ("солнце", astronomy_fact1)
  , ("дыра", astronomy_fact2)
  , ("гора", geography_fact0)
  , ("точка", geography_fact1)
  , ("озеро", geography_fact2)
  , ("римская", history_fact0)
  , ("революция", history_fact1)
  , ("война", history_fact2)
  , ("право", law_fact0)
  , ("хартия", law_fact1)
  , ("презумпция", law_fact2)
  , ("адам", economics_fact0)
  , ("валова", economics_fact1)
  , ("инфляция", economics_fact2)
  , ("алан", computer_science_fact0)
  , ("компьютер", computer_science_fact1)
  , ("интернет", computer_science_fact2)
  , ("мир", linguistics_fact0)
  , ("язык", linguistics_fact1)
  , ("санскрит", linguistics_fact2)
  , ("зигмунд", psychology_fact0)
  , ("эксперимент", psychology_fact1)
  , ("диссонанс", psychology_fact2)
  , ("роман", literature_fact0)
  , ("комедия", literature_fact1)
  , ("мигель", literature_fact2)
  , ("леонардо", art_fact0)
  , ("импрессионизм", art_fact1)
  , ("пабло", art_fact2)
  , ("иоганн", music_fact0)
  , ("вольфганг", music_fact1)
  , ("людвиг", music_fact2)
  , ("сократ", philosophy_fact0)
  , ("критика", philosophy_fact1)
  , ("аристотель", philosophy_fact2)
  , ("христианство", religion_fact0)
  , ("ислам", religion_fact1)
  , ("индуизм", religion_fact2)
  , ("демократия", politics_fact0)
  , ("организация", politics_fact1)
  , ("разделение", politics_fact2)
  , ("огюст", sociology_fact0)
  , ("макс", sociology_fact1)
  , ("эмиль", sociology_fact2)
  , ("сердце", gen_medicine_fact0)
  , ("артерия", gen_medicine_fact1)
  , ("печень", gen_medicine_fact2)
  , ("тело", gen_medicine_fact3)
  , ("группа", gen_medicine_fact4)
  , ("скорость", gen_physics_fact0)
  , ("закон", gen_physics_fact1)
  , ("атом", gen_physics_fact2)
  , ("теория", gen_physics_fact3)
  , ("механика", gen_physics_fact4)
  , ("вода", gen_chemistry_fact0)
  , ("таблица", gen_chemistry_fact1)
  , ("элемент", gen_chemistry_fact2)
  , ("углерод", gen_chemistry_fact3)
  , ("реакция", gen_chemistry_fact4)
  , ("теория", gen_biology_fact0)
  , ("клетка", gen_biology_fact1)
  , ("митохондрия", gen_biology_fact2)
  , ("геном", gen_biology_fact3)
  , ("существо", gen_biology_fact4)
  , ("число", gen_mathematics_fact0)
  , ("теорема", gen_mathematics_fact1)
  , ("теорема", gen_mathematics_fact2)
  , ("ноль", gen_mathematics_fact3)
  , ("сечение", gen_mathematics_fact4)
  , ("возраст", gen_astronomy_fact0)
  , ("солнце", gen_astronomy_fact1)
  , ("дыра", gen_astronomy_fact2)
  , ("планета", gen_astronomy_fact3)
  , ("свет", gen_astronomy_fact4)
  , ("гора", gen_geography_fact0)
  , ("точка", gen_geography_fact1)
  , ("озеро", gen_geography_fact2)
  , ("река", gen_geography_fact3)
  , ("сахар", gen_geography_fact4)
  , ("римская", gen_history_fact0)
  , ("революция", gen_history_fact1)
  , ("война", gen_history_fact2)
  , ("великое", gen_history_fact3)
  , ("эпоха", gen_history_fact4)
  , ("право", gen_law_fact0)
  , ("хартия", gen_law_fact1)
  , ("презумпция", gen_law_fact2)
  , ("декларация", gen_law_fact3)
  , ("конституция", gen_law_fact4)
  , ("адам", gen_economics_fact0)
  , ("валова", gen_economics_fact1)
  , ("инфляция", gen_economics_fact2)
  , ("закон", gen_economics_fact3)
  , ("депрессия", gen_economics_fact4)
  , ("алан", gen_computer_science_fact0)
  , ("компьютер", gen_computer_science_fact1)
  , ("интернет", gen_computer_science_fact2)
  , ("язык", gen_computer_science_fact3)
  , ("сложность", gen_computer_science_fact4)
  , ("мир", gen_linguistics_fact0)
  , ("язык", gen_linguistics_fact1)
  , ("санскрит", gen_linguistics_fact2)
  , ("фердинанд", gen_linguistics_fact3)
  , ("язык", gen_linguistics_fact4)
  , ("зигмунд", gen_psychology_fact0)
  , ("эксперимент", gen_psychology_fact1)
  , ("диссонанс", gen_psychology_fact2)
  , ("пирамида", gen_psychology_fact3)
  , ("эффект", gen_psychology_fact4)
  , ("роман", gen_literature_fact0)
  , ("комедия", gen_literature_fact1)
  , ("мигель", gen_literature_fact2)
  , ("уильям", gen_literature_fact3)
  , ("фёдор", gen_literature_fact4)
  , ("леонардо", gen_art_fact0)
  , ("импрессионизм", gen_art_fact1)
  , ("пабло", gen_art_fact2)
  , ("капелла", gen_art_fact3)
  , ("винсент", gen_art_fact4)
  , ("иоганн", gen_music_fact0)
  , ("вольфганг", gen_music_fact1)
  , ("людвиг", gen_music_fact2)
  , ("джаз", gen_music_fact3)
  , ("рок", gen_music_fact4)
  , ("сократ", gen_philosophy_fact0)
  , ("критика", gen_philosophy_fact1)
  , ("аристотель", gen_philosophy_fact2)
  , ("экзистенциализм", gen_philosophy_fact3)
  , ("заратустра", gen_philosophy_fact4)
  , ("христианство", gen_religion_fact0)
  , ("ислам", gen_religion_fact1)
  , ("индуизм", gen_religion_fact2)
  , ("буддизм", gen_religion_fact3)
  , ("иудаизм", gen_religion_fact4)
  , ("демократия", gen_politics_fact0)
  , ("организация", gen_politics_fact1)
  , ("разделение", gen_politics_fact2)
  , ("союз", gen_politics_fact3)
  , ("война", gen_politics_fact4)
  , ("огюст", gen_sociology_fact0)
  , ("макс", gen_sociology_fact1)
  , ("эмиль", gen_sociology_fact2)
  , ("стратификация", gen_sociology_fact3)
  , ("урбанизация", gen_sociology_fact4)
  ]

heartFacts :: [FactAtoms]
heartFacts = [heartPump, aorta, vessels]

bloodFacts :: [FactAtoms]
bloodFacts = [bloodVolume, bloodGroups]
