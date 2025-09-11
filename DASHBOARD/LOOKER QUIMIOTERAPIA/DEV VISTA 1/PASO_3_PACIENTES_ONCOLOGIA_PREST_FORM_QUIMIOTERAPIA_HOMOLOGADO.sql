-- ========================================================================================================================================================
-- ✨ 1) TABLA TEMPORAL MANEJO SOLO DE HOMOLOGACION DE INICIO Y TERMINO DE QUIMIOTERAPIA PARA LA PESTAÑA 1 DE LOOKER QUIMIOTERAPIA  - INICIO
-- ========================================================================================================================================================
CREATE OR REPLACE TABLE `ci-datalake-dev.ci_dtlk_bqd_business_dev.TMP_HOMOLOGACION_INICIO_TERMINO_QUIMIOTERAPIA` AS
WITH src AS (
  SELECT *
  FROM `ci-datalake-dev.ci_dtlk_bqd_business_dev.PACIENTES_ONCOLOGIA_PREST_FORM_QUIMIOTERAPIA`
),

-- 2) Limpieza base -> clean_*
cleaned AS (
  SELECT
    src.*,

    -- Limpieza HORA_INICIO_QUIMIOTERAPIA
    REGEXP_REPLACE(
      UPPER(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            REGEXP_REPLACE(
              REGEXP_REPLACE(
                REGEXP_REPLACE(
                  TRIM(HORA_INICIO_QUIMIOTERAPIA),
                  '[-;_.,xX]', ':'                  -- unifica separadores
                ),
                '\\s*:\\s*', ':'
              ),
              ':+', ':'
            ),
            '(?i)\\bA\\.?\\s*M\\.?\\b', 'AM'
          ),
          '(?i)\\bP\\.?\\s*M\\.?\\b', 'PM'
        )
      ),
      '\\s*(HRS?\\.?|HRAS?|HORAS?|HS|H)\\.?$', ''
    ) AS clean_ini,

    -- Limpieza HORA_TERMINO_QUIMIOTERAPIA
    REGEXP_REPLACE(
      UPPER(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            REGEXP_REPLACE(
              REGEXP_REPLACE(
                REGEXP_REPLACE(
                  TRIM(HORA_TERMINO_QUIMIOTERAPIA),
                  '[-;_.,xX]', ':'
                ),
                '\\s*:\\s*', ':'
              ),
              ':+', ':'
            ),
            '(?i)\\bA\\.?\\s*M\\.?\\b', 'AM'
          ),
          '(?i)\\bP\\.?\\s*M\\.?\\b', 'PM'
        )
      ),
      '\\s*(HRS?\\.?|HRAS?|HORAS?|HS|H)\\.?$', ''
    ) AS clean_fin
  FROM src
),

-- 3) Normalización norm_ini
norm AS (
  SELECT
    cleaned.*,
    REGEXP_REPLACE(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            REGEXP_REPLACE(clean_ini, ':$', ''),
            '^(\\d{1,2}:[0-5]\\d):0$', '\\1'
          ),
          '^(\\d{1,2}:[0-5]\\d)\\.00$', '\\1'
        ),
        '\\s+(AM|PM)$', '\\1'
      ),
      '^(\\d{1,2}):([0-9])(AM|PM)?$', '\\1:0\\2\\3'
    ) AS norm_ini,

    REGEXP_REPLACE(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            REGEXP_REPLACE(clean_fin, ':$', ''),
            '^(\\d{1,2}:[0-5]\\d):0$', '\\1'
          ),
          '^(\\d{1,2}:[0-5]\\d)\\.00$', '\\1'
        ),
        '\\s+(AM|PM)$', '\\1'
      ),
      '^(\\d{1,2}):([0-9])(AM|PM)?$', '\\1:0\\2\\3'
    ) AS norm_fin
  FROM cleaned
),

-- 4) Tokens horarios
tokens AS (
  SELECT
    norm.*,
    ARRAY_REVERSE(
      REGEXP_EXTRACT_ALL(norm.norm_ini,
        '(?i)\\b(?:\\d{1,2}(?::[0-5]\\d)?\\s*(?:A\\.?M\\.?|P\\.?M\\.?|AM|PM|M))\\b'
      )
    )[SAFE_OFFSET(0)] AS ini_ampm_tok,

    ARRAY_REVERSE(
      REGEXP_EXTRACT_ALL(norm.norm_fin,
        '(?i)\\b(?:\\d{1,2}(?::[0-5]\\d)?\\s*(?:A\\.?M\\.?|P\\.?M\\.?|AM|PM|M))\\b'
      )
    )[SAFE_OFFSET(0)] AS fin_ampm_tok,

    ARRAY_REVERSE(REGEXP_EXTRACT_ALL(norm.norm_ini, '\\b\\d{1,2}:[0-5]\\d\\b'))[SAFE_OFFSET(0)] AS ini_24_tok,
    ARRAY_REVERSE(REGEXP_EXTRACT_ALL(norm.norm_fin, '\\b\\d{1,2}:[0-5]\\d\\b'))[SAFE_OFFSET(0)] AS fin_24_tok
  FROM norm
),

