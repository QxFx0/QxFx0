concrete QxFx0SyntaxEng of QxFx0Syntax = QxFx0LexiconEng ** open SyntaxEng, ParadigmsEng in {
  lincat
    Move = S ;
    NP = SyntaxEng.NP ;
    VP = SyntaxEng.VP ;
    GfNumber = { s : Str } ;
    Modifier = { s : Str } ;
    Relation = { s : Str } ;
    Mechanism = { s : Str } ;
  lin
    NumSg = { s = "maintain" } ;
    NumPl = { s = "maintain" } ;
    MkNP lex = mkNP lex ;
    ActMaintain num obj = { s = num.s ++ " " ++ obj.s } ;
    ActDefine obj = { s = "define " ++ obj.s } ;
    ModFirst = { s = "first" } ;
    ModStrictly = { s = "strictly" } ;
    MoveInvite topic mod vp = mkS (mkCl (mkNP i_Pron) vp) ;
    RelIdentity = { s = "is" } ;
    MechParse = { s = "parse" } ;
    MoveDefine subj rel obj = mkS (mkCl subj (mkVP (mkV2 (mkV "define")) obj)) ;
    MoveCause subj mech = mkS (mkCl subj (mkVP (mkV "explain"))) ;
    MovePurpose topic = mkS (mkCl topic (mkVP (mkV "matter"))) ;
    MoveSelfState = mkS (mkCl (mkNP i_Pron) (mkVP (mkV "work"))) ;
    MoveCompare a b = mkS (mkCl a (mkVP (mkV2 (mkV "compare")) b)) ;
    MoveOperationalStatus = mkS (mkCl (mkNP i_Pron) (mkVP (mkV "work"))) ;
    MoveOperationalCause = mkS (mkCl (mkNP i_Pron) (mkVP (mkV "route"))) ;
    MoveSystemLogic = mkS (mkCl (mkNP i_Pron) (mkVP (mkV "reason"))) ;
    MoveMisunderstanding = mkS (mkCl (mkNP i_Pron) (mkVP (mkV "misunderstand"))) ;
    MoveGenerativeThought = mkS (mkCl (mkNP i_Pron) (mkVP (mkV "think"))) ;
    MoveContemplative topic = mkS (mkCl topic (mkVP (mkV "mean"))) ;
    MoveGround topic = mkS (mkCl (mkNP i_Pron) (mkVP (mkVP (mkV "ground") topic) (mkAdv "in" (mkNP concrete_N)))) ;
    MoveContact topic = mkS (mkCl (mkNP i_Pron) (mkVP (mkV "contact"))) ;
    MoveReflect topic = mkS (mkCl (mkNP i_Pron) (mkVP (mkV "reflect"))) ;
    MoveDescribe topic = mkS (mkCl topic (mkVP (mkV "describe"))) ;
    MoveDeepen topic = mkS (mkCl (mkNP i_Pron) (mkVP (mkV "deepen"))) ;
    MoveConfront topic = mkS (mkCl (mkNP i_Pron) (mkVP (mkV "confront"))) ;
    MoveAnchor topic = mkS (mkCl (mkNP i_Pron) (mkVP (mkV "anchor"))) ;
    MoveClarify topic = mkS (mkCl (mkNP i_Pron) (mkVP (mkV "clarify"))) ;
    MoveNextStepLocal topic = mkS (mkCl (mkNP i_Pron) (mkVP (mkV "continue"))) ;
    MoveHypothesis topic = mkS (mkCl (mkNP i_Pron) (mkVP (mkV "hypothesize"))) ;
    MoveDistinguish a b = mkS (mkCl a (mkVP (mkV2 (mkV "distinguish")) b)) ;
    ApplyStanceTentative move = mkS (mkCl (mkNP i_Pron) (mkVP (mkV "say"))) ;
    ApplyStanceFirm move = mkS (mkCl (mkNP i_Pron) (mkVP (mkV "state"))) ;
}
