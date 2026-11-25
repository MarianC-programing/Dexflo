{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Main where

import           Data.Aeson (encode)
import           Data.ByteString.Lazy.Char8 (putStrLn, writeFile)
import           Data.Maybe (fromMaybe)
import           Data.Text (Text)
import           System.Environment (getArgs, getProgName)
import           System.Exit (exitFailure, exitSuccess)
import           System.IO (hPutStrLn, stderr)
import           Junit.Parse (parseJUnitFile, JUnit(..))
import           Report.Build (buildReport, SuiteReport)
import           Report.Compare (compareReports)

data Options = Options
  { junitFile   :: FilePath
  , previous    :: Maybe FilePath
  , slowThreshold :: Double
  , outputFile  :: Maybe FilePath
  }

defaultOptions :: Options
defaultOptions = Options
  { junitFile   = "results/junit.xml"
  , previous    = Nothing
  , slowThreshold = 5.0
  , outputFile  = Nothing
  }

parseArgs :: [String] -> Either String Options
parseArgs args = go args defaultOptions
  where
    go [] opts = Right opts
    go ("--junit":f:rest) opts = go rest opts{ junitFile = f }
    go ("--previous":f:rest) opts = go rest opts{ previous = Just f }
    go ("--slow-threshold":t:rest) opts =
      case reads t of
        [(v,"")] -> go rest opts{ slowThreshold = v }
        _         -> Left ("valor invalido para --slow-threshold: " ++ t)
    go ("-o":f:rest) opts = go rest opts{ outputFile = Just f }
    go ("--output":f:rest) opts = go rest opts{ outputFile = Just f }
    go ("--help":_) _ =
      Right defaultOptions{ junitFile = "--help" }
    go (a:_) _ = Left ("argumento desconocido: " ++ a)

printUsage :: IO ()
printUsage = do
  prog <- getProgName
  putStrLn $ unlines
    [ "Uso: " ++ prog ++ " [OPCIONES]"
    , ""
    , "Lee un archivo JUnit (resultados de Playwright/Dexflo) y genera un JSON"
    , "con totales, resultados por tag, tests lentos y comparacion con la"
    , "ejecucion anterior."
    , ""
    , "Opciones:"
    , "  --junit FILE        archivo JUnit de entrada (por defecto: results/junit.xml)"
    , "  --previous FILE     JUnit previo para comparacion (opcional)"
    , "  --slow-threshold SEG  umbral para tests lentos en segundos (por defecto: 5.0)"
    , "  -o FILE, --output FILE  archivo de salida JSON (por defecto: stdout)"
    , "  --help              muestra esta ayuda"
    ]

run :: Options -> IO ()
run opts = do
  doc <- parseJUnitFile (junitFile opts)
  let report = buildReport (junitSuites doc) (slowThreshold opts)
  output <- case previous opts of
    Nothing -> return (Left report)
    Just prevFile -> do
      prevDoc <- parseJUnitFile prevFile
      let prevReport = buildReport (junitSuites prevDoc) (slowThreshold opts)
      return (Right (compareReports prevReport report))
  case output of
    Left r  -> writeOutput (encode r)
    Right c -> writeOutput (encode c)
  where
    writeOutput :: ToJSON a => a -> IO ()
    writeOutput val = case outputFile opts of
      Nothing  -> putStrLn (encode val)
      Just f   -> writeFile f (encode val) >> putStrLn ("escrito en: " ++ f)

main :: IO ()
main = do
  args <- getArgs
  case parseArgs args of
    Left err -> do
      hPutStrLn stderr ("Error: " ++ err)
      printUsage
      exitFailure
    Right opts
      | junitFile opts == "--help" -> printUsage >> exitSuccess
      | otherwise -> run opts
