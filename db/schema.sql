-- #13
Create Table If Not Exists users(
    azureid Text Unique Not Null,
    upn Text Unique Not Null,
    stamnr Text,
    naam Text
);

Create Table If Not Exists magisterteam(
    naam Text Not Null Unique,
    type Text 
);

-- Koppeltabel tussen docenten en teams op ROWID
Create Table If Not Exists magisterdocentenrooster(
    docentid Integer Not Null,
    teamid Integer Not Null,
-- #13
    -- Foreign Key (docentid) References magisterdocent(ROWID),
    Foreign Key (docentid) References users(ROWID),
    Foreign Key (teamid) References magisterteam(ROWID)
);

-- Koppeltabel tussen leerlingen en teams op ROWID
Create Table If Not Exists magisterleerlingenrooster(
    leerlingid Integer Not Null,
    teamid Integer Not Null,
    -- #13
    -- Foreign Key (leerlingid) References magisterleerling(ROWID),
    Foreign Key (leerlingid) References users(ROWID),
    Foreign Key (teamid) References magisterteam(ROWID)
);

Create Table If Not Exists azureteam(
    id Text Not Null Unique,
    description Text Not Null,
    displayName Text Not Null,
    secureName Text Not Null
);

Create Table If Not Exists azuredocrooster(
    azureteam_id Integer Not Null,
    azuredocent_id Integer Not Null,
    -- #13
    -- Foreign Key (azuredocent_id) References azuredocent(ROWID),
    Foreign Key (azuredocent_id) References users(ROWID),
    Foreign Key (azureteam_id) References azureteam(ROWID)
);

Create Table If Not Exists azureleerlingrooster(
    azureteam_id Integer Not Null,
    azureleerling_id Integer Not Null,
    -- #13
    --Foreign Key (azureleerling_id) References azureleerling(ROWID),
    Foreign Key (azureleerling_id) References users(ROWID),
    Foreign Key (azureteam_id) References azureteam(ROWID)
);

-- Voor de verdere inrichting van het team
Create Table If Not Exists teamcreated(
    naam Text Not NULL,
    timestamp Text Not Null,
    id Text Unique,
    members Text Not Null,
    owners Text Not Null,
    general_checked Text default '0',
    naam_hersteld Text default '0'
);

