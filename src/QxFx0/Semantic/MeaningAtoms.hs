{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Semantic.MeaningAtoms
  ( collectAtoms
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

collectAtoms :: Text -> [ClusterDef] -> AtomSet
collectAtoms input clusters =
  let inputLower = T.toLower input
      inputTokens = tokenizeKeywordText input
      suppressedExhaustion = shouldSuppressExhaustion inputTokens
      foundAtoms0 = concatMap (matchCluster inputLower inputTokens) clusters
      foundAtoms = if suppressedExhaustion then filter (not . isExhaustionAtom) foundAtoms0 else foundAtoms0
      lexical = lexicalAtoms inputLower inputTokens
      structural = if containsAnyKeywordPhrase inputTokens ["\1095\1090\1086", "\1082\1072\1082", "\1087\1086\1095\1077\1084\1091"] || T.isSuffixOf "?" (T.strip input)
                   then [MeaningAtom (extractObject input) (Searching (extractObject input)) (fallbackEmbedding (T.unpack inputLower))]
                   else []
      allFound = foundAtoms ++ lexical ++ structural
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
  let keywords = map T.toLower (cdKeywords cd)
      hits = filter (containsKeywordPhrase inpTokens) keywords
  in if not (null hits)
     then [MeaningAtom (T.intercalate ", " hits) (tagFromCluster (T.toLower $ cdName cd) (T.intercalate ", " hits)) (fallbackEmbedding (T.unpack inp))]
     else []

lexicalAtoms :: Text -> [Text] -> [MeaningAtom]
lexicalAtoms inputLower inputTokens =
  concat
    [ detectUnless suppressedExhaustion (Exhaustion "\1083\1077\1082\1089\1080\1082\1072") exhaustionLexemes
    , detect (NeedContact "\1083\1077\1082\1089\1080\1082\1072") contactLexemes
    , detect (NeedMeaning "\1083\1077\1082\1089\1080\1082\1072") meaningLexemes
    , detect (AgencyLost semanticLexicalAgencyLostStrength) agencyLostLexemes
    ]
  where
    suppressedExhaustion = shouldSuppressExhaustion inputTokens

    detect :: AtomTag -> [Text] -> [MeaningAtom]
    detect tag lexemes =
      if containsAnyKeywordPhrase inputTokens lexemes
        then [MeaningAtom "\1083\1077\1082\1089\1080\1082\1072" tag (fallbackEmbedding (T.unpack inputLower))]
        else []

    detectUnless :: Bool -> AtomTag -> [Text] -> [MeaningAtom]
    detectUnless suppressed tag lexemes =
      if suppressed then [] else detect tag lexemes

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
