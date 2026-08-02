{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Lexicon.ParticipleGerund
  ( participleGerundEntries
  , participleForms
  , gerundForms
  ) where

import Data.Text (Text)

-- | Additional lexeme entries for participles (причастия) and gerunds (деепричастия)
-- These complement the main generated lexicon with common participle and gerund forms
participleGerundEntries :: [(Text, Text, Text, Text)]
participleGerundEntries = 
  -- Present active participles (действительные причастия настоящего времени)
  [ ("читающий", "читать", "participle", "nominative")
  , ("читающего", "читать", "participle", "genitive")
  , ("читающему", "читать", "participle", "dative")
  , ("читающего", "читать", "participle", "accusative")
  , ("читающим", "читать", "participle", "instrumental")
  , ("читающем", "читать", "participle", "prepositional")
  
  , ("пишущий", "писать", "participle", "nominative")
  , ("пишущего", "писать", "participle", "genitive")
  , ("пишущему", "писать", "participle", "dative")
  , ("пишущего", "писать", "participle", "accusative")
  , ("пишущим", "писать", "participle", "instrumental")
  , ("пишущем", "писать", "participle", "prepositional")
  
  , ("любящий", "любить", "participle", "nominative")
  , ("любящего", "любить", "participle", "genitive")
  , ("любящему", "любить", "participle", "dative")
  , ("любящего", "любить", "participle", "accusative")
  , ("любящим", "любить", "participle", "instrumental")
  , ("любящем", "любить", "participle", "prepositional")

  -- Past active participles (действительные причастия прошедшего времени)
  , ("читавший", "читать", "participle", "nominative")
  , ("читавшего", "читать", "participle", "genitive")
  , ("читавшему", "читать", "participle", "dative")
  , ("читавшего", "читать", "participle", "accusative")
  , ("читавшим", "читать", "participle", "instrumental")
  , ("читавшем", "читать", "participle", "prepositional")
  
  , ("писавший", "писать", "participle", "nominative")
  , ("писавшего", "писать", "participle", "genitive")
  , ("писавшему", "писать", "participle", "dative")
  , ("писавшего", "писать", "participle", "accusative")
  , ("писавшим", "писать", "participle", "instrumental")
  , ("писавшем", "писать", "participle", "prepositional")

  -- Present passive participles (страдательные причастия настоящего времени)
  , ("читаемый", "читать", "participle", "nominative")
  , ("читаемого", "читать", "participle", "genitive")
  , ("читаемому", "читать", "participle", "dative")
  , ("читаемый", "читать", "participle", "accusative")
  , ("читаемым", "читать", "participle", "instrumental")
  , ("читаемом", "читать", "participle", "prepositional")

  -- Past passive participles (страдательные причастия прошедшего времени)
  , ("прочитанный", "читать", "participle", "nominative")
  , ("прочитанного", "читать", "participle", "genitive")
  , ("прочитанному", "читать", "participle", "dative")
  , ("прочитанный", "читать", "participle", "accusative")
  , ("прочитанным", "читать", "participle", "instrumental")
  , ("прочитанном", "читать", "participle", "prepositional")
  
  , ("сделанный", "сделать", "participle", "nominative")
  , ("сделанного", "сделать", "participle", "genitive")
  , ("сделанному", "сделать", "participle", "dative")
  , ("сделанный", "сделать", "participle", "accusative")
  , ("сделанным", "сделать", "participle", "instrumental")
  , ("сделанном", "сделать", "participle", "prepositional")

  -- Gerunds (деепричастия)
  , ("читая", "читать", "gerund", "nominative")
  , ("пиша", "писать", "gerund", "nominative")
  , ("любя", "любить", "gerund", "nominative")
  
  -- Past gerunds (деепричастия прошедшего времени)
  , ("прочитав", "читать", "gerund", "nominative")
  , ("прочитавши", "читать", "gerund", "nominative")
  , ("написав", "писать", "gerund", "nominative")
  , ("написавши", "писать", "gerund", "nominative")
  
  -- More common participles
  , ("знающий", "знать", "participle", "nominative")
  , ("знающего", "знать", "participle", "genitive")
  , ("знающему", "знать", "participle", "dative")
  , ("знающего", "знать", "participle", "accusative")
  , ("знающим", "знать", "participle", "instrumental")
  , ("знающем", "знать", "participle", "prepositional")
  
  , ("видящий", "видеть", "participle", "nominative")
  , ("видящего", "видеть", "participle", "genitive")
  , ("видящему", "видеть", "participle", "dative")
  , ("видящего", "видеть", "participle", "accusative")
  , ("видящим", "видеть", "participle", "instrumental")
  , ("видящем", "видеть", "participle", "prepositional")

  , ("слышащий", "слышать", "participle", "nominative")
  , ("слышащего", "слышать", "participle", "genitive")
  , ("слышащему", "слышать", "participle", "dative")
  , ("слышащего", "слышать", "participle", "accusative")
  , ("слышащим", "слышать", "participle", "instrumental")
  , ("слышащем", "слышать", "participle", "prepositional")

  , ("думающий", "думать", "participle", "nominative")
  , ("думающего", "думать", "participle", "genitive")
  , ("думающему", "думать", "participle", "dative")
  , ("думающего", "думать", "participle", "accusative")
  , ("думающим", "думать", "participle", "instrumental")
  , ("думающем", "думать", "participle", "prepositional")

  , ("говорящий", "говорить", "participle", "nominative")
  , ("говорящего", "говорить", "participle", "genitive")
  , ("говорящему", "говорить", "participle", "dative")
  , ("говорящего", "говорить", "participle", "accusative")
  , ("говорящим", "говорить", "participle", "instrumental")
  , ("говорящем", "говорить", "participle", "prepositional")

  -- More gerunds
  , ("зная", "знать", "gerund", "nominative")
  , ("видя", "видеть", "gerund", "nominative")
  , ("слыша", "слышать", "gerund", "nominative")
  , ("думая", "думать", "gerund", "nominative")
  , ("говоря", "говорить", "gerund", "nominative")
  
  , ("узнав", "узнaть", "gerund", "nominative")
  , ("узнавши", "узнaть", "gerund", "nominative")
  , ("увидев", "увидеть", "gerund", "nominative")
  , ("увидевши", "увидеть", "gerund", "nominative")
  ]

-- | Additional finite verb forms for participles and gerunds
-- Maps infinitive to participle/gerund form
participleForms :: [(Text, Text)]
participleForms = 
  [ ("читать", "читающий")
  , ("читать", "читавший")
  , ("читать", "читаемый")
  , ("читать", "прочитанный")
  , ("писать", "пишущий")
  , ("писать", "писавший")
  , ("любить", "любящий")
  , ("любить", "любимый")
  , ("любить", "любимый")
  , ("знать", "знающий")
  , ("знать", "знавший")
  , ("видеть", "видящий")
  , ("видеть", "видимый")
  , ("слышать", "слышащий")
  , ("слышать", "слышимый")
  , ("думать", "думающий")
  , ("говорить", "говорящий")
  , ("сделать", "сделанный")
  ]

-- | Additional gerund forms
-- Maps infinitive to gerund form  
gerundForms :: [(Text, Text)]
gerundForms = 
  [ ("читать", "читая")
  , ("читать", "прочитав")
  , ("читать", "прочитавши")
  , ("писать", "пиша")
  , ("писать", "написав")
  , ("писать", "написавши")
  , ("любить", "любя")
  , ("знать", "зная")
  , ("видеть", "видя")
  , ("слышать", "слыша")
  , ("думать", "думая")
  , ("говорить", "говоря")
  , ("узнать", "узнав")
  , ("узнать", "узнавши")
  , ("увидеть", "увидев")
  , ("увидеть", "увидевши")
  ]
