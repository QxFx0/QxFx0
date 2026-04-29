module QxFx0.Types.Decision.Family
  ( familyToRelation
  , familyToStrategy
  , familyToStance
  , familyToEpistemic
  , familyToSpeechAct
  , familyToOpeningMove
  , familyToCoreMove
  ) where

import QxFx0.Types.Decision.Enums
import QxFx0.Types.Config.Decision (defaultEpistemicForFamily)
import QxFx0.Types.Domain (CanonicalMoveFamily(..))

familyToRelation :: CanonicalMoveFamily -> SemanticRelation
familyToRelation CMGround = SRGround
familyToRelation CMDefine = SRDefine
familyToRelation CMDistinguish = SRDistinguish
familyToRelation CMReflect = SRReflect
familyToRelation CMDescribe = SRDescribe
familyToRelation CMPurpose = SRPurpose
familyToRelation CMHypothesis = SRHypothesis
familyToRelation CMRepair = SRRepair
familyToRelation CMContact = SRContact
familyToRelation CMAnchor = SRAnchor
familyToRelation CMClarify = SRClarify
familyToRelation CMDeepen = SRDeepen
familyToRelation CMConfront = SRConfront
familyToRelation CMNextStep = SRNextStep

familyToStrategy :: CanonicalMoveFamily -> AnswerStrategy
familyToStrategy CMGround = DirectThenGround
familyToStrategy CMDefine = DefineThenUnfold
familyToStrategy CMDistinguish = ContrastThenDistinguish
familyToStrategy CMReflect = ReflectThenMirror
familyToStrategy CMDescribe = DescribeThenSketch
familyToStrategy CMPurpose = PurposeThenTeleology
familyToStrategy CMHypothesis = HypothesizeThenTest
familyToStrategy CMRepair = RepairThenRestore
familyToStrategy CMContact = ContactThenBridge
familyToStrategy CMAnchor = AnchorThenStabilize
familyToStrategy CMClarify = ClarifyThenDisambiguate
familyToStrategy CMDeepen = DeepenThenProbe
familyToStrategy CMConfront = DeepenThenProbe
familyToStrategy CMNextStep = DirectThenGround

familyToStance :: CanonicalMoveFamily -> StanceMarker
familyToStance CMGround = Firm
familyToStance CMDefine = Commit
familyToStance CMDistinguish = Observe
familyToStance CMReflect = Honest
familyToStance CMDescribe = Observe
familyToStance CMPurpose = Explore
familyToStance CMHypothesis = Tentative
familyToStance CMRepair = Honest
familyToStance CMContact = Honest
familyToStance CMAnchor = Firm
familyToStance CMClarify = Tentative
familyToStance CMDeepen = Explore
familyToStance CMConfront = Commit
familyToStance CMNextStep = Explore

familyToEpistemic :: CanonicalMoveFamily -> EpistemicStatus
familyToEpistemic = defaultEpistemicForFamily

familyToSpeechAct :: CanonicalMoveFamily -> SpeechAct
familyToSpeechAct CMGround = Assert
familyToSpeechAct CMDefine = Assert
familyToSpeechAct CMDistinguish = Assert
familyToSpeechAct CMReflect = Reflect
familyToSpeechAct CMDescribe = Assert
familyToSpeechAct CMPurpose = Assert
familyToSpeechAct CMHypothesis = Ask
familyToSpeechAct CMRepair = Offer
familyToSpeechAct CMContact = MakeContact
familyToSpeechAct CMAnchor = Assert
familyToSpeechAct CMClarify = Ask
familyToSpeechAct CMDeepen = Ask
familyToSpeechAct CMConfront = Confront
familyToSpeechAct CMNextStep = Offer

familyToOpeningMove :: CanonicalMoveFamily -> ContentMove
familyToOpeningMove CMGround = MoveGroundKnown
familyToOpeningMove CMDefine = MoveDefineFrame
familyToOpeningMove CMDistinguish = MoveShowContrast
familyToOpeningMove CMReflect = MoveReflectMirror
familyToOpeningMove CMDescribe = MoveDescribeSketch
familyToOpeningMove CMPurpose = MovePurposeTeleology
familyToOpeningMove CMHypothesis = MoveHypothesizeTest
familyToOpeningMove CMRepair = MoveRepairBridge
familyToOpeningMove CMContact = MoveContactBridge
familyToOpeningMove CMAnchor = MoveAnchorStabilize
familyToOpeningMove CMClarify = MoveClarifyDisambiguate
familyToOpeningMove CMDeepen = MoveDeepenProbe
familyToOpeningMove CMConfront = MoveConfrontChallenge
familyToOpeningMove CMNextStep = MoveNextStep

familyToCoreMove :: CanonicalMoveFamily -> ContentMove
familyToCoreMove CMGround = MoveGroundBasis
familyToCoreMove CMDefine = MoveStateDefinition
familyToCoreMove CMDistinguish = MoveStateBoundary
familyToCoreMove CMReflect = MoveReflectResonate
familyToCoreMove CMDescribe = MoveDescribeSketch
familyToCoreMove CMPurpose = MovePurposeTeleology
familyToCoreMove CMHypothesis = MoveHypothesizeTest
familyToCoreMove CMRepair = MoveAcknowledgeRupture
familyToCoreMove CMContact = MoveContactReach
familyToCoreMove CMAnchor = MoveAnchorStabilize
familyToCoreMove CMClarify = MoveClarifyDisambiguate
familyToCoreMove CMDeepen = MoveDeepenProbe
familyToCoreMove CMConfront = MoveConfrontChallenge
familyToCoreMove CMNextStep = MoveNextStep
