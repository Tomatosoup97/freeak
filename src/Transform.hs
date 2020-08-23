module Transform where

import AST
import Types
import qualified Data.Map as Map

type AlgSignMap = Map.Map EffLabel AlgTheoryName

getCoalgebra :: AlgTheoryName -> Comp -> Comp
getCoalgebra algT = (ELet algT . EReturn . VVar) algT
-- getCoalgebra algT = ELet algT (EOp (algT ++ "Get") VUnit)

putCoalgebra :: AlgTheoryName -> Value -> Comp -> Comp
putCoalgebra algT = ELet algT . EReturn
-- putCoalgebra algT = ELet algT . EOp (algT ++ "Put")

coopTransV :: AlgSignMap -> Value -> Value
coopTransV m v = case v of
    VLambda x t c -> VLambda x t (coopTrans m c)
    VFix g x c -> VFix g x (coopTrans m c)
    VPair v1 v2 -> VPair (coopTransV m v1) (coopTransV m v2)
    VBinOp op v1 v2 -> VBinOp op (coopTransV m v1) (coopTransV m v2)
    v -> v

coopTransHandler :: AlgSignMap -> Handler -> Handler
coopTransHandler m (HRet v c) = HRet v (coopTrans m c)
coopTransHandler m (HOps (AlgOp l p r c) h) =
    HOps (AlgOp l p r (coopTrans m c)) (coopTransHandler m h)

coopTrans :: AlgSignMap -> Comp -> Comp
coopTrans m c = case c of
    EVal v -> EVal (coopTransV m v)
    ELet x varC bC -> ELet x (coopTrans m varC) (coopTrans m bC)
    EApp v1 v2 -> EApp (coopTransV m v1) (coopTransV m v2)
    EReturn v -> EReturn (coopTransV m v)
    EAbsurd v -> EAbsurd (coopTransV m v)
    EIf v tC fC -> EIf (coopTransV m v) (coopTrans m tC) (coopTrans m fC)
    EOp l v -> EOp l (coopTransV m v)
    EHandle c h -> EHandle (coopTrans m c) (coopTransHandler m h)
    ECoop l v -> case Map.lookup l m of
        Just algT ->
            let algTRes = algT ++ "Res" in
            let coop = ECoop l (VPair (VVar algT) (coopTransV m v)) in
            let bindResult = ELet algTRes coop in
            let contComp = EReturn (VSnd (VVar algTRes)) in
            (getCoalgebra algT . bindResult . putCoalgebra algT (VVar algT)) contComp
        Nothing -> ECoop l (coopTransV m v)
    ECohandleIR algTheoryName initV c h ->
        let algTVar = "#" ++ algTheoryName in
        let sign = hopsL h in
        let m' = foldl (\m s -> Map.insert s algTVar m) m sign in
        -- TODO: Add handling for #AlgTheoryPut and #AlgTheoryGet effects
        let h' = coopTransHandler m' h in
        let cohandle = (`ECohandle` h') in
        (cohandle . putCoalgebra algTVar initV . coopTrans m') c

transform :: Comp -> Comp
transform = coopTrans Map.empty
