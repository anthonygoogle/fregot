{-|
Copyright   : (c) 2020 Fugue, Inc.
License     : Apache License, version 2.0
Maintainer  : jasper@fugue.co
Stability   : experimental
Portability : POSIX
-}
{-# LANGUAGE Rank2Types #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Data.HashMap.Strict.Extended
    ( module Data.HashMap.Strict
    , toHashMapOf
    , shortcuts
    , fromValues
    ) where

import           Control.Arrow       ((&&&))
import           Control.Lens        (IndexedFold, ifoldlOf)
import qualified Data.Binary         as Binary
import           Data.Hashable       (Hashable)
import           Data.HashMap.Strict
import           Prelude             hiding (lookup)

instance (Binary.Binary k, Binary.Binary v, Eq k, Hashable k)
            => Binary.Binary (HashMap k v) where
    put = Binary.put . toList
    get = fromList <$> Binary.get

toHashMapOf :: (Eq k, Hashable k) => IndexedFold k s a -> s -> HashMap k a
toHashMapOf f = ifoldlOf f (\k acc v -> insert k v acc) empty

shortcuts :: (Eq k, Hashable k) => HashMap k k -> HashMap k a -> HashMap k a
shortcuts cuts base = foldlWithKey'
    (\acc from to -> case lookup to acc of
        Just v | Nothing <- lookup from acc -> insert from v acc
        _                                   -> acc)
    base
    cuts

fromValues :: (Eq k, Hashable k) => (v -> k) -> [v] -> HashMap k v
fromValues f = fromList . fmap (f &&& id)
