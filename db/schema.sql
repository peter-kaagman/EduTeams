-- 
-- Users
--
Create Table If Not Exists users(
    azureid Text Unique Not Null,
    upn Text Unique Not Null,
    memberid Text,
    stamnr Text,
    naam Text,
    locatie Text
);

--
-- Magister
--
-- Groepen en klassen uit magister
--
Create Table If Not Exists magisterteam(
    naam Text Not Null Unique,
    locatie Text,
    type Text 
);

--
-- Koppeltabel tussen docenten en teams op ROWID
--
Create Table If Not Exists magisterdocentenrooster(
    docentid Integer Not Null,
    teamid Integer Not Null,
    Foreign Key (docentid) References users(ROWID),
    Foreign Key (teamid) References magisterteam(ROWID)
);

--
-- Koppeltabel tussen leerlingen en teams op ROWID
--
Create Table If Not Exists magisterleerlingenrooster(
    leerlingid Integer Not Null,
    teamid Integer Not Null,
    Foreign Key (leerlingid) References users(ROWID),
    Foreign Key (teamid) References magisterteam(ROWID)
);

--
-- Azure
--
-- Azure teams
--
Create Table If Not Exists azureteam(
    id Text Not Null Unique,
    description Text Not Null,
    displayName Text Not Null,
    secureName Text Not Null,
    locatie Text
);

Create Table If Not Exists azuredocrooster(
    azureteam_id Integer Not Null,
    azuredocent_id Integer Not Null,
    Foreign Key (azuredocent_id) References users(ROWID),
    Foreign Key (azureteam_id) References azureteam(ROWID)
);

Create Table If Not Exists azureleerlingrooster(
    azureteam_id Integer Not Null,
    azureleerling_id Integer Not Null,
    Foreign Key (azureleerling_id) References users(ROWID),
    Foreign Key (azureteam_id) References azureteam(ROWID)
);

-- Voor de verdere inrichting van het team
Create Table If Not Exists teamcreated(
    naam Text Not NULL,
    timestamp Text Not Null,
    id Text Unique Not Null,
    members Text Not Null,
    --owners Text Not Null,
    owner_added Text default '0',       -- voorwaarde voor de transitie
    general_checked Text default '0',
    team_gemaakt Text default '0'
);

