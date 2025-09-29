CREATE OR REPLACE TABLE `ci-datalake-dev.ci_dtlk_bqd_access_dev.TMP_KPI2_ONCOLOGIA_DE_MAMA` AS

-- =========================
-- KPI1 (journey completo: mamografía → alerta)
-- =========================
WITH kpi1 AS (
   SELECT *
  FROM (
    SELECT
      DNI,
      FH_INFORME_FINALIZADO,
      FCH_COMUNICACION_ALERTA,
      EDAD_PACIENTE,
      EDAD_GRUPO,
      NOM_SEDE,
      NOM_GARANTE_AGRUP,
      COD_GARANTE_AGRUP,
      ESPECIALIDAD,
      TIPO_MUESTRA_PRUEBA,
      ROW_NUMBER() OVER (
        PARTITION BY DNI
        ORDER BY FCH_COMUNICACION_ALERTA ASC
      ) AS rn
    FROM `ci-datalake-dev.ci_dtlk_bqd_access_dev.TMP_KPI1_ONCOLOGIA_DE_MAMA`
  )
  WHERE rn = 1   -- primera alerta por paciente
),

-- =========================
-- Fase 3 (consultas)
-- =========================
fase3 AS (
  SELECT
    f3.DNI,
    CASE
      WHEN REGEXP_CONTAINS(CAST(f3.FEH_CITA AS STRING), r'^\d{2}/\d{2}/\d{4}$')
        THEN PARSE_DATE('%d/%m/%Y', CAST(f3.FEH_CITA AS STRING))
      ELSE DATE(f3.FEH_CITA)
    END AS FEH_CITA,
    f3.ESPECIALIDAD   AS ESPECIALIDAD_F3,
    f3.SEDE           AS NOM_SEDE_F3,
    f3.ENCUENTRO      AS ENCUENTRO_F3,
    f3.EDAD_PACIENTE  AS EDAD_PACIENTE_F3,
    f3.EDAD_GRUPO     AS EDAD_GRUPO_F3
  FROM `ci-datalake-dev.ci_dtlk_bqd_access_dev.TBL_ONCOLOGIA_MAMA_FASE3_CONSULTA_ONCOLOGICA` f3
  WHERE f3.FEH_CITA IS NOT NULL
),

-- =========================
-- Prefactura (garantes)
-- =========================
prefac AS (
  SELECT
    CAST(p.NUM_ENCUENTRO AS STRING) AS ENCUENTRO_STR,
    p.COD_GARANTE_AGRUP,
    p.NOM_GARANTE_AGRUP
  FROM `ci-datalake-prod.ci_dtlk_bqd_staging_prod.OD_PREFACTURA` p
),

-- =========================
-- Fase 2 (alertas)
-- =========================
fase2 AS (
  SELECT *
  FROM (
    SELECT
      f2.DNI_PCTE AS DNI,
      DATE(f2.FCH_COMUNICACION_ALERTA) AS FCH_COMUNICACION_ALERTA,
      f2.TIPO_MUESTRA_PRUEBA,
      ROW_NUMBER() OVER (
        PARTITION BY f2.DNI_PCTE
        ORDER BY DATE(f2.FCH_COMUNICACION_ALERTA) ASC
      ) AS rn
    FROM `ci-datalake-dev.ci_dtlk_bqd_access_dev.TBL_ONCOLOGIA_MAMA_FASE2_ALERTA_POSITIVO` f2
    WHERE f2.FCH_COMUNICACION_ALERTA IS NOT NULL
  )
  WHERE rn = 1   --  primera alerta por paciente
),

-- =========================
-- A) Journey completo (F1 → F2 → F3)
-- =========================
pares_kpi1 AS (
  SELECT
    k1.DNI,
    k1.FH_INFORME_FINALIZADO,
    k1.FCH_COMUNICACION_ALERTA,
    f3.FEH_CITA,
    COALESCE(f3.ESPECIALIDAD_F3, k1.ESPECIALIDAD) AS ESPECIALIDAD,
    UPPER(COALESCE(f3.NOM_SEDE_F3, k1.NOM_SEDE))  AS NOM_SEDE,
    COALESCE(k1.COD_GARANTE_AGRUP, p.COD_GARANTE_AGRUP) AS COD_GARANTE_AGRUP,
    COALESCE(k1.NOM_GARANTE_AGRUP, p.NOM_GARANTE_AGRUP) AS NOM_GARANTE_AGRUP,
    COALESCE(f3.EDAD_PACIENTE_F3, k1.EDAD_PACIENTE) AS EDAD_PACIENTE,
    COALESCE(f3.EDAD_GRUPO_F3, k1.EDAD_GRUPO)       AS EDAD_GRUPO,
    k1.TIPO_MUESTRA_PRUEBA,
    DATE_DIFF(f3.FEH_CITA, k1.FCH_COMUNICACION_ALERTA, DAY) AS dias_diff
  FROM kpi1 k1
  JOIN fase3 f3
    ON k1.DNI = f3.DNI
   AND f3.FEH_CITA >= k1.FCH_COMUNICACION_ALERTA
  LEFT JOIN prefac p
    ON CAST(f3.ENCUENTRO_F3 AS STRING) = p.ENCUENTRO_STR
  QUALIFY
    -- forward: alerta → primera consulta posterior
    ROW_NUMBER() OVER (
      PARTITION BY k1.DNI, k1.FCH_COMUNICACION_ALERTA
      ORDER BY f3.FEH_CITA ASC
    ) = 1
    AND
    -- back-link: consulta → alerta más cercana previa
    ROW_NUMBER() OVER (
      PARTITION BY k1.DNI, f3.FEH_CITA
      ORDER BY DATE_DIFF(f3.FEH_CITA, k1.FCH_COMUNICACION_ALERTA, DAY) ASC
    ) = 1
),
final_kpi1 AS (
  SELECT
    'BIOPSIA_A_CONSULTA_EXTERNA' AS kpi_nombre,
    7 AS meta_dias,
    EXTRACT(YEAR  FROM FEH_CITA) AS anio,
    EXTRACT(MONTH FROM FEH_CITA) AS mes,
    FORMAT_DATE('%Y-%m', FEH_CITA) AS anio_mes,
    DNI,
    EDAD_PACIENTE,
    EDAD_GRUPO,
    FH_INFORME_FINALIZADO,
    FCH_COMUNICACION_ALERTA,
    FEH_CITA,
    CAST(NULL AS DATE)   AS FCH_TRATAMIENTO_QUIRURGICO,
    CAST(NULL AS DATE)   AS FCH_TRATAMIENTO_NO_QUIRURGICO,
    CAST(NULL AS STRING) AS DX_QUIRURGICO,
    CAST(NULL AS STRING) AS TIPO_TRATAMIENTO_NO_QUIRURGICO,
    NOM_SEDE,
    NOM_GARANTE_AGRUP,
    COD_GARANTE_AGRUP,
    ESPECIALIDAD,
    dias_diff,
    CURRENT_DATETIME('America/Lima') AS FH_ULTIMA_ACTUALIZACION,
    TIPO_MUESTRA_PRUEBA
  FROM pares_kpi1
),

