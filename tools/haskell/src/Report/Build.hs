{-# LANGUAGE OverloadedStrings #-}

module Report.Build
  ( buildReport
  , SuiteReport(..)
  , TagSummary(..)
  , SlowTest(..)
  ) where

import           Data.Aeson (ToJSON(..), object, (.=))
import           Data.List (sortBy, groupBy, sort)
import           Data.Ord (comparing)
import           Data.Maybe (fromMaybe)
import           Data.Text (Text)
import           Data.Time.Clock (NominalDiffTime)
import           Junit.Model (SuiteResult(..), TestResult(..), TestStatus(..), Tag(..), tagText)
import           Junit.Parse (suiteResult, TestSuite)

data TagSummary = TagSummary
  { tagName   :: Text
  , tagTests  :: Int
  , tagPassed :: Int
  , tagFailed :: Int
  } deriving (Show)

instance ToJSON TagSummary where
  toJSON TagSummary{..} = object
    [ "tag"   .= tagName
    , "tests" .= tagTests
    , "passed" .= tagPassed
    , "failed" .= tagFailed
    ]

data SlowTest = SlowTest
  { slowTestName   :: Text
  , slowTestTime   :: NominalDiffTime
  , slowTestTags   :: [Tag]
  } deriving (Show)

instance ToJSON SlowTest where
  toJSON SlowTest{..} = object
    [ "name"       .= slowTestName
    , "time_seconds" .= realToFrac slowTestTime :: Double
    , "tags"       .= slowTestTags
    ]

data SuiteReport = SuiteReport
  { reportName        :: Text
  , reportTests       :: Int
  , reportPassed      :: Int
  , reportFailed      :: Int
  , reportSkipped     :: Int
  , reportTime        :: NominalDiffTime
  , reportTags        :: [TagSummary]
  , reportSlowTests   :: [SlowTest]
  , reportTestsDetails :: [TestResult]
  } deriving (Show)

instance ToJSON SuiteReport where
  toJSON SuiteReport{..} = object
    [ "name"        .= reportName
    , "tests"       .= reportTests
    , "passed"      .= reportPassed
    , "failed"      .= reportFailed
    , "skipped"     .= reportSkipped
    , "time_seconds" .= realToFrac reportTime :: Double
    , "tags"        .= reportTags
    , "slow_tests"  .= reportSlowTests
    , "tests"       .= reportTestsDetails
    ]

buildReport :: [TestSuite] -> Double -> SuiteReport
buildReport suites slowThreshold =
  let results = map suiteResult suites
      totalTests = sum (map suiteTests results)
      totalPassed = sum (map suitePassed results)
      totalFailed = sum (map suiteFailed results)
      totalSkipped = sum (map suiteSkipped results)
      totalTime = sum (map suiteTime results)
      allTests = concat (map suiteTestsDetails results)
      tagSummaries = buildTagSummaries allTests
      slowTests = reverse (sortBy (comparing slowTestTime) (filter (isSlow slowThreshold) allTests))
  in SuiteReport
    { reportName        = "dexflo-run"
    , reportTests       = totalTests
    , reportPassed      = totalPassed
    , reportFailed      = totalFailed
    , reportSkipped     = totalSkipped
    , reportTime        = totalTime
    , reportTags        = tagSummaries
    , reportSlowTests   = slowTests
    , reportTestsDetails = allTests
    }

buildTagSummaries :: [TestResult] -> [TagSummary]
buildTagSummaries tests =
  let tagged = concatMap (\t -> map (\tag -> (tag, t)) (testTags t)) tests
      sorted = sortBy (comparing fst) tagged
      grouped = groupBy (\a b -> fst a == fst b) sorted
      summaries = map (\g ->
        let tag = fst (head g)
            testsOfTag = map snd g
            passed = length (filter (\t -> testStatus t == TestPassed) testsOfTag)
            failed = length (filter (\t -> testStatus t == TestFailed) testsOfTag)
        in TagSummary (tagText tag) (length testsOfTag) passed failed
      ) grouped
  in summaries

isSlow :: Double -> TestResult -> Bool
isSlow threshold t = case testTime t of
  Just tm -> realToFrac tm > threshold
  Nothing -> False
