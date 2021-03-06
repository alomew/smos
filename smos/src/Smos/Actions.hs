{-# LANGUAGE OverloadedStrings #-}

module Smos.Actions
  ( Action (..),
    ActionUsing (..),
    AnyAction (..),
    module Smos.Actions,
    module Smos.Actions.Browser,
    module Smos.Actions.Convenience,
    module Smos.Actions.Entry,
    module Smos.Actions.Entry.Contents,
    module Smos.Actions.Entry.Header,
    module Smos.Actions.Entry.Logbook,
    module Smos.Actions.Entry.Properties,
    module Smos.Actions.Entry.Tags,
    module Smos.Actions.Entry.Timestamps,
    module Smos.Actions.File,
    module Smos.Actions.Forest,
    module Smos.Actions.Help,
    module Smos.Actions.Report,
    module Smos.Actions.Undo,
    module Smos.Actions.Utils,
  )
where

import Smos.Actions.Browser
import Smos.Actions.Convenience
import Smos.Actions.Entry
import Smos.Actions.Entry.Contents
import Smos.Actions.Entry.Header
import Smos.Actions.Entry.Logbook
import Smos.Actions.Entry.Properties
import Smos.Actions.Entry.Tags
import Smos.Actions.Entry.Timestamps
import Smos.Actions.File
import Smos.Actions.Forest
import Smos.Actions.Help
import Smos.Actions.Report
import Smos.Actions.Undo
import Smos.Actions.Utils
import Smos.Types

allActions :: [AnyAction]
allActions = map PlainAction allPlainActions ++ map UsingCharAction allUsingCharActions

allPlainActions :: [Action]
allPlainActions =
  concat
    [ [ startEntryFromEmptyAndSelectHeader,
        selectHelp,
        selectEditor,
        saveFile,
        stop
      ],
      allContentsPlainActions,
      allEntryPlainActions,
      allForestPlainActions,
      allHeaderPlainActions,
      allLogbookPlainActions,
      allTagsPlainActions,
      allPropertiesPlainActions,
      allTimestampsPlainActions,
      allUndoPlainActions,
      allConveniencePlainActions,
      allPlainBrowserActions,
      allHelpPlainActions,
      allPlainReportNextActions
    ]

allUsingCharActions :: [ActionUsing Char]
allUsingCharActions =
  concat
    [ allContentsUsingCharActions,
      allEntryUsingCharActions,
      allForestUsingCharActions,
      allHeaderUsingCharActions,
      allTimestampsUsingCharActions,
      allTagsUsingCharActions,
      allPropertiesUsingCharActions,
      allUndoUsingCharActions,
      allBrowserUsingCharActions,
      allHelpUsingCharActions,
      allReportNextActionsUsingActions
    ]

startEntryFromEmptyAndSelectHeader :: Action
startEntryFromEmptyAndSelectHeader =
  Action
    { actionName = "startEntryFromEmptyAndSelectHeader",
      actionFunc = modifyEmptyFile startSmosFile,
      actionDescription = "Start a first entry in an empty Smos File and select its header"
    }

selectHelp :: Action
selectHelp =
  Action
    { actionName = "selectHelp",
      actionFunc = modifyEditorCursorS $ \ec -> do
        km <- asks configKeyMap
        pure $ editorCursorSwitchToHelp km ec,
      actionDescription = "Show the (contextual) help screen"
    }

selectEditor :: Action
selectEditor =
  Action
    { actionName = "selectEditor",
      actionFunc = do
        ec <- gets smosStateCursor
        case editorCursorFileCursor ec of
          Just _ -> modifyEditorCursor $ editorCursorSelect FileSelected
          Nothing -> switchToFile (editorCursorLastOpenedFile ec),
      actionDescription = "Hide the help screen"
    }