-- 5) Normalización final tokens
norm_tokens AS (
  SELECT
    tokens.*,
    COALESCE(
      UPPER(REGEXP_REPLACE(tokens.ini_ampm_tok, '[\\s\\.]', '')),
      tokens.ini_24_tok,
      tokens.norm_ini
    ) AS final_norm_ini,
    COALESCE(
      UPPER(REGEXP_REPLACE(tokens.fin_ampm_tok, '[\\s\\.]', '')),
      tokens.fin_24_tok,
      tokens.norm_fin
    ) AS final_norm_fin
  FROM tokens
),

ajuste AS (
  SELECT
    norm_tokens.* EXCEPT(clean_ini, clean_fin, norm_ini, norm_fin, ini_ampm_tok, fin_ampm_tok, ini_24_tok, fin_24_tok, final_norm_ini, final_norm_fin),


-- ===============================
-- HORA INICIO HOMOLOGADA
-- ===============================
CASE
 
  -- Casos con sufijos de horas tipo "14:00 HRS", "15 HRAS"
  WHEN REGEXP_CONTAINS(UPPER(TRIM(HORA_INICIO_QUIMIOTERAPIA)),
       '^(\\d{1,2}:[0-5]\\d)\\s*(HRS?|HRAS?|HORAS?|HS)\\.?$')
    THEN FORMAT_TIME('%H:%M',
           SAFE.PARSE_TIME('%H:%M',
             REGEXP_EXTRACT(UPPER(TRIM(HORA_INICIO_QUIMIOTERAPIA)),
             '^(\\d{1,2}:[0-5]\\d)')))

  WHEN REGEXP_CONTAINS(UPPER(TRIM(HORA_INICIO_QUIMIOTERAPIA)),
       '^(\\d{1,2})\\s*(HRS?|HRAS?|HORAS?|HS)\\.?$')
    THEN FORMAT_TIME('%H:%M',
           SAFE.PARSE_TIME('%H',
             REGEXP_EXTRACT(UPPER(TRIM(HORA_INICIO_QUIMIOTERAPIA)),
             '^(\\d{1,2})')))

  -- Casos con separadores extraños
  WHEN REGEXP_CONTAINS(TRIM(HORA_INICIO_QUIMIOTERAPIA), '^0?8[\\./\\]]00$')
    THEN '08:00'

  -- Casos con variantes menores
  WHEN REGEXP_CONTAINS(UPPER(TRIM(HORA_INICIO_QUIMIOTERAPIA)), '^00[\\.,]00\\s*(HRS?|HRAS?|HORAS?)$')
    THEN '00:00'

  -- =======================
  -- CASOS DE ERROR FORM
  -- =======================

  WHEN REGEXP_CONTAINS(UPPER(TRIM(HORA_INICIO_QUIMIOTERAPIA)),
       '(INF(USION)?|CONT(INUA)?|CONTI?\\.?|HOSPITALIZADO|PASANDSOI|PENDIENTE|SE PROGRAMA EN 24 HORAS|QUEDA PASANDO)')
    OR REGEXP_CONTAINS(UPPER(TRIM(HORA_INICIO_QUIMIOTERAPIA)), '^(AM|PM)$')
    OR REGEXP_CONTAINS(UPPER(TRIM(HORA_INICIO_QUIMIOTERAPIA)), '^(0\\.715277778|0\\.902777778)$')
    OR REGEXP_CONTAINS(TRIM(HORA_INICIO_QUIMIOTERAPIA), '^\\d{1,2}/\\d{1,2}/\\d{2,4}$')
        -- 🚨 Casos de 24h o mayores
    OR REGEXP_CONTAINS(TRIM(final_norm_ini), '^(2[4-9]|[3-9][0-9]):[0-5]\\d$')
    OR REGEXP_CONTAINS(TRIM(final_norm_ini), '^(2[4-9]|[3-9][0-9])$')
  THEN 'ERROR: DATO FORM'

  -- =======================
  -- BLOQUE PRINCIPAL - DIFERENTES VARIANTES
  -- =======================

  ELSE
    CASE
      
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'^(24|24:00|2400|00AM)$')                                              THEN '00:00'
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'\\b(MEDIODIA|NOON)\\b')                                               THEN '12:00'
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'\\b(MEDIANOCHE|MIDNIGHT)\\b')                                         THEN '00:00'
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'^12\\s*M$')                                                           THEN '12:00'
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'^12M$')                                                               THEN '12:00'
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'^\\d{1,2}:[0-5]\\d:[0-5]\\d$')                                        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%H:%M:%S', REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$','')))
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'^\\s*\\d{1,2}\\s*:\\s*[0-5]\\d\\s*:\\s*[0-5]\\d\\s*$')                THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%H:%M:%S', REGEXP_REPLACE(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'\\s*:\\s*',':')))
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'^(1[3-9]|2[0-3]):[0-5]\\d(AM|PM)$')                                   THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%H:%M', REGEXP_REPLACE(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'(AM|PM)$','')))
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'^(1[3-9]|2[0-3])(AM|PM)$')                                            THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%H', REGEXP_REPLACE(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'(AM|PM)$','')))
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'^\\d{1,2}:[0-5]\\d(AM|PM)$')                                          THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%I:%M%p', REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$','')))
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'^\\d{1,2}:(AM|PM)$')                                                  THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%I:%M%p',REGEXP_REPLACE(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),':(AM|PM)$',':00\\1')))
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'^\\d{3,4}(AM|PM)$')                                                   THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%I%M%p', REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$','')))
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'^\\d{1,2}:[0-5]\\d$')                                                 THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%H:%M', REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$','')))
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'^\\s*\\d{1,2}\\s*:\\s*[0-5]\\d\\s*$')                                 THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%H:%M', REGEXP_REPLACE(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'\\s*:\\s*',':')))
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'^\\d{3,4}$')                                                          THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%H%M', LPAD(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),4,'0')))
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'^\\d{1,2}(AM|PM)$')                                                   THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%I%p', REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$','')))
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'^\\d{1,2}$')                                                          THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%H', REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$','')))

      -- separador punto/coma -> ":"
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'^(\\d{1,2})[\\.,](\\d{1,2})$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%H:%M',
               REGEXP_REPLACE(REGEXP_REPLACE(TRIM(final_norm_ini),'[\\.,;:]+$',''),'^(\\d{1,2})[\\.,](\\d{1,2})$','\\1:\\2')))

      -- minuto 1 dígito -> cero a la izquierda
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)),'^\\d{1,2}:[0-9](AM|PM)?$')
        THEN FORMAT_TIME('%H:%M', COALESCE(
                 SAFE.PARSE_TIME('%I:%M%p',
                   UPPER(REGEXP_REPLACE(TRIM(final_norm_ini),'^(\\d{1,2}):([0-9])(AM|PM)?$','\\1:0\\2\\3'))),
                 SAFE.PARSE_TIME('%H:%M',
                   REGEXP_REPLACE(TRIM(final_norm_ini),'^(\\d{1,2}):([0-9])$','\\1:0\\2'))
               ))

      -- "00.OO" → "00:00"
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)), '^00[\\.,"]?OO$')                              THEN '00:00'
      -- "11:3.2" → "11:32"
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^11:3[\\.,]?2$')                                     THEN '11:32'
      -- "040:50" → "04:50"
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^0?40:50$')                                          THEN '04:50'
      -- "15 00 PM" → "15:00"
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)), '^(\\d{1,2})\\s*00\\s*PM$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%I:%M%p',
              REGEXP_REPLACE(UPPER(TRIM(final_norm_ini)), '^(\\d{1,2})\\s*00\\s*PM$', '\\1:00PM')))
      -- "18: pm" → "18:00"
      WHEN REGEXP_CONTAINS(LOWER(TRIM(final_norm_ini)), '^18:\\s*pm$')                                  THEN '18:00'
      -- "2 P.M" → "14:00"
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)), '^2\\s*P\\.?M\\.?$')                            THEN '14:00'
      -- "2030PM" → "20:30"
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)), '^[0-9]{3,4}(AM|PM)$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%I%M%p', UPPER(TRIM(final_norm_ini))))
      -- "620PM" → "18:20"
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)), '^[0-9]{3,4}(AM|PM)$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%I%M%p', UPPER(TRIM(final_norm_ini))))
      -- "6:00P.M." → "18:00"
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)), '^6:00P\\.?M\\.?$')
        THEN '18:00'

