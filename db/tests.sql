Select * From docrooster
   Join team On team.ROWID = docrooster.teamid
   Join docent On docent.ROWID = docrooster.docid
   Where docrooster.teamid = 1616
;

select 
   locatie.short,
   azuredocent.naam,
   azureteam.description
from azuredocent
   Join locatie on azuredocent.idloc = locatie.ROWID
   Join azureteam on azureteam.ROWID = azuredocrooster.azureteam_id
   Join azuredocrooster on azuredocent.ROWID = azuredocrooster.azuredocent_id
   Where azuredocent.naam Like "%Steiger"
;