-- -- Huidige query
-- Declare @periode varchar(4)='#lesperiode#'
-- SELECT DISTINCT
--     sis_lvak.idleer AS id_leerling,
--     sis_lvak.stamnr AS stamnr,
--     sis_bgrp.groep AS groep,
--     sis_lvak.c_vak AS course
-- FROM sis_lvak
--     INNER JOIN sis_aanm ON sis_lvak.stamnr = sis_aanm.stamnr
--     INNER JOIN sis_bgrp ON sis_bgrp.idbgrp = sis_aanm.idbgrp
--     INNER JOIN sis_bvak ON sis_lvak.c_vak = sis_bvak.c_vak
-- WHERE
--     -- Poging om niet aktieve vakken te filteren
--     sis_aanm.idbgrp_v_grp Is Not null -- <- werkt niet
--     AND sis_lvak.dbegin <= GETDATE()
--     AND sis_lvak.deinde > GETDATE()
--     AND sis_aanm.lesperiode = @periode
-- ORDER BY 
--     sis_lvak.idleer

-- -- sis_aanm.idbgrp_v_grp is Null als de leerling niet
-- -- verhuisd is. Deze check werkt dus niet.

-- -- vakken
-- SELECT
--     'b' + cast(sis_lvak.stamnr AS varchar(6) ) AS b_nummer,
--     sis_bgrp.groep + '-' +  sis_lvak.c_vak AS code   
-- FROM sis_lvak
--     --JOIN sis_lvak On sis_lvak.stamnr = sis_leer.stamnr
--     INNER JOIN sis_aanm ON sis_lvak.stamnr = sis_aanm.stamnr
--     INNER JOIN sis_bgrp ON sis_bgrp.idbgrp = sis_aanm.idbgrp
--     INNER JOIN sis_bvak ON sis_lvak.c_vak = sis_bvak.c_vak
-- WHERE
--     sis_lvak.dbegin <= GETDATE()
--     AND sis_lvak.deinde > GETDATE()
--     AND sis_aanm.dBegin <= GETDATE()
--     AND sis_aanm.dEinde >= GETDATE()
--     AND (sis_lvak.stamnr = 140082 )
-- --ORDER BY  b_nummer, code

-- UNION

-- -- clusters
-- SELECT
--     --sis_lvak.idleer AS id_leerling,
--     'b' + cast(sis_lvak.stamnr AS varchar(6) ) AS b_nummer,
--     sis_bgrp.groep AS code
-- FROM sis_lvak
--     INNER JOIN sis_bgrp ON sis_lvak.idBgrp=sis_bgrp.idBgrp
--     -- INNER JOIN sis_bvak ON sis_lvak.c_vak = sis_bvak.c_vak
-- WHERE  
--   sis_lvak.dbegin <= GETDATE()
--   AND sis_lvak.deinde > GETDATE()
--   AND (sis_lvak.stamnr = 140082 OR sis_lvak.stamnr = 141028 )
-- --ORDER BY  sis_lvak.idleer



-- -- vakken met lesgroep
-- SELECT
--     'b' + cast(sis_lvak.stamnr AS varchar(6) ) AS b_nummer,
--     sis_bgrp.groep + '-' +  sis_lvak.c_vak AS code,
--     sis_lvak.idbgrp
-- FROM sis_lvak
--     --JOIN sis_lvak On sis_lvak.stamnr = sis_leer.stamnr
--     INNER JOIN sis_aanm ON sis_lvak.stamnr = sis_aanm.stamnr
--     INNER JOIN sis_bgrp ON sis_bgrp.idbgrp = sis_aanm.idbgrp
--     INNER JOIN sis_bvak ON sis_lvak.c_vak = sis_bvak.c_vak
-- WHERE
--     sis_lvak.dbegin <= GETDATE()
--     AND sis_lvak.deinde > GETDATE()
--     AND sis_aanm.dBegin <= GETDATE()
--     AND sis_aanm.dEinde >= GETDATE()
--     AND (sis_lvak.stamnr = 141028 )
-- --ORDER BY  b_nummer, code



-- #8 Dit doet het
-- vakken zonder lesgroep
Declare @periode varchar(4)='#lesperiode#'
SELECT
    'b' + cast(sis_lvak.stamnr AS varchar(6) ) AS b_nummer,
    @periode + '-' + sis_bgrp.groep + '-' +  sis_lvak.c_vak AS code
FROM sis_lvak
    --JOIN sis_lvak On sis_lvak.stamnr = sis_leer.stamnr
    INNER JOIN sis_aanm ON sis_lvak.stamnr = sis_aanm.stamnr
    INNER JOIN sis_bgrp ON sis_bgrp.idbgrp = sis_aanm.idbgrp
    INNER JOIN sis_bvak ON sis_lvak.c_vak = sis_bvak.c_vak
WHERE
    sis_lvak.dbegin <= GETDATE()
    AND sis_lvak.deinde > GETDATE()
    AND sis_aanm.dBegin <= GETDATE()
    AND sis_aanm.dEinde >= GETDATE()
    AND sis_lvak.idbgrp Is Null -- Er is geen cluster voor
    --AND (sis_lvak.stamnr = 141028 )
--ORDER BY  b_nummer, code  -- Order kan niet bij een Union?

UNION

-- clusters
SELECT
    --sis_lvak.idleer AS id_leerling,
    'b' + cast(sis_lvak.stamnr AS varchar(6) ) AS b_nummer,
    @periode + '-' + sis_bgrp.groep AS code
FROM sis_lvak
    INNER JOIN sis_bgrp ON sis_lvak.idBgrp=sis_bgrp.idBgrp
    -- INNER JOIN sis_bvak ON sis_lvak.c_vak = sis_bvak.c_vak
WHERE  
  sis_lvak.dbegin <= GETDATE()
  AND sis_lvak.deinde > GETDATE()
  --AND (sis_lvak.stamnr = 141028 )
--ORDER BY  sis_lvak.idleer -- Order kan niet bij een Union?