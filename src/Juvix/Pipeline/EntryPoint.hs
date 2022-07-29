module Juvix.Pipeline.EntryPoint
  ( module Juvix.Pipeline.EntryPoint,
    module Juvix.Pipeline.Package,
  )
where

import Juvix.Pipeline.Package
import Juvix.Prelude

-- | The head of _entryModulePaths is assumed to be the Main module
data EntryPoint = EntryPoint
  { _entryPointRoot :: FilePath,
    _entryPointNoTermination :: Bool,
    _entryPointNoPositivity :: Bool,
    _entryPointNoStdlib :: Bool,
    _entryPointPackage :: Package,
    _entryPointModulePaths :: NonEmpty FilePath
  }
  deriving stock (Eq, Show)

defaultEntryPoint :: FilePath -> EntryPoint
defaultEntryPoint mainFile =
  EntryPoint
    { _entryPointRoot = ".",
      _entryPointNoTermination = False,
      _entryPointNoPositivity = False,
      _entryPointNoStdlib = False,
      _entryPointPackage = emptyPackage,
      _entryPointModulePaths = pure mainFile
    }

makeLenses ''EntryPoint

mainModulePath :: Lens' EntryPoint FilePath
mainModulePath = entryPointModulePaths . _head
