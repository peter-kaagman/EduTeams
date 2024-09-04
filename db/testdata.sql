-- Normaal haalt getUsers dit op
-- Ik heb echter de rowid nodig voor rooster en zo
Insert Into users ('ROWID','stamnr','naam','upn','azureid') values 
    (1,'123456','Test Docent 1',    'docent1@ict-atlascollege.nl',  '50794d26-aa78-4cf2-bede-a39ae2da20ad'),
    (2,'123457','Test Docent 2',    'docent2@ict-atlascollege.nl',  'bb32a504-c67e-475d-9b47-3c6c8e49cf6f'),
    (3,'234567','Test Leerling 1',  'b234567@ict-atlascollege.nl',  '2d6adf65-a0ce-43d5-a078-bdde1fea563c'),
    (4,'234568','Test Leerling 2',  'b234568@ict-atlascollege.nl',  'ccccb41d-292e-4b2a-90e1-80df05f12dae'),
    (5,'234569','Test Leerling 3',  'b234569@ict-atlascollege.nl',  '2c03712f-c3f3-4169-b3dc-de199398ba3e'),
    (6,'234560','Test Leerling 4',  'b234560@ict-atlascollege.nl',  '911e64b1-ee37-4ffd-9ac3-fc6c60fece6d'),
    (7,'123458','Test Docent 3',    'docent3@ict-atlascollege.nl',  'e5814b22-aca9-471b-b538-9b7549fc404b'),
    (8,'123499','Peter Kaagman',    'pkn@ict-atlascollege.nl',      'f0ec128d-5ce8-44d2-b7ee-a2e123a426d8')
;

-- Test data voor op ictatlascollege
Insert Into magisterteam ('ROWID','naam','type') Values 
    (1,'2324-0Test1.abc','clustergroep'),
    (2,'2324-0Test2.xyz','clustergroep'),
    (3,'2324-1Test3-en1','klasgroep'),
    (4,'2324-1Test4-en2','klasgroep'),
    (5,'2324-1Test5-en3','klasgroep'),
    (6,'2324-1Test6-en4','klasgroep')
;

Insert Into magisterdocentenrooster ('docentid','teamid') values
    ('1','1'),
    ('1','4'),
    ('1','5'),
    ('1','6'),
    ('1','2'),
    ('2','2'),
    ('1','3')--,
    -- ('7','4')
;

Insert Into magisterleerlingenrooster ('leerlingid','teamid') values
   ('3','1'),
   ('4','1'),
   ('5','1'),
   ('3','4'),
   ('4','4'),
   ('5','4'),
   ('3','5'),
   ('4','5'),
   ('5','5'),
   ('4','2'),
   ('5','2'),
   ('6','2'),
   ('4','6'),
   ('5','6'),
   ('6','6'),
   ('3','3')--,
--    ('4','3')
;

-- Geen Azure gegevens in de database, geen van de teams is dus bekend
-- Docenten en leerlingen moeten wel bestaan