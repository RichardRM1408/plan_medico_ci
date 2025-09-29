CREATE OR REPLACE TABLE `ci-datalake-dev.ci_dtlk_bqd_access_dev.TBL_ONCOLOGIA_MAMA_FASE4_TRATAMIENTO_QUIRURGICO` AS
SELECT 
  
  codigo_cliente, 
  epis_pk as NUM_ENCUENTRO,
  N_DOCUMENTO AS DNI,
  PACIENTE,
  DIAGNOSTICO, 
  -- Extracción de códigos
  REGEXP_EXTRACT(DIAGNOSTICO, r'DX Preoperatorio:\s*([A-Z0-9\.]+)') AS DX1,
  REGEXP_EXTRACT(DIAGNOSTICO, r'DX\s*Postoperatorio:\s*([A-Z0-9\.]+)') AS DX2,
  fecha_registro_form AS fecha_registro_form_original,
  FORMAT_DATE('%d/%m/%Y', fecha_registro_form) AS fecha_registro_form,
  FECHA_ACTUAL AS FECHA_ACTUAL_ORIGINAL,
  FORMAT_DATE(
    '%d/%m/%Y', 
    PARSE_DATE('%d/%m/%Y', TRIM(SPLIT(FECHA_ACTUAL, ',')[OFFSET(0)]))
  ) AS FECHA_ACTUAL

FROM `ci-datalake-dev.ci_dtlk_bqd_staging_dev_RNC.FORM_REPORTE_OPERATORIO`
WHERE 
  REGEXP_EXTRACT(DIAGNOSTICO, r'DX Preoperatorio:\s*([A-Z0-9\.]+)') IN ('C50.0','C50.1','C50.2','C50.3','C50.4','C50.5','C50.6','C50.8','C50.9','D05.0','D05.1','D05.7','D05.9')
  OR 
  REGEXP_EXTRACT(DIAGNOSTICO, r'DX\s*Postoperatorio:\s*([A-Z0-9\.]+)') IN ('C50.0','C50.1','C50.2','C50.3','C50.4','C50.5','C50.6','C50.8','C50.9','D05.0','D05.1','D05.7','D05.9');
