CREATE OR REPLACE TABLE `ci-datalake-dev.ci_dtlk_bqd_access_dev.TBL_ONCOLOGIA_PROTOCOLO_SESION_TAREA_BASE` AS
WITH
-- ===============================
-- 1) Protocolo
-- ===============================
p AS (
  SELECT 
    HP.HOJA_PROT_PK,
    HP.CODIGO_CLIENTE,
    HP.EPIS_PK,
    HP.PROT_MEDICO_PK AS CODIGO_PROTOCOLO,
    PM.NOMBRE AS PROTOCOLO,
    FORMAT_TIMESTAMP('%d/%m/%Y %H:%M:%S', TIMESTAMP(HP.FECHA_REG)) AS FECHA_HORA_REGISTRO,
    HP.PRESCRIPTOR,
    FP.NOMBRE_CORTO AS NOMBRE_PRESCRIPTOR,
    CASE HP.ESTADO
      WHEN 1 THEN 'Provisional'
      WHEN 2 THEN 'Planificado'
      WHEN 3 THEN 'En curso'
      WHEN 4 THEN 'Finalizado'
      WHEN 5 THEN 'Interrumpido'
      WHEN 6 THEN 'Anulado'
    END AS ESTADO,
    FORMAT_DATE('%d/%m/%Y', DATE(HP.FECHA_PREV_INICIO)) AS FECHA_INICIO,
    FORMAT_DATE('%d/%m/%Y', DATE(HP.FECHA_FIN)) AS FECHA_FIN,
    HP.PROF_ULT_MODIF,
    FP2.NOMBRE_CORTO AS NOMBRE_PROF_ULT_MODIF,
    FORMAT_TIMESTAMP('%d/%m/%Y %H:%M:%S', TIMESTAMP(HP.FECHA_ULT_MODIF)) AS FECHA_MODIF,
    HP.ICD_PK AS CODIGO_DIAGNOSTICO,
    CONCAT(DIAG.ICD_COD, ' - ', DIAG.ICD_NOM) AS DIAGNOSTICO
  FROM `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_HOJA_PROT_acc`  HP
  LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_PROT_MEDICO_acc`  PM
    ON PM.PROT_MEDICO_PK = HP.PROT_MEDICO_PK
  LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_FPERSONA_acc`  FP 
    ON FP.codigo_personal = HP.PRESCRIPTOR
  LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_FPERSONA_acc`  FP2 
    ON FP2.codigo_personal = HP.PROF_ULT_MODIF
  LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_ICD_acc`  DIAG
    ON DIAG.ICD_PK = HP.ICD_PK
),

-- ===============================
-- 2) Sesión
-- ===============================
s AS (
  SELECT 
    PC.HOJA_PROT_PK,
    PC.PRES_CICLO_PK, 
    CONCAT(PTC.SIGLA, ' - Ciclo ', PC.ORDEN) AS CICLO,
    PSC.PRES_SESION_CAB_PK,
    PSC.NUMERO_SESION,
    PSC.EPIS_REALIZACION AS ENCUENTRO,
    PES.DESCRIPCION AS ESTADO_SESION,
    CASE DESTINO
      WHEN 0 THEN 'IntraHospitalario'
      WHEN 1 THEN 'Domicilio'
    END AS DESTINO,
    PSC.PROF_CONFIRMA,
    FP3.NOMBRE_CORTO AS PROF_CONFIRMA_CISE,
    PDA.DESCRIPCION AS AREA_ADMINISTRACION,
    TC.TIPO_COMP_DESC AS RECURSO,
    CONCAT(CAST(PSC.DURACION AS STRING), ' min.') AS TIEMPO_ESTIMADO,
    FORMAT_DATE('%d/%m/%Y', DATE(PSC.FECHA_PREV)) AS FECHA_PREVISTA,
    FORMAT_TIMESTAMP('%d/%m/%Y %H:%M:%S', TIMESTAMP(PSC.FECHA_PLANIF)) AS FECHA_HORA_PROGRAMADA
  FROM `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_PRES_CICLO_acc`  PC 
  LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_PROT_TIPO_CICLO_acc`  PTC 
    ON PTC.TIPO_CICLO_PK = PC.PROT_TIPO_CICLO_PK
  LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_PRES_SESION_CAB_acc`  PSC 
    ON PC.PRES_CICLO_PK = PSC.PRES_CICLO_PK 
  LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_PRES_EST_SESION_acc`  PES 
    ON PSC.ESTADO_SESION = PES.PRES_EST_SESION_PK
  LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_TIPO_COMPATIBLE_acc`  TC 
    ON PSC.TIPO_COMPATIBLE_PK = TC.TIPO_COMP_PK
  LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_FPERSONA_acc`  FP3 
    ON FP3.codigo_personal = PSC.PROF_CONFIRMA
  LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_PRES_DESTINO_ADMIN_acc`  PDA 
    ON PDA.PRES_DEST_ADMIN_PK = PSC.DESTINO_ADMIN
),

