module Scope.Positive where

import Base
import qualified MiniJuvix.Syntax.Concrete.Scoped.Pretty.Text as M
import qualified MiniJuvix.Syntax.Concrete.Scoped.Scoper as M
import MiniJuvix.Syntax.Concrete.Scoped.Utils
import qualified Data.HashMap.Strict as HashMap


data PosTest = PosTest {
  name :: String,
  relDir :: FilePath,
  file :: FilePath
  }

root :: FilePath
root = "tests/positive"

testDescr :: PosTest -> TestDescr
testDescr PosTest {..} = TestDescr {
  testName = name,
  testRoot = root </> relDir,
  testAssertion = Steps $ \step -> do
    step "Parse"
    p <- parseModuleIO file
    -- do something

    step "Scope"
    -- do something
    s <- scopeModuleIO p
    let
      fs :: HashMap FilePath Text
      fs = HashMap.fromList
         [ (getModuleFilePath m , M.renderPrettyCodeDefault m)
           | m <- toList (getAllModules s) ]

    step "Pretty"
    let txt = M.renderPrettyCodeDefault s

    step "Parse again"
    p' <- parseTextModuleIO txt
    assertEqual "check: parse. pretty . scope . parse = id" p p'

    step "Scope again"
    s' <- fromRightIO' printErrorAnsi $ M.scopeCheck1Pure fs "." p'
    assertEqual "check: scope . parse . pretty . scope . parse = id" s s'
  }

allTests :: TestTree
allTests = testGroup "Scope positive tests"
  (map (mkTest . testDescr) tests)

tests :: [PosTest]
tests = [
  PosTest "Inductive"
     "." "Inductive.mjuvix",
  PosTest "Imports and qualified names"
     "Imports" "A.mjuvix",
  PosTest "Data.List and friends from the stdlib"
     "StdlibList" "Data/List.mjuvix"
 ]
