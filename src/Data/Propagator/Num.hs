{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}
module Data.Propagator.Num where

import Control.Monad
import Control.Monad.ST
import Data.Propagator.Cell
import Data.Propagator.Class
import Numeric.Natural
import Numeric.Interval.Internal

class Propagated a => PropagatedNum a where
  cplus :: Cell s a -> Cell s a -> Cell s a -> ST s ()
  default cplus :: Num a => Cell s a -> Cell s a -> Cell s a -> ST s ()
  cplus x y z = do
    lift2 (+) x y z
    lift2 (-) z x y
    lift2 (-) z y x

  ctimes :: Cell s a -> Cell s a -> Cell s a -> ST s ()
  default ctimes :: Num a => Cell s a -> Cell s a -> Cell s a -> ST s ()
  ctimes = lift2 (*)

  cabs :: Cell s a -> Cell s a -> ST s ()
  default cabs :: (Num a, Eq a) => Cell s a -> Cell s a -> ST s ()
  cabs x y = do
    lift1 abs x y
    watch y $ \b -> when (b == 0) $ write x 0

  csignum :: Cell s a -> Cell s a -> ST s ()
  default csignum :: (Num a, Eq a) => Cell s a -> Cell s a -> ST s ()
  csignum x y = do
    lift1 signum x y
    watch y $ \b -> when (b == 0) $ write x 0

instance PropagatedNum Integer where
  ctimes x y z = do
    lift2 (*) x y z
    watch z $ \c -> if c == 0
      then watch x $ \ a -> when (a /= 0) $ write y 0
      else watch y $ \ b -> when (b /= 0) $ write x 0

instance PropagatedNum Natural where
  ctimes x y z = do
    lift2 (*) x y z
    watch z $ \c -> if c == 0
      then watch x $ \ a -> when (a /= 0) $ write y 0
      else watch y $ \ b -> when (b /= 0) $ write x 0
  cabs = unify

instance PropagatedNum Int

instance PropagatedNum Word where
  cabs = unify


ctimesFractional :: (Eq a, Fractional a) => Cell s a -> Cell s a -> Cell s a -> ST s ()
ctimesFractional x y z = do
  watch x $ \a ->
    if a == 0
    then write z 0
    else do
      with y $ \b -> write z (a*b)
      with z $ \c -> write y (c/a) -- a /= 0 determined above
  watch y $ \b ->
    if b == 0
    then write z 0
    else do
      with x $ \a -> write z (a*b)
      with z $ \c -> write x (c/b) -- b /= 0 determined above
  watch z $ \c -> do
    with x $ \a -> when (a /= 0) $ write y (c/a)
    with y $ \b -> when (b /= 0) $ write x (c/b)

instance PropagatedNum Rational where
  ctimes = ctimesFractional

instance PropagatedNum Double where
  ctimes = ctimesFractional

instance PropagatedNum Float where
  ctimes = ctimesFractional

class PropagatedNum a => PropagatedFloating a where
  cexp :: Cell s a -> Cell s a -> ST s ()
  default cexp :: Floating a => Cell s a -> Cell s a -> ST s ()
  cexp x y = do
    lift1 exp x y
    lift1 log y x

  csqrt :: Cell s a -> Cell s a -> ST s ()
  default csqrt :: Floating a => Cell s a -> Cell s a -> ST s ()
  csqrt x y = do
    lift1 sqrt x y
    lift1 (\a -> a*a) y x

  csin :: Cell s a -> Cell s a -> ST s ()
  default csin :: (Floating a, Ord a) => Cell s a -> Cell s a -> ST s ()
  csin x y = do
    lift1 sin x y
    watch y $ \b -> do
       unless (abs b <= 1) $ fail "output of sin not between -1 and 1"
       write x (asin b)

  ccos :: Cell s a -> Cell s a -> ST s ()
  default ccos :: (Floating a, Ord a) => Cell s a -> Cell s a -> ST s ()
  ccos x y = do
    lift1 cos x y
    watch y $ \b -> do
       unless (abs b <= 1) $ fail "output of cos not between -1 and 1"
       write x (acos b)

  ctan :: Cell s a -> Cell s a -> ST s ()
  default ctan :: (Floating a, Ord a) => Cell s a -> Cell s a -> ST s ()
  ctan x y = do
    lift1 tan x y
    watch y $ \b -> do
      unless (abs b <= pi/2) $ fail "output of tan not between -pi/2 and pi/2"
      write x (atan b)

  csinh :: Cell s a -> Cell s a -> ST s ()
  default csinh :: (Floating a, Ord a) => Cell s a -> Cell s a -> ST s ()
  csinh x y = do
    lift1 sinh x y
    lift1 asinh y x

  ccosh :: Cell s a -> Cell s a -> ST s ()
  default ccosh :: (Floating a, Ord a) => Cell s a -> Cell s a -> ST s ()
  ccosh x y = do
    lift1 cosh x y
    watch y $ \b -> do
      unless (b >= 1) $ fail "output of cosh not >= 1"
      lift1 acosh y x

  ctanh :: Cell s a -> Cell s a -> ST s ()
  default ctanh :: (Floating a, Ord a) => Cell s a -> Cell s a -> ST s ()
  ctanh x y = do
    lift1 tanh x y
    watch y $ \b -> do
      unless (abs b <= 1) $ fail "output of tanh not between -1 and 1"
      write x (tanh b)

instance PropagatedFloating Float
instance PropagatedFloating Double

-- Interval arithmetic

class (Floating a, Ord a) => PropagatedInterval a where
  infinity :: a

instance PropagatedInterval Double where
  infinity = 1/0

instance PropagatedInterval Float where
  infinity = 1/0

instance PropagatedInterval a => PropagatedNum (Interval a) where
  ctimes = ctimesFractional

  cabs x y = do
    write y (0...infinity)
    lift1 abs x y
    watch y $ \case
      I _ b -> write x (-b...b)
      Empty -> write x Empty

  csignum x y = do
    write y (-1...1)
    lift1 signum x y
    watch y $ \case
      I a b | a < 1 && b > -1 -> write x $ I (if a <= -1 then -infinity else 0) (if b >= 1 then infinity else 0)
      _ -> write x Empty

instance (PropagatedInterval a, RealFloat a) => PropagatedFloating (Interval a) where
  cexp x y = do
    write y (0...infinity)
    lift1 exp x y
    lift1 log y x

  csqrt x y = do
    write x (0...infinity)
    write y (0...infinity)
    lift1 sqrt x y
    lift1 (\a -> a*a) y x

  csin x y = do
    write y (-1...1)
    lift1 sin x y
    lift1 asin y x

  ccos x y = do
    write y (-1...1)
    lift1 cos x y
    lift1 acos y x

  ctan x y = do
    write y (-pi/2...pi/2)
    lift1 tan x y
    lift1 atan y x

  csinh x y = do
    lift1 sinh x y
    lift1 asinh y x

  ccosh x y = do
    write y (1...infinity)
    lift1 cosh x y
    lift1 acosh y x

  ctanh x y = do
    write y (-1...1)
    lift1 tanh x y
    lift1 atanh y x