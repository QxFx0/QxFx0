{-|
Module      : QxFx0.Self.MeaningDirective
Description : canonical — FMAR Phase-5 — re-export shim for 'MeaningDirective'.

The 'MeaningDirective' type is /defined/ in 'QxFx0.Types.Domain.R5'
alongside 'R5Verdict' (which carries it as @Maybe MeaningDirective@).
Defining it there avoids a module import cycle: @R5Verdict@ needs
@MeaningDirective@, and @MeaningDirective@ needs the @R5@ move-family
enums.

This module re-exports it under the @Self@-layer name used by the FMAR
plan and downstream callers, so the conceptual home stays in the Self
layer even though the definition is physically colocated with @R5Verdict@.
-}
module QxFx0.Self.MeaningDirective
  ( MeaningDirective (..)
  ) where

import QxFx0.Types.Domain.R5 (MeaningDirective (..))
