{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
module Fregot.Prepare
    ( prepareRule
    , mergeRules

    , prepareExpr
    ) where


import           Control.Applicative       ((<|>))
import           Control.Lens              (view, (%~), (&), (^.))
import           Control.Monad.Extended    (foldM, unless, when)
import           Control.Monad.Parachute   (ParachuteT, tellError)
import           Data.Maybe                (isJust, isNothing, mapMaybe)
import           Fregot.Error              (Error)
import qualified Fregot.Error              as Error
import           Fregot.Prepare.AST
import           Fregot.PrettyPrint        ((<+>))
import           Fregot.Sources.SourceSpan (SourceSpan)
import qualified Fregot.Sugar              as Sugar
import           Prelude                   hiding (head)

-- | Create a new compiled rule from a sugared rule.
prepareRule
    :: Monad m
    => [Sugar.Import SourceSpan] -> Sugar.Rule SourceSpan
    -> ParachuteT Error m (Rule SourceSpan)
prepareRule imports rule
    | head ^. Sugar.ruleDefault = do
        -- NOTE(jaspervdj): Perform sanity checks on default rules.
        when (isJust $ head ^. Sugar.ruleIndex) $ tellError $ Error.mkError
            "compile"
            (head ^. Sugar.ruleAnn)
            "bad default"
            "Default rule should not have an index associated with it."

        unless (null $ rule ^. Sugar.ruleBody) $ tellError $ Error.mkError
            "compile"
            (head ^. Sugar.ruleAnn)
            "bad default"
            "Default rule should not have a body."

        -- TODO(jaspervdj): About the default term, they write:
        --
        --     The term may be any scalar, composite, or comprehension value but
        --     it may not be a variable or reference. If the value is a
        --     composite then it may not contain variables or references.
        def <- traverse prepareTerm (head ^. Sugar.ruleValue)
        pure Rule
            { _ruleName    = head ^. Sugar.ruleName
            , _ruleAnn     = head ^. Sugar.ruleAnn
            , _ruleDefault = def
            , _ruleKind    = CompleteRule
            , _ruleDefs    = []
            }

    | not (null (head ^. Sugar.ruleArgs)) = do
        -- It's a function.
        unless (isNothing $ head ^. Sugar.ruleIndex) $ tellError $ Error.mkError
            "compile"
            (head ^. Sugar.ruleAnn)
            "invalid function" $
            "Rule should have function arguments, " <>
            "or regular arguments, but not both."

        body  <- prepareRuleBody (rule ^. Sugar.ruleBody)
        args  <- traverse (traverse prepareTerm) (head ^. Sugar.ruleArgs)
        index <- traverse prepareTerm (head ^. Sugar.ruleIndex)
        value <- traverse prepareTerm (head ^. Sugar.ruleValue)
        pure Rule
            { _ruleName    = head ^. Sugar.ruleName
            , _ruleAnn     = head ^. Sugar.ruleAnn
            , _ruleDefault = Nothing
            , _ruleKind    = FunctionRule
            , _ruleDefs    =
                [ RuleDefinition
                    { _ruleDefName    = head ^. Sugar.ruleName
                    , _ruleDefImports = imports
                    , _ruleDefAnn     = head ^. Sugar.ruleAnn
                    , _ruleArgs       = args
                    , _ruleIndex      = index
                    , _ruleValue      = value
                    , _ruleBody       = body
                    }
                ]
            }

    | otherwise = do
        let kind
                | Nothing <- head ^. Sugar.ruleIndex = CompleteRule
                | Nothing <- head ^. Sugar.ruleValue = GenSetRule
                | otherwise                          = GenObjectRule

        -- NOTE(jaspervdj): Perform sanity checks on rules.
        body  <- prepareRuleBody (rule ^. Sugar.ruleBody)
        args  <- traverse (traverse prepareTerm) (head ^. Sugar.ruleArgs)
        index <- traverse prepareTerm (head ^. Sugar.ruleIndex)
        value <- traverse prepareTerm (head ^. Sugar.ruleValue)
        pure Rule
            { _ruleName    = head ^. Sugar.ruleName
            , _ruleAnn     = head ^. Sugar.ruleAnn
            , _ruleDefault = Nothing
            , _ruleKind    = kind
            , _ruleDefs    =
                [ RuleDefinition
                    { _ruleDefName    = head ^. Sugar.ruleName
                    , _ruleDefImports = imports
                    , _ruleDefAnn     = head ^. Sugar.ruleAnn
                    , _ruleArgs       = args
                    , _ruleIndex      = index
                    , _ruleValue      = value
                    , _ruleBody       = body
                    }
                ]
            }
  where
    head = rule ^. Sugar.ruleHead

-- | Merge two rules that have the same name.  This can go wrong in all sorts of
-- ways.
mergeRules
    :: Monad m
    => Rule SourceSpan -> Rule SourceSpan
    -> ParachuteT Error m (Rule SourceSpan)
mergeRules x y = do
    let defaults = mapMaybe (view ruleDefault) [x, y]
    when (length defaults > 1) $ tellError $ Error.mkMultiError
        "compile" "conflicting default"
        [ (def ^. termAnn, "default defined here")
        | def <- defaults
        ]

    when (x ^. ruleKind /= y ^. ruleKind) $ tellError $
        Error.mkMultiError
            "compile" "complete definition mismatch"
            [ (c ^. ruleAnn, describeKind (c ^. ruleKind))
            | c <- [x, y]
            ]

    -- Merge y into x
    return $! x
        & ruleDefault %~ (<|> y ^. ruleDefault)
        & ruleDefs    %~ (++ y ^. ruleDefs)

  where
    describeKind = \case
        CompleteRule  -> "is a complete rule"
        GenSetRule    -> "generates a set"
        GenObjectRule -> "generates an object"
        FunctionRule  -> "is a function"

--------------------------------------------------------------------------------

prepareRuleBody
    :: Monad m
    => Sugar.RuleBody SourceSpan
    -> ParachuteT Error m (RuleBody SourceSpan)
prepareRuleBody = mapM prepareLiteral

prepareLiteral
    :: Monad m
    => Sugar.Literal SourceSpan
    -> ParachuteT Error m (Literal SourceSpan)
prepareLiteral slit = do
    statement <- case slit ^. Sugar.literalExpr of
        Sugar.BinOpE ann x Sugar.UnifyO y ->
            UnifyS ann <$> prepareExpr x <*> prepareExpr y
        Sugar.BinOpE ann (Sugar.TermE _ (Sugar.VarT _ v)) Sugar.AssignO y ->
            AssignS ann v <$> prepareExpr y
        expr -> ExprS <$> prepareExpr expr

    pure Literal
        { _literalNegation  = slit ^. Sugar.literalNegation
        , _literalStatement = statement
        , _literalWith      = slit ^. Sugar.literalWith
        }

prepareExpr
    :: Monad m
    => Sugar.Expr SourceSpan
    -> ParachuteT Error m (Expr SourceSpan)
prepareExpr = \case
    Sugar.TermE source t -> TermE source <$> prepareTerm t
    Sugar.BinOpE source x o y -> BinOpE source
        <$> prepareExpr x
        <*> prepareBinOp source o
        <*> prepareExpr y
    Sugar.ParensE _source e -> prepareExpr e

prepareTerm
    :: Monad m
    => Sugar.Term SourceSpan
    -> ParachuteT Error m (Term SourceSpan)
prepareTerm = \case
    Sugar.RefT source varSource var0 refs -> foldM
        (\acc refArg -> case refArg of
            Sugar.RefDotArg ann (Var v) -> return $
                RefT source acc (ScalarT ann (Sugar.String v))
            Sugar.RefBrackArg k -> do
                k' <- prepareTerm k
                return $ RefT source acc k')
        (VarT varSource var0)
        refs

    Sugar.CallT source vars args ->
        CallT source vars <$> traverse prepareTerm args
    Sugar.VarT source v -> pure $ VarT source v
    Sugar.ScalarT source s -> pure $ ScalarT source s

    Sugar.ArrayT source a -> ArrayT source <$> traverse prepareExpr a
    Sugar.SetT source a -> SetT source <$> traverse prepareExpr a
    Sugar.ObjectT source o -> ObjectT source <$> traverse prepareObjectItem o

    Sugar.ArrayCompT ann h b ->
        ArrayCompT ann <$> prepareTerm h <*> prepareRuleBody b
    Sugar.SetCompT ann h b ->
        SetCompT ann <$> prepareTerm h <*> prepareRuleBody b
    Sugar.ObjectCompT ann k h b -> ObjectCompT ann
        <$> prepareObjectKey k
        <*> prepareTerm h
        <*> prepareRuleBody b

prepareRef
    :: Monad m
    => SourceSpan -> SourceSpan -> Var -> [Sugar.RefArg SourceSpan]
    -> ParachuteT Error m (Term SourceSpan)
prepareRef source varSource var0 refs = foldM
    (\acc refArg -> case refArg of
        Sugar.RefDotArg ann (Var v) -> return $
            RefT source acc (ScalarT ann (Sugar.String v))
        Sugar.RefBrackArg k -> do
            k' <- prepareTerm k
            return $ RefT source acc k')
    (VarT varSource var0)
    refs

prepareObjectItem
    :: Monad m
    => (Sugar.ObjectKey SourceSpan, Sugar.Expr SourceSpan)
    -> ParachuteT Error m (Term SourceSpan, Expr SourceSpan)
prepareObjectItem (k, e) = (,) <$> prepareObjectKey k <*> prepareExpr e

prepareObjectKey
    :: Monad m
    => Sugar.ObjectKey SourceSpan
    -> ParachuteT Error m (Term SourceSpan)
prepareObjectKey = \case
    Sugar.ScalarK ann s      -> return $! ScalarT ann s
    Sugar.VarK    ann v      -> return $! VarT ann v
    Sugar.RefK    ann v args -> prepareRef ann ann v args

prepareBinOp
    :: Monad m
    => SourceSpan
    -> Sugar.BinOp
    -> ParachuteT Error m BinOp
prepareBinOp source = \case
    Sugar.EqualO              -> pure EqualO
    Sugar.NotEqualO           -> pure NotEqualO
    Sugar.LessThanO           -> pure LessThanO
    Sugar.LessThanOrEqualO    -> pure LessThanOrEqualO
    Sugar.GreaterThanO        -> pure GreaterThanO
    Sugar.GreaterThanOrEqualO -> pure GreaterThanOrEqualO
    Sugar.PlusO               -> pure PlusO
    Sugar.MinusO              -> pure MinusO
    Sugar.TimesO              -> pure TimesO
    Sugar.DivideO             -> pure DivideO
    Sugar.UnifyO              -> do
        tellError $ Error.mkError "compile" source
            "invalid unification" $
            "The `=` operator should not appear in this context, perhaps" <+>
            "you meant to write `==`?"
        pure EqualO
    Sugar.AssignO             -> do
        tellError $ Error.mkError "compile" source
            "invalid unification" $
            "The `:=` operator should not appear in this context, perhaps" <+>
            "you meant to write `==`?"
        pure EqualO