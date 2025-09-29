CREATE OR REPLACE TABLE `ci-datalake-dev.ci_dtlk_bqd_access_dev.TBL_ONCOLOGIA_MAMA_FASE1_MAMOGRAFIA` AS

WITH 
EXAMENES_FINALIZADOS AS (
    SELECT  PETICION_PK, 
            DATETIME(DATE(GHI_FECHA), TIME(GHI_HORA)) AS FH_FINALIZADO,
            ROW_NUMBER() OVER (PARTITION BY PETICION_PK 
  ORDER BY DATETIME(DATE(GHI_FECHA), TIME(GHI_HORA)) ASC) AS ORDEN -- Primera Finalización de Informe
  FROM `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_GPC_HIST_ESTADO_acc` 
  WHERE ESTADO_PK = 7 
),

INFORME_RECIENTE AS (
    
    SELECT  A.PETICION_PK, A.INFORME_RESULTADO_PK, A.CODIGO_PERSONAL, B.GRI_INFORME,
            DATETIME(DATE(B.GRI_FECHA_INF), TIME(B.GRI_HORA_INF)) AS FH_INFORME_FH,
            ROW_NUMBER() OVER (PARTITION BY PETICION_PK 
  ORDER BY DATETIME(DATE(B.GRI_FECHA_INF), TIME(B.GRI_HORA_INF)) DESC) AS ORDEN -- Informe Más Recientes
  FROM  `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_GPC_INFORME_RESULTADO_acc` as A
  LEFT JOIN  `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_GPC_REVISION_INFORME_acc`  AS B
  ON A.informe_resultado_pk = B.informe_resultado_pk
)

SELECT  DISTINCT
        epi.epis_pk as EPISODIO,
        epi.CODIGO_CLIENTE,
        CONCAT(TRIM(cl.apellido1),' ',TRIM(cl.apellido2),' ',TRIM(cl.nombre)) as PACIENTE,
        cl.CODIGO1 AS DNI,
        cl.NAC_FECHA AS FECHA_NACIMIENTO_PACIENTE,
        -- Calcular edad PACIENTE al momento de la atentcions
        DATE_DIFF(DATE( gped.gpd_fecha_solic), DATE(NAC_FECHA), YEAR) AS EDAD_PACIENTE,

        -- Clasificación por grupos de edad
        CASE 
          WHEN DATE_DIFF(DATE( gped.gpd_fecha_solic), DATE(NAC_FECHA), YEAR) < 18 THEN "Pediátrico"
          WHEN DATE_DIFF(DATE( gped.gpd_fecha_solic), DATE(NAC_FECHA), YEAR) BETWEEN 18 AND 39 THEN "Joven adulto"
          WHEN DATE_DIFF(DATE( gped.gpd_fecha_solic), DATE(NAC_FECHA), YEAR) BETWEEN 40 AND 59 THEN "Adulto mediana edad"
          WHEN DATE_DIFF(DATE( gped.gpd_fecha_solic), DATE(NAC_FECHA), YEAR) >= 60 THEN "Adulto mayor"
        END AS EDAD_GRUPO ,
        CASE WHEN epi.tipo_episodio_pk = 1 THEN 'Emergencias'
        WHEN epi.tipo_episodio_pk = 2 THEN 'Consulta Externa'
        WHEN epi.tipo_episodio_pk = 3 THEN 'Hospital' else NULL end as TIPO_EPISODIO,
        gped.gpd_pedido as PEDIDO_PK,
        gpeti.peticion_pk as PETICION_PK,
        gped.gpd_fecha_solic as FECHA_SOLIC_EXAM,     
        gped.gpd_hora_solic as HORA_SOLIC_EXAM,
        gfamilia.Gfa_Nombre as CLASE_PRUEBA,
        gcat.GCA_CODIGO AS CODIGO_PRUEBA,
        gcat.GCA_NOMBRE AS NOMBRE_PRUEBA,
        gpeti.estado_pk AS ESTADO_PK, -- ESTADO ACTUAL DE LA PRUEBA
        gest.ges_nombre AS ESTADO_DESC, -- DESCRIPCION DEL ESTADO ACTUAL DE LA PRUEBA
        efin.FH_FINALIZADO AS FH_INFORME_FINALIZADO,
        --inf_fin.GRI_INFORME,
        REGEXP_EXTRACT(
        REGEXP_REPLACE(
        REGEXP_REPLACE(UPPER(inf_fin.GRI_INFORME), r'[S\- ]', ''),
         r'\r|\n', ' '),
        r'CONCLU.*?(BIRAD.{1})') AS BIRAD_INFORME,
        --los informes con los siguientes valores (BI-RADS, BI-RAD, BIRADS, BIRAD) + 4 o 5
        --cuando lleguemos a big query hay q considerar leer el informe desde la derecha, ya que el BIRAD se indica al final (conclusión).

         S_INGRESO.SERVICIO as SERVICIO_INGRESO,
         S_ATENCION.SERVICIO as SERVICIO_ATENCION,
         C.NOMBRE_CENTRO AS SEDE

    FROM `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_EPISODIOS_acc`  epi
    left join `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_CLIENTES_acc` cl
    on epi.codigo_cliente = cl.codigo_cliente
    left join `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_GPC_PEDIDO_acc` gped 
    on epi.epis_pk = gped.epis_pk  and epi.codigo_cliente = gped.codigo_cliente
    left join `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_GPC_PETICION_acc` gpeti 
    on gped.pedido_pk = gpeti.pedido_pk
    left join `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_GPC_FAMILIA_acc`  gfamilia 
    on gpeti.familia_pk = gfamilia.familia_pk and (gfamilia.familia_pk in (2))
    left join `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_GPC_PRUEBA_acc`  gprueba 
    on gpeti.peticion_pk = gprueba.peticion_pk
    left join `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_GPC_CATALOGO_acc`  gcat 
    on gprueba.catalogo_pk = gcat.catalogo_pk
    left join `ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_GPC_ESTADO_acc`  gest 
    on gpeti.estado_pk =  gest.estado_pk
    left join EXAMENES_FINALIZADOS as efin
    on gpeti.peticion_pk = efin.peticion_pk AND efin.ORDEN = 1
    left join INFORME_RECIENTE as inf_fin
    on inf_fin.peticion_pk = gpeti.peticion_pk AND inf_fin.ORDEN=1


    /* 18.09.25 - Agregar Servicio y Sede desde donde se solicita Examen*/

    /*Nuevo Cambio para Considerar Servicios por Tipo de Encuentro*/

