{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Self.Adjunction
Description : Phase-3 algebraic backbone of the dual-mode runtime.

A typed, pure realisation of the @Holistic ⊣ Formal@ adjunction
named in @docs\/THEORY.md@ §3.2 and pinned by
@docs\/adr\/0008-left-right-adjunction.md@.

== What this module is

The right-hemispheric (\"holistic\") and left-hemispheric (\"formal\")
modes of operation live as two parameterised types,

@
'Holistic' a = (a, 'Field')      -- value perceived together with its field
'Formal'   a = 'Field' -> a      -- value as a strategy across fields
@

The pair is the textbook product–exponential adjunction
\(- \times s \dashv s \to -\) with \(s = \mathrm{Field}\), and it
is the standard /currying/ isomorphism

@
('Holistic' a -> b)  ≅  (a -> 'Formal' b)
@

witnessed by 'leftAdjunct' and 'rightAdjunct'. The unit and counit
of the adjunction are forced by the types up to 'Functor' action;
neither requires a designated zero field, monoid structure, or any
choice beyond what the types determine.

== What this module is /not/

This module is the algebraic /spine/ of the dual-mode story. It
does /not/ implement any holistic computation, does /not/ touch
the turn pipeline, and does /not/ commit to a final shape of
'Field' (which is intentionally a stub here and grows in Phase 4).
Phase 4–5 work re-shapes call sites in @Core.Intuition@,
@Core.ConsciousnessLoop@, and @RouteEffects@ in terms of these
types; this module only provides the algebra those phases will
quote from.

== Triangle identities

The adjunction is required to satisfy

@
counit . fmap unit       ≡ id   -- on 'Holistic' (left triangle)
fmap counit . unit       ≡ id   -- on 'Formal'   (right triangle, pointwise)
@

Both hold by direct calculation on the concrete instance below;
both are also verified by the @Test.Suite.SelfAdjunction@
property suite.
-}
module QxFx0.Self.Adjunction
  ( -- * The adjunction class
    Adjunction (..)
    -- * Concrete adjunction for Phase 3
  , Field
  , Holistic (..)
  , Formal   (..)
    -- * Derived combinators
  , groundIn
  , rebroaden
  , probe
  ) where

import QxFx0.Self.Field (Field)

-- | Categorical adjunction @l ⊣ r@: a pair of functors with a
-- natural hom-set isomorphism witnessed by @leftAdjunct@ and
-- @rightAdjunct@, equivalently by the 'unit' and 'counit' natural
-- transformations.
--
-- Default implementations express @leftAdjunct@/@rightAdjunct@ in
-- terms of @unit@/@counit@; instances may override them for
-- efficiency but the laws (the triangle identities and
-- naturality) must hold either way.
class (Functor l, Functor r) => Adjunction l r | l -> r, r -> l where
  -- | @η : 1 ⇒ r ∘ l@. Lifts a value into the round-trip
  -- @r (l a)@.
  unit         :: a -> r (l a)

  -- | @ε : l ∘ r ⇒ 1@. Collapses a round-trip @l (r a)@ back to
  -- @a@.
  counit       :: l (r a) -> a

  -- | The forward direction of the hom-set isomorphism
  -- @Hom(l a, b) ≅ Hom(a, r b)@.
  leftAdjunct  :: (l a -> b) -> (a -> r b)
  leftAdjunct g a = fmap g (unit a)

  -- | The reverse direction of the hom-set isomorphism
  -- @Hom(l a, b) ≅ Hom(a, r b)@.
  rightAdjunct :: (a -> r b) -> (l a -> b)
  rightAdjunct k la = counit (fmap k la)

-- | Right-hemispheric mode: a value perceived /with/ its field,
-- inseparable from its ground.
--
-- The left adjoint of the adjunction. As a functor, 'Holistic' is
-- the product functor @(- × Field)@; @fmap@ acts on the value and
-- leaves the field untouched.
newtype Holistic a = Holistic { runHolistic :: (a, Field) }
  deriving stock (Eq, Show, Functor)

-- | Left-hemispheric mode: a value as a /strategy/ across fields,
-- a context-respecting commitment that is re-evaluable in any
-- field.
--
-- The right adjoint of the adjunction. As a functor, 'Formal' is
-- the exponential @(Field -> -)@; @fmap@ post-composes with the
-- function.
newtype Formal a = Formal { runFormal :: Field -> a }
  deriving stock (Functor)

-- | The adjunction @Holistic ⊣ Formal@. The unit and counit are
-- forced by the types up to 'Functor' action and require no
-- additional structure on 'Field'.
instance Adjunction Holistic Formal where
  unit a                            = Formal (\fd -> Holistic (a, fd))
  counit (Holistic (Formal f, fd))  = f fd

-- | Sharpen: extract the value from a holistic observation,
-- forgetting the field. The dual of 'rebroaden' at the value
-- level; together they witness the basic correspondence
--
-- @groundIn (Holistic (a, fd)) ≡ runFormal (rebroaden a) fd ≡ a@
groundIn :: Holistic a -> a
groundIn (Holistic (a, _fd)) = a

-- | Broaden: lift a bare value to a formal strategy that ignores
-- the field on which it is evaluated.
rebroaden :: a -> Formal a
rebroaden a = Formal (\_fd -> a)

-- | Evaluate a formal commitment under a probe field without
-- baking it into a particular call site.
--
-- This is just 'runFormal'; the alias exists to mark observational
-- (diagnostic) uses distinct from genuine grounding. Production
-- code should generally go through 'rightAdjunct' rather than call
-- 'probe' directly.
probe :: Formal a -> Field -> a
probe = runFormal
