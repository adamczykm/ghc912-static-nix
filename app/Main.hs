{-# LANGUAGE OverloadedStrings #-}

module Main where

import qualified Data.ByteString.Lazy.Char8 as B
import Data.Aeson (object, (.=), encode)
import System.IO

main :: IO ()
main = do
    hSetBuffering stdout LineBuffering
    input <- B.getContents
    let msg = object
          [ "message" .= ("Hello from statically linked Haskell!" :: String)
          , "input"   .= B.unpack input
          ]
    B.putStrLn (encode msg)
