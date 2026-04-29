{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Policy.RenderLexicon where

import Data.Text (Text)

stanceExplore :: Text
stanceExplore = "\1074\1086\1079\1084\1086\1078\1085\1086, "

stanceTentative :: Text
stanceTentative = "\1086\1089\1090\1086\1088\1086\1078\1085\1086: "

stanceFirm :: Text
stanceFirm = "\1086\1087\1088\1077\1076\1077\1083\1105\1085\1085\1086: "

stanceHonest :: Text
stanceHonest = "\1095\1077\1089\1090\1085\1086: "

stanceHoldBack :: Text
stanceHoldBack = "\1089\1076\1077\1088\1078\1072\1085\1085\1086: "

stanceCurated :: Text
stanceCurated = "\1074\1099\1073\1080\1088\1072\1085\1086: "

styleFormal :: Text
styleFormal = "\1057\1080\1089\1090\1077\1084\1085\1086:"

styleWarm :: Text
styleWarm = "\1041\1077\1088\1077\1078\1085\1086:"

styleDirect :: Text
styleDirect = "\1055\1088\1103\1084\1086:"

stylePoetic :: Text
stylePoetic = "\1054\1073\1088\1072\1079\1085\1086:"

styleClinical :: Text
styleClinical = "\1058\1086\1095\1085\1086:"

styleCautious :: Text
styleCautious = "\1054\1089\1090\1086\1088\1086\1078\1085\1086:"

styleRecovery :: Text
styleRecovery = "\1042\1086\1089\1089\1090\1072\1085\1086\1074\1083\1077\1085\1080\1077:"

moveGroundKnownPrefix :: Text
moveGroundKnownPrefix = "\1048\1079\1074\1077\1089\1090\1085\1086 \1087\1088\1086 "

moveGroundKnownPrepSuffix :: Text
moveGroundKnownPrepSuffix = "."

moveGroundBasisPrefix :: Text
moveGroundBasisPrefix = "\1054\1073\1086\1089\1085\1086\1074\1072\1085\1080\1077: "

moveShiftFromLabelPrefix :: Text
moveShiftFromLabelPrefix = "\1059\1081\1076\1105\1084 \1086\1090 \1103\1088\1083\1099\1082\1072 "

moveDefineFramePrefix :: Text
moveDefineFramePrefix = "\1054\1087\1088\1077\1076\1077\1083\1080\1084 \1088\1072\1084\1082\1091: "

moveStateDefinitionPrefix :: Text
moveStateDefinitionPrefix = "\1054\1087\1088\1077\1076\1077\1083\1080\1084: "

moveShowContrastPrefix :: Text
moveShowContrastPrefix = "\1045\1089\1090\1100 \1086\1090\1083\1080\1095\1080\1077 \1074 "

moveShowContrastPrepSuffix :: Text
moveShowContrastPrepSuffix = "."

moveStateBoundaryPrefix :: Text
moveStateBoundaryPrefix = "\1055\1088\1086\1074\1077\1076\1105\1084 \1075\1088\1072\1085\1080\1094\1091: "

moveReflectMirrorPrefix :: Text
moveReflectMirrorPrefix = "\1057\1084\1099\1089\1083\1086\1074\1072\1103 \1090\1086\1095\1082\1072: "

moveReflectResonatePrefix :: Text
moveReflectResonatePrefix = "\1059\1090\1086\1095\1085\1102 \1089\1084\1099\1089\1083: \1095\1090\1086 \1080\1084\1077\1085\1085\1086 \1086\1079\1085\1072\1095\1072\1077\1090 "

moveDescribeSketchPrefix :: Text
moveDescribeSketchPrefix = "\1054\1087\1080\1096\1091 "

movePurposeTeleologyPrefix :: Text
movePurposeTeleologyPrefix = "\1062\1077\1083\1100: "

moveHypothesizeTestPrefix :: Text
moveHypothesizeTestPrefix = "\1040 \1077\1089\1083\1080 "

moveAffirmPresence :: Text
moveAffirmPresence = "\1071 \1079\1076\1077\1089\1100."

moveAcknowledgeRupture :: Text
moveAcknowledgeRupture = "\1055\1088\1080\1079\1085\1072\1102 \1088\1072\1079\1088\1099\1074."

moveRepairBridgePrefix :: Text
moveRepairBridgePrefix = "\1042\1077\1088\1085\1105\1084 \1082\1086\1085\1090\1072\1082\1090"

moveContactBridgePrefix :: Text
moveContactBridgePrefix = "\1050\1086\1085\1090\1072\1082\1090"

moveContactReachPrefix :: Text
moveContactReachPrefix = "\1071 \1088\1103\1076\1086\1084"

moveAnchorStabilizePrefix :: Text
moveAnchorStabilizePrefix = "\1059\1087\1086\1088"

moveClarifyDisambiguatePrefix :: Text
moveClarifyDisambiguatePrefix = "\1059\1090\1086\1095\1085\1102: "

moveDeepenProbePrefix :: Text
moveDeepenProbePrefix = "\1043\1083\1091\1073\1086\1082\1086: \1095\1090\1086 \1079\1072 "

moveConfrontChallengePrefix :: Text
moveConfrontChallengePrefix = "\1057\1086\1084\1085\1077\1074\1072\1102\1089\1100: "

moveNextStepPrefix :: Text
moveNextStepPrefix = "\1044\1072\1083\1100\1096\1077 "

moveLexRepairBridgeSep :: Text
moveLexRepairBridgeSep = " \8212 "

moveLexContactBridgeSep :: Text
moveLexContactBridgeSep = " \8212 "

moveLexContactReachSep :: Text
moveLexContactReachSep = " \8212 "

moveLexAnchorStabilizeSep :: Text
moveLexAnchorStabilizeSep = " \8212 "

moveLexNextStepSep :: Text
moveLexNextStepSep = " \8212 "

openGuillemet :: Text
openGuillemet = "\171"

closeGuillemet :: Text
closeGuillemet = "\187"

arrowSeparator :: Text
arrowSeparator = " \8594 "

dashSeparator :: Text
dashSeparator = " \8212 "

morphVerbSuffixT :: Text
morphVerbSuffixT = "\1090\1100"

morphVerbSuffixTi :: Text
morphVerbSuffixTi = "\1090\1080"

morphAdjSuffixYj :: Text
morphAdjSuffixYj = "\1099\1081"

morphAdjSuffixIj :: Text
morphAdjSuffixIj = "\1080\1081"

morphAdjSuffixOj :: Text
morphAdjSuffixOj = "\1086\1081"

morphAdvSuffixO :: Text
morphAdvSuffixO = "\1086"

morphNounSuffixOst :: Text
morphNounSuffixOst = "\1086\1089\1090\1100"

morphNounSuffixNost :: Text
morphNounSuffixNost = "\1085\1086\1089\1090\1100"

morphNounSuffixEnie :: Text
morphNounSuffixEnie = "\1077\1085\1080\1077"

morphNounSuffixNnie :: Text
morphNounSuffixNnie = "\1085\1080\1077"

morphNounSuffixA :: Text
morphNounSuffixA = "\1072"

morphNounSuffixIya :: Text
morphNounSuffixIya = "\1080\1103"

morphInstrSuffixOm :: Text
morphInstrSuffixOm = "\1086\1084"

morphGenSuffixI :: Text
morphGenSuffixI = "\1080"

morphPrepSuffixE :: Text
morphPrepSuffixE = "\1077"

morphDatSuffixU :: Text
morphDatSuffixU = "\1091"

morphAccSuffixUyu :: Text
morphAccSuffixUyu = "\1091\1102"

morphPluralSuffixY :: Text
morphPluralSuffixY = "\1099"

morphPluralSuffixI :: Text
morphPluralSuffixI = "\1080"

morphPluralSuffixAmi :: Text
morphPluralSuffixAmi = "\1072\1084\1080"

morphFemSuffixA :: Text
morphFemSuffixA = "\1072"

morphFemSuffixYa :: Text
morphFemSuffixYa = "\1103"

morphNeutSuffixO :: Text
morphNeutSuffixO = "\1086"

morphNeutSuffixE :: Text
morphNeutSuffixE = "\1077"

morphVerbDerivOvat :: Text
morphVerbDerivOvat = "\1086\1074\1072\1090\1100"

morphVerbDerivT :: Text
morphVerbDerivT = "\1090\1100"

morphVerbDerivTi :: Text
morphVerbDerivTi = "\1090\1080"

morphAdjDerivYj :: Text
morphAdjDerivYj = "\1099\1081"

morphAdjDerivIj :: Text
morphAdjDerivIj = "\1080\1081"

morphDerivEnie :: Text
morphDerivEnie = "\1077\1085\1080\1077"

morphDerivOst :: Text
morphDerivOst = "\1086\1089\1090\1100"
