{-# LANGUAGE OverloadedStrings #-}

module Report.Compare
  ( compareReports
  , Comparison(..)
  , SuiteComparison(..)
  ) where

import           Data.Aeson (ToJSON(..), object, (.=))
import           Data.Text (Text)
import           Junit.Model (SuiteResult(..))

data Comparison = Comparison
  { comparisonPrevious :: SuiteComparison
  , comparisonCurrent  :: SuiteComparison
  , comparisonDelta    :: Delta
  } deriving (Show)

instance ToJSON Comparison where
  toJSON Comparison{..} = object
    [ "previous" .= comparisonPrevious
    , "current"  .= comparisonCurrent
    , "delta"    .= comparisonDelta
    ]

data SuiteComparison = SuiteComparison
  { scName        :: Text
  , scTests       :: Int
  , scPassed      :: Int
  , scFailed      :: Int
  , scSkipped     :: Int
  , scTime        :: NominalDiffTime
  } deriving (Show)

instance ToJSON SuiteComparison where
  toJSON SuiteComparison{..} = object
    [ "name"   .= scName
    , "tests"  .= scTests
    , "passed" .= scPassed
    , "failed" .= scFailed
    , "skipped" .= scSkipped
    , "time_seconds" .= realToFrac scTime :: Double
    ]

data Delta = Delta
  { deltaTests   :: Int
  , deltaPassed  :: Int
  , deltaFailed  :: Int
  , deltaSkipped :: Int
  , deltaTime    :: NominalDiffTime
  } deriving (Show)

instance ToJSON Delta where
  toJSON Delta{..} = object
    [ "tests"   .= deltaTests
    , "passed"  .= deltaPassed
    , "failed"  .= deltaFailed
    , "skipped" .= deltaSkipped
    , "time_seconds" .= realToFrac deltaTime :: Double
    ]

compareReports :: SuiteReport -> SuiteReport -> Comparison
compareReports prev curr = Comparison
  { comparisonPrevious = suiteToComparison (reportName curr) prev
  , comparisonCurrent  = suiteToComparison (reportName curr) curr
  , comparisonDelta    = computeDelta prev curr
  }
  where
    suiteToComparison name r = SuiteComparison
      { scName        = name
      , scTests       = reportTests r
      , scPassed      = reportPassed r
      , scFailed      = reportFailed r
      , scSkipped     = reportSkipped r
      , scTime        = reportTime r
      }

    computeDelta p c = Delta
      { deltaTests   = reportTests c - reportTests p
      , deltaPassed  = reportPassed c - reportPassed p
      , deltaFailed  = reportFailed c - reportFailed p
      , deltaSkipped = reportSkipped c - reportSkipped p
      , deltaTime    = reportTime c - reportTime p
      }