-- ===============================
-- 3) Tareas
-- ===============================
t AS (
  SELECT 
    PSD.PRES_SESION_CAB_PK, 
    PSD.PRES_SESION_DET_PK,
    PSD.ORDEN AS NRO_TAREA, 
    PSD.DESCRIPCION AS TAREA,  
    TCC.DESCRIPCION AS TIPO_TAREA,
    CONCAT(CAST(PSD.DURACION AS STRING), ' min.') AS DURACION,
    CASE PSD.ESTADO
      WHEN 1 THEN 'Pendiente'
      WHEN 2 THEN 'Anulado enfermería'
      WHEN 3 THEN 'Realizado'
      WHEN 4 THEN 'Interrumpido'
      WHEN 5 THEN 'Pendiente confirmación'
      WHEN 6 THEN 'En curso'
      WHEN 7 THEN 'Realizado parcial'
      ELSE ''
    END AS ESTADO_TAREA,
    FORMAT_TIMESTAMP('%d/%m/%Y %H:%M:%S',
      TIMESTAMP(DATETIME(DATE(SDA.FECHA_RECEPCION), TIME(SDA.HORA_RECEPCION)))
    ) AS FECHA_HORA_RECEP_FARMACIA,
    FORMAT_TIMESTAMP('%d/%m/%Y %H:%M:%S',
      TIMESTAMP(DATETIME(DATE(SDA.FECHA_INICIO), TIME(SDA.HORA_INICIO)))
    ) AS FECHA_HORA_INICIO,
    FORMAT_TIMESTAMP('%d/%m/%Y %H:%M:%S',
      TIMESTAMP(DATETIME(DATE(SDA.FECHA_FIN), TIME(SDA.HORA_FIN)))
    ) AS FECHA_HORA_FIN,
    FORMAT_TIMESTAMP('%d/%m/%Y %H:%M:%S',
      TIMESTAMP(DATETIME(DATE(SDA.FECHA_DEVOLUCION), TIME(SDA.HORA_DEVOLUCION)))
    ) AS FECHA_HORA_DEVOL_FARMACIA,
    SDA.OBSERVACIONES
  FROM `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_PRES_SESION_DET_acc`  PSD
  INNER JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_TIPO_COMP_CICLO_acc`  TCC 
    ON TCC.TIPO_COMP_CICLO_PK = PSD.TIPO_COMP_CICLO_PK
  LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_SESION_DET_ADMIN_acc`  SDA 
    ON SDA.SESION_DET_ADMI_PK = PSD.SESION_DET_ADMI_PK
)

-- ===============================
-- Unión final 
-- ===============================
SELECT
  -- Protocolo
  p.HOJA_PROT_PK,
  p.CODIGO_CLIENTE,
  p.EPIS_PK                           AS ENCUENTRO_PROTOCOLO,
  p.CODIGO_PROTOCOLO,
  p.PROTOCOLO,
  p.CODIGO_DIAGNOSTICO,
  p.DIAGNOSTICO,
  p.ESTADO                            AS ESTADO_PROTOCOLO,
  p.FECHA_INICIO                      AS FECHA_INICIO_PROTOCOLO,
  p.FECHA_FIN                         AS FECHA_FIN_PROTOCOLO,
  p.FECHA_HORA_REGISTRO,

  -- Sesión
  s.PRES_CICLO_PK,
  s.CICLO,
  s.PRES_SESION_CAB_PK,
  s.NUMERO_SESION,
  s.ENCUENTRO                         AS ENCUENTRO_SESION,
  s.ESTADO_SESION,
  s.DESTINO,
  s.RECURSO,
  s.TIEMPO_ESTIMADO,
  s.FECHA_PREVISTA,
  s.FECHA_HORA_PROGRAMADA,

  -- Tarea
  t.PRES_SESION_DET_PK,
  t.NRO_TAREA,
  t.TAREA,
  t.TIPO_TAREA,
  t.DURACION,
  t.ESTADO_TAREA,
  t.FECHA_HORA_RECEP_FARMACIA,
  t.FECHA_HORA_INICIO,
  t.FECHA_HORA_FIN,
  t.FECHA_HORA_DEVOL_FARMACIA,
  t.OBSERVACIONES

FROM p
LEFT JOIN s
  ON CAST(p.HOJA_PROT_PK AS STRING) = CAST(s.HOJA_PROT_PK AS STRING)
LEFT JOIN t
  ON t.PRES_SESION_CAB_PK = s.PRES_SESION_CAB_PK;
