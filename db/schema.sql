Create Table If Not Exists magisterteam(
    naam Text Not Null Unique,
    type Text Not NUll
);

Create Table If Not Exists magisterdocent(
    stamnr Text Not Null Unique,
    inlogcode Text Not Null,
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

Create Table If Not Exists magisterleerling(
    stamnr Text Not Null Unique,
    b_nummer Text Not Null,
    upn Text Not Null,
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

Create Table If Not Exists azuredocent(
    upn Text Not Null Unique,
    naam Text Not Null
);

Create Table If Not Exists azuredocrooster(
    azureteam_id Integer Not Null,
    azuredocent_id Integer Not Null,
    Foreign Key (azuredocent_id) References azuredocent(ROWID),
    Foreign Key (azureteam_id) References azureteam(ROWID)
);

Create Table If Not Exists azureleerling(
    upn Text Not Null Unique,
    naam Text Not Null
);

Create Table If Not Exists azureleerlingrooster(
    azureteam_id Integer Not Null,
    azureleerling_id Integer Not Null,
    Foreign Key (azureleerling_id) References azureleerling(ROWID),
    Foreign Key (azureteam_id) References azureteam(ROWID)
);