Select
    azureteam.*,
    azuredocent.upn As 'docent_upn',
    azuredocent.naam As 'docent_naam',
    azureleerling.upn As 'leerling_upn',
    azureleerling.naam As 'leerling_naam'
From azureteam
Left Join azuredocrooster       On azuredocrooster.azureteam_id = azureteam.ROWID
Left Join azuredocent           On azuredocrooster.azuredocent_id = azuredocent.ROWID
Left Join azureleerlingrooster   On azureleerlingrooster.azureteam_id = azureteam.ROWID
Left Join azureleerling         On azureleerlingrooster.azureleerling_id = azureleerling.ROWID
Where azureteam.description = '2324-9k4b.men2'



Select 
    magisterteam.*,
    users.naam,
    users.azureid
From magisterteam,magisterleerlingenrooster,users
Where magisterteam.ROWID = magisterleerlingenrooster.teamid
And   users.ROWID = magisterleerlingenrooster.leerlingid
Order By magisterteam.naam