-- Colloquial register concrete syntax for Russian.
-- Overrides selected moves to use second-person pronouns and informal particles.
-- Known limitation: finite verb inflection remains affected by the same RGL issue
-- as the formal register (verbs surface in infinitive in mkCl + mkS pipeline).

concrete QxFx0SyntaxRusColloquial of QxFx0Syntax = QxFx0LexiconRus ** open SyntaxRus, ParadigmsRus in {
  lincat
    Move = S ;
    NP = SyntaxRus.NP ;
    VP = SyntaxRus.VP ;
    GfNumber = { s : Str } ;
    Modifier = { s : Str } ;
    Relation = { s : Str } ;
    Mechanism = { s : Str } ;
    ActTopic = { s : Str } ;
  lin
    NumSg = { s = "держу" } ;
    NumPl = { s = "держим" } ;
    MkNP lex = mkNP lex ;
    ActMaintain num obj = { s = num.s ++ " " ++ obj.acc } ;
    ActDefine obj = { s = "определяю " ++ obj.acc } ;
    ModFirst = { s = "сначала" } ;
    ModStrictly = { s = "строго" } ;
    MoveInvite topic mod vp = mkS (mkCl (mkNP youSg_Pron) vp) ;
    RelIdentity = { s = "это" } ;
    MechParse = { s = "разбором" } ;
    ActAnswer = { s = "ответ" } ;
    ActQuestion = { s = "вопрос" } ;
    ActTopicTerm = { s = "тема" } ;
    ActProject = { s = "проект" } ;
    ActResult = { s = "результат" } ;
    MoveActOnTopic act = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV2 (mkV "говорить" "говорю" "говорит") prepositional) (mkNP (mkN act.s)))) ;
    MoveDefine subj rel obj = mkS (mkCl subj (mkVP (mkV2 (mkV "определять" "определяю" "определяет") accusative) obj)) ;
    MoveCause subj mech = mkS (mkCl subj (mkVP (mkV "объяснять" "объясняю" "объясняет"))) ;
    MovePurpose topic = mkS (mkCl topic (mkVP (mkV "значить" "значу" "значит"))) ;
    MoveSelfState = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV "работать" "работаю" "работает"))) ;
    MoveCompare a b = mkS (mkCl a (mkVP (mkV2 (mkV "сравнивать" "сравниваю" "сравнивает") accusative) b)) ;
    MoveOperationalStatus = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV "работать" "работаю" "работает"))) ;
    MoveOperationalCause = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV "маршрутизировать" "маршрутизирую" "маршрутизирует"))) ;
    MoveSystemLogic = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV "рассуждать" "рассуждаю" "рассуждает"))) ;
    MoveMisunderstanding = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV "непонимать" "непонимаю" "непонимает"))) ;
    MoveGenerativeThought = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV "думать" "думаю" "думает"))) ;
    MoveContemplative topic = mkS (mkCl topic (mkVP (mkV "значить" "значу" "значит"))) ;
    MoveGround topic = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV2 (mkV "держать" "держу" "держит") accusative) topic)) ;
    MoveContact topic = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV "контактировать" "контактирую" "контактирует"))) ;
    MoveReflect topic = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV "отражать" "отражаю" "отражает"))) ;
    MoveDescribe topic = mkS (mkCl topic (mkVP (mkV "описывать" "описываю" "описывает"))) ;
    MoveDeepen topic = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV "углублять" "углубляю" "углубляет"))) ;
    MoveConfront topic = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV "сопоставлять" "сопоставляю" "сопоставляет"))) ;
    MoveAnchor topic = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV "фиксировать" "фиксирую" "фиксирует"))) ;
    MoveClarify topic = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV "уточнять" "уточняю" "уточняет"))) ;
    MoveNextStepLocal topic = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV "продолжать" "продолжаю" "продолжает"))) ;
    MoveHypothesis topic = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV "предполагать" "предполагаю" "предполагает"))) ;
    MoveDistinguish a b = mkS (mkCl a (mkVP (mkV2 (mkV "различать" "различаю" "различает") accusative) b)) ;
    ApplyStanceTentative move = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV "сказать" "скажу" "скажет"))) ;
    ApplyStanceFirm move = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV "зафиксировать" "зафиксирую" "зафиксирует"))) ;
}
