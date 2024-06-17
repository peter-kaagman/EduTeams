Create Table If Not Exists magisterteam(
    naam Text Not Null Unique,
    type Text 
);
-- UPN en AzureID worden tijdens ophalen uit magister uit Azure gehaald
Create Table If Not Exists magisterdocent(
    stamnr Text Not Null Unique,
    --inlogcode Text Not Null,
    azureid Text,
    upn Text Not Null,
    naam Text
);

-- Koppeltabel tussen docenten en teams op ROWID
Create Table If Not Exists magisterdocentenrooster(
    docentid Integer Not Null,
    teamid Integer Not Null,
    Foreign Key (docentid) References magisterdocent(ROWID),
    Foreign Key (teamid) References magisterteam(ROWID)
);
-- AzureID wordt tijdens de vergelijking/sync opgehaald
-- dan pas is ook echt bekend of de leerling een Azure account heeft
Create Table If Not Exists magisterleerling(
    stamnr Text Not Null Unique,
    b_nummer Text Not Null,
    upn Text Not Null,
    azureid Text,
    naam Text
);
-- Koppeltabel tussen leerlingen en teams op ROWID
Create Table If Not Exists magisterleerlingenrooster(
    leerlingid Integer Not Null,
    teamid Integer Not Null,
    Foreign Key (leerlingid) References magisterleerling(ROWID),
    Foreign Key (teamid) References magisterteam(ROWID)
);

Create Table If Not Exists azureteam(
    id Text Not Null Unique,
    description Text Not Null,
    displayName Text Not Null
);
-- Dit zijn docenten tijdens het ophalen gevonden in een bestaand team
-- Als geen van de teams van een docent al bestaan
-- dan komt hij tijdens het ophalen niet in deze tabel
Create Table If Not Exists azuredocent(
    upn Text Not Null Unique,
    azureid Text Not Null,
    naam Text Not Null
);

Create Table If Not Exists azuredocrooster(
    azureteam_id Integer Not Null,
    azuredocent_id Integer Not Null,
    Foreign Key (azuredocent_id) References azuredocent(ROWID),
    Foreign Key (azureteam_id) References azureteam(ROWID)
);
-- Dit zijn leerlingen tijdens het ophalen gevonden in een bestaand team
-- Als geen van de teams van een leerling al bestaan 
-- dan komt hij tijdens het ophalen niet in deze tabel
Create Table If Not Exists azureleerling(
    upn Text Not Null Unique,
    azureid Text,
    naam Text Not Null
);

Create Table If Not Exists azureleerlingrooster(
    azureteam_id Integer Not Null,
    azureleerling_id Integer Not Null,
    Foreign Key (azureleerling_id) References azureleerling(ROWID),
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

