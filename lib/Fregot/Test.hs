module Fregot.Test
    ( main
    ) where

import           Control.Monad           (forM_)
import           Control.Monad.Parachute
import           Control.Monad.Trans     (liftIO)
import qualified Data.IORef              as IORef
import qualified Fregot.Error            as Error
import qualified Fregot.Interpreter      as Interpreter
import qualified Fregot.Sources          as Sources
import           System.Environment      (getArgs)
import qualified System.IO               as IO

main :: IO ()
main = do
    sources <- Sources.newHandle
    interpreter <- Interpreter.newHandle sources
    (errors, _mbResult) <- runParachuteT $ do
        args <- liftIO getArgs
        forM_ args $ \arg -> Interpreter.loadModule interpreter arg
        rules <- Interpreter.readRules interpreter
        liftIO $ print rules

    sources' <- IORef.readIORef sources
    Error.hPutErrors IO.stderr sources' Error.TextFmt errors