-- ==== Otros Casos no homologados  ====

      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^11:3[\\.,]?2$')
        THEN '11:32'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)), '^00[\\.,"]?OO$')
        THEN '00:00'
      WHEN REGEXP_CONTAINS(LOWER(TRIM(final_norm_ini)), '^00:30\\s*am$')
        THEN '00:30'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^0?40:50$')
        THEN '04:50'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)), '^(\\d{1,2})\\s*00\\s*PM$')
        THEN FORMAT_TIME('%H:%M',
              SAFE.PARSE_TIME('%I:%M%p',
                REGEXP_REPLACE(UPPER(TRIM(final_norm_ini)), '^(\\d{1,2})\\s*00\\s*PM$', '\\1:00PM')))
      WHEN REGEXP_CONTAINS(LOWER(TRIM(final_norm_ini)), '^18:\\s*pm$')
        THEN '18:00'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)), '^2\\s*P\\.?M\\.?$')
        THEN '14:00'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)), '^[0-9]{3,4}(AM|PM)$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%I%M%p', UPPER(TRIM(final_norm_ini))))
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)), '^6:00P\\.?M\\.?$')
        THEN '18:00'

      -- ==== Casos inválidos → ERROR: DATO FORM adicionales====
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)),
            '(PASANDSOI|PENDIENTE|SE PROGRAMA EN 24 HORAS|QUEDA PASANDO)')
        THEN 'ERROR: DATO FORM'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^\\d{1,2}/\\d{1,2}/\\d{2,4}$')
        THEN 'ERROR: DATO FORM'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^\\d+\\.\\d+$')
        THEN 'ERROR: DATO FORM'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^(2[4-9]|[3-9][0-9]):[0-5]\\d$')
        THEN 'ERROR: DATO FORM'

      -- ============================
      -- BLOQUE COMPLEMENTARIO CASUSITICAS ESPECIFICAS
      -- ============================

      -- ==== Casos válidos con formatos raros ====
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^0?8[\\./]00$')        THEN '08:00'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^0?8[\\]:;]00$')       THEN '08:00'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^10:000$')             THEN '10:00'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^11:3[\\.,]?2$')       THEN '11:32'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)), '^12:\\s*00\\s*M$') THEN '12:00'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)), '^12:\\s*30\\s*M$') THEN '12:30'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)), '^12:\\s*40\\s*M$') THEN '12:40'
      WHEN REGEXP_CONTAINS(LOWER(TRIM(final_norm_ini)), '^2:\\s*oo\\s*pm$') THEN '14:00'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^2:000$')              THEN '02:00'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^12:\"0$')             THEN '12:00'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^12:05\\s*[Mm]$')      THEN '12:05'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^15:400$')             THEN '15:40'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^16\\s*00$')           THEN '16:00'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^17\\s*pmm$')          THEN '17:00'
      WHEN REGEXP_CONTAINS(LOWER(TRIM(final_norm_ini)), '^18:\\s*pm$')   THEN '18:00'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^18:30HRS.*$')         THEN '18:30'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^19:30HRS.*$')         THEN '19:30'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^20:300pm$')           THEN '20:30'
      WHEN REGEXP_CONTAINS(LOWER(TRIM(final_norm_ini)), '^2:00mpm$')     THEN '14:00'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)), '^6:00P\\.?M\\.?$') THEN '18:00'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)), '^620PM$')       THEN '18:20'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^09:210$')             THEN '09:21'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^11:000$')             THEN '11:00'

      -- ==== Casos inválidos → ERROR: DATO FORM - adicional 2 ====
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)), '^(M|00\\.OO)$') THEN 'ERROR: DATO FORM'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^16:70$')              THEN 'ERROR: DATO FORM'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)), '^(24\\s*H|24HR|24HRAS?|24HRS?|24 HORAS?)$')
        THEN 'ERROR: DATO FORM'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_ini)), '^(46|48)\\s*(HORAS?|HRAS?\\.?|HRS?\\.?|H\\b).*')
        THEN 'ERROR: DATO FORM'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^(2[4-9]|[3-9][0-9]):[0-5]\\d$')
        THEN 'ERROR: DATO FORM'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_ini), '^(2[4-9]|[3-9][0-9])$')
        THEN 'ERROR: DATO FORM'

            ELSE NULL
          END
      END AS HORA_INICIO_QUIMIOTERAPIA_HOMOLOGADO,

