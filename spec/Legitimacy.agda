module Legitimacy where

data IsLegit (A : Set) : Set where
  Legit-Acknowledge : IsLegit A
  Legit-Clarify     : IsLegit A
  Legit-Insight     : IsLegit A

{-# COMPILE GHC IsLegit = data QxFx0.Types.IsLegit
  ( Legit-Acknowledge = QxFx0.Types.LegitAcknowledge
  | Legit-Clarify     = QxFx0.Types.LegitClarify
  | Legit-Insight     = QxFx0.Types.LegitInsight
  ) #-}

data LegitimacyReason : Set where
  ReasonShadowDivergence   : LegitimacyReason
  ReasonShadowUnavailable  : LegitimacyReason
  ReasonLowParserConfidence : LegitimacyReason
  ReasonOk                 : LegitimacyReason

{-# COMPILE GHC LegitimacyReason = data QxFx0.Types.LegitimacyReason
  ( ReasonShadowDivergence   = QxFx0.Types.ReasonShadowDivergence
  | ReasonShadowUnavailable  = QxFx0.Types.ReasonShadowUnavailable
  | ReasonLowParserConfidence = QxFx0.Types.ReasonLowParserConfidence
  | ReasonOk                 = QxFx0.Types.ReasonOk
  ) #-}

data DecisionDisposition : Set where
  DispositionPermit   : DecisionDisposition
  DispositionRepair   : DecisionDisposition
  DispositionDeny     : DecisionDisposition
  DispositionAdvisory : DecisionDisposition

{-# COMPILE GHC DecisionDisposition = data QxFx0.Types.DecisionDisposition
  ( DispositionPermit   = QxFx0.Types.DispositionPermit
  | DispositionRepair   = QxFx0.Types.DispositionRepair
  | DispositionDeny     = QxFx0.Types.DispositionDeny
  | DispositionAdvisory = QxFx0.Types.DispositionAdvisory
  ) #-}

data ⊥ : Set where

legit-not-empty : {A : Set} → IsLegit A → ⊥ → ⊥
legit-not-empty Legit-Acknowledge ()
legit-not-empty Legit-Clarify ()
legit-not-empty Legit-Insight ()

legit-consistent : {A : Set} → (l : IsLegit A) → IsLegit A
legit-consistent l = l
