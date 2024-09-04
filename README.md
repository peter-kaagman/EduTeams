# EduTeams
## Inleiding
De voormalige SDS implementatie die ik in 2018 geschreven heb werkt niet langer. Magister heeft tabellen verwijderd waar de import van gegevens van afhankelijk was.
In hoofdlijnen deed deze implementatie het volgende
- Downloaden Magister gegevens (uitvoeren SQL queries)
- Normaliseren gegevens naar sql database
- Schrijven van CSV bestanden voor SDS import.

Zonder in detail te willen treden: het normaliseren, specifiek het maken van het rooster, was complex. Alhoewel dit tijden op de agenda gestaan heeft om te verbeteren is hier nooit de tijd voor gekomen.

Een andere school heeft een SDS import gemaakt waarbij Powershell gebruikt wordt om standaard datasets te downloaden bij Magister: "aktieve docenten" en "aktieve leerlingen". In de gedwonloade gegevens staan per docent/leerling welke klassen/cluster ze geven/volgen.
Dit geeft mogelijkheden mijn eerdere implementatie te herstellen en zelfs te verbeteren.
Daarnaast zijn wij onderweg naar een identity management systeem (IDM) waarbij de edu teams niet langer via SDS gemaakt gaan worden maar door MS Graph. Tot de tijd dat IDM het beheer van de eduteams overneem (verwacht aanvang studiejaar 25-26) zal er een ander systeem moeten komen wat de edu teams gaat beheren: EduTeams
## Tooling
- Perl voor scripting
    - Zelf geschreven Perl module voor interakties met Azure
    - Zelf geschreven Perl module voor interakties met Magister
- LWP voor http requests
- MS Graph voor Azure interactie
- Sqlite3 voor tussentijdse opslag.

