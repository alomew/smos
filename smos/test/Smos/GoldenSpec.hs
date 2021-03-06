{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}

module Smos.GoldenSpec
  ( spec,
  )
where

import Control.Applicative
import qualified Data.ByteString.Char8 as SB8
import Data.DirForest (DirForest)
import qualified Data.DirForest as DF
import Data.Either
import Data.Function
import Data.Functor.Classes
import Data.List
import qualified Data.Text as T
import Data.Time
import Data.Yaml as Yaml
import Smos
import Smos.App
import Smos.Data
import Smos.Default
import Smos.Types
import TestImport
import UnliftIO.Resource

spec :: Spec
spec = do
  tfs <-
    runIO $ do
      resourcesDir <- resolveDir' "test_resources/golden"
      fs <- snd <$> listDirRecur resourcesDir
      pure $ filter ((== Just ".yaml") . fileExtension) fs
  describe "Preconditions"
    $ specify "all actions have unique names"
    $ let allActionNames = map anyActionName allActions
          grouped = group $ sort allActionNames
       in forM_ grouped $ \case
            [] -> pure () -- impossible, but fine
            [_] -> pure () -- fine
            (an : _) -> expectationFailure $ unwords ["This action name occurred more than once: ", T.unpack (actionNameText an)]
  describe "Golden" $ makeTestcases tfs

data GoldenTestCase
  = GoldenTestCase
      { goldenTestCaseStartingFile :: Path Rel File,
        goldenTestCaseBefore :: DirForest SmosFile,
        goldenTestCaseCommands :: [Command],
        goldenTestCaseAfter :: DirForest SmosFile
      }
  deriving (Show, Generic)

instance Validity GoldenTestCase

instance FromJSON GoldenTestCase where
  parseJSON =
    withObject "GoldenTestCase" $ \o ->
      let defaultFile = [relfile|example.smos|]
          dirForestParser :: Text -> Parser (DirForest SmosFile)
          dirForestParser k =
            ( (o .: k :: Parser (DirForest SmosFile))
                <|> (DF.singletonFile defaultFile <$> (o .: k :: Parser SmosFile))
            )
       in GoldenTestCase
            <$> o .:? "starting-file" .!= defaultFile
            <*> dirForestParser "before"
            <*> o .:? "commands" .!= []
            <*> dirForestParser "after"

makeTestcases :: [Path Abs File] -> Spec
makeTestcases = mapM_ makeTestcase

makeTestcase :: Path Abs File -> Spec
makeTestcase p =
  it (fromAbsFile p) $ do
    gtc@GoldenTestCase {..} <- decodeFileThrow (fromAbsFile p)
    run <- runCommandsOn goldenTestCaseStartingFile goldenTestCaseBefore goldenTestCaseCommands
    shouldBeValid gtc
    expectResults p goldenTestCaseBefore goldenTestCaseAfter run

failure :: String -> IO a
failure s = expectationFailure s >> undefined

data Command where
  CommandPlain :: Action -> Command
  CommandUsing :: Show a => ActionUsing a -> a -> Command

instance Validity Command where
  validate = trivialValidation

instance Show Command where
  show (CommandPlain a) = T.unpack $ actionNameText $ actionName a
  show (CommandUsing au inp) = unwords [T.unpack $ actionNameText $ actionUsingName au, show inp]

instance FromJSON Command where
  parseJSON =
    withText "Command" $ \t ->
      case parseCommand t of
        Left err -> fail err
        Right c -> pure c

parseCommand :: Text -> Either String Command
parseCommand t =
  case T.words t of
    [] -> Left "Should never happen."
    [n] ->
      case filter ((== ActionName n) . actionName) allPlainActions of
        [] -> Left $ unwords ["No action found with name", show n]
        [a] -> pure $ CommandPlain a
        _ -> Left $ unwords ["More than one action found with name", show n]
    [n, arg] ->
      case T.unpack arg of
        [] -> Left "Should never happen."
        [c] ->
          case filter ((== ActionName n) . actionUsingName) allUsingCharActions of
            [] -> Left $ unwords ["No action found with name", show n]
            [a] -> pure $ CommandUsing a c
            _ -> Left $ unwords ["More than one action found with name", show n]
        _ -> Left "Multichar operand"
    _ -> Left "Unable to parse command: more than two words"

data CommandsRun
  = CommandsRun
      { intermidiaryResults :: [(Command, DirForest SmosFile)],
        finalResult :: DirForest SmosFile
      }

