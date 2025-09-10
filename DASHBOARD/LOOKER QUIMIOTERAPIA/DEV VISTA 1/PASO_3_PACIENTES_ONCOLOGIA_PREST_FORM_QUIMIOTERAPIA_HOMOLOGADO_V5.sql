CREATE OR REPLACE TABLE `ci-datalake-dev.ci_dtlk_bqd_business_dev.PACIENTES_ONCOLOGIA_PREST_FORM_QUIMIOTERAPIA_HOMOLOGADO` AS

WITH origen AS (
  SELECT
    o.*,

    -- Fechas como DATE
     PARSE_TIMESTAMP('%d/%m/%Y', FECHA_ATENCION) AS FECHA_ATENCION_TS,
    PARSE_TIMESTAMP('%d/%m/%Y', Fecha_Actual)   AS FECHA_ACTUAL_TS,

    REGEXP_REPLACE(
  UPPER(
    REGEXP_REPLACE(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            REGEXP_REPLACE(
              REPLACE(REPLACE(REPLACE(TRIM(HORA_INICIO_QUIMIOTERAPIA),
                                      ';', ':'), '_', ':'), '.', ':' ),
              r'\s*:\s*', ':'
            ),
            r':+', ':'
          ),
          r'^\s*([0-9]{1,2})\s*:\s*$', r'\1'
        ),
        r'(?i)\bA\.?\s*M\.?\b', 'AM'
      ),
      r'(?i)\bP\.?\s*M\.?\b', 'PM'
    )
  ),
  r'(?i)\bM\b', 'PM'
) AS clean_ini,


    -- Limpieza/normalización de hora de término
 REGEXP_REPLACE(
  UPPER(
    REGEXP_REPLACE(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            REGEXP_REPLACE(
              REPLACE(REPLACE(REPLACE(TRIM(HORA_TERMINO_QUIMIOTERAPIA),
                                      ';', ':'), '_', ':'), '.', ':' ),
              r'\s*:\s*', ':'
            ),
            r':+', ':'
          ),
          r'^\s*([0-9]{1,2})\s*:\s*$', r'\1'
        ),
        r'(?i)\bA\.?\s*M\.?\b', 'AM'
      ),
      r'(?i)\bP\.?\s*M\.?\b', 'PM'
    )
  ),
  r'(?i)\bM\b', 'PM'
) AS clean_fin,


  FROM `ci-datalake-dev.ci_dtlk_bqd_business_dev.PACIENTES_ONCOLOGIA_PREST_FORM_QUIMIOTERAPIA` o
),

