{-# LANGUAGE OverloadedStrings #-}

module Junit.Parse
  ( parseJUnitFile
  , JUnit(..)
  , TestSuite(..)
  , TestCase(..)
  , suiteResult
  ) where

import           Data.Text (Text, pack, unpack, isInfixOf, words, stripPrefix, breakOn)
import           Data.Text.IO (readFile)
import           Data.Maybe (mapMaybe, fromMaybe, listToMaybe)
import           Data.Time.Clock (NominalDiffTime, secondsToDiffTime)
import           Text.XML (Document, parseLBS_, def)
import           Text.XML.Cursor (Cursor, ($//), element, attribute, fromDocument, attributeName)
import qualified Text.XML.Cursor as CU
import           Junit.Model (Tag(..), SuiteResult(..), TestResult(..), TestStatus(..))

data JUnit = JUnit
  { junitSuites :: [TestSuite]
  } deriving (Show)

data TestSuite = TestSuite
  { tsName    :: Text
  , tsTests   :: Int
  , tsPassed  :: Int
  , tsFailed  :: Int
  , tsSkipped :: Int
  , tsTime    :: NominalDiffTime
  , tsCases   :: [TestCase]
  } deriving (Show)

data TestCase = TestCase
  { tcName   :: Text
  , tcStatus :: TestStatus
  , tcTime   :: Maybe NominalDiffTime
  , tcTags   :: [Tag]
  , tcFile   :: Maybe Text
  , tcLine   :: Maybe Int
  } deriving (Show)

parseJUnitFile :: FilePath -> IO JUnit
parseJUnitFile path = do
  doc <- parseLBS_ def <$> readFile path
  let cursor = fromDocument doc
      suites = cursor $// element "testsuite" &| parseSuite
  return (JUnit suites)

parseSuite :: Cursor -> TestSuite
parseSuite cu = TestSuite
  { tsName    = fromMaybe "" (attribute "name" cu)
  , tsTests   = readMaybe (attribute "tests" cu)
  , tsPassed  = 0
  , tsFailed  = 0
  , tsSkipped = 0
  , tsTime    = readMaybeDiffTime (attribute "time" cu)
  , tsCases   = map parseTestCase (cu $// element "testcase")
  }
  where
    readMaybe s = case reads (unpack s) of [(v,"")] -> v; _ -> 0
    readMaybeDiffTime s = case reads (unpack s) of [(v,"")] -> secondsToDiffTime (round v :: Integer); _ -> 0

parseTestCase :: Cursor -> TestCase
parseTestCase cu = TestCase
  { tcName   = fromMaybe "" (attribute "name" cu)
  , tcStatus = case attribute "status" cu of
                 Just "failed" -> TestFailed
                 Just "skipped" -> TestSkipped
                 _             -> TestPassed
  , tcTime   = readMaybeTime (attribute "time" cu)
  , tcTags   = extractTags cu
  , tcFile   = attribute "file" cu
  , tcLine   = readMaybe <$> attribute "line" cu
  }
  where
    readMaybeTime s = case reads (unpack s) of [(v,"")] -> Just (secondsToDiffTime (round v :: Integer)); _ -> Nothing

extractTags :: Cursor -> [Tag]
extractTags cu =
  let nameAttr = attribute "name" cu
      nameTags = extractTagsFromText (fromMaybe "" nameAttr)
      attrTags = case attribute "tags" cu of
                   Just t -> parseTagList t
                   Nothing -> []
  in nameTags ++ attrTags

extractTagsFromText :: Text -> [Tag]
extractTagsFromText txt = mapMaybe parseTag (words txt)
  where
    parseTag w
      | "@smoke" `isInfixOf` w = Just TagSmoke
      | "@e2e"   `isInfixOf` w = Just TagE2E
      | "@api"   `isInfixOf` w = Just TagAPI
      | "@web3"  `isInfixOf` w = Just TagWeb3
      | otherwise              = Nothing

parseTagList :: Text -> [Tag]
parseTagList t = case stripPrefix "[" t of
  Just rest -> case breakOn "]" rest of
    (tagPart, _) -> mapMaybe parseTag (words tagPart)
  Nothing -> mapMaybe parseTag (words t)

suiteResult :: TestSuite -> SuiteResult
suiteResult ts@TestSuite{..} = SuiteResult
  { suiteName   = tsName
  , suiteTests  = tsTests
  , suitePassed = length (filter isPassed tsCases)
  , suiteFailed = length (filter isFailed tsCases)
  , suiteSkipped = length (filter isSkipped tsCases)
  , suiteTime   = tsTime
  , suiteTestsDetails = map testCaseToResult tsCases
  }
  where
    isPassed tc = tcStatus tc == TestPassed
    isFailed tc = tcStatus tc == TestFailed
    isSkipped tc = tcStatus tc == TestSkipped

testCaseToResult :: TestCase -> TestResult
testCaseToResult tc = TestResult
  { testName     = tcName tc
  , testStatus   = tcStatus tc
  , testTime     = tcTime tc
  , testTags     = tcTags tc
  , testFile     = tcFile tc
  , testLine     = tcLine tc
  }

attribute :: Text -> Cursor -> Maybe Text
attribute name cu = listToMaybe (CU.attribute (attributeName name) cu)
