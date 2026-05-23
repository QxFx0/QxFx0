{-| Facade for turn-planning modulation, builders, templates, and claims integration. -}
module QxFx0.Core.TurnPlanning
  ( egoModulateStance
  , egoModulateEpistemic
  , egoModulateEpistemicWithTruthContract
  , traceModulateStance
  , threeStageModulation
  , threeStageModulationWithTruthContract
  , feralDegradation
  , antiStuck
  , buildRMP
  , buildRMPWithTruthContract
  , buildRCP
  , templateToMoves
  , integrateIdentityClaims
  ) where

import QxFx0.Core.TurnPlanning.Builders
  ( buildRCP
  , buildRMP
  , buildRMPWithTruthContract
  )
import QxFx0.Core.TurnPlanning.Claims (integrateIdentityClaims)
import QxFx0.Core.TurnPlanning.Modulation
  ( antiStuck
  , egoModulateEpistemic
  , egoModulateEpistemicWithTruthContract
  , egoModulateStance
  , feralDegradation
  , threeStageModulation
  , threeStageModulationWithTruthContract
  , traceModulateStance
  )
import QxFx0.Core.TurnPlanning.Templates (templateToMoves)
