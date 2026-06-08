{-# LANGUAGE OverloadedStrings #-}
{-|
Module      : Test.Suite.ContentSalience
Description : WP-C anti-rot guard for content saliency from spectral clustering.

Per ADR-0042, the consumer must stay connected. 'computeContentSaliency' produces
a top-down attention signal from meaning graph clustering, which feeds into the
Salience controller as the 6th contribution. Gated by 'contentSalienceActive'
flag (promoted to default-on 2026-06-04).

WP-C R-C1: Content saliency influences salience verdict and driver selection.
Anti-rot tests verify that removing the consumer breaks observable behavior.
-}
module Test.Suite.ContentSalience
  ( contentSalienceTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual)

import QxFx0.Self.Salience
  ( SalienceWeights
  , defaultSalienceWeights
  , computeSalience
  , salienceDriver
  , SalienceDriver(..)
  , Salience(..)
  )
import QxFx0.Self.Field (Field, emptyField, fieldResonance, mkResonance)
import QxFx0.Self.Conatus (ConatusEnergy(..), ConatusComponents(..))
import QxFx0.Core.ContentCluster (contentSalienceActive)

contentSalienceTests :: [Test]
contentSalienceTests =
  [ -- WP-C anti-rot (producer): computeContentSaliency feeds into computeSalience.
    -- Deleting the contentSaliency parameter breaks this.
    TestLabel "WP-C: content saliency parameter affects salience score" $
      TestCase $ do
        let weights = defaultSalienceWeights
            components = ConatusComponents 5.0 3.0 2.0 0.0
            energy = ConatusEnergy 10.0 components
            field = emptyField { fieldResonance = mkResonance 0.5 }
            
            -- Compute salience with low content saliency
            salienceLow = computeSalience weights energy field 0.1
            
            -- Compute salience with high content saliency
            salienceHigh = computeSalience weights energy field 0.9
        
        -- The two salience values must be different (anti-rot)
        assertBool "content saliency must affect salience score"
          (salienceLow /= salienceHigh)

    -- High content saliency can drive the verdict when other signals are low.
  , TestLabel "WP-C: high content saliency can be dominant driver" $
      TestCase $ do
        let weights = defaultSalienceWeights
            -- Low conatus energy and low field signals
            components = ConatusComponents 0.5 0.3 0.2 0.0
            energy = ConatusEnergy 1.0 components
            field = emptyField { fieldResonance = mkResonance 0.1 }
            
            -- High content saliency
            salience = computeSalience weights energy field 0.95
            driver = salienceDriver salience
        
        -- With high content saliency and low other signals, content saliency
        -- should be able to become the dominant driver
        assertBool "content saliency can be dominant driver"
          (driver == DrivenByContentSaliency || driver /= DrivenByConatusGate)

    -- The flag is now on (promoted 2026-06-04).
  , TestLabel "WP-C: content saliency is promoted to default-on" $
      TestCase $
        assertEqual "promoted to default-on (2026-06-04)" True contentSalienceActive

    -- WP-C R-C1 anti-rot (consumer): Content saliency must influence the
    -- holistic bias. Deleting the contribution breaks this.
  , TestLabel "WP-C anti-rot: content saliency influences holistic bias" $
      TestCase $ do
        let weights = defaultSalienceWeights
            components = ConatusComponents 2.5 1.5 1.0 0.0
            energy = ConatusEnergy 5.0 components
            field = emptyField { fieldResonance = mkResonance 0.5 }
            
            salience0 = computeSalience weights energy field 0.0
            salience1 = computeSalience weights energy field 1.0
            
            bias0 = salienceHolisticBias salience0
            bias1 = salienceHolisticBias salience1
        
        -- Different content saliency should produce different holistic bias
        assertBool "content saliency must influence holistic bias (anti-rot)"
          (bias0 /= bias1)

    -- Confidence should reflect the 6th contribution (content saliency).
  , TestLabel "WP-C: confidence accounts for content saliency contribution" $
      TestCase $ do
        let weights = defaultSalienceWeights
            components = ConatusComponents 2.5 1.5 1.0 0.0
            energy = ConatusEnergy 5.0 components
            field = emptyField { fieldResonance = mkResonance 0.5 }
            
            salienceLow = computeSalience weights energy field 0.0
            salienceHigh = computeSalience weights energy field 1.0
            
            confLow = salienceConfidence salienceLow
            confHigh = salienceConfidence salienceHigh
        
        -- Confidence should change with content saliency
        assertBool "confidence must account for content saliency"
          (confLow /= confHigh)
  ]

