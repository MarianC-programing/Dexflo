{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Junit.Model
  ( Tag(..)
  , SuiteResult(..)
  , TestResult(..)
  , SlowTest(..)
  , tagText
  ) where

import           Data.Aeson (ToJSON(..), object, (.=), (.=?))
import           Data.Text (Text)
import           Data.Time.Clock (NominalDiffTime)
import           GHC.Generics (Generic)

-- | Etiquetas de Playwright que puede tener un test.
data Tag
  = TagSmoke   -- ^ @smoke
  | TagE2E     -- ^ @e2e
  | TagAPI     -- ^ @api
  | TagWeb3    -- ^ @web3
  | TagOther Text  -- ^ cualquier otra etiqueta
  deriving (Eq, Ord, Show, Generic)

instance ToJSON Tag where
  toJSON tag = case tag of
    TagSmoke   -> String "@smoke"
    TagE2E     -> String "@e2e"
    TagAPI     -> String "@api"
    TagWeb3    -> String "@web3"
    TagOther t -> String t

tagText :: Tag -> Text
tagText tag = case tag of
  TagSmoke   -> "@smoke"
  TagE2E     -> "@e2e"
  TagAPI     -> "@api"
  TagWeb3    -> "@web3"
  TagOther t -> t

-- | Resultado de una suite de tests (un archivo JUnit puede tener varias suites).
data SuiteResult = SuiteResult
  { suiteName   :: Text
  , suiteTests  :: Int
  , suitePassed :: Int
  , suiteFailed :: Int
  , suiteSkipped :: Int
  , suiteTime   :: NominalDiffTime
  , suiteTestsDetails :: [TestResult]
  } deriving (Show, Generic)

instance ToJSON SuiteResult where
  toJSON SuiteResult{..} = object
    [ "name"   .= suiteName
    , "tests"  .= suiteTests
    , "passed" .= suitePassed
    , "failed" .= suiteFailed
    , "skipped" .= suiteSkipped
    , "time_seconds" .= realToFrac suiteTime :: Double
    , "tests_details" .= suiteTestsDetails
    ]

-- | Resultado individual de un test.
data TestResult = TestResult
  { testName     :: Text
  , testStatus   :: TestStatus
  , testTime     :: Maybe NominalDiffTime
  , testTags     :: [Tag]
  , testFile     :: Maybe Text
  , testLine     :: Maybe Int
  } deriving (Show, Generic)

data TestStatus = TestPassed | TestFailed | TestSkipped
  deriving (Eq, Show, Generic)

instance ToJSON TestStatus where
  toJSON TestPassed   = String "passed"
  toJSON TestFailed   = String "failed"
  toJSON TestSkipped  = String "skipped"

instance ToJSON TestResult where
  toJSON TestResult{..} = object
    [ "name"  .= testName
    , "status" .= testStatus
    , "time_seconds" .= fmap realToFrac testTime :: Maybe Double
    , "tags"   .= testTags
    , "file"   .= testFile
    , "line"   .= testLine
    ]

-- | Test considerado "lento" (supera el umbral configurado).
data SlowTest = SlowTest
  { slowTestName   :: Text
  , slowTestTime   :: NominalDiffTime
  , slowTestTags   :: [Tag]
  } deriving (Show, Generic)

instance ToJSON SlowTest where
  toJSON SlowTest{..} = object
    [ "name"  .= slowTestName
    , "time_seconds" .= realToFrac slowTestTime :: Double
    , "tags" .= slowTestTags
    ]