-- ===============================
-- HORA TÉRMINO HOMOLOGADA
-- ===============================

CASE
      -- =======================
      -- CASOS GENERALES
      -- =======================
      -- Casos con sufijos de horas tipo "14:00 HRS", "15 HRAS"
      WHEN REGEXP_CONTAINS(UPPER(TRIM(HORA_TERMINO_QUIMIOTERAPIA)),
          '^(\\d{1,2}:[0-5]\\d)\\s*(HRS?|HRAS?|HORAS?|HS)\\.?$')
        THEN FORMAT_TIME('%H:%M',
              SAFE.PARSE_TIME('%H:%M',
                REGEXP_EXTRACT(UPPER(TRIM(HORA_TERMINO_QUIMIOTERAPIA)),
                '^(\\d{1,2}:[0-5]\\d)')))

      WHEN REGEXP_CONTAINS(UPPER(TRIM(HORA_TERMINO_QUIMIOTERAPIA)),
          '^(\\d{1,2})\\s*(HRS?|HRAS?|HORAS?|HS)\\.?$')
        THEN FORMAT_TIME('%H:%M',
              SAFE.PARSE_TIME('%H',
                REGEXP_EXTRACT(UPPER(TRIM(HORA_TERMINO_QUIMIOTERAPIA)),
                '^(\\d{1,2})')))

      -- Casos con separadores extraños
      WHEN REGEXP_CONTAINS(TRIM(HORA_TERMINO_QUIMIOTERAPIA), '^0?8[\\./\\]]00$')
        THEN '08:00'

      -- Casos con variantes menores
      WHEN REGEXP_CONTAINS(UPPER(TRIM(HORA_TERMINO_QUIMIOTERAPIA)), '^00[\\.,]00\\s*(HRS?|HRAS?|HORAS?)$')
        THEN '00:00'

      -- =======================
      -- CASOS DE ERROR FORM
      -- =======================
      WHEN REGEXP_CONTAINS(UPPER(TRIM(HORA_TERMINO_QUIMIOTERAPIA)),
          '(INF(USION)?|CONT(INUA)?|CONTI?\\.?|HOSPITALIZADO|PASANDSOI|PENDIENTE|SE PROGRAMA EN 24 HORAS|QUEDA PASANDO)')
        OR REGEXP_CONTAINS(UPPER(TRIM(HORA_TERMINO_QUIMIOTERAPIA)), '^(AM|PM|M)$')
        OR REGEXP_CONTAINS(UPPER(TRIM(HORA_TERMINO_QUIMIOTERAPIA)), '^(0\\.715277778|0\\.902777778)$')
          -- 🚨 Casos de 24h o mayores
        OR REGEXP_CONTAINS(TRIM(final_norm_fin), '^(2[4-9]|[3-9][0-9]):[0-5]\\d$')
        OR REGEXP_CONTAINS(TRIM(final_norm_fin), '^(2[4-9]|[3-9][0-9])$')
        
      THEN 'ERROR: DATO FORM'


  -- =======================
  -- BLOQUE PRINCIPAL
  -- =======================
  ELSE
    CASE
      -- =======================
      -- BLOQUE ORIGINAL
      -- =======================
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'^(24|24:00|2400|00AM)$')
        THEN '00:00'
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'\\b(MEDIODIA|NOON)\\b')
        THEN '12:00'
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'\\b(MEDIANOCHE|MIDNIGHT)\\b')
        THEN '00:00'
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'^12\\s*M$')
        THEN '12:00'
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'^12M$')
        THEN '12:00'

      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'^\\d{1,2}:[0-5]\\d:[0-5]\\d$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%H:%M:%S', REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$','')))
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'^\\s*\\d{1,2}\\s*:\\s*[0-5]\\d\\s*:\\s*[0-5]\\d\\s*$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%H:%M:%S', REGEXP_REPLACE(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'\\s*:\\s*',':')))

      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'^(1[3-9]|2[0-3]):[0-5]\\d(AM|PM)$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%H:%M', REGEXP_REPLACE(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'(AM|PM)$','')))
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'^(1[3-9]|2[0-3])(AM|PM)$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%H', REGEXP_REPLACE(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'(AM|PM)$','')))

      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'^\\d{1,2}:[0-5]\\d(AM|PM)$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%I:%M%p', REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$','')))
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'^\\d{1,2}:(AM|PM)$')
        THEN FORMAT_TIME('%H:%M',
             SAFE.PARSE_TIME('%I:%M%p',REGEXP_REPLACE(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),':(AM|PM)$',':00\\1')))

      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'^\\d{3,4}(AM|PM)$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%I%M%p', REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$','')))

      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'^\\d{1,2}:[0-5]\\d$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%H:%M', REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$','')))
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'^\\s*\\d{1,2}\\s*:\\s*[0-5]\\d\\s*$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%H:%M', REGEXP_REPLACE(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'\\s*:\\s*',':')))

      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'^\\d{3,4}$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%H%M', LPAD(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),4,'0')))

      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'^\\d{1,2}(AM|PM)$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%I%p', REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$','')))
      WHEN REGEXP_CONTAINS(REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$',''),'^\\d{1,2}$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%H', REGEXP_REPLACE(TRIM(final_norm_fin),'[\\.,;:]+$','')))

      -- =======================
      -- BLOQUES COMPLEMENTARIOS 1 al 9 (copiados de INICIO)
      -- =======================

      -- "00.OO" → "00:00"
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)), '^00[\\.,"]?OO$')
        THEN '00:00'
      -- "11:3.2" → "11:32"
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^11:3[\\.,]?2$')
        THEN '11:32'
      -- "040:50" → "04:50"
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^0?40:50$')
        THEN '04:50'
      -- "15 00 PM" → "15:00"
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)), '^(\\d{1,2})\\s*00\\s*PM$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%I:%M%p',
              REGEXP_REPLACE(UPPER(TRIM(final_norm_fin)), '^(\\d{1,2})\\s*00\\s*PM$', '\\1:00PM')))
      -- "18: pm" → "18:00"
      WHEN REGEXP_CONTAINS(LOWER(TRIM(final_norm_fin)), '^18:\\s*pm$')
        THEN '18:00'
      -- "2 P.M" → "14:00"
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)), '^2\\s*P\\.?M\\.?$')
        THEN '14:00'
      -- "2030PM" → "20:30"
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)), '^[0-9]{3,4}(AM|PM)$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%I%M%p', UPPER(TRIM(final_norm_fin))))
      -- "620PM" → "18:20"
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)), '^[0-9]{3,4}(AM|PM)$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%I%M%p', UPPER(TRIM(final_norm_fin))))
      -- "6:00P.M." → "18:00"
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)), '^6:00P\\.?M\\.?$')
        THEN '18:00'

      -- ============================
      -- BLOQUE COMPLEMENTARIO 10 (casuísticas unificadas INICIO / TÉRMINO)
      -- ============================
      -- ==== Casos válidos con formatos raros ====


      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^11:3[\\.,]?2$')
        THEN '11:32'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)), '^00[\\.,"]?OO$')
        THEN '00:00'
      WHEN REGEXP_CONTAINS(LOWER(TRIM(final_norm_fin)), '^00:30\\s*am$')
        THEN '00:30'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^0?40:50$')
        THEN '04:50'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)), '^(\\d{1,2})\\s*00\\s*PM$')
        THEN FORMAT_TIME('%H:%M',
              SAFE.PARSE_TIME('%I:%M%p',
                REGEXP_REPLACE(UPPER(TRIM(final_norm_fin)), '^(\\d{1,2})\\s*00\\s*PM$', '\\1:00PM')))
      WHEN REGEXP_CONTAINS(LOWER(TRIM(final_norm_fin)), '^18:\\s*pm$')
        THEN '18:00'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)), '^2\\s*P\\.?M\\.?$')
        THEN '14:00'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)), '^[0-9]{3,4}(AM|PM)$')
        THEN FORMAT_TIME('%H:%M', SAFE.PARSE_TIME('%I%M%p', UPPER(TRIM(final_norm_fin))))
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)), '^6:00P\\.?M\\.?$')
        THEN '18:00'
      -- ==== Casos inválidos → ERROR: DATO FORM ====
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)),
            '(PASANDSOI|PENDIENTE|SE PROGRAMA EN 24 HORAS|QUEDA PASANDO)')
        THEN 'ERROR: DATO FORM'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^\\d{1,2}/\\d{1,2}/\\d{2,4}$')
        THEN 'ERROR: DATO FORM'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^\\d+\\.\\d+$')
        THEN 'ERROR: DATO FORM'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^(2[4-9]|[3-9][0-9]):[0-5]\\d$')
        THEN 'ERROR: DATO FORM'


      -- ============================
      -- BLOQUE COMPLEMENTARIO casuisticas especificas
      -- ============================

      -- ==== Casos válidos con formatos raros ====
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^0?8[\\./]00$')        THEN '08:00'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^0?8[\\]:;]00$')       THEN '08:00'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^10:000$')             THEN '10:00'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^11:3[\\.,]?2$')       THEN '11:32'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)), '^12:\\s*00\\s*M$') THEN '12:00'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)), '^12:\\s*30\\s*M$') THEN '12:30'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)), '^12:\\s*40\\s*M$') THEN '12:40'
      WHEN REGEXP_CONTAINS(LOWER(TRIM(final_norm_fin)), '^2:\\s*oo\\s*pm$') THEN '14:00'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^2:000$')              THEN '02:00'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^12:\"0$')             THEN '12:00'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^12:05\\s*[Mm]$')      THEN '12:05'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^15:400$')             THEN '15:40'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^16\\s*00$')           THEN '16:00'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^17\\s*pmm$')          THEN '17:00'
      WHEN REGEXP_CONTAINS(LOWER(TRIM(final_norm_fin)), '^18:\\s*pm$')   THEN '18:00'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^18:30HRS.*$')         THEN '18:30'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^19:30HRS.*$')         THEN '19:30'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^20:300pm$')           THEN '20:30'
      WHEN REGEXP_CONTAINS(LOWER(TRIM(final_norm_fin)), '^2:00mpm$')     THEN '14:00'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)), '^6:00P\\.?M\\.?$') THEN '18:00'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)), '^620PM$')       THEN '18:20'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^09:210$')             THEN '09:21'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^11:000$')             THEN '11:00'

      -- ==== Casos inválidos → ERROR: DATO FORM adicionales ====
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)), '^(M|00\\.OO)$') THEN 'ERROR: DATO FORM'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^16:70$')              THEN 'ERROR: DATO FORM'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)), '^(24\\s*H|24HR|24HRAS?|24HRS?|24 HORAS?)$')
        THEN 'ERROR: DATO FORM'
      WHEN REGEXP_CONTAINS(UPPER(TRIM(final_norm_fin)), '^(46|48)\\s*(HORAS?|HRAS?\\.?|HRS?\\.?|H\\b).*')
        THEN 'ERROR: DATO FORM'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^(2[4-9]|[3-9][0-9]):[0-5]\\d$')
        THEN 'ERROR: DATO FORM'
      WHEN REGEXP_CONTAINS(TRIM(final_norm_fin), '^(2[4-9]|[3-9][0-9])$')
        THEN 'ERROR: DATO FORM'


            ELSE NULL
          END
      END AS HORA_TERMINO_QUIMIOTERAPIA_HOMOLOGADO,


  FROM norm_tokens
)
SELECT *
FROM ajuste;

