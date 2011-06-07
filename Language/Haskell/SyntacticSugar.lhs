> {-# LANGUAGE TemplateHaskell #-}

> module Language.Haskell.SyntacticSugar (codo, bido) where

> import Text.ParserCombinators.Parsec
> import Language.Haskell.SyntacticSugar.Parse
> import Language.Haskell.TH 
> import Language.Haskell.TH.Quote
> import Language.Haskell.SyntaxTrees.ExtsToTH
> import Data.Generics

> free var = varE $ mkName var

> interpretBlock :: Parser Block -> (Block -> Maybe (Q Exp)) -> String -> Q Exp
> interpretBlock parse interpret input = 
>                        do loc <- location
>                           let pos = (loc_filename loc,
>                                      fst (loc_start loc), 
>                                      snd (loc_start loc))
>                           expr <- (parseExpr parse) pos input
>                           dataToExpQ (const Nothing `extQ` interpret) expr

> pair :: (a -> b, a -> c) -> a -> (b, c)
> pair (f, g) = \x -> (f x, g x)

> codo :: QuasiQuoter
> codo = QuasiQuoter { quoteExp = interpretBlock parseBlock interpretCoDo,
>                      quotePat = (\_ -> wildP) --,
>                       -- quoteType = undefined,
>                       -- quoteDec = undefined
>                     }

> mkProjBind :: String -> ExpQ -> DecQ
> mkProjBind "_" prj = valD wildP (normalB ([| $(free "cmap") $(prj) $(free "gamma") |])) []
> mkProjBind var prj = valD (varP $ mkName var) (normalB ([| $(free "cmap") $(prj) $(free "gamma") |])) []

> projs :: [String] -> [DecQ]
> projs x = projs' x [| id |]

> projs' :: [String] -> ExpQ -> [DecQ]
> projs' [] _ = []
> projs' [x] l = [valD (varP $ mkName x) (normalB [| $(free "gamma") |]) []]
> projs' [x, y] l = [mkProjBind x [| fst . $(l) |], mkProjBind y [| snd . $(l) |]]
> projs' (x:xs) l = (mkProjBind x [| fst . $(l) |]):(projs' xs [| $(l) . snd |])

> replaceToWild :: [Variable] -> Variable -> [Variable]
> replaceToWild [] _ = []
> replaceToWild (x:xs) y = (if (x==y) then "_" else x):(replaceToWild xs y)

> interpretCoDo :: Block -> Maybe (Q Exp)
> interpretCoDo (Block var binds) =
>     do inner <- interpretCobinds binds [var]
>        Just $ lamE [varP $ mkName var] (appE inner (varE $ mkName var))
> interpretCobinds :: Binds -> [Variable] -> Maybe (Q Exp)
> interpretCobinds (EndExpr exp) binders =
>      case parseToTH exp of
>             Left x -> error x
>             Right exp' -> Just $ (lamE [varP $ mkName "gamma"] (letE (projs binders) (return exp')))
> interpretCobinds (LetBind var exp binds) binders =
>     case parseToTH exp of
>             Left x -> error x
>             Right exp' -> 
>                do let binders' = replaceToWild binders var
>                   let morph = lamE [varP $ mkName "gamma"] (letE (projs binders) (return exp'))
>                   inner <- (interpretCobinds binds binders')
>                   return $ [| $(lamE [varP $ mkName var] inner) $(return exp') |]
> interpretCobinds (WildBind exp binds) binders =
>      case parseToTH exp of
>             Left x -> error x
>             Right exp' ->
>                 do 
>                   let binders' = (head binders):(replaceToWild binders (head binders))
>                   let coKleisli = lamE [varP $ mkName "gamma"] (letE (projs binders) (return exp'))
>                   inner <- (interpretCobinds binds binders')
>                   return [| $(inner) . ($(free "cobind") (pair ($(coKleisli), $(free "coreturn")))) |]
> interpretCobinds (Bind var exp binds) binders = 
>      case parseToTH exp of
>         Left x -> error x
>         Right exp' ->
>             do 
>                let binders' = var:(replaceToWild binders (head binders))
>                let coKleisli = lamE [varP $ mkName "gamma"] (letE (projs binders) (return exp'))
>                inner <- (interpretCobinds binds binders')
>                return [| $(inner) . ($(free "cobind") (pair ($(coKleisli), $(free "coreturn")))) |]


> -- Infix >>=

> bind :: Monad m => (a -> m b) -> m a -> m b
> bind = flip (>>=)

> -- All monads in Haskell are strong

> mstrength :: Monad m => (a, m b) -> m (a, b)
> mstrength (a, mb) = mb >>= (\b -> return (a, b))

> mstrength' :: Monad m => (m a, b) -> m (a, b)
> mstrength' (ma, b) = ma >>= (\a -> return (a, b))

> bido :: QuasiQuoter
> bido = QuasiQuoter { quoteExp = interpretBlock parseBlock interpretBiDo,
>                      quotePat = (\_ -> wildP) --,
>                       -- quoteType = undefined,
>                       -- quoteDec = undefined
>                     }

> interpretBiDo :: Block -> Maybe (Q Exp)
> interpretBiDo (Block var binds) = 
>     do inner <- interpretBiBinds binds [var]
>        Just $ lamE [varP $ mkName var] [| $(inner) $(free var) |]


> interpretBiBinds :: Binds -> [Variable] -> Maybe (Q Exp)
> interpretBiBinds (EndExpr exp) binders =
>     case parseToTH exp of
>        Left x -> error x
>        Right exp' ->
>             return $ lamE [varP $ mkName "gamma"] (letE (projs binders) (return exp'))

> interpretBiBinds (Bind var exp binds) binders =
>     case parseToTH exp of
>        Left x -> error x
>        Right exp' ->
>             do let binders' = var:binders
>                let biKleisli = lamE [varP $ mkName "gamma"] (letE (projs binders) (return exp'))
>                inner <- (interpretBiBinds binds binders')
>                return [|  ($(free "bind") $(inner)) .
>                           ($(free "dist")) .
>                           ($(free "cobind") ($(free "mstrength'") .
>                                             (pair ($(biKleisli), $(free "coreturn"))))) |]


 -- Alternatively we could use biextension

 bibind, biextend :: (Comonad c, Monad m, Dist c m) => (c a -> m b) -> m (c a) -> m (c b)
 bibind f = bind (dist . (cobind f))
 biextend = bibind


 interpretBiDo :: Block -> Maybe (Q Exp)
 interpretBiDo (Block var binds) = 
     do inner <- interpretBiBinds binds [var]
        Just $ lamE [varP $ mkName var] [| $(inner) $(free var) |]


 interpretBiBinds :: Binds -> [Variable] -> Maybe (Q Exp)
 interpretBiBinds (EndExpr exp) binders =
     case parseToTH exp of
        Left x -> error x
        Right exp' ->
             return $ lamE [varP $ mkName "gamma"] (letE (projs binders) (return exp'))

 interpretBiBinds (Bind var exp binds) binders =
     case parseToTH exp of
        Left x -> error x
        Right exp' ->
             do let binders' = var:binders
                let biKleisli = lamE [varP $ mkName "gamma"] (letE (projs binders) (return exp'))
                inner <- (interpretBiBinds binds binders')
                return [|  ($(free "fmap") $(free "coreturn")) .
                           ($(free "bibind") $(inner)) .
                           ($(free "bibind") ($(free "mstrength'") .
                                             (pair ($(biKleisli), $(free "coreturn"))))) .
                           ($(free "return")) |]

