-- Colloquial register concrete syntax for Russian.
-- Overrides selected moves to use second-person pronouns and informal particles.
-- Known limitation: finite verb inflection remains affected by the same RGL issue
-- as the formal register (verbs surface in infinitive in mkCl + mkS pipeline).

concrete QxFx0SyntaxRusColloquial of QxFx0Syntax = QxFx0LexiconRus ** open SyntaxRus, ParadigmsRus in {
  lincat
    Move = S ;
    NP = SyntaxRus.NP ;
    VP = SyntaxRus.VP ;
    AP = SyntaxRus.AP ;
    AdvP = SyntaxRus.Adv ;
  lin
    MkNP lex = mkNP lex ;
    MkNPWithDet det lex = mkNP det lex ;
    MkVP verb = mkVP verb ;
    MkVPWithAdv vp adv = mkVP vp adv ;
    MkAP adj = mkAP adj ;
    MkAdvP adv = adv ;
    MoveCritique topic = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV2 (mkV "критиковать" "критикую" "критикует") accusative) topic)) ;
    MoveGround topic = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV2 (mkV "держать" "держу" "держит") accusative) topic)) ;
    MovePurpose topic = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV2 (mkV "иметь" "имею" "имеет") accusative) topic)) ;
    MoveParadox a b = mkS (mkCl a (mkVP (mkV2 (mkV "возражать" "возражаю" "возражает") dative) b)) ;
    MoveCompare a b = mkS (mkCl a (mkVP (mkV2 (mkV "сравнивать" "сравниваю" "сравнивает") accusative) b)) ;
    MoveDefine subj obj = mkS (mkCl subj obj) ;
    MoveExplain subj vp = mkS (mkCl subj vp) ;
    MoveQuestion topic = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV2 (mkV "спрашивать" "спрашиваю" "спрашивает") accusative) topic)) ;
    MoveWithAdj np ap = mkS (mkCl np ap) ;
    MoveWithAdv vp adv = mkS (mkCl (mkNP youSg_Pron) vp) ;
}