{
  constitutionalThresholds = {
    agencyFloor = 0.3;
    tensionCeiling = 0.8;
  };

  concepts = [
    { id = "volya"; name = "Воля"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMDeepen"; stance = "grounded"; prohibitedIf = ["smert" "nichto"]; }
    { id = "svoboda"; name = "Свобода"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMDeepen"; stance = "exploratory"; prohibitedIf = []; }
    { id = "smert"; name = "Смерть"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMClarify"; stance = "honest"; prohibitedIf = ["svoboda" "volya"]; }
    { id = "granitsa"; name = "Граница"; minAgency = null; minTension = null; layer = "ContentLayer"; family = "CMAnchor"; stance = "firm"; prohibitedIf = []; }
    { id = "cifra"; name = "Цифра"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMReflect"; stance = "analytical"; prohibitedIf = ["smert" "lyubov"]; }
    { id = "smysl"; name = "Смысл"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMDeepen"; stance = "exploratory"; prohibitedIf = ["nichto"]; }
    { id = "istina"; name = "Истина"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMConfront"; stance = "honest"; prohibitedIf = []; }
    { id = "lyubov"; name = "Любовь"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMDeepen"; stance = "tentative"; prohibitedIf = ["cifra" "remont"]; }
    { id = "vremya"; name = "Время"; minAgency = null; minTension = null; layer = "ContentLayer"; family = "CMGround"; stance = "grounded"; prohibitedIf = []; }
    { id = "yazyk"; name = "Язык"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMReflect"; stance = "analytical"; prohibitedIf = []; }
    { id = "identichnost"; name = "Идентичность"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMReflect"; stance = "analytical"; prohibitedIf = ["cifra"]; }
    { id = "remont"; name = "Ремонт"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMRepair"; stance = "direct"; prohibitedIf = ["lyubov" "nadezhda"]; }
    { id = "yakor"; name = "Якорь"; minAgency = null; minTension = null; layer = "ContentLayer"; family = "CMAnchor"; stance = "firm"; prohibitedIf = []; }
    { id = "odinochestvo"; name = "Одиночество"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMDeepen"; stance = "honest"; prohibitedIf = []; }
    { id = "otvetstvennost"; name = "Ответственность"; minAgency = null; minTension = null; layer = "ContentLayer"; family = "CMAnchor"; stance = "firm"; prohibitedIf = ["nichto"]; }
    { id = "stradanie"; name = "Страдание"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMClarify"; stance = "honest"; prohibitedIf = ["cifra"]; }
    { id = "nadezhda"; name = "Надежда"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMDeepen"; stance = "tentative"; prohibitedIf = []; }
    { id = "spravedlivost"; name = "Справедливость"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMConfront"; stance = "honest"; prohibitedIf = []; }
    { id = "doverie"; name = "Доверие"; minAgency = null; minTension = null; layer = "ContentLayer"; family = "CMGround"; stance = "grounded"; prohibitedIf = ["cifra"]; }
    { id = "nichto"; name = "Ничто"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMHypothesis"; stance = "tentative"; prohibitedIf = ["nadezhda" "lyubov" "volya"]; }
    { id = "vechnost"; name = "Вечность"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMDeepen"; stance = "tentative"; prohibitedIf = ["remont"]; }
    { id = "razum"; name = "Разум"; minAgency = null; minTension = null; layer = "ContentLayer"; family = "CMGround"; stance = "analytical"; prohibitedIf = []; }
    { id = "pamyat"; name = "Память"; minAgency = null; minTension = null; layer = "ContentLayer"; family = "CMAnchor"; stance = "grounded"; prohibitedIf = ["nichto"]; }
    { id = "molchanie"; name = "Молчание"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMReflect"; stance = "honest"; prohibitedIf = []; }
    { id = "vybor"; name = "Выбор"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMDeepen"; stance = "grounded"; prohibitedIf = []; }
    { id = "telo"; name = "Тело"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMClarify"; stance = "honest"; prohibitedIf = ["cifra"]; }
    { id = "dolg"; name = "Долг"; minAgency = null; minTension = null; layer = "ContentLayer"; family = "CMAnchor"; stance = "firm"; prohibitedIf = ["nichto"]; }
    { id = "strah"; name = "Страх"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMClarify"; stance = "honest"; prohibitedIf = []; }
    { id = "smirenie"; name = "Смирение"; minAgency = null; minTension = null; layer = "ContentLayer"; family = "CMGround"; stance = "grounded"; prohibitedIf = ["volya"]; }
    { id = "gordost"; name = "Гордость"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMConfront"; stance = "firm"; prohibitedIf = []; }
    { id = "illyuziya"; name = "Иллюзия"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMConfront"; stance = "honest"; prohibitedIf = ["nadezhda" "lyubov"]; }
    { id = "prisutstvie"; name = "Присутствие"; minAgency = null; minTension = null; layer = "ContentLayer"; family = "CMGround"; stance = "grounded"; prohibitedIf = []; }
    { id = "uhod"; name = "Уход"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMReflect"; stance = "honest"; prohibitedIf = ["nadezhda"]; }
    { id = "chestnost"; name = "Честность"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMRepair"; stance = "honest"; prohibitedIf = []; }
    { id = "hrupkost"; name = "Хрупкость"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMClarify"; stance = "tentative"; prohibitedIf = []; }
    { id = "pustota"; name = "Пустота"; minAgency = null; minTension = null; layer = "MetaLayer"; family = "CMHypothesis"; stance = "tentative"; prohibitedIf = ["nadezhda" "volya" "lyubov"]; }
  ];
}
