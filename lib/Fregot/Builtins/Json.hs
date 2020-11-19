{-|
Copyright   : (c) 2020 Fugue, Inc.
License     : Apache License, version 2.0
Maintainer  : jasper@fugue.co
Stability   : experimental
Portability : POSIX

Json-related builtins.
-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Fregot.Builtins.Json
    ( builtins
    ) where

import qualified Data.Aeson               as A
import qualified Data.HashMap.Strict      as HMS
import qualified Data.Text.Encoding       as T
import qualified Data.Text.Lazy.Encoding  as TL
import           Fregot.Builtins.Internal
import qualified Fregot.Eval.Json         as Json
import           Fregot.Names
import           Fregot.Types.Builtins    ((🡒))
import qualified Fregot.Types.Builtins    as Ty
import qualified Fregot.Types.Internal    as Ty

builtins :: Builtins IO
builtins = HMS.fromList
    [ (NamedFunction (QualifiedName "json.is_valid"),  builtin_json_is_valid)
    , (NamedFunction (QualifiedName "json.marshal"),   builtin_json_marshal)
    , (NamedFunction (QualifiedName "json.unmarshal"), builtin_json_unmarshal)
    ]

builtin_json_is_valid :: Monad m => Builtin m
builtin_json_is_valid = Builtin
    (Ty.string 🡒 Ty.out Ty.boolean) $ pure $
    \(Cons str Nil) -> pure $ case A.eitherDecodeStrict' (T.encodeUtf8 str) of
        Left  _              -> False
        Right (_ :: A.Value) -> True

builtin_json_marshal :: Monad m => Builtin m
builtin_json_marshal = Builtin
    (Ty.any 🡒 Ty.out Ty.string) $ pure $
    \(Cons val Nil) -> case Json.fromValue val of
        Left err   -> throwDoc err
        Right json -> return $! TL.decodeUtf8 $! A.encode json

builtin_json_unmarshal :: Monad m => Builtin m
builtin_json_unmarshal = Builtin
    (Ty.string 🡒 Ty.out Ty.unknown) $ pure $
    \(Cons str Nil) -> case A.eitherDecodeStrict' (T.encodeUtf8 str) of
        Left  err -> throwString err
        Right val -> return $! Json.toValue val