-- ========================================================================================================================================================
-- ✨ 1) TABLA TEMPORAL MANEJO SOLO DE HOMOLOGACION DE INICIO Y TERMINO DE QUIMIOTERAPIA PARA LA PESTAÑA 1 DE LOOKER QUIMIOTERAPIA - FIN
-- ========================================================================================================================================================


-- ========================================================================================================================================================
-- ✨ 2) TABLA ALIMENTADORA DE LA VISTA FINAL - inicio
-- ========================================================================================================================================================
CREATE OR REPLACE TABLE `ci-datalake-dev.ci_dtlk_bqd_business_dev.PACIENTES_ONCOLOGIA_PREST_FORM_QUIMIOTERAPIA_HOMOLOGADO` AS
WITH base AS (
  SELECT
    t.*,

    -- FECHAS HOMOLOGADAS A TIMESTAMP PARA USARLO EN LOOKER
    PARSE_TIMESTAMP('%d/%m/%Y', FECHA_ATENCION) AS FECHA_ATENCION_TS,
    PARSE_TIMESTAMP('%d/%m/%Y', Fecha_Actual)   AS FECHA_ACTUAL_TS,

    -- Edad homologada a partir de EDAD_ANO_MES_DIA proviene de Formulario
    SAFE_CAST(REGEXP_EXTRACT(EDAD_ANO_MES_DIA, r'(?i)(?:^|\s)(\d{1,3})\s*(?:A|AÑOS|ANO|ANOS)\b')AS INT64) AS EDAD_HOMOLOGADA,

    -- DURACION EN MINUTOS DE QUIMIOTERAPIA EN BASE  A INCIO Y TERMINO HOMOLOGADOS
    CASE
      WHEN  
       HORA_INICIO_QUIMIOTERAPIA_HOMOLOGADO IS NULL
        OR HORA_TERMINO_QUIMIOTERAPIA_HOMOLOGADO IS NULL
        OR HORA_INICIO_QUIMIOTERAPIA_HOMOLOGADO LIKE 'ERROR%'
        OR HORA_TERMINO_QUIMIOTERAPIA_HOMOLOGADO LIKE 'ERROR%'
      THEN NULL
      ELSE
        (EXTRACT(HOUR FROM SAFE.PARSE_TIME('%H:%M', HORA_TERMINO_QUIMIOTERAPIA_HOMOLOGADO)) * 60 + EXTRACT(MINUTE FROM SAFE.PARSE_TIME('%H:%M', HORA_TERMINO_QUIMIOTERAPIA_HOMOLOGADO)))
        -
        (EXTRACT(HOUR FROM SAFE.PARSE_TIME('%H:%M', HORA_INICIO_QUIMIOTERAPIA_HOMOLOGADO)) * 60 + EXTRACT(MINUTE FROM SAFE.PARSE_TIME('%H:%M', HORA_INICIO_QUIMIOTERAPIA_HOMOLOGADO)))
        + IF(SAFE.PARSE_TIME('%H:%M', HORA_TERMINO_QUIMIOTERAPIA_HOMOLOGADO) < SAFE.PARSE_TIME('%H:%M', HORA_INICIO_QUIMIOTERAPIA_HOMOLOGADO), 1440, 0)
    END AS DURACION_MINUTOS
  FROM `ci-datalake-dev.ci_dtlk_bqd_business_dev.TMP_HOMOLOGACION_INICIO_TERMINO_QUIMIOTERAPIA` t
)

