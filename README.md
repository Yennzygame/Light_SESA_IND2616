# Light SESA · IND2616 — Pronóstico de demanda eléctrica

Pronóstico del consumo mensual facturado de **Light SESA** (TUSD CATIVO + LIVRE)
para **sep/2026 – ago/2027**, con intervención COVID y combinación de modelos.

- **Serie:** 140 meses (ene/2015 – ago/2026), SAMP/ANEEL.
- **Modelos comparados:** ETS, ARIMA, ARIMAX con pulso COVID, ensamble simple y
  BMC (bootstrap model combination).
- **Evaluación:** test fijo de 12 meses + origen rodante de 21 ventanas
  (MASE, Winkler 95 %, cobertura).
- **Modelo oficial:** ARIMAX, elegido por promedio de rangos de cuatro métricas
  fuera de muestra.
- **Previsión:** **22.812 GWh** en 12 meses; los cinco modelos difieren 0,30 %.

## Contenido

```
Light_SESA_IND2616/
├── 1_codigo/
│   └── Light_ARIMAX_ADAPTED_CSVS.R    script único (Partes 1 a 10)
├── 2_datos/
│   ├── serie_mensual_light_gwh.csv    serie consolidada (140 meses)
│   └── crudos_SAMP/                   solo un LEEME: los CSV crudos (~2,9 GB)
│                                      no se versionan
├── 3_resultados/                      salidas del script, por etapa
│   ├── 0_cache/                       caché de rolling
│   ├── 1_eda/                         gráficos y atípicos
│   ├── 2_pesos_bmc/                   pesos del bootstrap
│   ├── 3_evaluacion_test/             métricas del test fijo
│   ├── 4_rolling_origin/              métricas del origen rodante
│   ├── 5_pronostico/                  previsión, IC y comparación de modelos
│   └── 6_apendices/                   impacto 2020 y cambios estructurales
├── LEEME.md                           estructura y reglas de uso
└── RESULTADOS.md                      todos los números y qué archivo citar
```

## Cómo correr

1. Instalar R (>= 4.5) y los paquetes:

   ```r
   install.packages(c("fpp3", "readr", "urca", "strucchange"))
   ```

2. Abrir `1_codigo/Light_ARIMAX_ADAPTED_CSVS.R` y ajustar la ruta del proyecto
   en la Parte 0.1 (la línea `carpeta_proyecto <- "..."`).

3. Ejecutar el script completo (botón **Source** o `source()`).

Tiempo aproximado: **3–4 minutos** con la caché incluida. Si se fuerza el
bootstrap (`forzar_bootstrap <- TRUE`), ~25 minutos.

## Resultados principales

| Concepto | Valor |
|---|---|
| Modelo oficial | ARIMAX con errores ARIMA(1,0,0)(1,1,1)[12] |
| Efecto COVID (140 meses) | −306,4 GWh/mes (ee 60,7) |
| Previsión sep/2026 – ago/2027 | **22.812 GWh** |
| Ancho IC 95 % mensual | 392–397 GWh (≈ ±197) |
| Dispersión entre los 5 modelos | 0,30 % (22.743–22.812 GWh) |

Detalle completo, mes por mes y justificación de la elección:
**[RESULTADOS.md](RESULTADOS.md)**.

## Documentos de estudio

- [LEEME.md](LEEME.md) — estructura del proyecto y cómo ejecutarlo.
- [RESULTADOS.md](RESULTADOS.md) — resultados canónicos.

## Datos

La serie consolidada está incluida. Los 12 CSV crudos del SAMP (~2,9 GB) no se
versionan por tamaño; su procedencia y filtros están descritos en
`2_datos/crudos_SAMP/LEEME.txt`.

## Autor

_[Tu nombre]_ · IND2616 · Análise de Séries Temporais · PUC-Rio
