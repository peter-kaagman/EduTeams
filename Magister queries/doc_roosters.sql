-- query as of 22 jan 2023
Declare @periode varchar(4)='#lesperiode#'
SELECT DISTINCT
    sis_pers.stamnr AS stamnummer,
    sis_pers.E_Mailwerk AS email,
    sis_bgrp.groep as KlasGroep,
    sis_blok.c_lokatie as LocatieCode,
    sis_pgvk.c_vak
FROM sis_pgvk
    LEFT JOIN sis_pers on sis_pgvk.idPers=sis_pers.idPers
    LEFT JOIN sis_bgrp on sis_pgvk.idBgrp=sis_bgrp.idBgrp
    LEFT JOIN sis_blpe on sis_pgvk.lesperiode=sis_blpe.lesperiode --voor periode, zie de where
    -- LEFT JOIN sis_bvak on sis_pgvk.c_vak=sis_bvak.c_vak -- niet nodig lijkt wel
    LEFT JOIN sis_blok on sis_bgrp.c_lokatie=sis_blok.c_lokatie
WHERE 
    sis_blpe.lesperiode = @periode -- is er ook een andere tabel met periode
                                    -- of start- en 
                                    -- match op sis_blpe zorgt ervoor dat de vakken ook meekomen
                                    -- lesperiode staat ook in sis_pgvk, maar dan komer er alleen clusters


-- Updated versie 20250122
SELECT DISTINCT
    sis_pers.E_Mailwerk AS email,
    sis_blok.c_lokatie as LocatieCode,
    IIF(
      sis_bgrp.groep Like '%.%', 
      sis_blpe.lesperiode + '-' + sis_bgrp.groep,
      sis_blpe.lesperiode + '-' + sis_bgrp.groep + '-' +  sis_pgvk.c_vak     
    ) as team
FROM sis_pgvk
    LEFT JOIN sis_pers on sis_pgvk.idPers=sis_pers.idPers -- email
    LEFT JOIN sis_bgrp on sis_pgvk.idBgrp=sis_bgrp.idBgrp -- groepnaam
    LEFT JOIN sis_blpe on sis_pgvk.lesperiode=sis_blpe.lesperiode -- voor vakken
    LEFT JOIN sis_blok on sis_bgrp.c_lokatie=sis_blok.c_lokatie
WHERE 
    sis_blpe.lesperiode = 2425