base AS (
  SELECT
    * EXCEPT(clean_ini, clean_fin),

    -- Hora inicio homologada
    CASE
      WHEN REGEXP_CONTAINS(UPPER(TRIM(HORA_INICIO_QUIMIOTERAPIA)),
           r'(?i)\b(0\.715277778|0\.902777778|INF\.?\s*CONT(INUA)?|CONT(INUA)?|CONTINUA|INFUSION\s+DE\s+46HRS?\.?|46\s*(HRS?|HRAS?|HORAS?)|48\s*(HRS?|HRAS?|HORAS?)|24\s*(HRS?|HRAS?|HORAS?))\b')
      THEN 'ERROR: DATO FORM'
      ELSE FORMAT_TIME(
        '%H:%M',
        CASE
          WHEN clean_ini IN ('24','24:00','2400')                          THEN TIME '00:00:00'
          WHEN REGEXP_CONTAINS(clean_ini, r'^00AM$')                       THEN TIME '00:00:00'  -- fix medianoche
          WHEN REGEXP_CONTAINS(clean_ini, r'^\d{1,2}$')                    THEN SAFE.PARSE_TIME('%H', clean_ini)
          WHEN REGEXP_CONTAINS(clean_ini, r'^\d{3,4}$')                    THEN SAFE.PARSE_TIME('%H%M', LPAD(clean_ini, 4, '0'))
          WHEN REGEXP_CONTAINS(clean_ini, r'^\d{3,4}(AM|PM)$')             THEN SAFE.PARSE_TIME('%I%M%p', clean_ini)
          WHEN REGEXP_CONTAINS(clean_ini, r'^\d{1,2}(AM|PM)$')             THEN SAFE.PARSE_TIME('%I%p', clean_ini)
          WHEN REGEXP_CONTAINS(clean_ini, r'^\d{1,2}:[0-5][0-9](AM|PM)$')  THEN SAFE.PARSE_TIME('%I:%M%p', clean_ini)
          WHEN REGEXP_CONTAINS(clean_ini, r'^(1[3-9]|2[0-3])$')            THEN SAFE.PARSE_TIME('%H', clean_ini)
          WHEN REGEXP_CONTAINS(clean_ini, r'^(1[3-9]|2[0-3]):[0-5][0-9]$') THEN SAFE.PARSE_TIME('%H:%M', clean_ini)
          WHEN REGEXP_CONTAINS(clean_ini, r'^(1[3-9]|2[0-3])(AM|PM)$')     THEN SAFE.PARSE_TIME('%H', REGEXP_REPLACE(clean_ini,'(AM|PM)$',''))
          WHEN REGEXP_CONTAINS(clean_ini, r'^(1[3-9]|2[0-3]):[0-5][0-9](AM|PM)$')
                                                                           THEN SAFE.PARSE_TIME('%H:%M', REGEXP_REPLACE(clean_ini,'(AM|PM)$',''))
          WHEN REGEXP_CONTAINS(clean_ini, r'^12M$')                        THEN TIME '12:00:00'
          WHEN REGEXP_CONTAINS(clean_ini, r'^12:[0-5][0-9]M$')             THEN SAFE.PARSE_TIME('%I:%M%p', REGEXP_REPLACE(clean_ini,'M$','PM'))
          WHEN REGEXP_CONTAINS(clean_ini, r'^\d{1,2}:[0-5][0-9]:[0-5][0-9]$') THEN SAFE.PARSE_TIME('%H:%M:%S', clean_ini)
          WHEN REGEXP_CONTAINS(clean_ini, r'^\d{1,2}:[0-5][0-9]$')         THEN SAFE.PARSE_TIME('%H:%M', clean_ini)
          ELSE NULL
        END
      )
    END AS HORA_INICIO_QUIMIOTERAPIA_HOMOLOGADO,

    -- Hora término homologada
    CASE
      WHEN REGEXP_CONTAINS(UPPER(TRIM(HORA_TERMINO_QUIMIOTERAPIA)),
           r'(?i)\b(0\.715277778|0\.902777778|INF\.?\s*CONT(INUA)?|CONT(INUA)?|CONTINUA|INFUSION\s+DE\s+46HRS?\.?|46\s*(HRS?|HRAS?|HORAS?)|48\s*(HRS?|HRAS?|HORAS?)|24\s*(HRS?|HRAS?|HORAS?))\b')
      THEN 'ERROR: DATO FORM'
      ELSE FORMAT_TIME(
        '%H:%M',
        CASE
          WHEN clean_fin IN ('24','24:00','2400')                          THEN TIME '00:00:00'
          WHEN REGEXP_CONTAINS(clean_fin, r'^00AM$')                       THEN TIME '00:00:00'  -- fix medianoche
          WHEN REGEXP_CONTAINS(clean_fin, r'^\d{1,2}$')                    THEN SAFE.PARSE_TIME('%H', clean_fin)
          WHEN REGEXP_CONTAINS(clean_fin, r'^\d{3,4}$')                    THEN SAFE.PARSE_TIME('%H%M', LPAD(clean_fin, 4, '0'))
          WHEN REGEXP_CONTAINS(clean_fin, r'^\d{3,4}(AM|PM)$')             THEN SAFE.PARSE_TIME('%I%M%p', clean_fin)
          WHEN REGEXP_CONTAINS(clean_fin, r'^\d{1,2}(AM|PM)$')             THEN SAFE.PARSE_TIME('%I%p', clean_fin)
          WHEN REGEXP_CONTAINS(clean_fin, r'^\d{1,2}:[0-5][0-9](AM|PM)$')  THEN SAFE.PARSE_TIME('%I:%M%p', clean_fin)
          WHEN REGEXP_CONTAINS(clean_fin, r'^(1[3-9]|2[0-3])$')            THEN SAFE.PARSE_TIME('%H', clean_fin)
          WHEN REGEXP_CONTAINS(clean_fin, r'^(1[3-9]|2[0-3]):[0-5][0-9]$') THEN SAFE.PARSE_TIME('%H:%M', clean_fin)
          WHEN REGEXP_CONTAINS(clean_fin, r'^(1[3-9]|2[0-3])(AM|PM)$')     THEN SAFE.PARSE_TIME('%H', REGEXP_REPLACE(clean_fin,'(AM|PM)$',''))
          WHEN REGEXP_CONTAINS(clean_fin, r'^(1[3-9]|2[0-3]):[0-5][0-9](AM|PM)$')
                                                                           THEN SAFE.PARSE_TIME('%H:%M', REGEXP_REPLACE(clean_fin,'(AM|PM)$',''))
          WHEN REGEXP_CONTAINS(clean_fin, r'^12M$')                        THEN TIME '12:00:00'
          WHEN REGEXP_CONTAINS(clean_fin, r'^12:[0-5][0-9]M$')             THEN SAFE.PARSE_TIME('%I:%M%p', REGEXP_REPLACE(clean_fin,'M$','PM'))
          WHEN REGEXP_CONTAINS(clean_fin, r'^\d{1,2}:[0-5][0-9]:[0-5][0-9]$') THEN SAFE.PARSE_TIME('%H:%M:%S', clean_fin)
          WHEN REGEXP_CONTAINS(clean_fin, r'^\d{1,2}:[0-5][0-9]$')         THEN SAFE.PARSE_TIME('%H:%M', clean_fin)
          ELSE NULL
        END
      )
    END AS HORA_TERMINO_QUIMIOTERAPIA_HOMOLOGADO,

    -- Edad homologada
    SAFE_CAST(
      REGEXP_EXTRACT(
        EDAD_ANO_MES_DIA,
        r'(?i)(?:^|\s)(\d{1,3})\s*(?:a|años|ano|anos)\b'
      ) AS INT64
    ) AS EDAD_HOMOLOGADA

  FROM origen
),

