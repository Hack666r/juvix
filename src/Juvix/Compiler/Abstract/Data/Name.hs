module Juvix.Compiler.Abstract.Data.Name
  ( module Juvix.Compiler.Abstract.Data.Name,
    module Juvix.Data.NameKind,
    module Juvix.Data.NameId,
    module Juvix.Data.Fixity,
  )
where

import Juvix.Data.Fixity
import Juvix.Data.NameId
import Juvix.Data.NameKind
import Juvix.Prelude
import Juvix.Prelude.Pretty

data Name = Name
  { _nameText :: Text,
    _nameId :: NameId,
    _nameKind :: NameKind,
    _namePretty :: Text, -- How to print this name in error messages
    _nameLoc :: Interval
  }
  deriving stock (Show)

makeLenses ''Name

instance HasAtomicity Name where
  atomicity = const Atom

instance HasLoc Name where
  getLoc = (^. nameLoc)

instance Eq Name where
  (==) = (==) `on` (^. nameId)

instance Ord Name where
  compare = compare `on` (^. nameId)

instance Hashable Name where
  hashWithSalt salt = hashWithSalt salt . (^. nameId)

instance HasNameKind Name where
  getNameKind = (^. nameKind)

instance Pretty Name where
  pretty n =
    pretty (n ^. namePretty)
      <> "@"
      <> pretty (n ^. nameId)

addNameIdTag :: Bool -> NameId -> Doc a -> Doc a
addNameIdTag showNameId nid
  | showNameId = (<> ("@" <> pretty nid))
  | otherwise = id

prettyName :: HasNameKindAnn a => Bool -> Name -> Doc a
prettyName showNameId n =
  annotate
    (annNameKind (n ^. nameKind))
    (addNameIdTag showNameId (n ^. nameId) (pretty (n ^. namePretty)))

type FunctionName = Name

type ConstructorName = Name

type AxiomName = Name

type VarName = Name

type ConstrName = Name

type InductiveName = Name
