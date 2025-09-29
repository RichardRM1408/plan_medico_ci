CREATE OR REPLACE TABLE `ci-datalake-dev.ci_dtlk_bqd_access_dev.TBL_ONCOLOGIA_MAMA_JOURNEY` AS
SELECT * FROM `ci-datalake-dev.ci_dtlk_bqd_access_dev.TMP_KPI1_ONCOLOGIA_DE_MAMA`
UNION ALL
SELECT * FROM `ci-datalake-dev.ci_dtlk_bqd_access_dev.TMP_KPI2_ONCOLOGIA_DE_MAMA`
UNION ALL
SELECT * FROM `ci-datalake-dev.ci_dtlk_bqd_access_dev.TMP_KPI3_ONCOLOGIA_DE_MAMA`
UNION ALL
SELECT * FROM `ci-datalake-dev.ci_dtlk_bqd_access_dev.TMP_KPI4_ONCOLOGIA_DE_MAMA`;


CREATE OR REPLACE TABLE `ci-datalake-dev.ci_dtlk_bqd_access_dev.TBL_ONCOLOGIA_MAMA_JOURNEY` AS
WITH base AS (
  SELECT *
  FROM `ci-datalake-dev.ci_dtlk_bqd_access_dev.TBL_ONCOLOGIA_MAMA_JOURNEY`
),
--  primera consulta válida (posterior a la alerta)
primera_consulta AS (
  SELECT
    DNI,
    MIN(FEH_CITA) AS FEH_CITA_VALIDA
  FROM base
  WHERE FEH_CITA IS NOT NULL
    AND FCH_COMUNICACION_ALERTA IS NOT NULL
    AND FEH_CITA >= FCH_COMUNICACION_ALERTA
  GROUP BY DNI
)
SELECT
  b.kpi_nombre,
  b.meta_dias,
  b.anio,
  b.mes,
  b.anio_mes,
  b.DNI,
  b.EDAD_PACIENTE,
  b.EDAD_GRUPO,
  b.FH_INFORME_FINALIZADO,
  b.FCH_COMUNICACION_ALERTA,

  CASE
    WHEN b.kpi_nombre IN ('CONSULTA_A_TRATAMIENTO_QUIRURGICO','CONSULTA_A_TRATAMIENTO_NO_QUIRURGICO')
         AND (b.FEH_CITA IS NULL OR b.FEH_CITA < b.FCH_COMUNICACION_ALERTA)
      THEN pc.FEH_CITA_VALIDA
    ELSE b.FEH_CITA
  END AS FEH_CITA,
  b.FCH_TRATAMIENTO_QUIRURGICO,
  b.FCH_TRATAMIENTO_NO_QUIRURGICO,
  b.DX_QUIRURGICO,
  b.TIPO_TRATAMIENTO_NO_QUIRURGICO AS DESCRIPCION_TRATAMIENTO_NO_QUIRURGICO,
  b.NOM_SEDE,
  b.NOM_GARANTE_AGRUP,
  b.COD_GARANTE_AGRUP,
  b.ESPECIALIDAD,
  
  CASE
    WHEN b.kpi_nombre IN ('CONSULTA_A_TRATAMIENTO_QUIRURGICO','CONSULTA_A_TRATAMIENTO_NO_QUIRURGICO')
         AND (b.FEH_CITA IS NULL OR b.FEH_CITA < b.FCH_COMUNICACION_ALERTA)
      THEN DATE_DIFF(
             COALESCE(b.FCH_TRATAMIENTO_QUIRURGICO, b.FCH_TRATAMIENTO_NO_QUIRURGICO),
             COALESCE(pc.FEH_CITA_VALIDA, b.FCH_COMUNICACION_ALERTA),
             DAY
           )
    ELSE b.dias_diff
  END AS dias_diff,
  b.FH_ULTIMA_ACTUALIZACION,
  b.TIPO_MUESTRA_PRUEBA
FROM base b
LEFT JOIN primera_consulta pc
  ON b.DNI = pc.DNI;


----

-- aGREGADO 29/09/2025 - Ajuste por paciente solo debe quedar o bien TRAT QUIRU O NO QUIRUR SE QUEDA MAS ANTIGUO
MERGE INTO `ci-datalake-dev.ci_dtlk_bqd_access_dev.TBL_ONCOLOGIA_MAMA_JOURNEY` AS T
USING (
    WITH RANKED_ROWS AS (
        SELECT
            DNI,
            kpi_nombre,
            FCH_TRATAMIENTO_QUIRURGICO,
            FCH_TRATAMIENTO_NO_QUIRURGICO,
            ROW_NUMBER() OVER(
                PARTITION BY DNI
                ORDER BY
                    CASE
                        WHEN kpi_nombre = 'CONSULTA_A_TRATAMIENTO_QUIRURGICO' THEN FCH_TRATAMIENTO_QUIRURGICO
                        WHEN kpi_nombre = 'CONSULTA_A_TRATAMIENTO_NO_QUIRURGICO' THEN FCH_TRATAMIENTO_NO_QUIRURGICO
                        ELSE NULL
                    END DESC NULLS LAST
            ) AS rn
        FROM `ci-datalake-dev.ci_dtlk_bqd_access_dev.TBL_ONCOLOGIA_MAMA_JOURNEY`
        WHERE kpi_nombre IN ('CONSULTA_A_TRATAMIENTO_QUIRURGICO', 'CONSULTA_A_TRATAMIENTO_NO_QUIRURGICO')
    ),

    ROWS_TO_DELETE AS (
        SELECT
            r.DNI,
            r.kpi_nombre,
            r.FCH_TRATAMIENTO_QUIRURGICO,
            r.FCH_TRATAMIENTO_NO_QUIRURGICO
        FROM RANKED_ROWS AS r
        INNER JOIN (
            SELECT DNI
            FROM `ci-datalake-dev.ci_dtlk_bqd_access_dev.TBL_ONCOLOGIA_MAMA_JOURNEY`
            WHERE kpi_nombre IN ('CONSULTA_A_TRATAMIENTO_QUIRURGICO', 'CONSULTA_A_TRATAMIENTO_NO_QUIRURGICO')
            GROUP BY DNI
            HAVING COUNT(DISTINCT kpi_nombre) = 2
        ) AS dca ON r.DNI = dca.DNI
        WHERE r.rn = 1 
    )

    SELECT * FROM ROWS_TO_DELETE
) AS S ON
    T.DNI = S.DNI
    AND T.kpi_nombre = S.kpi_nombre
    AND COALESCE(T.FCH_TRATAMIENTO_QUIRURGICO, T.FCH_TRATAMIENTO_NO_QUIRURGICO) = COALESCE(S.FCH_TRATAMIENTO_QUIRURGICO, S.FCH_TRATAMIENTO_NO_QUIRURGICO)
WHEN MATCHED THEN
    DELETE