-- =========================
-- B) Journey abierto (F2 → F3 sin pasar por KPI1)
-- =========================
dni_con_kpi1 AS (
  SELECT DISTINCT DNI FROM kpi1
),
pares_directo AS (
  SELECT
    f2.DNI,
    CAST(NULL AS DATE) AS FH_INFORME_FINALIZADO,
    f2.FCH_COMUNICACION_ALERTA,
    f3.FEH_CITA,
    COALESCE(f3.ESPECIALIDAD_F3, CAST(NULL AS STRING)) AS ESPECIALIDAD,
    UPPER(f3.NOM_SEDE_F3) AS NOM_SEDE,
    p.COD_GARANTE_AGRUP,
    p.NOM_GARANTE_AGRUP,
    f3.EDAD_PACIENTE_F3 AS EDAD_PACIENTE,
    f3.EDAD_GRUPO_F3    AS EDAD_GRUPO,
    f2.TIPO_MUESTRA_PRUEBA,
    DATE_DIFF(f3.FEH_CITA, f2.FCH_COMUNICACION_ALERTA, DAY) AS dias_diff
  FROM fase2 f2
  JOIN fase3 f3
    ON f2.DNI = f3.DNI
   AND f3.FEH_CITA >= f2.FCH_COMUNICACION_ALERTA
  LEFT JOIN prefac p
    ON CAST(f3.ENCUENTRO_F3 AS STRING) = p.ENCUENTRO_STR
  LEFT JOIN dni_con_kpi1 k
    ON k.DNI = f2.DNI
  WHERE k.DNI IS NULL
  QUALIFY
    -- forward: alerta → primera consulta posterior
    ROW_NUMBER() OVER (
      PARTITION BY f2.DNI, f2.FCH_COMUNICACION_ALERTA
      ORDER BY f3.FEH_CITA ASC
    ) = 1
    AND
    -- back-link: consulta → alerta más cercana previa
    ROW_NUMBER() OVER (
      PARTITION BY f2.DNI, f3.FEH_CITA
      ORDER BY DATE_DIFF(f3.FEH_CITA, f2.FCH_COMUNICACION_ALERTA, DAY) ASC
    ) = 1
),
final_directo AS (
  SELECT
    'BIOPSIA_A_CONSULTA_EXTERNA' AS kpi_nombre,
    7 AS meta_dias,
    EXTRACT(YEAR  FROM FEH_CITA) AS anio,
    EXTRACT(MONTH FROM FEH_CITA) AS mes,
    FORMAT_DATE('%Y-%m', FEH_CITA) AS anio_mes,
    DNI,
    EDAD_PACIENTE,
    EDAD_GRUPO,
    FH_INFORME_FINALIZADO,  -- siempre NULL aquí
    FCH_COMUNICACION_ALERTA,
    FEH_CITA,
    CAST(NULL AS DATE)   AS FCH_TRATAMIENTO_QUIRURGICO,
    CAST(NULL AS DATE)   AS FCH_TRATAMIENTO_NO_QUIRURGICO,
    CAST(NULL AS STRING) AS DX_QUIRURGICO,
    CAST(NULL AS STRING) AS TIPO_TRATAMIENTO_NO_QUIRURGICO,
    NOM_SEDE,
    NOM_GARANTE_AGRUP,
    COD_GARANTE_AGRUP,
    ESPECIALIDAD,
    dias_diff,
    CURRENT_DATETIME('America/Lima') AS FH_ULTIMA_ACTUALIZACION,
    TIPO_MUESTRA_PRUEBA
  FROM pares_directo
)

-- =========================
-- Unión final
-- =========================
SELECT * FROM final_kpi1
UNION ALL
SELECT * FROM final_directo;