runCommandsOn :: Path Rel File -> DirForest SmosFile -> [Command] -> IO CommandsRun
runCommandsOn startingFile start commands =
  withSystemTempDir "smos-golden" $ \tdir -> do
    workflowDir <- resolveDir tdir "workflow"
    let testConf :: SmosConfig
        testConf =
          defaultConfig
            { configReportConfig =
                defaultReportConfig
                  { smosReportConfigDirectoryConfig =
                      defaultDirectoryConfig
                        { directoryConfigWorkflowFileSpec = DirAbsolute workflowDir
                        }
                  }
            }
    DF.write workflowDir start writeSmosFile
    runResourceT $ do
      mErrOrEC <- startEditorCursor $ workflowDir </> startingFile
      case mErrOrEC of
        Nothing -> liftIO $ die "Could not lock pretend file."
        Just errOrEC -> case errOrEC of
          Left err -> liftIO $ die $ "Not a smos file: " <> err
          Right ec -> do
            zt <- liftIO getZonedTime
            let startState =
                  initStateWithCursor zt ec
            (_, rs) <- foldM (go testConf) (startState, []) commands
            finalState <- readWorkflowDir testConf
            pure $
              CommandsRun
                { intermidiaryResults = reverse rs,
                  finalResult = finalState
                }
  where
    readWorkflowDir :: MonadIO m => SmosConfig -> m (DirForest SmosFile)
    readWorkflowDir testConf = liftIO $ do
      workflowDir <- resolveReportWorkflowDir (configReportConfig testConf)
      DF.read workflowDir (fmap (fromRight (error "A smos file was not valid.") . fromJust) . readSmosFile)
    go :: SmosConfig -> (SmosState, [(Command, DirForest SmosFile)]) -> Command -> ResourceT IO (SmosState, [(Command, DirForest SmosFile)])
    go testConf (ss, rs) c = do
      let func = do
            case c of
              CommandPlain a -> actionFunc a
              CommandUsing a arg -> actionUsingFunc a arg
            actionFunc saveFile
      let eventFunc = runSmosM' testConf ss func
      ((s, ss'), _) <- eventFunc
      intermadiateState <- readWorkflowDir testConf
      case s of
        Stop -> liftIO $ failure "Premature stop"
        Continue () ->
          pure
            ( ss',
              (c, intermadiateState)
                : rs
            )

expectResults :: Path Abs File -> DirForest SmosFile -> DirForest SmosFile -> CommandsRun -> IO ()
expectResults p bf af CommandsRun {..} =
  unless (finalResult `dEqForTest` af)
    $ failure
    $ unlines
    $ concat
      [ [ "The expected result did not match the actual result.",
          "The starting situation looked as follows:",
          ppShow bf,
          "The commands to run were these:",
          ppShow $ map fst intermidiaryResults,
          "The result was supposed to look like this:",
          ppShow af,
          "",
          "The intermediary steps built up to the result as follows:",
          ""
        ],
        concatMap (uncurry go) intermidiaryResults,
        [ "The expected result was the following:",
          ppShow af,
          "The actual result was the following:",
          ppShow finalResult
        ],
        [ unwords
            [ "If this was intentional, you can replace the contents of the 'after' part in",
              fromAbsFile p,
              "by the following:"
            ],
          "---[START]---",
          SB8.unpack (Yaml.encode finalResult) <> "---[END]---"
        ]
      ]
  where
    go :: Command -> DirForest SmosFile -> [String]
    go c isf =
      ["After running the following command:", show c, "The situation looked as follows:", ppShow isf]

dEqForTest :: DirForest SmosFile -> DirForest SmosFile -> Bool
dEqForTest = liftEq eqForTest

eqForTest :: SmosFile -> SmosFile -> Bool
eqForTest = forestEqForTest `on` smosFileForest
  where
    forestEqForTest :: Forest Entry -> Forest Entry -> Bool
    forestEqForTest = forestEq1 entryEqForTest
    forestEq1 :: (a -> a -> Bool) -> Forest a -> Forest a -> Bool
    forestEq1 eq = listEq1 (treeEq1 eq)
    treeEq1 :: (a -> a -> Bool) -> Tree a -> Tree a -> Bool
    treeEq1 eq (Node n1 fs1) (Node n2 fs2) = (n1 `eq` n2) && forestEq1 eq fs1 fs2
    listEq1 :: (a -> a -> Bool) -> [a] -> [a] -> Bool
    listEq1 eq as bs = go $ zip (map Just as ++ repeat Nothing) (map Just bs ++ repeat Nothing)
      where
        go [] = True
        go (a : rest) =
          case a of
            (Nothing, Nothing) -> True
            (Just _, Nothing) -> False
            (Nothing, Just _) -> False
            (Just t1, Just t2) -> eq t1 t2 && go rest
    entryEqForTest :: Entry -> Entry -> Bool
    entryEqForTest =
      ((==) `on` entryHeader)
        &&& ((==) `on` entryContents)
        &&& ((==) `on` entryTimestamps)
        &&& ((==) `on` entryProperties)
        &&& (stateHistoryEqForTest `on` entryStateHistory)
        &&& ((==) `on` entryTags)
        &&& (logbookEqForTest `on` entryLogbook)
    stateHistoryEqForTest :: StateHistory -> StateHistory -> Bool
    stateHistoryEqForTest sh1 sh2 =
      listEq1 stateHistoryEntryEqForTest (unStateHistory sh1) (unStateHistory sh2)
    stateHistoryEntryEqForTest :: StateHistoryEntry -> StateHistoryEntry -> Bool
    stateHistoryEntryEqForTest =
      ((==) `on` stateHistoryEntryNewState) &&& (dateTimeEqForTest `on` stateHistoryEntryTimestamp)
    logbookEqForTest :: Logbook -> Logbook -> Bool
    logbookEqForTest lb1 lb2 =
      case (lb1, lb2) of
        (LogOpen ut1 lbes1, LogOpen ut2 lbes2) ->
          dateTimeEqForTest ut1 ut2 && listEq1 logbookEntryEqForTest lbes1 lbes2
        (LogClosed lbes1, LogClosed lbes2) -> listEq1 logbookEntryEqForTest lbes1 lbes2
        (_, _) -> False
    logbookEntryEqForTest :: LogbookEntry -> LogbookEntry -> Bool
    logbookEntryEqForTest (LogbookEntry s1 e1) (LogbookEntry s2 e2) =
      dateTimeEqForTest s1 s2 && dateTimeEqForTest e1 e2
    dateTimeEqForTest :: UTCTime -> UTCTime -> Bool
    dateTimeEqForTest _ _ = True
    (&&&) :: (a -> b -> Bool) -> (a -> b -> Bool) -> (a -> b -> Bool)
    (&&&) f g a b = f a b && g a b
