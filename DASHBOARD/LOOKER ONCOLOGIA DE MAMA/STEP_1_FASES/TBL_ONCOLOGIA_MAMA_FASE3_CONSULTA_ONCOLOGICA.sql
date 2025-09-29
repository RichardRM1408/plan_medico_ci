CREATE OR REPLACE TABLE `ci-datalake-dev.ci_dtlk_bqd_access_dev.TBL_ONCOLOGIA_MAMA_FASE3_CONSULTA_ONCOLOGICA` AS

SELECT 
    A1.N_SOLIC AS SOLICITUD,
    A1.DURACION AS TIEMPO_CUPO,
    A11.EPIS_PK AS ENCUENTRO,
    A5.CONSULT_DESC AS CONSULTORIO,
    E.NHC AS HC,
    A13.NOM_TVISIT AS TIPO_AGENDA,
    UPPER(A7.NOMBRE_CENTRO) AS SEDE,
    GAR_AGRUP.COD_GARANTE_AGRUP,          												
GAR_AGRUP.NOM_GARANTE_AGRUP, 												
EMP_GARANTE.COD_EMPR_GARANTE,           												
EMP_GARANTE.NOM_EMPR_GARANTE,
    --G.NOMBRE_GARANTE AS GARANTE,
    A2.CODIGO1 AS DNI,           
    A2.NAC_FECHA AS FECHA_NACIMIENTO_PACIENTE,   
    -- Calcular edad PACIENTE al momento de la atentcions
    -- Edad al momento de la cita
    DATE_DIFF(DATE(CAST(CONCAT( CAST(A1.FECHA AS DATE), ' ',  EXTRACT(HOUR FROM A1.HORA), ':',  EXTRACT(MINUTE FROM A1.HORA), ':', EXTRACT(SECOND FROM A1.HORA) ) AS TIMESTAMP )),  
    DATE(A2.NAC_FECHA),  YEAR) AS EDAD_PACIENTE,

    -- Clasificación por grupos de edad
    CASE 
      WHEN DATE_DIFF(
            DATE(
              CAST(
                CONCAT(
                  CAST(A1.FECHA AS DATE), ' ',
                  EXTRACT(HOUR FROM A1.HORA), ':',
                  EXTRACT(MINUTE FROM A1.HORA), ':',
                  EXTRACT(SECOND FROM A1.HORA)
                ) AS TIMESTAMP
              )
            ),
            DATE(A2.NAC_FECHA),
            YEAR
          ) < 18 THEN "Pediátrico"
      WHEN DATE_DIFF(
            DATE(
              CAST(
                CONCAT(
                  CAST(A1.FECHA AS DATE), ' ',
                  EXTRACT(HOUR FROM A1.HORA), ':',
                  EXTRACT(MINUTE FROM A1.HORA), ':',
                  EXTRACT(SECOND FROM A1.HORA)
                ) AS TIMESTAMP
              )
            ),
            DATE(A2.NAC_FECHA),
            YEAR
          ) BETWEEN 18 AND 39 THEN "Joven adulto"
      WHEN DATE_DIFF(
            DATE(
              CAST(
                CONCAT(
                  CAST(A1.FECHA AS DATE), ' ',
                  EXTRACT(HOUR FROM A1.HORA), ':',
                  EXTRACT(MINUTE FROM A1.HORA), ':',
                  EXTRACT(SECOND FROM A1.HORA)
                ) AS TIMESTAMP
              )
            ),
            DATE(A2.NAC_FECHA),
            YEAR
          ) BETWEEN 40 AND 59 THEN "Adulto mediana edad"
      WHEN DATE_DIFF(
            DATE(
              CAST(
                CONCAT(
                  CAST(A1.FECHA AS DATE), ' ',
                  EXTRACT(HOUR FROM A1.HORA), ':',
                  EXTRACT(MINUTE FROM A1.HORA), ':',
                  EXTRACT(SECOND FROM A1.HORA)
                ) AS TIMESTAMP
              )
            ),
            DATE(A2.NAC_FECHA),
            YEAR
          ) >= 60 THEN "Adulto mayor"
    END AS EDAD_GRUPO,
                   
    TRIM(A2.apellido1) || ' ' || TRIM(A2.apellido2) || ', ' || TRIM(A2.nombre) AS PACIENTE,
    (TRIM(REGEXP_REPLACE(A4.SERVICIO ,'-CEX|- CEX|CEX|SIS|SUR',''))) AS ESPECIALIDAD,
    A3.CODIGO_PERSONAL AS CODMED,
    TRIM(A3.apellido1) || ' ' || TRIM(A3.apellido2) || ', ' || TRIM(A3.nombre) AS MEDICO,

    -- Fechas y horas consolidadas
    CAST(CONCAT(CAST(A1.FECHA AS DATE),' ',EXTRACT(HOUR FROM A1.HORA),':',EXTRACT(MINUTE FROM A1.HORA),':',EXTRACT(SECOND FROM A1.HORA)) AS TIMESTAMP) AS FEH_CITA,
    CAST(CONCAT(CAST(A1.FECHA AS DATE),' ',EXTRACT(HOUR FROM A1.T_LLEGADA),':',EXTRACT(MINUTE FROM A1.T_LLEGADA),':',EXTRACT(SECOND FROM A1.T_LLEGADA)) AS TIMESTAMP) AS FEH_LLEGADA,
    CAST(CONCAT(CAST(A1.FECHA AS DATE),' ',EXTRACT(HOUR FROM A1.T_ENTRADA),':',EXTRACT(MINUTE FROM A1.T_ENTRADA),':',EXTRACT(SECOND FROM A1.T_ENTRADA)) AS TIMESTAMP) AS FEH_ENTRADA,
    CAST(CONCAT(CAST(A1.FECHA AS DATE),' ',EXTRACT(HOUR FROM A1.T_SALIDA),':',EXTRACT(MINUTE FROM A1.T_SALIDA),':',EXTRACT(SECOND FROM A1.T_SALIDA)) AS TIMESTAMP) AS FEH_SALIDA,

    A12.PREST_ITEM_DESC AS PREST_DESCRIPCION

