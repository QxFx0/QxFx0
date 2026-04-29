{
  constitutionalThresholds = {
    agencyFloor = 0.3;
    tensionCeiling = 0.8;
  };

  concepts = [
    { name = "Воля"; minAgency = 0.5; minTension = null; layer = "ContentLayer"; family = "Deepen"; stance = "grounded"; prohibitedIf = ["Death" "Nothingness"]; }
    { name = "Свобода"; minAgency = 0.3; minTension = 0.2; layer = "ContentLayer"; family = "Explore"; stance = "exploratory"; prohibitedIf = []; }
    { name = "Смерть"; minAgency = 0.4; minTension = 0.3; layer = "ContentLayer"; family = "Clarify"; stance = "honest"; prohibitedIf = ["Freedom" "Will"]; }
    { name = "Граница"; minAgency = 0.3; minTension = null; layer = "ContentLayer"; family = "Anchor"; stance = "firm"; prohibitedIf = []; }
    { name = "Цифра"; minAgency = 0.5; minTension = null; layer = "MetaLayer"; family = "Reflect"; stance = "analytical"; prohibitedIf = ["Death" "Love"]; }
    { name = "Смысл"; minAgency = 0.3; minTension = 0.2; layer = "ContentLayer"; family = "Deepen"; stance = "exploratory"; prohibitedIf = ["Nothingness"]; }
    { name = "Истина"; minAgency = 0.4; minTension = 0.3; layer = "ContentLayer"; family = "Challenge"; stance = "honest"; prohibitedIf = []; }
    { name = "Любовь"; minAgency = 0.3; minTension = 0.2; layer = "ContentLayer"; family = "Explore"; stance = "tentative"; prohibitedIf = ["Digital" "Repair"]; }
    { name = "Время"; minAgency = 0.3; minTension = null; layer = "ContentLayer"; family = "Ground"; stance = "grounded"; prohibitedIf = []; }
    { name = "Язык"; minAgency = 0.3; minTension = null; layer = "MetaLayer"; family = "Meta"; stance = "analytical"; prohibitedIf = []; }
    { name = "Идентичность"; minAgency = 0.5; minTension = null; layer = "ReflectiveLayer"; family = "Reflect"; stance = "analytical"; prohibitedIf = ["Digital"]; }
    { name = "Ремонт"; minAgency = 0.4; minTension = 0.3; layer = "ContentLayer"; family = "Operational"; stance = "direct"; prohibitedIf = ["Love" "Hope"]; }
    { name = "Якорь"; minAgency = 0.5; minTension = 0.1; layer = "ContentLayer"; family = "Anchor"; stance = "firm"; prohibitedIf = []; }
    { name = "Одиночество"; minAgency = 0.3; minTension = 0.2; layer = "ContentLayer"; family = "Deepen"; stance = "honest"; prohibitedIf = []; }
    { name = "Ответственность"; minAgency = 0.5; minTension = null; layer = "ContentLayer"; family = "Anchor"; stance = "firm"; prohibitedIf = ["Nothingness"]; }
    { name = "Страдание"; minAgency = 0.3; minTension = 0.3; layer = "ContentLayer"; family = "Clarify"; stance = "honest"; prohibitedIf = ["Digital"]; }
    { name = "Надежда"; minAgency = 0.3; minTension = null; layer = "ContentLayer"; family = "Explore"; stance = "tentative"; prohibitedIf = []; }
    { name = "Справедливость"; minAgency = 0.5; minTension = 0.2; layer = "ContentLayer"; family = "Challenge"; stance = "honest"; prohibitedIf = []; }
    { name = "Доверие"; minAgency = 0.4; minTension = null; layer = "ContentLayer"; family = "Ground"; stance = "grounded"; prohibitedIf = ["Digital"]; }
    { name = "Ничто"; minAgency = 0.5; minTension = 0.3; layer = "ContentLayer"; family = "Hypothesize"; stance = "tentative"; prohibitedIf = ["Hope" "Love" "Will"]; }
    { name = "Вечность"; minAgency = 0.4; minTension = null; layer = "ContentLayer"; family = "Explore"; stance = "tentative"; prohibitedIf = ["Repair"]; }
    { name = "Разум"; minAgency = 0.4; minTension = null; layer = "ContentLayer"; family = "Ground"; stance = "analytical"; prohibitedIf = []; }
    { name = "Память"; minAgency = 0.3; minTension = null; layer = "ContentLayer"; family = "Anchor"; stance = "grounded"; prohibitedIf = ["Nothingness"]; }
    { name = "Молчание"; minAgency = 0.3; minTension = 0.2; layer = "ReflectiveLayer"; family = "Reflect"; stance = "honest"; prohibitedIf = []; }
    { name = "Выбор"; minAgency = 0.4; minTension = null; layer = "ContentLayer"; family = "Deepen"; stance = "grounded"; prohibitedIf = []; }
    { name = "Тело"; minAgency = 0.3; minTension = 0.2; layer = "ContentLayer"; family = "Clarify"; stance = "honest"; prohibitedIf = ["Digital"]; }
    { name = "Долг"; minAgency = 0.5; minTension = null; layer = "ContentLayer"; family = "Anchor"; stance = "firm"; prohibitedIf = ["Nothingness"]; }
    { name = "Страх"; minAgency = 0.3; minTension = 0.3; layer = "ContentLayer"; family = "Clarify"; stance = "honest"; prohibitedIf = []; }
    { name = "Смирение"; minAgency = 0.3; minTension = null; layer = "ContentLayer"; family = "Ground"; stance = "grounded"; prohibitedIf = ["Will"]; }
    { name = "Гордость"; minAgency = 0.4; minTension = null; layer = "ContentLayer"; family = "Challenge"; stance = "firm"; prohibitedIf = []; }
    { name = "Иллюзия"; minAgency = 0.5; minTension = 0.2; layer = "ReflectiveLayer"; family = "Challenge"; stance = "honest"; prohibitedIf = ["Hope" "Love"]; }
    { name = "Присутствие"; minAgency = 0.3; minTension = null; layer = "ContentLayer"; family = "Ground"; stance = "grounded"; prohibitedIf = []; }
    { name = "Уход"; minAgency = 0.4; minTension = 0.3; layer = "ContentLayer"; family = "Reflect"; stance = "honest"; prohibitedIf = ["Hope"]; }
    { name = "Честность"; minAgency = 0.5; minTension = null; layer = "MetaLayer"; family = "Operational"; stance = "honest"; prohibitedIf = []; }
    { name = "Хрупкость"; minAgency = 0.3; minTension = 0.2; layer = "ContentLayer"; family = "Clarify"; stance = "tentative"; prohibitedIf = []; }
    { name = "Пустота"; minAgency = 0.5; minTension = 0.3; layer = "ContentLayer"; family = "Hypothesize"; stance = "tentative"; prohibitedIf = ["Hope" "Will" "Love"]; }
  ];
}
