CREATE OR REPLACE VIEW `ci-datalake-dev.ci_dtlk_bqd_access_dev.VW_ONCOLOGIA_MAMA_KPIS` AS
-- FLAG DE JOURNEY COMPLETO
WITH journey AS (
  SELECT *
  FROM `ci-datalake-dev.ci_dtlk_bqd_access_dev.TBL_ONCOLOGIA_MAMA_JOURNEY`
),
flags AS (
  SELECT
    DNI,
    MAX(CASE WHEN kpi_nombre = 'MAMOGRAFIA_A_BIOPSIA' THEN 1 ELSE 0 END) AS has_kpi1,
    MAX(CASE WHEN kpi_nombre = 'BIOPSIA_A_CONSULTA_EXTERNA' THEN 1 ELSE 0 END) AS has_kpi2,
    MAX(CASE WHEN kpi_nombre = 'CONSULTA_A_TRATAMIENTO_QUIRURGICO' THEN 1 ELSE 0 END) AS has_kpi3,
    MAX(CASE WHEN kpi_nombre = 'CONSULTA_A_TRATAMIENTO_NO_QUIRURGICO' THEN 1 ELSE 0 END) AS has_kpi4
  FROM journey
  GROUP BY DNI
),
journey_flagged AS (
  SELECT
    j.*,
    CASE 
      WHEN f.has_kpi1 = 1 
       AND f.has_kpi2 = 1 
       AND (f.has_kpi3 = 1 OR f.has_kpi4 = 1)
      THEN 1 ELSE 0
    END AS FLAG_JOURNEY_COMPLETO
  FROM journey j
  LEFT JOIN flags f
    ON j.DNI = f.DNI
)
SELECT * 
FROM journey_flagged;