calc AS (
  SELECT
    base.*,

    -- Duración en minutos
    CASE
      WHEN HORA_INICIO_QUIMIOTERAPIA_HOMOLOGADO IS NULL
        OR HORA_TERMINO_QUIMIOTERAPIA_HOMOLOGADO IS NULL
        OR HORA_INICIO_QUIMIOTERAPIA_HOMOLOGADO LIKE 'ERROR%'
        OR HORA_TERMINO_QUIMIOTERAPIA_HOMOLOGADO LIKE 'ERROR%'
      THEN NULL
      ELSE
        (
          (EXTRACT(HOUR   FROM SAFE.PARSE_TIME('%H:%M', HORA_TERMINO_QUIMIOTERAPIA_HOMOLOGADO)) * 60) +
           EXTRACT(MINUTE FROM SAFE.PARSE_TIME('%H:%M', HORA_TERMINO_QUIMIOTERAPIA_HOMOLOGADO))
        )
        -
        (
          (EXTRACT(HOUR   FROM SAFE.PARSE_TIME('%H:%M', HORA_INICIO_QUIMIOTERAPIA_HOMOLOGADO)) * 60) +
           EXTRACT(MINUTE FROM SAFE.PARSE_TIME('%H:%M', HORA_INICIO_QUIMIOTERAPIA_HOMOLOGADO))
        )
        +
        IF(
          SAFE.PARSE_TIME('%H:%M', HORA_TERMINO_QUIMIOTERAPIA_HOMOLOGADO) <
          SAFE.PARSE_TIME('%H:%M', HORA_INICIO_QUIMIOTERAPIA_HOMOLOGADO),
          1440, 0
        )
    END AS DURACION_MINUTOS
  FROM base
)

SELECT
  calc.*,
  DURACION_MINUTOS AS DURACION_QUIMIOTERAPIA_MIN,

  -- Duración en HH:MM
  CASE
    WHEN DURACION_MINUTOS IS NULL THEN NULL
    ELSE FORMAT('%02d:%02d', DIV(DURACION_MINUTOS, 60), MOD(DURACION_MINUTOS, 60))
  END AS DURACION_QUIMIOTERAPIA,

  -- Rangos etarios
  CASE
    WHEN EDAD_HOMOLOGADA BETWEEN 0  AND 11 THEN 'Infancia [0-11 años]'
    WHEN EDAD_HOMOLOGADA BETWEEN 12 AND 18 THEN 'Adolescencia [12-18 años]'
    WHEN EDAD_HOMOLOGADA BETWEEN 19 AND 29 THEN 'Juventud [19-29 años]'
    WHEN EDAD_HOMOLOGADA BETWEEN 30 AND 59 THEN 'Adultez [30-59 años]'
    WHEN EDAD_HOMOLOGADA >= 60            THEN 'Vejez [60+ años]'
    ELSE 'Desconocido'
  END AS RANGO_ETARIO,

  CASE
    WHEN EDAD_HOMOLOGADA BETWEEN 0  AND 9   THEN '0 - 9'
    WHEN EDAD_HOMOLOGADA BETWEEN 10 AND 19  THEN '10 - 19'
    WHEN EDAD_HOMOLOGADA BETWEEN 20 AND 29  THEN '20 - 29'
    WHEN EDAD_HOMOLOGADA BETWEEN 30 AND 39  THEN '30 - 39'
    WHEN EDAD_HOMOLOGADA BETWEEN 40 AND 49  THEN '40 - 49'
    WHEN EDAD_HOMOLOGADA BETWEEN 50 AND 59  THEN '50 - 59'
    WHEN EDAD_HOMOLOGADA BETWEEN 60 AND 69  THEN '60 - 69'
    WHEN EDAD_HOMOLOGADA BETWEEN 70 AND 79  THEN '70 - 79'
    WHEN EDAD_HOMOLOGADA BETWEEN 80 AND 89  THEN '80 - 89'
    WHEN EDAD_HOMOLOGADA BETWEEN 90 AND 99  THEN '90 - 99'
    WHEN EDAD_HOMOLOGADA >= 100             THEN '100+'
    ELSE 'Desconocido'
  END AS RANGO_ETARIO_10_ANIOS,

  COALESCE(NULLIF(TRIM(TIPO_PACIENTE), ''), 'En blanco') AS TIPO_PACIENTE_HOMOLOGADO,
  COALESCE(NULLIF(TRIM(AMBITO), ''), 'Sin dato') AS AMBITO_HOMOLOGADO,
  FORMAT_DATETIME('%Y-%m-%d %H:%M', CURRENT_DATETIME('America/Lima')) AS FH_ULTIMA_ACTUALIZACION

FROM calc;
