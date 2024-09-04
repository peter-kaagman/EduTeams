Ik ga maar ff bijhouden wat ik allemaal test;

- Create team zonder leden => niets te doen
- Create team zonder docent => teams zonder docent komen niet meer in het rooster
- Create team zonder leerlingen, met docent => niets te doen
- Bestaand team geen docent meer
    Team wordt gearchiveert, de leden worden echter nog gechecked en bijgewerkt => Zo laten
- Create team met lln en doc => wordt correct gemaakt incl create team cyclus
- Gemaakte teams zijn niet aktief => check
- Archiveer een team => check
- Dearchiveer een team => check

Probleem:
Als een team gearchiveert wordt wat ook onderdeel is van een jaarlaag dan worden niet alle leerlingen uit de jaarlaag verwijderd? Zijn de leerlingen lid via een ander team? => Leerlingen zijn inderdaad nog lid via een ander team.
Geen probleem dus

"MagisterAzure geen leerlingen in team" wordt ook getriggered als het team geen docent heeft in Magister. De Magisterhash van het team is in dat geval leeg. Dit komt alleen voor tijdens testen => getMagister zal geen team aangeven voor een groep zonder docent. Hier verder geen voorzieningen voor treffen daar dez

https://graph.microsoft.com/v1.0/groups?$filter=mailNickname eq 'Archived_EduTeam_2324-1Test3-en1'
