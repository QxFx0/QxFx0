{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}
{-| Minimal legal DB adapter: traceable fact pipeline with safety boundary.

  For low-RAM environments the adapter uses an in-memory lookup table.
  All legal responses carry a mandatory disclaimer and source trace.
-}
module QxFx0.Legal.Adapter
  ( LegalFact(..)
  , retrieveLegalFact
  , legalDisclaimer
  , legalFactToKnowledgeFragment
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map.Strict as M

-- | A legal fact retrieved from an external or embedded source.
data LegalFact = LegalFact
  { lfSourceId :: !Text    -- ^ Canonical source identifier (e.g. "ru.civil.code.art1")
  , lfSection :: !Text     -- ^ Section or article reference
  , lfText :: !Text        -- ^ Fact text in Russian
  , lfConfidence :: !Double -- ^ Confidence score in [0,1]
  , lfUncertainty :: !Bool  -- ^ True when the fact has known uncertainty / caveats
  } deriving stock (Eq, Show)

-- | Mandatory safety disclaimer appended to every legal response.
legalDisclaimer :: Text
legalDisclaimer = "Это не юридическая консультация."

-- | In-memory legal fact DB for low-RAM / degraded-local profiles.
--   Keys are lowercase Russian topic keywords.
legalFactDb :: M.Map Text LegalFact
legalFactDb = M.fromList
  [ ("право", LegalFact
      { lfSourceId = "ru.civil.code.art1"
      , lfSection = "Общие положения"
      , lfText = "Право регулирует имущественные и личные неимущественные отношения."
      , lfConfidence = 0.92
      , lfUncertainty = False
      })
  , ("закон", LegalFact
      { lfSourceId = "ru.constitution.art15"
      , lfSection = "Верховенство закона"
      , lfText = "Конституция РФ имеет высшую юридическую силу."
      , lfConfidence = 0.95
      , lfUncertainty = False
      })
  , ("хартия", LegalFact
      { lfSourceId = "en.magna-carta.1215"
      , lfSection = "Ограничение власти"
      , lfText = "Великая хартия вольностей 1215 года ограничила власть английского короля."
      , lfConfidence = 0.88
      , lfUncertainty = True
      })
  , ("презумпция", LegalFact
      { lfSourceId = "ru.criminal.procedure.art14"
      , lfSection = "Презумпция невиновности"
      , lfText = "Обвиняемый считается невиновным, пока его виновность не будет доказана."
      , lfConfidence = 0.97
      , lfUncertainty = False
      })
  , ("юридический", LegalFact
      { lfSourceId = "ru.civil.code.art1"
      , lfSection = "Общие положения"
      , lfText = "Юридические понятия регулируются нормами права."
      , lfConfidence = 0.90
      , lfUncertainty = False
      })
  ]

-- | Retrieve a legal fact by subject keyword.
--   Returns 'Nothing' for non-legal topics or unknown keywords.
retrieveLegalFact :: Text -> IO (Maybe LegalFact)
retrieveLegalFact key = pure $ M.lookup (T.toLower (T.strip key)) legalFactDb

-- | Render a 'LegalFact' into a single knowledge fragment.
--   Includes the fact text, source trace, confidence annotation, and mandatory disclaimer.
legalFactToKnowledgeFragment :: LegalFact -> Text
legalFactToKnowledgeFragment lf =
  let sourceTrace = "[источник: " <> lfSourceId lf <> " | раздел: " <> lfSection lf <> "]"
      confidenceLabel
        | lfConfidence lf >= 0.95 = " (высокая достоверность)"
        | lfUncertainty lf        = " (есть неопределенность)"
        | otherwise               = ""
  in T.intercalate " "
       [ lfText lf
       , sourceTrace
       , confidenceLabel
       , legalDisclaimer
       ]
