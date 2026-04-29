module QxFx0.Types.Config.Decision
  ( defaultInputPropositionConfidence
  , defaultEpistemicForFamily
  ) where

import QxFx0.Types.Decision.Enums (EpistemicStatus(..))
import QxFx0.Types.Domain (CanonicalMoveFamily(..))

defaultInputPropositionConfidence :: Double
defaultInputPropositionConfidence = 0.5

defaultEpistemicForFamily :: CanonicalMoveFamily -> EpistemicStatus
defaultEpistemicForFamily CMGround = Known 0.9
defaultEpistemicForFamily CMDefine = Known 0.85
defaultEpistemicForFamily CMDistinguish = Probable 0.7
defaultEpistemicForFamily CMReflect = Uncertain 0.5
defaultEpistemicForFamily CMDescribe = Probable 0.7
defaultEpistemicForFamily CMPurpose = Speculative 0.4
defaultEpistemicForFamily CMHypothesis = Speculative 0.3
defaultEpistemicForFamily CMRepair = Probable 0.6
defaultEpistemicForFamily CMContact = Uncertain 0.5
defaultEpistemicForFamily CMAnchor = Known 0.8
defaultEpistemicForFamily CMClarify = Uncertain 0.4
defaultEpistemicForFamily CMDeepen = Speculative 0.35
defaultEpistemicForFamily CMConfront = Probable 0.65
defaultEpistemicForFamily CMNextStep = Uncertain 0.5
