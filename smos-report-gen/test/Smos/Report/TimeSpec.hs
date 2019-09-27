{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE OverloadedStrings #-}

module Smos.Report.TimeSpec
  ( spec
  ) where

import Data.Text (Text)

import Test.Hspec
import Test.Validity
import Test.Validity.Aeson

import Text.Megaparsec

import Cursor.Forest.Gen ()

import Smos.Report.Path.Gen ()
import Smos.Report.Time
import Smos.Report.Time.Gen ()

spec :: Spec
spec = do
  eqSpecOnValid @Time
  ordSpecOnValid @Time
  genValidSpec @Time
  jsonSpecOnValid @Time
  describe "timeP" $ parsesValidSpec timeP
  describe "renderTime" $ do
    it "produces valid texts" $ producesValidsOnValids renderTime
    it "renders bys that parse to the same" $ forAllValid $ \s -> parseJust timeP (renderTime s) s

parsesValidSpec :: (Show a, Eq a, Validity a) => P a -> Spec
parsesValidSpec p = it "only parses valid values" $ forAllValid $ parsesValid p

parseJust :: (Show a, Eq a) => P a -> Text -> a -> Expectation
parseJust p s res =
  case parse (p <* eof) "test input" s of
    Left err ->
      expectationFailure $
      unlines ["P failed on input", show s, "with error", errorBundlePretty err]
    Right out -> out `shouldBe` res

parsesValid :: (Show a, Eq a, Validity a) => P a -> Text -> Expectation
parsesValid p s =
  case parse (p <* eof) "test input" s of
    Left _ -> pure ()
    Right out -> shouldBeValid out
