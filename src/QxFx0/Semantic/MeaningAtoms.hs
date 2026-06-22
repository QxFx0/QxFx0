{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Semantic.MeaningAtoms
  ( RawClusterPhraseDecision(..)
  , RawLexicalPhraseDecision(..)
  , RawLexicalClusterPhraseDecisions(..)
  , RawClusterPhraseContainment(..)
  , LexicalPhraseContainmentClass(..)
  , RawLexicalPhraseContainment(..)
  , RawLexicalClusterPhraseContainment(..)
  , RawClusterHit(..)
  , RawLexicalHit(..)
  , RawLexicalClusterHits(..)
  , RawLexicalClusterMatches(..)
  , RawAtomFindings(..)
  , clusterPhraseDecisionTag
  , lexicalPhraseDecisionTag
  , collectRawLexicalClusterPhraseDecisions
  , buildRawLexicalClusterPhraseContainmentFromDecisions
  , clusterPhraseContainmentTag
  , lexicalPhraseContainmentTag
  , collectRawLexicalClusterPhraseContainment
  , buildRawLexicalClusterHitsFromPhraseContainment
  , collectRawLexicalClusterHits
  , buildRawLexicalClusterMatchesFromHits
  , collectRawLexicalClusterMatches
  , collectStructuralAtoms
  , buildRawAtomFindingsFromMatches
  , collectRawAtomFindings
  , buildAtomSetFromFindings
  , collectAtoms
  , updateTrace
  , extractObjectFromAtom
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.List as L
import QxFx0.Types (AtomSet(..), MeaningAtom(..), AtomTag(..), Register(..), AtomTrace(..), ClusterDef(..))
import QxFx0.Semantic.Embedding (fallbackEmbedding)
import QxFx0.Semantic.KeywordMatch
  ( tokenizeKeywordText
  , containsKeywordPhrase
  , containsAnyKeywordPhrase
  )
import QxFx0.Policy.SemanticScoring
  ( semanticAtomIntensity
  , semanticLexicalAgencyLostStrength
  )
import QxFx0.Types.Text (textShow)

data RawAtomFindings = RawAtomFindings
  { rafClusterAtoms :: ![MeaningAtom]
  , rafLexicalAtoms :: ![MeaningAtom]
  , rafStructuralAtoms :: ![MeaningAtom]
  } deriving stock (Eq, Show)

data RawLexicalClusterMatches = RawLexicalClusterMatches
  { rlmClusterAtoms :: ![MeaningAtom]
  , rlmLexicalAtoms :: ![MeaningAtom]
  } deriving stock (Eq, Show)

data RawClusterPhraseDecision = RawClusterPhraseDecision
  { rcpdClusterName :: !Text
  , rcpdPhrase :: !Text
  , rcpdMatched :: !Bool
  } deriving stock (Eq, Show)

data RawClusterPhraseContainment = RawClusterPhraseContainment
  { rcpcClusterName :: !Text
  , rcpcMatchedKeywords :: ![Text]
  } deriving stock (Eq, Show)

data LexicalPhraseContainmentClass
  = LpcExhaustion
  | LpcNegatedExhaustion
  | LpcModalAbilityContrast
  | LpcNeedContact
  | LpcNeedMeaning
  | LpcAgencyLost
  deriving stock (Eq, Show)

data RawLexicalPhraseContainment = RawLexicalPhraseContainment
  { rlpcClass :: !LexicalPhraseContainmentClass
  , rlpcMatchedLexemes :: ![Text]
  } deriving stock (Eq, Show)

data RawLexicalPhraseDecision = RawLexicalPhraseDecision
  { rlpdClass :: !LexicalPhraseContainmentClass
  , rlpdPhrase :: !Text
  , rlpdMatched :: !Bool
  } deriving stock (Eq, Show)

data RawLexicalClusterPhraseDecisions = RawLexicalClusterPhraseDecisions
  { rlcpdInputLower :: !Text
  , rlcpdClusterDecisions :: ![RawClusterPhraseDecision]
  , rlcpdLexicalDecisions :: ![RawLexicalPhraseDecision]
  } deriving stock (Eq, Show)

data RawLexicalClusterPhraseContainment = RawLexicalClusterPhraseContainment
  { rlcpcInputLower :: !Text
  , rlcpcClusterContainment :: ![RawClusterPhraseContainment]
  , rlcpcLexicalContainment :: ![RawLexicalPhraseContainment]
  } deriving stock (Eq, Show)

data RawClusterHit = RawClusterHit
  { rchTag :: !AtomTag
  , rchMatchedKeywords :: ![Text]
  } deriving stock (Eq, Show)

data RawLexicalHit = RawLexicalHit
  { rlhTag :: !AtomTag
  , rlhMatchedLexemes :: ![Text]
  } deriving stock (Eq, Show)

data RawLexicalClusterHits = RawLexicalClusterHits
  { rlchInputLower :: !Text
  , rlchClusterHits :: ![RawClusterHit]
  , rlchLexicalHits :: ![RawLexicalHit]
  } deriving stock (Eq, Show)

collectAtoms :: Text -> [ClusterDef] -> AtomSet
collectAtoms input clusters =
  let inputLower = T.toLower input
      inputTokens = tokenizeKeywordText input
      rawMatches = collectRawLexicalClusterMatches input clusters
      foundAtoms = rlmClusterAtoms rawMatches
      lexical = rlmLexicalAtoms rawMatches
      structural = if containsAnyKeywordPhrase inputTokens ["\1095\1090\1086", "\1082\1072\1082", "\1087\1086\1095\1077\1084\1091"] || T.isSuffixOf "?" (T.strip input)
                   then [MeaningAtom (extractObject input) (Searching (extractObject input)) (fallbackEmbedding inputLower)]
                   else []
      allFound = foundAtoms ++ lexical ++ structural
      load = L.foldl' (\acc a -> acc + atomIntensity a) 0.0 allFound
  in AtomSet
    { asAtoms    = allFound
    , asLoad     = min 1.0 load
    , asRegister = inferRegister allFound
    }

collectRawAtomFindings :: Text -> [ClusterDef] -> RawAtomFindings
collectRawAtomFindings input clusters =
  buildRawAtomFindingsFromMatches (collectRawLexicalClusterMatches input clusters) (collectStructuralAtoms input)

collectRawLexicalClusterMatches :: Text -> [ClusterDef] -> RawLexicalClusterMatches
collectRawLexicalClusterMatches input clusters =
  buildRawLexicalClusterMatchesFromHits (collectRawLexicalClusterHits input clusters)

collectRawLexicalClusterPhraseDecisions :: Text -> [ClusterDef] -> RawLexicalClusterPhraseDecisions
collectRawLexicalClusterPhraseDecisions input clusters =
  let inputLower = T.toLower input
      inputTokens = tokenizeKeywordText input
  in RawLexicalClusterPhraseDecisions
      { rlcpdInputLower = inputLower
      , rlcpdClusterDecisions = concatMap (collectRawClusterPhraseDecisions inputTokens) clusters
      , rlcpdLexicalDecisions = collectRawLexicalPhraseDecisions inputTokens
      }

buildRawLexicalClusterPhraseContainmentFromDecisions :: RawLexicalClusterPhraseDecisions -> RawLexicalClusterPhraseContainment
buildRawLexicalClusterPhraseContainmentFromDecisions rawDecisions =
  RawLexicalClusterPhraseContainment
    { rlcpcInputLower = rlcpdInputLower rawDecisions
    , rlcpcClusterContainment = buildRawClusterPhraseContainmentFromDecisions (rlcpdClusterDecisions rawDecisions)
    , rlcpcLexicalContainment = buildRawLexicalPhraseContainmentFromDecisions (rlcpdLexicalDecisions rawDecisions)
    }

collectRawLexicalClusterPhraseContainment :: Text -> [ClusterDef] -> RawLexicalClusterPhraseContainment
collectRawLexicalClusterPhraseContainment input clusters =
  buildRawLexicalClusterPhraseContainmentFromDecisions (collectRawLexicalClusterPhraseDecisions input clusters)

collectRawLexicalClusterHits :: Text -> [ClusterDef] -> RawLexicalClusterHits
collectRawLexicalClusterHits input clusters =
  buildRawLexicalClusterHitsFromPhraseContainment (collectRawLexicalClusterPhraseContainment input clusters)

buildRawLexicalClusterHitsFromPhraseContainment :: RawLexicalClusterPhraseContainment -> RawLexicalClusterHits
buildRawLexicalClusterHitsFromPhraseContainment rawContainment =
  let suppressedExhaustion = any suppressesExhaustion (rlcpcLexicalContainment rawContainment)
      rawClusterHits0 = concatMap buildRawClusterHitsFromPhraseContainment (rlcpcClusterContainment rawContainment)
      rawClusterHits
        | suppressedExhaustion = filter (not . rawClusterHitIsExhaustion) rawClusterHits0
        | otherwise = rawClusterHits0
  in RawLexicalClusterHits
      { rlchInputLower = rlcpcInputLower rawContainment
      , rlchClusterHits = rawClusterHits
      , rlchLexicalHits = buildRawLexicalHitsFromPhraseContainment (rlcpcLexicalContainment rawContainment)
      }
  where
    suppressesExhaustion rawLexicalContainment =
      rlpcClass rawLexicalContainment == LpcNegatedExhaustion
        || rlpcClass rawLexicalContainment == LpcModalAbilityContrast

rawClusterHitIsExhaustion :: RawClusterHit -> Bool
rawClusterHitIsExhaustion rawHit =
  case rchTag rawHit of
    Exhaustion _ -> True
    _ -> False

clusterPhraseContainmentTag :: RawClusterPhraseContainment -> AtomTag
clusterPhraseContainmentTag rawContainment =
  tagFromCluster
    (rcpcClusterName rawContainment)
    (T.intercalate ", " (rcpcMatchedKeywords rawContainment))

clusterPhraseDecisionTag :: RawClusterPhraseDecision -> AtomTag
clusterPhraseDecisionTag rawDecision =
  tagFromCluster
    (rcpdClusterName rawDecision)
    (rcpdPhrase rawDecision)

lexicalPhraseContainmentTag :: RawLexicalPhraseContainment -> Maybe AtomTag
lexicalPhraseContainmentTag rawContainment =
  case rlpcClass rawContainment of
    LpcExhaustion -> Just (Exhaustion "\1083\1077\1082\1089\1080\1082\1072")
    LpcNeedContact -> Just (NeedContact "\1083\1077\1082\1089\1080\1082\1072")
    LpcNeedMeaning -> Just (NeedMeaning "\1083\1077\1082\1089\1080\1082\1072")
    LpcAgencyLost -> Just (AgencyLost semanticLexicalAgencyLostStrength)
    LpcNegatedExhaustion -> Nothing
    LpcModalAbilityContrast -> Nothing

lexicalPhraseDecisionTag :: RawLexicalPhraseDecision -> Maybe AtomTag
lexicalPhraseDecisionTag rawDecision =
  case rlpdClass rawDecision of
    LpcExhaustion -> Just (Exhaustion "\1083\1077\1082\1089\1080\1082\1072")
    LpcNeedContact -> Just (NeedContact "\1083\1077\1082\1089\1080\1082\1072")
    LpcNeedMeaning -> Just (NeedMeaning "\1083\1077\1082\1089\1080\1082\1072")
    LpcAgencyLost -> Just (AgencyLost semanticLexicalAgencyLostStrength)
    LpcNegatedExhaustion -> Nothing
    LpcModalAbilityContrast -> Nothing

buildRawLexicalClusterMatchesFromHits :: RawLexicalClusterHits -> RawLexicalClusterMatches
buildRawLexicalClusterMatchesFromHits rawHits =
  RawLexicalClusterMatches
    { rlmClusterAtoms = emitClusterHits (rlchInputLower rawHits) (rlchClusterHits rawHits)
    , rlmLexicalAtoms = emitLexicalHits (rlchInputLower rawHits) (rlchLexicalHits rawHits)
    }

collectStructuralAtoms :: Text -> [MeaningAtom]
collectStructuralAtoms input =
  let inputLower = T.toLower input
      inputTokens = tokenizeKeywordText input
  in if containsAnyKeywordPhrase inputTokens ["что", "как", "почему"] || T.isSuffixOf "?" (T.strip input)
       then [MeaningAtom (extractObject input) (Searching (extractObject input)) (fallbackEmbedding inputLower)]
       else []

buildRawAtomFindingsFromMatches :: RawLexicalClusterMatches -> [MeaningAtom] -> RawAtomFindings
buildRawAtomFindingsFromMatches matches structural =
  RawAtomFindings
    { rafClusterAtoms = rlmClusterAtoms matches
    , rafLexicalAtoms = rlmLexicalAtoms matches
    , rafStructuralAtoms = structural
    }

buildAtomSetFromFindings :: RawAtomFindings -> AtomSet
buildAtomSetFromFindings findings =
  let allFound = rafClusterAtoms findings ++ rafLexicalAtoms findings ++ rafStructuralAtoms findings
      load = L.foldl' (\acc a -> acc + atomIntensity a) 0.0 allFound
  in AtomSet
    { asAtoms    = allFound
    , asLoad     = min 1.0 load
    , asRegister = inferRegister allFound
    }

atomIntensity :: MeaningAtom -> Double
atomIntensity = semanticAtomIntensity . maTag

isExhaustionAtom :: MeaningAtom -> Bool
isExhaustionAtom atom =
  case maTag atom of
    Exhaustion _ -> True
    _ -> False

matchCluster :: Text -> [Text] -> ClusterDef -> [MeaningAtom]
matchCluster inp inpTokens cd =
  emitClusterHits inp (collectRawClusterHits inpTokens cd)

collectRawClusterPhraseDecisions :: [Text] -> ClusterDef -> [RawClusterPhraseDecision]
collectRawClusterPhraseDecisions inpTokens cd =
  let clusterName = T.toLower (cdName cd)
      keywords = map T.toLower (cdKeywords cd)
  in map
       (\phrase -> RawClusterPhraseDecision clusterName phrase (containsKeywordPhrase inpTokens phrase))
       keywords

buildRawClusterPhraseContainmentFromDecisions :: [RawClusterPhraseDecision] -> [RawClusterPhraseContainment]
buildRawClusterPhraseContainmentFromDecisions rawDecisions =
  let matchedDecisions = filter rcpdMatched rawDecisions
      clusterNames = L.nub (map rcpdClusterName matchedDecisions)
      buildClusterContainment clusterName =
        RawClusterPhraseContainment
          clusterName
          [ rcpdPhrase decision
          | decision <- matchedDecisions
          , rcpdClusterName decision == clusterName
          ]
  in map buildClusterContainment clusterNames

collectRawClusterPhraseContainment :: [Text] -> ClusterDef -> [RawClusterPhraseContainment]
collectRawClusterPhraseContainment inpTokens cd =
  buildRawClusterPhraseContainmentFromDecisions (collectRawClusterPhraseDecisions inpTokens cd)

collectRawClusterHits :: [Text] -> ClusterDef -> [RawClusterHit]
collectRawClusterHits inpTokens cd =
  concatMap buildRawClusterHitsFromPhraseContainment (collectRawClusterPhraseContainment inpTokens cd)

buildRawClusterHitsFromPhraseContainment :: RawClusterPhraseContainment -> [RawClusterHit]
buildRawClusterHitsFromPhraseContainment rawContainment =
  [ RawClusterHit
      (clusterPhraseContainmentTag rawContainment)
      (rcpcMatchedKeywords rawContainment)
  ]

emitClusterHits :: Text -> [RawClusterHit] -> [MeaningAtom]
emitClusterHits inputLower = map emitClusterHit
  where
    emitClusterHit rawHit =
      MeaningAtom
        (T.intercalate ", " (rchMatchedKeywords rawHit))
        (rchTag rawHit)
        (fallbackEmbedding inputLower)

lexicalAtoms :: Text -> [Text] -> [MeaningAtom]
lexicalAtoms inputLower inputTokens =
  emitLexicalHits inputLower (collectRawLexicalHits inputTokens)

collectRawLexicalPhraseDecisions :: [Text] -> [RawLexicalPhraseDecision]
collectRawLexicalPhraseDecisions inputTokens =
  concat
    [ detect LpcExhaustion exhaustionLexemes
    , detect LpcNegatedExhaustion negatedExhaustionLexemes
    , detect LpcModalAbilityContrast modalAbilityContrastLexemes
    , detect LpcNeedContact contactLexemes
    , detect LpcNeedMeaning meaningLexemes
    , detect LpcAgencyLost agencyLostLexemes
    ]
  where
    detect :: LexicalPhraseContainmentClass -> [Text] -> [RawLexicalPhraseDecision]
    detect decisionClass lexemes =
      map
        (\phrase -> RawLexicalPhraseDecision decisionClass phrase (containsKeywordPhrase inputTokens phrase))
        lexemes

collectRawLexicalPhraseContainment :: [Text] -> [RawLexicalPhraseContainment]
collectRawLexicalPhraseContainment inputTokens =
  buildRawLexicalPhraseContainmentFromDecisions (collectRawLexicalPhraseDecisions inputTokens)

buildRawLexicalPhraseContainmentFromDecisions :: [RawLexicalPhraseDecision] -> [RawLexicalPhraseContainment]
buildRawLexicalPhraseContainmentFromDecisions rawDecisions =
  let lexicalClasses =
        [ LpcExhaustion
        , LpcNegatedExhaustion
        , LpcModalAbilityContrast
        , LpcNeedContact
        , LpcNeedMeaning
        , LpcAgencyLost
        ]
      matchedPhrases decisionClass =
        [ rlpdPhrase decision
        | decision <- rawDecisions
        , rlpdClass decision == decisionClass
        , rlpdMatched decision
        ]
      buildContainment decisionClass =
        case matchedPhrases decisionClass of
          [] -> []
          hits -> [RawLexicalPhraseContainment decisionClass hits]
  in concatMap buildContainment lexicalClasses

collectRawLexicalHits :: [Text] -> [RawLexicalHit]
collectRawLexicalHits inputTokens =
  buildRawLexicalHitsFromPhraseContainment (collectRawLexicalPhraseContainment inputTokens)

buildRawLexicalHitsFromPhraseContainment :: [RawLexicalPhraseContainment] -> [RawLexicalHit]
buildRawLexicalHitsFromPhraseContainment rawContainments =
  concatMap emitLexicalContainment rawContainments
  where
    suppressedExhaustion = any suppressesExhaustion rawContainments

    emitLexicalContainment rawContainment =
      case lexicalPhraseContainmentTag rawContainment of
        Just tag
          | rlpcClass rawContainment == LpcExhaustion && suppressedExhaustion -> []
          | otherwise -> [RawLexicalHit tag (rlpcMatchedLexemes rawContainment)]
        Nothing -> []

    suppressesExhaustion rawContainment =
      rlpcClass rawContainment == LpcNegatedExhaustion
        || rlpcClass rawContainment == LpcModalAbilityContrast

emitLexicalHits :: Text -> [RawLexicalHit] -> [MeaningAtom]
emitLexicalHits inputLower = map emitLexicalHit
  where
    emitLexicalHit rawHit =
      MeaningAtom
        "\1083\1077\1082\1089\1080\1082\1072"
        (rlhTag rawHit)
        (fallbackEmbedding inputLower)

exhaustionLexemes :: [Text]
exhaustionLexemes =
  [ "\1091\1089\1090\1072\1083", "\1091\1089\1090\1072\1083\1072", "\1074\1099\1075\1086\1088\1077\1083", "\1074\1099\1075\1086\1088\1077\1083\1072", "\1085\1077\1090 \1089\1080\1083", "\1080\1079\1084\1086\1090\1072\1085", "\1080\1079\1084\1086\1090\1072\1085\1072", "\1085\1077 \1084\1086\1075\1091 \1073\1086\1083\1100\1096\1077", "\1085\1077 \1084\1086\1075\1091 \1087\1088\1086\1076\1086\1083\1078\1072\1090\1100" ]

negatedExhaustionLexemes :: [Text]
negatedExhaustionLexemes =
  [ "\1085\1077 \1091\1089\1090\1072\1083"
  , "\1085\1077 \1091\1089\1090\1072\1083\1072"
  , "\1085\1077 \1074\1099\1075\1086\1088\1077\1083"
  , "\1085\1077 \1074\1099\1075\1086\1088\1077\1083\1072"
  , "\1085\1077 \1080\1079\1084\1086\1090\1072\1085"
  , "\1085\1077 \1080\1079\1084\1086\1090\1072\1085\1072"
  ]

modalAbilityContrastLexemes :: [Text]
modalAbilityContrastLexemes =
  [ "\1084\1086\1075\1091 \1085\1077"
  , "\1101\1090\1086 \1085\1077 \1079\1085\1072\1095\1080\1090"
  , "can choose not"
  , "does not mean"
  , "differs from being unable"
  ]

shouldSuppressExhaustion :: [Text] -> Bool
shouldSuppressExhaustion inputTokens =
  containsAnyKeywordPhrase inputTokens negatedExhaustionLexemes
    || containsAnyKeywordPhrase inputTokens modalAbilityContrastLexemes

contactLexemes :: [Text]
contactLexemes =
  [ "\1082\1086\1085\1090\1072\1082\1090", "\1085\1072 \1089\1074\1103\1079\1080", "\1085\1077 \1089\1083\1099\1096\1080\1096\1100", "\1088\1103\1076\1086\1084", "\1087\1088\1080\1089\1091\1090\1089\1090\1074\1080\1077" ]

meaningLexemes :: [Text]
meaningLexemes =
  [ "\1089\1084\1099\1089\1083", "\1079\1072\1095\1077\1084", "\1076\1083\1103 \1095\1077\1075\1086", "\1079\1085\1072\1095\1077\1085\1080\1077" ]

agencyLostLexemes :: [Text]
agencyLostLexemes =
  [ "\1085\1077 \1079\1085\1072\1102 \1095\1090\1086 \1076\1077\1083\1072\1090\1100", "\1087\1086\1090\1077\1088\1103\1083\1089\1103", "\1079\1072\1087\1091\1090\1072\1083\1089\1103", "\1079\1072\1087\1091\1090\1072\1083\1072\1089\1100" ]

tagFromCluster :: Text -> Text -> AtomTag
tagFromCluster t val
  | t == "exhaustion"   = Exhaustion val
  | t == "need_contact" = NeedContact val
  | t == "need_meaning" = NeedMeaning val
  | t == "anchoring"    = Anchoring val
  | t == "verification" = Verification val
  | t == "doubt"        = Doubt val
  | t == "logicalinference" = Verification val
  | t == "proofrequest" = Searching val
  | t == "distinctionrequest" = Doubt val
  | t == "counterexamplerequest" = Contradiction val val
  | t == "obligationduty" = Verification val
  | t == "permissionright" = Verification val
  | t == "temporalordering" = Verification val
  | t == "contrastcorrection" = Doubt val
  | otherwise           = CustomAtom t val

inferRegister :: [MeaningAtom] -> Register
inferRegister as
  | any (\a -> case maTag a of Exhaustion _ -> True; _ -> False) as = Exhaust
  | any (\a -> case maTag a of NeedContact _ -> True; _ -> False) as = Contact
  | any (\a -> case maTag a of Anchoring _ -> True; _ -> False) as = Anchor
  | any (\a -> case maTag a of Searching _ -> True; _ -> False) as = Search
  | otherwise = Neutral

updateTrace :: AtomTrace -> Int -> AtomSet -> AtomTrace
updateTrace old turn atoms =
  let newHistory = take 20 $ (fromIntegral turn, asLoad atoms) : atHistory old
      alpha = atAlpha old
      newLoad = if null (atHistory old)
                then asLoad atoms
                else alpha * asLoad atoms + (1.0 - alpha) * atCurrentLoad old
  in old { atHistory = newHistory, atCurrentLoad = newLoad }

extractObject :: Text -> Text
extractObject t =
  let ws = filter (\w -> T.length w > 3 && not (isStopWord w)) (T.words t)
  in case ws of
       (x:_) -> T.filter (`notElem` ("?!" :: String)) x
       []    -> "\1101\1090\1086"

isStopWord :: Text -> Bool
isStopWord w = T.toLower w `elem`
  [ "\1090\1077\1073\1077", "\1084\1077\1085\1103", "\1073\1099\1083\1086", "\1077\1089\1090\1100", "\1082\1086\1075\1076\1072", "\1077\1089\1083\1080"
  , "\1074\1089\1077", "\1074\1089\1103\1082\1086\1077", "\1089\1083\1077\1076\1086\1074\1072\1090\1077\1083\1100\1085\1086", "\1079\1076\1077\1089\1100", "\1084\1086\1078\1085\1086"
  , "\1089\1090\1072\1083\1086", "\1073\1099\1090\1100", "\1080\1090\1072\1082", "\1087\1086\1101\1090\1086\1084\1091", "\1087\1086\1090\1086\1084\1091", "\1083\1086\1075\1080\1095\1077\1089\1082\1080", "\1083\1086\1075\1080\1095\1077\1089\1082\1080\1081", "\1090\1086"
  , "\1084\1086\1075\1091", "\1084\1086\1078\1085\1086", "\1085\1077\1083\1100\1079\1103", "\1085\1091\1078\1085\1086", "\1085\1072\1076\1086", "\1076\1086\1083\1078\1077\1085", "\1076\1086\1083\1078\1085\1072", "\1076\1086\1083\1078\1085\1086", "\1076\1086\1083\1078\1085\1099"
  , "\1086\1073\1103\1079\1072\1085", "\1086\1073\1103\1079\1072\1085\1072", "\1086\1073\1103\1079\1072\1085\1086", "\1086\1073\1103\1079\1072\1085\1099", "\1087\1088\1072\1074\1086", "\1087\1088\1072\1074\1072", "\1087\1088\1072\1074\1086\1084", "\1076\1086\1083\1075", "\1076\1086\1083\1075\1072", "\1086\1073\1103\1079\1072\1085\1085\1086\1089\1090\1100", "\1086\1073\1103\1079\1072\1085\1085\1086\1089\1090\1100\1102"
  , "if", "then", "therefore", "because", "all", "every", "hence", "thus", "so", "consequently", "since"
  , "can", "may", "should", "must", "allowed", "forbidden", "right", "obligation", "duty"
  , "obligated", "responsible", "boundary", "fault"
  ]

extractObjectFromAtom :: MeaningAtom -> Text
extractObjectFromAtom a = case maTag a of
  Searching x     -> x
  Verification x  -> x
  Doubt x         -> x
  AgencyFound x   -> textShow x
  AgencyLost x    -> textShow x
  Anchoring x     -> x
  Contradiction x _ -> x
  Exhaustion x    -> x
  NeedContact x   -> x
  NeedMeaning x   -> x
  CustomAtom _ x  -> x
  AffectiveAtom x _ -> x
