{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}

module Smos.Docs.Site.Handler.SmosCalendarImport
  ( getSmosCalendarImportR,
  )
where

import qualified Env
import Options.Applicative
import Options.Applicative.Help
import Smos.Calendar.Import.OptParse as CalendarImport
import Smos.Docs.Site.Handler.Import
import YamlParse.Applicative

getSmosCalendarImportR :: Handler Html
getSmosCalendarImportR = do
  DocPage {..} <- lookupPage "smos-calendar-import"
  let argsHelpText = getHelpPageOf []
      envHelpText = Env.helpDoc CalendarImport.prefixedEnvironmentParser
      confHelpText = prettySchemaDoc @CalendarImport.Configuration
  defaultLayout $ do
    setTitle "Smos Documentation - smos-calendar-import"
    $(widgetFile "args")

getHelpPageOf :: [String] -> String
getHelpPageOf args =
  let res = runArgumentsParser $ args ++ ["--help"]
   in case res of
        Failure fr ->
          let (ph, _, cols) = execFailure fr "smos-calendar-import"
           in renderHelp cols ph
        _ -> error "Something went wrong while calling the option parser."