FROM      `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_CAGENDAS_acc`       A1
LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_CLIENTES_acc`       A2  ON  A1.CODIGO_CLIENTE  = A2.CODIGO_CLIENTE
LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_FPERSONA_acc`       A3  ON  A1.CODIGO_PERSONAL = A3.CODIGO_PERSONAL
LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_SERVICIOS_acc`      A4  ON  A1.CODIGO_SERVICIO = A4.CODIGO_SERVICIO
LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_TCONSULTORIO_acc`   A5  ON  A1.CONSULT_PK      = A5.CONSULT_PK
LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_CO_UBICACIONES_acc` A6  ON  A5.UBICAC_PK       = A6.UBICAC_PK
LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_AREA_FISICA_acc`    AF  ON  AF.AREAFIS_PK      = A6.AREAFIS_PK
LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_GARANTES_acc`       G   ON  G.CODIGO_GARANTE_PK = A1.COD_PAGADOR_PK

LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_staging_prod.MD_EMPRESA_GARANTE`                     AS EMP_GARANTE 												
          ON ( TRIM( CAST(G.CODIGO_GARANTE_PK as STRING) ) = TRIM( EMP_GARANTE.COD_EMPR_GARANTE ) 												
            AND UPPER(EMP_GARANTE.COD_APLICATIVO) = 'XHIS6')											
LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_staging_prod.MD_GARANTE_AGRUPADO` AS GAR_AGRUP												
          ON (  GAR_AGRUP.ID_DLK_EMPR_GARANTE = EMP_GARANTE.ID_DLK_EMPR_GARANTE 												
              AND UPPER(GAR_AGRUP.COD_APLICATIVO) = 'XHIS6' )		

LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_CENTROS_acc`        A7  ON  A4.COD_CENTRO = A7.COD_CENTRO
LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_TTIPOVIS_acc`       A8  ON  A1.COD_TVISIT = A8.COD_TVISIT
LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_FPERSONA_acc`       A9  ON  A1.CODIGO_PERSONAL2 = A9.CODIGO_PERSONAL
LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_CEX_acc`            A10 ON  A1.N_SOLIC = A10.CON_CITA_SN
LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_EPISODIOS_acc`      A11 ON  A10.CEX_PK = A11.referencia_id AND A11.TIPO_EPISODIO_PK = 2
LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_PREST_ITEM_acc`     A12 ON  A1.PREST_ITEM_PK = A12.PREST_ITEM_PK
LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_HC_acc`             E   ON  E.CODIGO_CLIENTE = A1.CODIGO_CLIENTE AND  E.ACTIVA_SN = 1
LEFT JOIN `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_TTIPOVIS_acc`       A13 ON  A1.COD_TVISIT = A13.COD_TVISIT

WHERE A1.FECHA BETWEEN '2022-01-01' AND DATE_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 DAY) 
  AND A1.CODIGO_CLIENTE IS NOT NULL
  AND A1.T_LLEGADA IS NOT NULL 
  AND A1.T_SALIDA IS NOT NULL
  --AND A1.CODIGO_SERVICIO IN (235,1295,975,931,1654);
  AND A1.CODIGO_SERVICIO IN (1398,154,119,235,1295,975,931,1091,1654);