SELECT
  base.*,

  -- Alias directo para DURACION_QUIMIOTERAPIA_MIN - TRAZABILIDAD
  DURACION_MINUTOS AS DURACION_QUIMIOTERAPIA_MIN,

  -- HOMOLOGAR A Formato HH:MM DURACION DE QUIMITOERAPIA QUE VENIA EN MINUTOS
  CASE
    WHEN DURACION_MINUTOS IS NULL THEN NULL
    ELSE FORMAT('%02d:%02d', DIV(DURACION_MINUTOS, 60), MOD(DURACION_MINUTOS, 60))
  END AS DURACION_QUIMIOTERAPIA,

  -- Clasificación por duración en base a DURACION_MINUTOS
  CASE
    WHEN DURACION_MINUTOS IS NULL THEN NULL
    WHEN DURACION_MINUTOS < 240 THEN 'CORTA'
    WHEN DURACION_MINUTOS BETWEEN 240 AND 360 THEN 'MEDIANA'
    WHEN DURACION_MINUTOS > 360 THEN 'LARGA'
  END AS CLASIFICACION_DURACION_QUIMIOTERAPIA,

  -- RANGO ETARIO SOLICITADO 
  CASE
    WHEN EDAD_HOMOLOGADA BETWEEN 0  AND 11 THEN 'Infancia [0-11 años]'
    WHEN EDAD_HOMOLOGADA BETWEEN 12 AND 18 THEN 'Adolescencia [12-18 años]'
    WHEN EDAD_HOMOLOGADA BETWEEN 19 AND 29 THEN 'Juventud [19-29 años]'
    WHEN EDAD_HOMOLOGADA BETWEEN 30 AND 59 THEN 'Adultez [30-59 años]'
    WHEN EDAD_HOMOLOGADA >= 60            THEN 'Vejez [60+ años]'
    ELSE 'Desconocido'
  END AS RANGO_ETARIO,

  -- Rango etario por décadas 
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

  -- HOMOLOGACION DE CAMPOS NULL Y VACIOS 
  COALESCE(NULLIF(TRIM(TIPO_PACIENTE), ''), 'En blanco') AS TIPO_PACIENTE_HOMOLOGADO,
  COALESCE(NULLIF(TRIM(AMBITO), ''), 'Sin dato')         AS AMBITO_HOMOLOGADO,

  -- FECHA DE ULTIMA DE ACTUALIZAION DE TABLA PREVIA A VISTA PARA VISUALIZAR EN LOOKER
  FORMAT_DATETIME('%Y-%m-%d %H:%M', CURRENT_DATETIME('America/Lima')) AS FH_ULTIMA_ACTUALIZACION

FROM base;

-- ========================================================================================================================================================
-- ✨ 2) TABLA ALIMENTADORA DE LA VISTA FINAL - FIN
-- ========================================================================================================================================================