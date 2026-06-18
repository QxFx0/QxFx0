{
  constitutionalThresholds = {
    agencyFloor = 0.3;
    tensionCeiling = 0.8;
  };

  concepts = [
    { id = "volya"; name = "Воля"; minAgency = 0.5; minTension = null; layer = "MetaLayer"; family = "CMDeepen"; stance = "grounded"; prohibitedIf = ["smert" "nichto"]; }
    { id = "svoboda"; name = "Свобода"; minAgency = 0.3; minTension = 0.1; layer = "MetaLayer"; family = "CMDeepen"; stance = "exploratory"; prohibitedIf = []; }
    { id = "smert"; name = "Смерть"; minAgency = 0.4; minTension = 0.1; layer = "MetaLayer"; family = "CMClarify"; stance = "honest"; prohibitedIf = ["svoboda" "volya"]; }
    { id = "granitsa"; name = "Граница"; minAgency = 0.3; minTension = null; layer = "ContentLayer"; family = "CMAnchor"; stance = "firm"; prohibitedIf = []; }
    { id = "cifra"; name = "Цифра"; minAgency = 0.5; minTension = null; layer = "MetaLayer"; family = "CMReflect"; stance = "analytical"; prohibitedIf = ["smert" "lyubov"]; }
    { id = "smysl"; name = "Смысл"; minAgency = 0.3; minTension = 0.1; layer = "MetaLayer"; family = "CMDeepen"; stance = "exploratory"; prohibitedIf = ["nichto"]; }
    { id = "istina"; name = "Истина"; minAgency = 0.4; minTension = 0.1; layer = "MetaLayer"; family = "CMConfront"; stance = "honest"; prohibitedIf = []; }
    { id = "lyubov"; name = "Любовь"; minAgency = 0.3; minTension = 0.1; layer = "MetaLayer"; family = "CMDeepen"; stance = "tentative"; prohibitedIf = ["cifra" "remont"]; }
    { id = "vremya"; name = "Время"; minAgency = 0.3; minTension = null; layer = "ContentLayer"; family = "CMGround"; stance = "grounded"; prohibitedIf = []; }
    { id = "yazyk"; name = "Язык"; minAgency = 0.3; minTension = null; layer = "MetaLayer"; family = "CMReflect"; stance = "analytical"; prohibitedIf = []; }
    { id = "identichnost"; name = "Идентичность"; minAgency = 0.5; minTension = null; layer = "MetaLayer"; family = "CMReflect"; stance = "analytical"; prohibitedIf = ["cifra"]; }
    { id = "remont"; name = "Ремонт"; minAgency = 0.4; minTension = 0.1; layer = "MetaLayer"; family = "CMRepair"; stance = "direct"; prohibitedIf = ["lyubov" "nadezhda"]; }
    { id = "yakor"; name = "Якорь"; minAgency = 0.5; minTension = 0.1; layer = "ContentLayer"; family = "CMAnchor"; stance = "firm"; prohibitedIf = []; }
    { id = "odinochestvo"; name = "Одиночество"; minAgency = 0.3; minTension = 0.2; layer = "MetaLayer"; family = "CMDeepen"; stance = "honest"; prohibitedIf = []; }
    { id = "otvetstvennost"; name = "Ответственность"; minAgency = 0.5; minTension = null; layer = "ContentLayer"; family = "CMAnchor"; stance = "firm"; prohibitedIf = ["nichto"]; }
    { id = "stradanie"; name = "Страдание"; minAgency = 0.3; minTension = 0.3; layer = "MetaLayer"; family = "CMClarify"; stance = "honest"; prohibitedIf = ["cifra"]; }
    { id = "nadezhda"; name = "Надежда"; minAgency = 0.3; minTension = null; layer = "MetaLayer"; family = "CMDeepen"; stance = "tentative"; prohibitedIf = []; }
    { id = "spravedlivost"; name = "Справедливость"; minAgency = 0.5; minTension = 0.2; layer = "MetaLayer"; family = "CMConfront"; stance = "honest"; prohibitedIf = []; }
    { id = "doverie"; name = "Доверие"; minAgency = 0.4; minTension = null; layer = "ContentLayer"; family = "CMGround"; stance = "grounded"; prohibitedIf = ["cifra"]; }
    { id = "nichto"; name = "Ничто"; minAgency = 0.5; minTension = 0.3; layer = "MetaLayer"; family = "CMHypothesis"; stance = "tentative"; prohibitedIf = ["nadezhda" "lyubov" "volya"]; }
    { id = "vechnost"; name = "Вечность"; minAgency = 0.4; minTension = null; layer = "MetaLayer"; family = "CMDeepen"; stance = "tentative"; prohibitedIf = ["remont"]; }
    { id = "razum"; name = "Разум"; minAgency = 0.4; minTension = null; layer = "ContentLayer"; family = "CMGround"; stance = "analytical"; prohibitedIf = []; }
    { id = "pamyat"; name = "Память"; minAgency = 0.3; minTension = null; layer = "ContentLayer"; family = "CMAnchor"; stance = "grounded"; prohibitedIf = ["nichto"]; }
    { id = "molchanie"; name = "Молчание"; minAgency = 0.3; minTension = 0.2; layer = "MetaLayer"; family = "CMReflect"; stance = "honest"; prohibitedIf = []; }
    { id = "vybor"; name = "Выбор"; minAgency = 0.4; minTension = null; layer = "MetaLayer"; family = "CMDeepen"; stance = "grounded"; prohibitedIf = []; }
    { id = "telo"; name = "Тело"; minAgency = 0.3; minTension = 0.2; layer = "MetaLayer"; family = "CMClarify"; stance = "honest"; prohibitedIf = ["cifra"]; }
    { id = "dolg"; name = "Долг"; minAgency = 0.5; minTension = null; layer = "ContentLayer"; family = "CMAnchor"; stance = "firm"; prohibitedIf = ["nichto"]; }
    { id = "strah"; name = "Страх"; minAgency = 0.3; minTension = 0.3; layer = "MetaLayer"; family = "CMClarify"; stance = "honest"; prohibitedIf = []; }
    { id = "smirenie"; name = "Смирение"; minAgency = 0.3; minTension = null; layer = "ContentLayer"; family = "CMGround"; stance = "grounded"; prohibitedIf = ["volya"]; }
    { id = "gordost"; name = "Гордость"; minAgency = 0.4; minTension = null; layer = "MetaLayer"; family = "CMConfront"; stance = "firm"; prohibitedIf = []; }
    { id = "illyuziya"; name = "Иллюзия"; minAgency = 0.5; minTension = 0.2; layer = "MetaLayer"; family = "CMConfront"; stance = "honest"; prohibitedIf = ["nadezhda" "lyubov"]; }
    { id = "prisutstvie"; name = "Присутствие"; minAgency = 0.3; minTension = null; layer = "ContentLayer"; family = "CMGround"; stance = "grounded"; prohibitedIf = []; }
    { id = "uhod"; name = "Уход"; minAgency = 0.4; minTension = 0.3; layer = "MetaLayer"; family = "CMReflect"; stance = "honest"; prohibitedIf = ["nadezhda"]; }
    { id = "chestnost"; name = "Честность"; minAgency = 0.5; minTension = null; layer = "MetaLayer"; family = "CMRepair"; stance = "honest"; prohibitedIf = []; }
    { id = "hrupkost"; name = "Хрупкость"; minAgency = 0.3; minTension = 0.2; layer = "MetaLayer"; family = "CMClarify"; stance = "tentative"; prohibitedIf = []; }
    { id = "pustota"; name = "Пустота"; minAgency = 0.5; minTension = 0.3; layer = "MetaLayer"; family = "CMHypothesis"; stance = "tentative"; prohibitedIf = ["nadezhda" "volya" "lyubov"]; }
  ];
}
