-- Select
--         magisterteam.*,
--         magisterdocent.azureid As 'azureid',
--         magisterdocent.naam As 'docent_naam',
--         magisterleerling.upn As 'leerling_upn',
--         magisterleerling.naam As 'leerling_naam'
-- From magisterteam
-- Left Join magisterdocentenrooster   On magisterdocentenrooster.teamid = magisterteam.ROWID
-- Left Join users                     On magisterdocentenrooster.docentid = users.ROWID
-- Left Join magisterleerlingenrooster On magisterleerlingenrooster.teamid = magisterteam.ROWID
-- Left Join users                       On magisterleerlingenrooster.leerlingid = users.ROWID
-- ;

-- Select 
--     magisterteam.*,
--     (
--         Select 
--             users.upn
--         From users 
--         Left Join magisterdocentenrooster On magisterdocenten.teamid = magisterteam.rowid
--         Left Join users On users.rowid = magisterdocentenrooster.docentid
--         Where magisterdocentenrooster.teamid = magisterteam.rowid
--     ) as docentid
-- From magisterteam
-- ;

Select
        azureteam.*,
        users.azureid As 'leerling_azureid',
        users.naam As 'leerling_naam'
    From azureteam
    Left Join azureleerlingrooster   On azureleerlingrooster.azureteam_id = azureteam.ROWID
    Left Join users         On azureleerlingrooster.azureleerling_id = users.ROWID
;    