CREATE OR REPLACE TABLE `ci-datalake-dev.ci_dtlk_bqd_access_dev.TMP_KPI3_ONCOLOGIA_DE_MAMA` AS

-- =========================
-- KPI2 (biopsia → consulta previa)
-- =========================
WITH kpi2 AS (
  SELECT
    DNI,
    FH_INFORME_FINALIZADO,
    FCH_COMUNICACION_ALERTA,
    FEH_CITA,
    EDAD_PACIENTE,
    EDAD_GRUPO,
    NOM_SEDE,
    NOM_GARANTE_AGRUP,
    COD_GARANTE_AGRUP,
    ESPECIALIDAD,
    TIPO_MUESTRA_PRUEBA
  FROM `ci-datalake-dev.ci_dtlk_bqd_access_dev.TMP_KPI2_ONCOLOGIA_DE_MAMA`
),

-- =========================
-- Fase 3 (consultas) → PRIMERA consulta por paciente
-- =========================
fase3 AS (
  SELECT *
  FROM (
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
      f3.COD_GARANTE_AGRUP  AS COD_GARANTE_AGRUP_F3,
      f3.NOM_GARANTE_AGRUP  AS NOM_GARANTE_AGRUP_F3,
      f3.EDAD_PACIENTE  AS EDAD_PACIENTE_F3,
      f3.EDAD_GRUPO     AS EDAD_GRUPO_F3,
      ROW_NUMBER() OVER (
        PARTITION BY f3.DNI
        ORDER BY DATE(f3.FEH_CITA) ASC
      ) AS rn_f3
    FROM `ci-datalake-dev.ci_dtlk_bqd_access_dev.TBL_ONCOLOGIA_MAMA_FASE3_CONSULTA_ONCOLOGICA` f3
    WHERE f3.FEH_CITA IS NOT NULL
  )
  WHERE rn_f3 = 1   -- primera consulta
),

-- =========================
-- Fase 4Q (tratamiento quirúrgico) → todas las cirugías
-- =========================
fase4Q AS (
  SELECT
    q.DNI,
    PARSE_DATE('%d/%m/%Y', q.FECHA_ACTUAL) AS FCH_TRATAMIENTO_QUIRURGICO,
    q.NUM_ENCUENTRO,
    q.DIAGNOSTICO AS DX_QUIRURGICO
  FROM `ci-datalake-dev.ci_dtlk_bqd_access_dev.TBL_ONCOLOGIA_MAMA_FASE4_TRATAMIENTO_QUIRURGICO` q
  WHERE q.FECHA_ACTUAL IS NOT NULL
),

-- =========================
-- Prefactura (garantes para fase4Q)
-- =========================
prefac AS (
  SELECT
    CAST(p.NUM_ENCUENTRO AS STRING) AS ENCUENTRO_STR,
    p.COD_GARANTE_AGRUP,
    p.NOM_GARANTE_AGRUP,
    p.NOM_SEDE,
    p.DES_ESPECIALIDAD
  FROM `ci-datalake-prod.ci_dtlk_bqd_staging_prod.OD_PREFACTURA` p
),

-- =========================
-- A) Journey completo (KPI2 → primera consulta → primera cirugía posterior)
-- =========================
pares_kpi2 AS (
  SELECT
    k2.DNI,
    k2.FH_INFORME_FINALIZADO,
    k2.FCH_COMUNICACION_ALERTA,
    f3.FEH_CITA,
    f4.FCH_TRATAMIENTO_QUIRURGICO,
    f4.DX_QUIRURGICO,
    COALESCE(f3.ESPECIALIDAD_F3, k2.ESPECIALIDAD, p.DES_ESPECIALIDAD) AS ESPECIALIDAD,
    UPPER(COALESCE(f3.NOM_SEDE_F3, k2.NOM_SEDE, p.NOM_SEDE))          AS NOM_SEDE,
    COALESCE(f3.COD_GARANTE_AGRUP_F3, k2.COD_GARANTE_AGRUP, p.COD_GARANTE_AGRUP) AS COD_GARANTE_AGRUP,
    COALESCE(f3.NOM_GARANTE_AGRUP_F3, k2.NOM_GARANTE_AGRUP, p.NOM_GARANTE_AGRUP) AS NOM_GARANTE_AGRUP,
    k2.EDAD_PACIENTE,
    k2.EDAD_GRUPO,
    k2.TIPO_MUESTRA_PRUEBA,
    DATE_DIFF(f4.FCH_TRATAMIENTO_QUIRURGICO, f3.FEH_CITA, DAY) AS dias_diff,
    ROW_NUMBER() OVER (
      PARTITION BY k2.DNI
      ORDER BY f4.FCH_TRATAMIENTO_QUIRURGICO ASC
    ) AS rn_post
  FROM kpi2 k2
  JOIN fase3 f3
    ON k2.DNI = f3.DNI
  JOIN fase4Q f4
    ON k2.DNI = f4.DNI
   AND f4.FCH_TRATAMIENTO_QUIRURGICO >= f3.FEH_CITA
  LEFT JOIN prefac p
    ON CAST(f4.NUM_ENCUENTRO AS STRING) = p.ENCUENTRO_STR
),
final_kpi2 AS (
  SELECT
    'CONSULTA_A_TRATAMIENTO_QUIRURGICO' AS kpi_nombre,
    30 AS meta_dias,
    EXTRACT(YEAR  FROM FCH_TRATAMIENTO_QUIRURGICO) AS anio,
    EXTRACT(MONTH FROM FCH_TRATAMIENTO_QUIRURGICO) AS mes,
    FORMAT_DATE('%Y-%m', FCH_TRATAMIENTO_QUIRURGICO) AS anio_mes,
    DNI,
    EDAD_PACIENTE,
    EDAD_GRUPO,
    FH_INFORME_FINALIZADO,
    FCH_COMUNICACION_ALERTA,
    FEH_CITA,
    FCH_TRATAMIENTO_QUIRURGICO,
    CAST(NULL AS DATE)   AS FCH_TRATAMIENTO_NO_QUIRURGICO,
    DX_QUIRURGICO,
    CAST(NULL AS STRING) AS TIPO_TRATAMIENTO_NO_QUIRURGICO,
    NOM_SEDE,
    NOM_GARANTE_AGRUP,
    COD_GARANTE_AGRUP,
    ESPECIALIDAD,
    dias_diff,
    CURRENT_DATETIME('America/Lima') AS FH_ULTIMA_ACTUALIZACION,
    TIPO_MUESTRA_PRUEBA
  FROM pares_kpi2
  WHERE rn_post = 1   -- primera cirugía posterior a la primera consulta
),

