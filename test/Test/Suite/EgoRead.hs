{-# LANGUAGE OverloadedStrings #-}
module Test.Suite.EgoRead
  ( egoReadTests
  ) where

import Test.HUnit (Test(..), (@?=))

import QxFx0.Core.Ego (readAgencyFromHistory)

egoReadTests :: [Test]
egoReadTests =
  [ TestLabel "readAgencyFromHistory parses plain double" $
      TestCase $
        readAgencyFromHistory "0.42" @?= 0.42
  , TestLabel "readAgencyFromHistory rejects trailing junk" $
      TestCase $
        readAgencyFromHistory "0.5 extra" @?= 0.0
  , TestLabel "readAgencyFromHistory rejects empty" $
      TestCase $
        readAgencyFromHistory "" @?= 0.0
  , TestLabel "readAgencyFromHistory rejects non-numeric" $
      TestCase $
        readAgencyFromHistory "agency" @?= 0.0
  , TestLabel "readAgencyFromHistory accepts integer form" $
      TestCase $
        readAgencyFromHistory "1" @?= 1.0
  ]
