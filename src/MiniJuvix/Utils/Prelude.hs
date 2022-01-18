{-
* This Predude is =Protolude= except with a few changes
  + _Additions_
    * ∨   :: Serves as an or function
    * ∧   :: Serves as an and function
    * |<< :: Serves as a map function
    * >>| :: Serves as the flip map function
  + _Changes_
    * The Capability library is imported and replaces the standard
      =MTL= constructs in =Protolude=
    * We don't import the Semiring typeclass from =Protolude=.
-}

-- | Adapted from heliaxdev/Juvix/library/StandardLibrary/src/Juvix/Library.hs
module MiniJuvix.Utils.Prelude
  ( module MiniJuvix.Utils.Prelude,
    module Data.List.Extra,
    module Control.Monad.Extra,
    module Relude,
  )
where

--------------------------------------------------------------------------------

import Control.Monad.Extra (maybeM)
import qualified Data.Char as Char
import Data.List.Extra (groupSortOn, unsnoc)
import qualified Data.List.NonEmpty as NonEmpty
import Relude hiding
  ( Type,
    one,
  )

--------------------------------------------------------------------------------
-- Logical connectives
--------------------------------------------------------------------------------

(∨) :: Bool -> Bool -> Bool
(∨) = (||)

infixr 2 ∨

(∧) :: Bool -> Bool -> Bool
(∧) = (&&)

infixr 3 ∧

(.||.) :: (a -> Bool) -> (a -> Bool) -> a -> Bool
(f .||. g) x = f x || g x

--------------------------------------------------------------------------------
-- High-level syntax sugar.
--------------------------------------------------------------------------------

-- Lift a map.
(|<<) ::
  forall a b f.
  (Functor f) =>
  (a -> b) ->
  -----------
  f a ->
  f b
(|<<) = fmap

infixr 1 |<<

-- Apply a lifted map.
(>>|) :: forall a b f. (Functor f) => f a -> (a -> b) -> f b
(>>|) = flip fmap

infixl 1 >>|

-- Postfix funciton application.
(|>) :: a -> (a -> b) -> b
(|>) = (&)

infixl 1 |>

--------------------------------------------------------------------------------

traverseM ::
  (Monad m, Traversable m, Applicative f) =>
  (a1 -> f (m a2)) ->
  m a1 ->
  f (m a2)
traverseM f = fmap join . traverse f

--------------------------------------------------------------------------------
-- String related util functions.
--------------------------------------------------------------------------------

toUpperFirst :: String -> String
toUpperFirst [] = []
toUpperFirst (x : xs) = Char.toUpper x : xs

--------------------------------------------------------------------------------
-- Semiring
--------------------------------------------------------------------------------

class Monoid m => Semiring m where
  {-# MINIMAL one, times #-}

  one :: m
  times :: m -> m -> m

--------------------------------------------------------------------------------
-- Maybe
--------------------------------------------------------------------------------

fromMaybeM :: Monad m => m a -> m (Maybe a) -> m a
fromMaybeM n = maybeM n pure

--------------------------------------------------------------------------------
-- NonEmpty
--------------------------------------------------------------------------------

nonEmptyUnsnoc :: NonEmpty a -> (Maybe (NonEmpty a), a)
nonEmptyUnsnoc e = (NonEmpty.nonEmpty (NonEmpty.init e), NonEmpty.last e)

--------------------------------------------------------------------------------
-- Tuple
--------------------------------------------------------------------------------

mapFirst :: (a -> b) -> (a, d) -> (b, d)
mapFirst f (a, b) = (f a, b)