/*Consulta Externa 30/05*/
LEFT JOIN ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_CEX_acc AS CEX ON
CEX.CEX_PK = epi.REFERENCIA_ID AND epi.tipo_episodio_pk = 2 -- CONSULTA EXTERNA--T1.CODIGO_SERVICIO1 = T4.CODIGO_SERVICIO
/*Hospitalizaciones 30/05*/
LEFT JOIN ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_INGRESOS_acc AS ING ON
ING.COD_INGRESO_PK = epi.REFERENCIA_ID AND epi.tipo_episodio_pk =3  --HOSPITAL
/*Emergencias 30/05*/
LEFT JOIN ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_URGENCIAS_acc URG ON
URG.ID_URGENCIA_PK = epi.REFERENCIA_ID AND epi.tipo_episodio_pk = 1 --EMERGENCIAS

/*Agrega Servicio Ingreso*/
LEFT JOIN ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_SERVICIOS_acc S_INGRESO ON 
S_INGRESO.CODIGO_SERVICIO = (CASE 
WHEN epi.tipo_episodio_pk = 1 then URG.CODIGO_SERVICIO
WHEN epi.tipo_episodio_pk = 3 then ING.CODIGO_SERVICIO
WHEN epi.tipo_episodio_pk = 2 then CEX.CODIGO_SERVICIO1
ELSE NULL END)

/*Agrega Servicio Atención*/
LEFT JOIN ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_SERVICIOS_acc S_ATENCION ON 
S_ATENCION.CODIGO_SERVICIO = (CASE 
WHEN epi.tipo_episodio_pk = 1 then URG.CODIGO_SERVICIO4
WHEN epi.tipo_episodio_pk = 3 then ING.CODIGO_SERVICIO4
WHEN epi.tipo_episodio_pk = 2 then CEX.CODIGO_SERVICIO1
ELSE NULL END) --BE_ENCUENTRO.SERVICIO_RESPONSABLE

/*Sede*/
LEFT JOIN ci-datalake-prod.ci_dtlk_bqd_access_prod.xhis6_CENTROS_acc C ON
S_INGRESO.COD_CENTRO = C.COD_CENTRO
    
WHERE epi.tipo_episodio_pk in (1,2,3) --Todos los tipos de Encuentro asociables a Mamografías
and gest.estado_pk = 7 --Estado Finalizado sin Revisar
and gcat.prest_item_pk in (756,758,762,763,764,765,1085659,1085660,1085661,1085662,1088783); -- Exámenes de Mamografía
--and epi.epis_pk = 23316482 AND gpeti.peticion_pk = 1408271
