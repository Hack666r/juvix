module Juvix.Compiler.Pipeline.Repl where

import Juvix.Compiler.Concrete (ignoreHighlightBuilder)
import Juvix.Compiler.Concrete.Language
import Juvix.Compiler.Concrete.Translation.FromParsed qualified as Scoper
import Juvix.Compiler.Concrete.Translation.FromSource qualified as Parser
import Juvix.Compiler.Concrete.Translation.FromSource.ParserResultBuilder (runParserResultBuilder)
import Juvix.Compiler.Concrete.Translation.FromSource.TopModuleNameChecker (runTopModuleNameChecker)
import Juvix.Compiler.Core qualified as Core
import Juvix.Compiler.Core.Transformation qualified as Core
import Juvix.Compiler.Core.Transformation.DisambiguateNames (disambiguateNames)
import Juvix.Compiler.Internal qualified as Internal
import Juvix.Compiler.Internal.Translation.FromInternal.Analysis.Termination.Checker
import Juvix.Compiler.Pipeline.Artifacts
import Juvix.Compiler.Pipeline.Artifacts.PathResolver
import Juvix.Compiler.Pipeline.Driver (evalModuleInfoCache)
import Juvix.Compiler.Pipeline.Driver qualified as Driver
import Juvix.Compiler.Pipeline.EntryPoint
import Juvix.Compiler.Pipeline.Loader.PathResolver (runDependencyResolver)
import Juvix.Compiler.Pipeline.Loader.PathResolver.Base
import Juvix.Compiler.Pipeline.Loader.PathResolver.Error
import Juvix.Compiler.Pipeline.ModuleInfoCache
import Juvix.Compiler.Pipeline.Package.Loader.Error
import Juvix.Compiler.Pipeline.Package.Loader.EvalEff.IO
import Juvix.Compiler.Pipeline.Result
import Juvix.Compiler.Store.Extra qualified as Store
import Juvix.Data.Effect.Git
import Juvix.Data.Effect.Process (runProcessIO)
import Juvix.Data.Effect.TaggedLock
import Juvix.Prelude