Perl is sinds jaar en dag de scripttaal die ik het liefst gebruik. Enige tijd geleden heb ik in Perl een aantal modules gemaakt voor groups en users in Azure. Deze modules zal ik gebruiken en daar waar nodig uitbreiden voor EduTeams. Analoog aan deze Azure modules zal ik modules ontwikkelen voor Magister.
## Aanpak
In hooflijnen lijkt de verwerking van EduTeams erg op mijn eerdere SDS scripts. Echter met de volgende verschillen:
- Er worden niet langer CSV bestanden geschreven voor een SDS import. 
- De aanpak zal meer modulair gedaan worden. Per staak een script voor die taak.
- De verschillen tussen Magister en Azure zullen niet langer door SDS gedaan kunnen worden.
Ik kom dan op een volgende aanpak"
- Downloaden en normaliseren Magister gegevens.
- Downloaden en normaliseren Azure gegevens.
- Vanuit de Magister gegevens kijken of er teams aangemaakt moeten worden.
- Vanuit Magister gegevens kijken om de juiste eigenaren (docenten) en leden (leerlingen) toegewezen zijn aan de teams.
- Vanuit Azure gegevens kijken of de teams volgens  Magister nog wel moeten bestaan.
- Vanuit Azure gegevens kijken of je juiste eigenaren (docenten) en leden (leerlingen) toegewezen zijn.
## Teams maken via MS GRaph
Volgens de documentatie is het zondermeer mogelijk om team (met een edu sjabloon) aan te maken via MS Graph. Hierbij heb ik de volgende bedenkingen:
- Kunnen ze assignment bevatten?
- Hebben ze een edu OneNote?
- Moeten deze teams ook geactiveerd worden?
### Procedure
Bron: https://learn.microsoft.com/en-us/graph/teams-create-group-and-team
- Maak een group (incl leden en owners)
- Eventueel "add owners", met pauze van 1 seconde (https://learn.microsoft.com/en-us/graph/api/group-post-owners)
- Eventueel "add member", met pauze van 1 seconde (https://learn.microsoft.com/en-us/graph/api/group-post-members)
- Group aanmaak kan 15 minuten duren, volgende stappen moeten dus wachten hierop.
- Maak er een team van met create team from group", (https://learn.microsoft.com/en-us/graph/api/team-post#example-4-create-a-team-from-group)

#### Bedenkingen
##### Add owner/member
Vereist een 1 seconde pauze tussen akties. De backend sync met teams kan 24uur duren en wordt pas getriggered indien 1 van de de leden of eigenaren online is in de Teams desktop app (niet de mobiele app).
##### Create team from group
Dit kan kan pas nadat de group aangemaakt is en kan 15 minuten duren. Zou de volgende methode werken?:
- Create group
- Entry maken in een separate tabel
- Separaat process wat deze tabel verwerkt en "create team from group" uitvoert
- Dit process periodiek uitvoeren.

Example 2 op de pagina https://learn.microsoft.com/en-us/graph/api/group-post-groups?view=graph-rest-1.0&tabs=http is een voorbeeld hoe een group met eigenaren en leden gemaakt wordt. Om eigenaren en leden toe te kunnen voegen is de ID van de gebruiker vereist. De UPN volstaat niet. 

## De scripts  
### Magister.pm (een module met generieke functies)
De SDS implementatie die ik gevonden heb van een school in Castricum maakt CSV bestanden voor SDS vanuit een download van standaard datasets voor aktieve docenten en leerlingen. Deze implementaite werkt volledig in Powershell. Aangezien ik niet echt "handig" ben met Powershell zal mijn implementatie met Perl geschreven worden. Via deze methode worden een tweetal CSV/XML bestanden gedownload. In deze bestanden staan de aktieve leerlingen en docenten, per leerling of docent de klassen/kluster die zij volgen danwel geven.
Voor alle generieke handelingen met Magister is een module geschreven: Magister.pm. Bij initialisatie van de module wordt een access key opgevraagt bij Magister. Deze module exporteert een object met de volgende methodes:
#### getDocenten / getLeerlingen
Download een CSV bestand (in het geheugen) met aktieve docenten of leerlingen en verwerkt de gegevens naar een Perl hash.
Dit zijn 2 verschillende functies omdat er bij leerlingen een les periode vereist is.
#### getRooster
Download per docent of leerling de lesgroepen die ze geven danwel volgen. Deze functie wordt per docent/leerling aangeroepen. De gegevens worden als CSV gedownload, maar ook weer in het geheugen verwerkt tot een Perl hash.
### getMagister.pl
Dit script roept de module functies aan om achtereenvolgens de docenten en dan de leerlingen te verkrijgen.
Vervolgens wordt per docent/leerling het roster opgehaald.
#### Docenten
Als de docent groepen lesgeeft die aktief zijn (niet al onze scholen gebruiken team) dan wordt zijn ID opghaald uit de database. Indien er nog geen record bestaat voor de docent dan wordt zijn UPN opgehaald aan de hand van zijn Magister inlogcode. Als hij een geldige UPN heeft (de docent heeft een account) dan wordt hij toegevoegd aan de database.
Vervolgens wordt het ID van de lesgroep opgehaald uit de database, eventueel wordt de lesgroep aangemaakt.
Als de IDs van de lesgroep en de docent bekend zijn wordt er een entry gemaakt in de tabel docentenrooster. 

### Notities
group info: https://graph.microsoft.com/v1.0/groups/some_id

id: bevat de graph identifier
description: bevat de originele section naam
displayName: is de naam die de docent kan instellen
mail : begint met EduTeam_, hieraan kun je een SDS team dus herkennen, mail kan gebruikt worden in een filter (https://learn.microsoft.com/en-us/graph/api/resources/group?view=graph-rest-1.0)


https://learn.microsoft.com/en-us/graph/filter-query-parameter?tabs=http geeft filter voorbeelden
https://graph.microsoft.com/v1.0/groups/?$filter=startswith(mail,'EduTeam_')
Geeft alle groepen waarvan mail begint met "EduTeam_", echter ook groepen van niet relevante studiejaren => ALLE SDS teams
@odata.nextlink geeft aan dat er nog meer resultaat is
Blijkt dat mijn msGraph Perl modules dit al regelen.

Voorbeel met multiple filters
https://graph.microsoft.com/beta/users?$count=true
&$filter=
    endsWith(userPrincipalName,'mydomain.com') and 
    accountEnabled eq false
&$orderBy=userPrincipalName
&$select=id,displayName,userPrincipalName

Op MS Build staan oa de properties van groups
https://learn.microsoft.com/en-us/graph/api/resources/group?view=graph-rest-1.0

description	String	An optional description for the group.
Returned by default. Supports $filter (eq, ne, not, ge, le, startsWith) and $search.

Ik zou een extra filter op description startsWith lesperiode kunnen gebruiken
Echter in sommige gevallen (waarom weet ik niet) begint de description met de locatie (OSG)
Beter achteraf filteren dus

De queries
https://graph.microsoft.com/v1.0/groups/some_id/owners/?$select=id,displayName,userPrincipalName
https://graph.microsoft.com/v1.0/groups/some_id/members/?$select=id,displayName,userPrincipalName
halen de leden en eigenaren op
NB Een eigenaar is ook een lid

EducationTerm
{
  "@odata.type": "#microsoft.graph.educationTerm",
  "displayName": "String",
  "endDate": "Date",
  "externalId": "String",
  "startDate": "Date"
}