{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Smos.Web.Server.OptParse.Types where

import Control.Monad.Logger
import Data.Yaml as Yaml
import GHC.Generics (Generic)
import Path
import Servant.Client
import Text.Read
import YamlParse.Applicative

data Arguments
  = Arguments Command Flags
  deriving (Show, Eq)

data Instructions
  = Instructions Dispatch Settings

newtype Command
  = CommandServe ServeFlags
  deriving (Show, Eq)

data ServeFlags
  = ServeFlags
      { serveFlagLogLevel :: !(Maybe LogLevel),
        serveFlagPort :: !(Maybe Int),
        serveFlagDocsUrl :: !(Maybe String),
        serveFlagAPIUrl :: !(Maybe String),
        serveFlagDataDir :: !(Maybe FilePath)
      }
  deriving (Show, Eq)

data Flags
  = Flags
      { flagConfigFile :: !(Maybe FilePath)
      }
  deriving (Show, Eq, Generic)

data Environment
  = Environment
      { envConfigFile :: !(Maybe FilePath),
        envLogLevel :: !(Maybe LogLevel),
        envPort :: !(Maybe Int),
        envDocsUrl :: !(Maybe String),
        envAPIUrl :: !(Maybe String),
        envDataDir :: !(Maybe FilePath)
      }
  deriving (Show, Eq, Generic)

data Configuration
  = Configuration
      { confLogLevel :: !(Maybe LogLevel),
        confPort :: !(Maybe Int),
        confDocsUrl :: !(Maybe String),
        confAPIUrl :: !(Maybe String),
        confDataDir :: !(Maybe FilePath)
      }
  deriving (Show, Eq, Generic)

instance FromJSON Configuration where
  parseJSON = viaYamlSchema

instance YamlSchema Configuration where
  yamlSchema =
    objectParser "Configuration" $
      Configuration
        <$> optionalFieldWith "log-level" "The minimal severity for log messages" (maybeParser parseLogLevel yamlSchema)
        <*> optionalField "port" "The port on which to serve web requests"
        <*> optionalField "docs-url" "The url for the documentation site to refer to"
        <*> optionalField "api-url" "The url for the api to use"
        <*> optionalField "data-dir" "The directory to store workflows during editing"

newtype Dispatch
  = DispatchServe ServeSettings
  deriving (Show, Eq, Generic)

data ServeSettings
  = ServeSettings
      { serveSetLogLevel :: !LogLevel,
        serveSetPort :: !Int,
        serveSetDocsUrl :: !(Maybe BaseUrl),
        serveSetAPIUrl :: !BaseUrl,
        serveSetDataDir :: !(Path Abs Dir)
      }
  deriving (Show, Eq, Generic)

data Settings
  = Settings
  deriving (Show, Eq, Generic)

parseLogLevel :: String -> Maybe LogLevel
parseLogLevel s = readMaybe $ "Level" <> s

renderLogLevel :: LogLevel -> String
renderLogLevel = drop 5 . show