upToInternalExpression ::
  (Members '[Reader EntryPoint, Error JuvixError, State Artifacts, Termination] r) =>
  ExpressionAtoms 'Parsed ->
  Sem r Internal.Expression
upToInternalExpression p = do
  scopeTable <- gets (^. artifactScopeTable)
  mtab <- gets (^. artifactModuleTable)
  runBuiltinsArtifacts
    . runScoperScopeArtifacts
    . runStateArtifacts artifactScoperState
    $ runNameIdGenArtifacts (Scoper.scopeCheckExpression (Store.getScopedModuleTable mtab) scopeTable p)
      >>= runNameIdGenArtifacts . runReader scopeTable . Internal.fromConcreteExpression

expressionUpToAtomsParsed ::
  (Members '[State Artifacts, Error JuvixError] r) =>
  Path Abs File ->
  Text ->
  Sem r (ExpressionAtoms 'Parsed)
expressionUpToAtomsParsed fp txt =
  runNameIdGenArtifacts
    . runBuiltinsArtifacts
    $ Parser.expressionFromTextSource fp txt

expressionUpToAtomsScoped ::
  (Members '[Reader EntryPoint, State Artifacts, Error JuvixError] r) =>
  Path Abs File ->
  Text ->
  Sem r (ExpressionAtoms 'Scoped)
expressionUpToAtomsScoped fp txt = do
  scopeTable <- gets (^. artifactScopeTable)
  mtab <- gets (^. artifactModuleTable)
  runBuiltinsArtifacts
    . runScoperScopeArtifacts
    . runStateArtifacts artifactScoperState
    . runNameIdGenArtifacts
    $ Parser.expressionFromTextSource fp txt
      >>= Scoper.scopeCheckExpressionAtoms (Store.getScopedModuleTable mtab) scopeTable

scopeCheckExpression ::
  (Members '[Reader EntryPoint, Error JuvixError, State Artifacts] r) =>
  ExpressionAtoms 'Parsed ->
  Sem r Expression
scopeCheckExpression p = do
  scopeTable <- gets (^. artifactScopeTable)
  mtab <- gets (^. artifactModuleTable)
  runNameIdGenArtifacts
    . runBuiltinsArtifacts
    . runScoperScopeArtifacts
    . runStateArtifacts artifactScoperState
    $ Scoper.scopeCheckExpression (Store.getScopedModuleTable mtab) scopeTable p

parseReplInput ::
  (Members '[PathResolver, Files, State Artifacts, Error JuvixError] r) =>
  Path Abs File ->
  Text ->
  Sem r Parser.ReplInput
parseReplInput fp txt =
  ignoreHighlightBuilder
    . runNameIdGenArtifacts
    . runStateLikeArtifacts runParserResultBuilder artifactParsing
    $ Parser.replInputFromTextSource fp txt

expressionUpToTyped ::
  (Members '[Reader EntryPoint, Error JuvixError, State Artifacts] r) =>
  Path Abs File ->
  Text ->
  Sem r Internal.TypedExpression
expressionUpToTyped fp txt = do
  p <- expressionUpToAtomsParsed fp txt
  runTerminationArtifacts
    ( upToInternalExpression p
        >>= Internal.typeCheckExpressionType
    )

compileExpression ::
  (Members '[Reader EntryPoint, Error JuvixError, State Artifacts] r) =>
  ExpressionAtoms 'Parsed ->
  Sem r Core.Node
compileExpression p =
  runTerminationArtifacts
    ( upToInternalExpression p
        >>= Internal.typeCheckExpression
    )
    >>= fromInternalExpression

registerImport ::
  (Members '[TaggedLock, Error JuvixError, State Artifacts, Reader EntryPoint, Files, GitClone, PathResolver, ModuleInfoCache] r) =>
  Import 'Parsed ->
  Sem r ()
registerImport i = do
  e <- ask
  PipelineResult {..} <- Driver.processImport e i
  let mtab' = Store.insertModule (i ^. importModulePath) _pipelineResult _pipelineResultImports
  modify' (appendArtifactsModuleTable mtab')
  scopeTable <- gets (^. artifactScopeTable)
  mtab'' <- gets (^. artifactModuleTable)
  void
    . runNameIdGenArtifacts
    . runBuiltinsArtifacts
    . runScoperScopeArtifacts
    . runStateArtifacts artifactScoperState
    $ Scoper.scopeCheckImport (Store.getScopedModuleTable mtab'') scopeTable i

fromInternalExpression :: (Members '[State Artifacts] r) => Internal.Expression -> Sem r Core.Node
fromInternalExpression exp = do
  typedTable <- gets (^. artifactInternalTypedTable)
  runNameIdGenArtifacts
    . runReader typedTable
    . tmpCoreInfoTableBuilderArtifacts
    . runFunctionsTableArtifacts
    . readerTypesTableArtifacts
    . runReader Core.initIndexTable
    $ Core.goExpression exp

data ReplPipelineResult
  = ReplPipelineResultNode Core.Node
  | ReplPipelineResultImport TopModulePath
  | ReplPipelineResultOpen Name

compileReplInputIO ::
  (Members '[Reader EntryPoint, State Artifacts, EmbedIO] r) =>
  Path Abs File ->
  Text ->
  Sem r (Either JuvixError ReplPipelineResult)
compileReplInputIO fp txt = do
  hasInternet <- not <$> asks (^. entryPointOffline)
  runError
    . evalInternet hasInternet
    . runTaggedLockPermissive
    . runLogIO
    . runFilesIO
    . mapError (JuvixError @GitProcessError)
    . runProcessIO
    . runGitProcess
    . mapError (JuvixError @DependencyError)
    . mapError (JuvixError @PackageLoaderError)
    . runEvalFileEffIO
    . runDependencyResolver
    . runPathResolverArtifacts
    . runTopModuleNameChecker
    . evalModuleInfoCache
    $ do
      p <- parseReplInput fp txt
      case p of
        Parser.ReplExpression e -> ReplPipelineResultNode <$> compileExpression e
        Parser.ReplImport i -> registerImport i $> ReplPipelineResultImport (i ^. importModulePath)
        Parser.ReplOpenImport i -> return (ReplPipelineResultOpen (i ^. openModuleName))

runTransformations ::
  forall r.
  (Members '[State Artifacts, Error JuvixError, Reader EntryPoint] r) =>
  Bool ->
  [Core.TransformationId] ->
  Core.Node ->
  Sem r Core.Node
runTransformations shouldDisambiguate ts n = runCoreInfoTableBuilderArtifacts $ do
  sym <- addNode n
  applyTransforms shouldDisambiguate ts
  getNode sym
  where
    addNode :: Core.Node -> Sem (Core.InfoTableBuilder ': r) Core.Symbol
    addNode node = do
      sym <- Core.freshSymbol
      Core.registerIdentNode sym node
      -- `n` will get filtered out by the transformations unless it has a
      -- corresponding entry in `infoIdentifiers`
      md <- Core.getModule
      let name = Core.freshIdentName md "_repl"
          idenInfo =
            Core.IdentifierInfo
              { _identifierName = name,
                _identifierSymbol = sym,
                _identifierLocation = Nothing,
                _identifierArgsNum = 0,
                _identifierType = Core.mkDynamic',
                _identifierIsExported = False,
                _identifierBuiltin = Nothing,
                _identifierPragmas = mempty,
                _identifierArgNames = []
              }
      Core.registerIdent name idenInfo
      return sym

    applyTransforms :: Bool -> [Core.TransformationId] -> Sem (Core.InfoTableBuilder ': r) ()
    applyTransforms shouldDisambiguate' ts' = do
      md <- Core.getModule
      md' <- mapReader Core.fromEntryPoint $ Core.applyTransformations ts' md
      let md'' =
            if
                | shouldDisambiguate' -> disambiguateNames md'
                | otherwise -> md'
      Core.setModule md''

    getNode :: Core.Symbol -> Sem (Core.InfoTableBuilder ': r) Core.Node
    getNode sym = fromMaybe impossible . flip Core.lookupIdentifierNode' sym <$> Core.getModule
