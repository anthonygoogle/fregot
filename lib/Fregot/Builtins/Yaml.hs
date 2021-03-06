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
module Fregot.Builtins.Yaml
    ( builtins
    ) where

import qualified Data.Aeson               as Aeson
import qualified Data.ByteString.Lazy     as BL
import qualified Data.HashMap.Strict      as HMS
import qualified Data.Text.Encoding       as T
import qualified Data.Text.Lazy.Encoding  as TL
import           Data.YAML                as Yaml (prettyPosWithSource)
import qualified Data.YAML.Aeson          as Yaml
import           Fregot.Builtins.Internal
import qualified Fregot.Eval.Json         as Json
import           Fregot.Names
import           Fregot.Types.Builtins    ((🡒))
import qualified Fregot.Types.Builtins    as Ty
import qualified Fregot.Types.Internal    as Ty

builtins :: Builtins IO
builtins = HMS.fromList
    [ (NamedFunction (QualifiedName "yaml.is_valid"),  builtin_yaml_is_valid)
    , (NamedFunction (QualifiedName "yaml.marshal"),   builtin_yaml_marshal)
    , (NamedFunction (QualifiedName "yaml.unmarshal"), builtin_yaml_unmarshal)
    ]

builtin_yaml_is_valid :: Monad m => Builtin m
builtin_yaml_is_valid = Builtin
    (Ty.string 🡒 Ty.out Ty.boolean) $ pure $
    \(Cons str Nil) ->
        let bl = BL.fromStrict $ T.encodeUtf8 str in
        pure $ case Yaml.decode1 bl of
            Left  _                  -> False
            Right (_ :: Aeson.Value) -> True

builtin_yaml_marshal :: Monad m => Builtin m
builtin_yaml_marshal = Builtin
    (Ty.any 🡒 Ty.out Ty.string) $ pure $
    \(Cons val Nil) -> case Json.fromValue val of
        Left err   -> throwDoc err
        Right yaml -> return $! TL.decodeUtf8 $! Yaml.encode1 yaml

builtin_yaml_unmarshal :: Monad m => Builtin m
builtin_yaml_unmarshal = Builtin
    (Ty.string 🡒 Ty.out Ty.unknown) $ pure $
    \(Cons str Nil) ->
        let bl = BL.fromStrict $ T.encodeUtf8 str in
        case Yaml.decode1 bl of
            Left (pos, err) -> throwString $ Yaml.prettyPosWithSource pos bl err
            Right val       -> return $! Json.toValue val
