{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ExistentialQuantification #-}
import Data.Bits
import System.Random
import Data.Char
import Data.List
import Text.Read
import Numeric (showHex)
import Data.Function

data Player = Alice|Rob deriving (Show, Eq)
(👩) = Alice
(👱) = Rob

data Coin = Heads|Tails deriving (Show, Enum, Eq)

-- Coppied from https://gist.github.com/trevordixon/6788535
expmod :: Integer -> Integer -> Integer -> Integer
expmod _ 0 _ = 1
expmod b e m = t * expmod ((b * b) `mod` m) (shiftR e 1) m `mod` m
  where t = if testBit e 0 then b `mod` m else 1

𝑝 = 0xFFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA237327FFFFFFFFFFFFFFFF
𝑞 = (𝑝 - 1) `div` 2
𝑔 = 2

data Group = ℤ𝑝|ℤ𝑞|𝔾    deriving (Show, Eq)

upperBound :: Group -> Integer
upperBound ℤ𝑝 = 𝑝
upperBound ℤ𝑞 = 𝑞

member :: Group -> Integer -> Bool
member 𝔾 x = (member ℤ𝑝 x) && (expmod x 𝑞 𝑝) == 1
member g x = x >= 0 && x < (upperBound g)

pick :: Group -> IO Integer
pick g = do stdgen <- newStdGen
            return $ fst (randomR (0, (upperBound g)) stdgen)

(⊕) = xor

class MessageValue a where
  gist :: a -> String

instance MessageValue String where
  gist = id

instance MessageValue Integer where
  gist x = "0x" ++ showHex x ""

instance MessageValue Coin where
  gist = show

-- Define a wrapping type for the message values
data MessageWrap = forall a. MessageValue a => MW a

-- Define gist which unwraps the the type
instance MessageValue MessageWrap where
  gist (MW m) = gist m

join = intercalate -- interyawotm8?
(⟹) :: (MessageValue a)  => Player -> [(String, a)] -> IO()
(⟹) sender message =
  let green = "\ESC[32m"
      reset = "\ESC[0m"
      header = ">>>=====" ++ (show sender) ++ " sends====>>>"
      body = (map (\(key,value) -> key ++ ": " ++ (gist value)) message) & (join "\n")
      in do
    putStrLn (green ++ header ++ reset)
    putStrLn body
    putStrLn (green ++ (replicate (length header) '=') ++ reset)


readLine :: IO String
readLine = do line <- getLine
              putStrLn("\ESC[A\r" ++ (replicate 40 'X') ++ (replicate (length(line) - 40) ' '))
              return line

secretPrompt :: (String -> Maybe a) -> IO a
secretPrompt parse = do
  line <- readLine
  case (parse line) of
       Nothing -> putStrLn "Invalid value. Try again." >>
                  secretPrompt parse
       Just x -> return x

chooseMove :: Player -> IO Coin
chooseMove player = do
  putStrLn(show player ++ ", choose an outcome")
  putStrLn( "[H]eads or [T]ails?" )
  secretPrompt (
    \choice ->
      let c = toUpper (head choice) in
        find (\x -> head (show x) == c)  [(Heads), (Tails)]
    )

readMaybeGroup :: Group -> String -> Maybe Integer
readMaybeGroup g string = case (readMaybe string) of
  Just x | member g x -> Just x
  _                   -> Nothing

chooseRandomness_ :: String -> Maybe (IO Integer)
chooseRandomness_ choice =  case choice of
      "H"    -> Just (pick ℤ𝑞)
      string -> case (readMaybeGroup ℤ𝑞 string) of
        Nothing -> Nothing
        Just x  -> Just (return x)

chooseRandomness :: Player -> IO Integer
chooseRandomness player = do
    putStrLn (show player ++ ", behave [H]onestly? or enter your own integer:")
    (secretPrompt chooseRandomness_ >>= id)

commit :: Integer -> Integer
commit 𝑥 | member ℤ𝑞 𝑥 = expmod 𝑔 𝑥 𝑝
         | otherwise = error ( show 𝑥 ++ " isn't a member of ℤ𝑞" )

chooseClaim_ :: Integer -> String -> Maybe Integer
chooseClaim_ hint choice = case choice of
      "H"    -> Just hint
      string -> readMaybeGroup ℤ𝑞 string


claim :: Player -> Integer -> IO Integer
claim player hint = do
  putStrLn (show player ++ ", what do you claim your randomness was?\n([H] to use the true value)")
  secretPrompt (chooseClaim_ hint)

checkResult :: Coin -> Integer -> IO()
checkResult aliceMove randomNumber =
  let odd       = randomNumber `rem` 2
      coinToss = (toEnum (fromIntegral odd)) :: Coin
      result    = aliceMove == coinToss
      in
    putStrLn (
     "============\n" ++
     "The final random number is:\n0x" ++ (showHex randomNumber "\n") ++
     "Which is " ++ (if odd == 1 then "odd" else "even") ++ ". So, the coin-toss resulted in " ++ (show coinToss) ++ "\n" ++
     "Alice chose " ++ (show aliceMove) ++ ", so " ++ (if result then "Alice" else "Rob") ++ " wins!"
    )

main :: IO()
main = do 𝑚 <- chooseMove (👩)
          𝑠ₐ <- chooseRandomness (👩)
          let 𝑐 = commit(𝑠ₐ) in do
            -- Alice sends her commitment and her move in the clear to Rob
            (👩) ⟹ [("move", MW 𝑚), ("commitment", MW 𝑐)]

            -- Rob sends his randomness in the clear to Alice
            𝑠ᵣ <- chooseRandomness (👱)
            (👱) ⟹ [("randomness", 𝑠ᵣ)]

            -- Alice sends her claim to Rob
            𝑠ₐʹ <- (claim (👩) 𝑠ₐ)
            (👩) ⟹ [("randomness", 𝑠ₐʹ)]

            -- Calculate what commitment should be from the claim
            let 𝑐ʹ = commit(𝑠ₐʹ) in
              -- Check they're the same
              if 𝑐ʹ ==  𝑐
              then do
                putStrLn "Alice's claim is the same as her commitment."
                let 𝑠 = 𝑠ₐʹ ⊕ 𝑠ᵣ in
                  checkResult 𝑚 𝑠
               else do
                putStrLn ("Alice's claim: " ++ (gist 𝑐ʹ))
                putStrLn "Alice is lying! Her claim is not the same as her commitment"
                putStrLn "Rob wins by default!"