-- =========================
-- B) Journey abierto (primera consulta → primera cirugía posterior, sin KPI2)
-- =========================
dni_con_kpi2 AS (
  SELECT DISTINCT DNI FROM kpi2
),
pares_directo AS (
  SELECT
    f3.DNI,
    CAST(NULL AS DATE) AS FH_INFORME_FINALIZADO,
    CAST(NULL AS DATE) AS FCH_COMUNICACION_ALERTA,
    f3.FEH_CITA,
    f4.FCH_TRATAMIENTO_QUIRURGICO,
    f4.DX_QUIRURGICO,
    COALESCE(f3.ESPECIALIDAD_F3, p.DES_ESPECIALIDAD) AS ESPECIALIDAD,
    UPPER(COALESCE(f3.NOM_SEDE_F3, p.NOM_SEDE))      AS NOM_SEDE,
    p.COD_GARANTE_AGRUP,
    p.NOM_GARANTE_AGRUP,
    f3.EDAD_PACIENTE_F3 AS EDAD_PACIENTE,
    f3.EDAD_GRUPO_F3    AS EDAD_GRUPO,
    CAST(NULL AS STRING) AS TIPO_MUESTRA_PRUEBA,
    DATE_DIFF(f4.FCH_TRATAMIENTO_QUIRURGICO, f3.FEH_CITA, DAY) AS dias_diff,
    ROW_NUMBER() OVER (
      PARTITION BY f3.DNI
      ORDER BY f4.FCH_TRATAMIENTO_QUIRURGICO ASC
    ) AS rn_post
  FROM fase3 f3
  JOIN fase4Q f4
    ON f3.DNI = f4.DNI
   AND f4.FCH_TRATAMIENTO_QUIRURGICO >= f3.FEH_CITA
  LEFT JOIN prefac p
    ON CAST(f4.NUM_ENCUENTRO AS STRING) = p.ENCUENTRO_STR
  LEFT JOIN dni_con_kpi2 k
    ON k.DNI = f3.DNI
  WHERE k.DNI IS NULL
),
final_directo AS (
  SELECT
    'CONSULTA_A_TRATAMIENTO_QUIRURGICO' AS kpi_nombre,
    30 AS meta_dias,
    EXTRACT(YEAR  FROM FCH_TRATAMIENTO_QUIRURGICO) AS anio,
    EXTRACT(MONTH FROM FCH_TRATAMIENTO_QUIRURGICO) AS mes,
    FORMAT_DATE('%Y-%m', FCH_TRATAMIENTO_QUIRURGICO) AS anio_mes,
    DNI,
    EDAD_PACIENTE,
    EDAD_GRUPO,
    FH_INFORME_FINALIZADO,
    FCH_COMUNICACION_ALERTA,
    FEH_CITA,
    FCH_TRATAMIENTO_QUIRURGICO,
    CAST(NULL AS DATE)   AS FCH_TRATAMIENTO_NO_QUIRURGICO,
    DX_QUIRURGICO,
    CAST(NULL AS STRING) AS TIPO_TRATAMIENTO_NO_QUIRURGICO,
    NOM_SEDE,
    NOM_GARANTE_AGRUP,
    COD_GARANTE_AGRUP,
    ESPECIALIDAD,
    dias_diff,
    CURRENT_DATETIME('America/Lima') AS FH_ULTIMA_ACTUALIZACION,
    TIPO_MUESTRA_PRUEBA
  FROM pares_directo
  WHERE rn_post = 1   -- primera cirugía posterior a la primera consulta
)

-- =========================
-- Unión final
-- =========================
SELECT * FROM final_kpi2
UNION ALL
SELECT * FROM final_directo;
