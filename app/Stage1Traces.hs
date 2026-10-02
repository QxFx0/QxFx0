{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

-- | Standalone Stage-1 trace emitter (ADR-0054 §2.3, pre-registered
-- 2026-10-02). SHADOW ONLY: reads the committed Stage-1 data
-- files, runs the file evaluators from 'QxFx0.Semantic.IREval.Batch',
-- and writes JSON evaluation traces plus a threshold summary.
-- No pipeline callers, no runtime reads, no new rules or data.
--
-- Usage: qxfx0-stage1-traces [--out DIR]
-- Writes DIR/exit_traces.jsonl, DIR/scenario_traces.jsonl and
-- DIR/summary.json. Exits 1 on any preset gate breach
-- (strict < 0.80, defeasible < 0.60, conflicts/presuppositions/
-- scenarios not exact), 0 otherwise. Run from the repo root
-- (data paths are relative).
module Main (main) where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (createDirectoryIfMissing)
import System.Environment (getArgs)
import System.Exit (exitFailure, exitSuccess)
import System.FilePath ((</>))

import QxFx0.Semantic.IREval (StrictRule)
import QxFx0.Semantic.IREval.Batch

exitData :: FilePath
exitData = "data/semantic_ir/exit_tasks.jsonl"

rulesData :: FilePath
rulesData = "data/semantic_ir/rules.jsonl"

scenariosData :: FilePath
scenariosData = "data/semantic_ir/scenarios.jsonl"

main :: IO ()
main = do
  args <- getArgs
  let outDir = case args of
        ["--out", dir] -> dir
        ["--out"] -> "stage1-traces"
        [] -> "stage1-traces"
        _ -> "stage1-traces"
  createDirectoryIfMissing True outDir
  exitRows <- readJsonlRowsLenient exitData :: IO [ExitTaskRow]
  strictRows <- readJsonlRowsLenient exitData :: IO [ExitStrictRow]
  fileRules <- readJsonlRowsLenient rulesData :: IO [RuleFileRow]
  scenarioRows <- readJsonlRowsLenient scenariosData :: IO [ScenarioRowEx]
  strictFileRules <- either fail pure
    (mapM toStrictFileRuleEither [ r | r <- fileRules, frKind r == "strict" ])

  exitTraces <- mapM evalRow
    [ r | r <- exitRows, exitKind r /= "strict" ]
  strictTraces <- mapM runStrict strictRows
  let allExit = exitTraces <> strictTraces
  scenarioTraces <- concat <$> mapM (runScenarios strictFileRules) scenarioRows

  BL.writeFile (outDir </> "exit_traces.jsonl")
    (BL.concat [ Aeson.encode t <> "\n" | t <- allExit ])
  BL.writeFile (outDir </> "scenario_traces.jsonl")
    (BL.concat [ Aeson.encode t <> "\n" | t <- scenarioTraces ])

  let summary = summarize allExit scenarioTraces
  BL.writeFile (outDir </> "summary.json") (Aeson.encode summary)
  TIO.putStrLn (T.pack ("wrote " <> outDir <> ": "
    <> show (length allExit) <> " exit traces, "
    <> show (length scenarioTraces) <> " scenario traces"))
  TIO.putStrLn (T.pack ("gates pass: " <> show (bsGatesPass summary)))
  if bsGatesPass summary then exitSuccess else exitFailure

evalRow :: ExitTaskRow -> IO ExitTrace
evalRow row = case exitKind row of
  "defeasible" -> do
    outcome <- either fail pure (runDefeasibleDetail row)
    pure (base (dfoPass outcome)) { etDefeasible = Just outcome }
  "defeasible-duel" -> do
    outcome <- either fail pure (runDefeasibleDetail row)
    pure (base (dfoPass outcome)) { etDefeasible = Just outcome }
  "conflict" -> do
    outcome <- either fail pure (runConflictDetail row)
    pure (base (coPass outcome)) { etConflict = Just outcome }
  "presupposition" -> do
    outcome <- either fail pure (runPresupDetail row)
    pure (base (poPass outcome)) { etPresup = Just outcome }
  other -> fail ("unknown exit kind: " <> T.unpack other)
  where
    base pass = ExitTrace (exitId row) (exitKind row) (exitExpected row)
      pass traceProvenance Nothing Nothing Nothing Nothing

runStrict :: ExitStrictRow -> IO ExitTrace
runStrict row = do
  outcome <- either fail pure (runStrictDetail row)
  pure (ExitTrace (esrId row) "strict" (esrExpected row)
    (soPass outcome) traceProvenance (Just outcome) Nothing Nothing Nothing)

runScenarios :: [StrictRule] -> ScenarioRowEx -> IO [ScenarioTrace]
runScenarios rules row = do
  results <- either fail pure (runScenarioDetail rules row)
  pure [ ScenarioTrace sid kind pass traceProvenance
       | (sid, kind, pass) <- results ]

summarize :: [ExitTrace] -> [ScenarioTrace] -> BatchSummary
summarize exits scenarios =
  let strict = [ etPass t | t <- exits, etKind t == "strict" ]
      def = [ etPass t | t <- exits, etKind t `elem` ["defeasible", "defeasible-duel"] ]
      conf = [ etPass t | t <- exits, etKind t == "conflict" ]
      presup = [ etPass t | t <- exits, etKind t == "presupposition" ]
      scen = [ stPass t | t <- scenarios ]
      gateS = (countPass strict, length strict)
      gateD = (countPass def, length def)
      gates = countPass strict * 5 >= length strict * 4
        && countPass def * 5 >= length def * 3
        && and conf && and presup && and scen
  in BatchSummary (length exits) gateS gateD
       (countPass conf, length conf)
       (countPass presup, length presup)
       (countPass scen, length scen)
       gates traceProvenance
  where
    countPass xs = length (filter id xs)
