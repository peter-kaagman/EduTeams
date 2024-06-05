-- Test data voor op ictatlascollege
Insert Into magisterteam ('ROWID','naam','type') Values 
---    (1,'2324-0Test1.abc','clustergroep'),
    (2,'2324-0Test2.xyz','clustergroep')
;
-- UPN is in magister niet bekend
-- UPN en AzureID ordt tijdens het ophalen ingevuld ToDo
-- In de test halen wel geen gegevens op dus faken
Insert Into magisterdocent ('ROWID','stamnr','naam','upn','azureid') values 
    (1,'123456','Test Docent 1','docent1@ict-atlascollege.nl', '50794d26-aa78-4cf2-bede-a39ae2da20ad'),
    (2,'123457','Test Docent 2','docent2@ict-atlascollege.nl', 'bb32a504-c67e-475d-9b47-3c6c8e49cf6f')
;
Insert Into magisterdocentenrooster ('docentid','teamid') values
    ('1','2')--,
--    ('2','1')
;
-- UPN is bekend, echter niet betrouwbaar, het is mogelijk dat een leerling niet in Azure bestaat
Insert Into magisterleerling ('ROWID','stamnr','b_nummer','upn','naam') values
    (1,'234567','b234567','b234567@ict-atlascollege.nl','Test Leerling 1'),
    (2,'234568','b234568','b234568@ict-atlascollege.nl','Test Leerling 2'),
    (3,'234569','b234569','b234569@ict-atlascollege.nl','Test Leerling 3'),
    (4,'234560','b234560','b234560@ict-atlascollege.nl','Test Leerling 4')
;
Insert Into magisterleerlingenrooster ('leerlingid','teamid') values
--    ('1','1'),
--    ('2','1'),
--    ('3','1'),
    ('2','2'),
    ('3','2'),
    ('4','2')
;
-- Geen Azure gegevens in de database, geen van de teams is dus bekend
-- Docenten en leerlingen moeten wel bestaan