module Smos.Query.NextSpec (spec) where

import Smos.Query.TestUtils
import Test.Hspec
import Test.Hspec.QuickCheck
import Test.Validity

spec :: Spec
spec = modifyMaxSuccess (`div` 50) -- The first test will be empty, the second will not
  $ describe "Next"
  $ it "'just works' for any InterestingStore"
  $ forAllValid
  $ \is -> testSmosQuery is ["next"]
