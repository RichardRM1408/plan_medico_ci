CREATE OR REPLACE TABLE `ci-datalake-dev.ci_dtlk_bqd_access_dev.TBL_ONCOLOGIA_MAMA_FASE4_TRATAMIENTO_NO_QUIRURGICO` AS

-- ==========================
-- QUIMIOTERAPIA
-- ==========================
SELECT 
    CAST(a.CODIGO_CLIENTE AS STRING)              AS CODIGO_CLIENTE,
    a.N_DOCUMENTO                                 AS DNI,
    a.fecha_registro_form                         AS FECHA_TRATAMIENTO,
    'QUIMIOTERAPIA'                               AS TIPO_TRATAMIENTO_NO_QUIRURGICO,
    -- columnas específicas
    --DIAGNOSTICO_ESQUEMA_QUIMIOTERAPIA             AS DIAGNOSTICO_TRATAMIENTO_NO_QUIRURGICO,
    a.NOMBRE_ESQUEMA_TERAPEUTICO                    AS DESCRIPCION_TRATAMIENTO_NO_QUIRURGICO,
   
FROM `ci-datalake-dev.ci_dtlk_bqd_staging_dev_RNC.FORM_ADMINISTRACION_QUIMIOTERAPIA_ENFERMERIA` a
WHERE a.AMBITO IN ('Ambulatorio', 'Hospitalario')

UNION ALL

-- ==========================
-- HORMONOTERAPIA
-- ==========================
SELECT 
    CAST(a.COD_PACIENTE AS STRING)                AS CODIGO_CLIENTE,
    cl.CODIGO1                                    AS DNI,
    DATE(a.FEH_PRESTACION_SERVICIO)               AS FECHA_TRATAMIENTO,
    'HORMONOTERAPIA'                              AS TIPO_TRATAMIENTO_NO_QUIRURGICO,
    -- columnas específicas
    --A.DES_DIAGNOSTICO_01                          AS DIAGNOSTICO_TRATAMIENTO_NO_QUIRURGICO,
    a.DES_PRESTACION                              AS DESCRIPCION_TRATAMIENTO_NO_QUIRURGICO,

FROM `ci-datalake-prod.ci_dtlk_bqd_staging_prod.OD_PREF_DETALLE_SERVICIO` a
LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_CLIENTES_acc` cl
  ON CAST(a.COD_PACIENTE AS STRING) = CAST(cl.CODIGO_CLIENTE AS STRING)
WHERE a.FEH_INGRESO >= DATE "2024-01-01"
  AND a.COD_PRESTACION IN (
    '2000098689','2000095351','2000087789','2000098411','2000096205',
    '2000083133','2000061991','2000087108','2000088513','2000095282',
    '2000011756','2000094683','2000088138','2000048918','2000040581',
    '2000048208','2000099339','2000088118','2000062107','2000049745',
    '2000098083','2000040476','2000054271','2000013501','2000054118',
    '2000043326','2000050253','2000054241','2000096802','2000096176',
    '2000052790','2000094081','2000059071','2000054108','2000054139',
    '2000050168','2000052233','2000051277','2000047731','2000047295',
    '2000043434','2000062269','2000063309','20000631'
  )
  AND a.COD_APLICATIVO IN ('XHIS6','XHIS5')

UNION ALL

-- ==========================
-- TERAPIA BIOLÓGICA
-- ==========================
SELECT 
    CAST(HP.CODIGO_CLIENTE AS STRING)             AS CODIGO_CLIENTE,
    cl.CODIGO1                                    AS DNI,
    DATE(HP.FECHA_REG)                            AS FECHA_TRATAMIENTO,
    'TERAPIA BIOLOGICA'                           AS TIPO_TRATAMIENTO_NO_QUIRURGICO,
    -- columnas específicas
    --A.DES_DIAGNOSTICO_01                          AS DIAGNOSTICO_TRATAMIENTO_NO_QUIRURGICO,
    PM.NOMBRE                                     AS DESCRIPCION_TRATAMIENTO_NO_QUIRURGICO,


FROM `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_HOJA_PROT_acc` HP
LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_CLIENTES_acc` cl
  ON CAST(HP.CODIGO_CLIENTE AS STRING) = CAST(cl.CODIGO_CLIENTE AS STRING)
INNER JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_PROT_MEDICO_acc` PM 
  ON PM.PROT_MEDICO_PK = HP.PROT_MEDICO_PK
INNER JOIN `ci-analytics-dev.ci_iagreda_bqd_business_dev.protocolo_tipo_tratamiento_rnc` PRO 
  ON TRIM(PM.NOMBRE) = TRIM(PRO.PROTOCOLO)
WHERE PRO.TIPO = 'Terapia Biológica'

UNION ALL

-- ==========================
-- INMUNOTERAPIA
-- ==========================
SELECT 
    CAST(HP.CODIGO_CLIENTE AS STRING) AS CODIGO_CLIENTE,
    cl.CODIGO1 AS DNI,
    DATE(HP.FECHA_REG) AS FECHA_TRATAMIENTO,
    'INMUNOTERAPIA' AS TIPO_TRATAMIENTO_NO_QUIRURGICO,
    -- columnas específicas
    --A.DES_DIAGNOSTICO_01                          AS DIAGNOSTICO_TRATAMIENTO_NO_QUIRURGICO,
    PM.NOMBRE                                     AS DESCRIPCION_TRATAMIENTO_NO_QUIRURGICO,

FROM `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_HOJA_PROT_acc` HP
LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_CLIENTES_acc` cl
  ON CAST(HP.CODIGO_CLIENTE AS STRING) = CAST(cl.CODIGO_CLIENTE AS STRING)
INNER JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_PROT_MEDICO_acc` PM 
  ON PM.PROT_MEDICO_PK = HP.PROT_MEDICO_PK
INNER JOIN `ci-analytics-dev.ci_iagreda_bqd_business_dev.protocolo_tipo_tratamiento_rnc` PRO 
  ON TRIM(PM.NOMBRE) = TRIM(PRO.PROTOCOLO)
WHERE PRO.TIPO = 'Inmunoterapia';
