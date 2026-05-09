concrete QxFx0SyntaxEng of QxFx0Syntax = QxFx0LexiconEng ** open SyntaxEng, ParadigmsEng in {
  lincat
    Move = S ;
    NP = SyntaxEng.NP ;
    VP = SyntaxEng.VP ;
    AP = SyntaxEng.AP ;
    AdvP = SyntaxEng.Adv ;
  lin
    MkNP lex = mkNP lex ;
    MkNPWithDet det lex = mkNP det lex ;
    MkVP verb = mkVP verb ;
    MkVPWithAdv vp adv = mkVP vp adv ;
    MkAP adj = mkAP adj ;
    MkAdvP adv = adv ;
    MoveCritique topic = mkS (mkCl (mkNP i_Pron) (mkVP (mkV2 (mkV "criticize")) topic)) ;
    MoveGround topic = mkS (mkCl (mkNP i_Pron) (mkVP (mkV2 (mkV "ground")) topic)) ;
    MovePurpose topic = mkS (mkCl (mkNP i_Pron) (mkVP (mkV2 (mkV "have")) topic)) ;
    MoveParadox a b = mkS (mkCl a (mkVP (mkV2 (mkV "contradict")) b)) ;
    MoveCompare a b = mkS (mkCl a (mkVP (mkV2 (mkV "compare")) b)) ;
    MoveDefine subj obj = mkS (mkCl subj obj) ;
    MoveExplain subj vp = mkS (mkCl subj vp) ;
    MoveQuestion topic = mkS (mkCl (mkNP i_Pron) (mkVP (mkV2 (mkV "ask")) topic)) ;
    MoveWithAdj np ap = mkS (mkCl np ap) ;
    MoveWithAdv vp adv = mkS (mkCl (mkNP i_Pron) vp) ;
}
