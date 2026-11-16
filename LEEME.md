# Light SESA · IND2616 — Proyecto de series temporales

Todo lo que se entrega vive en esta carpeta: **un solo script**, un solo dataset
de trabajo y los resultados separados por etapa. El material histórico quedó
fuera, en `../4_archivo/` (nada se borró).

## Estructura

```
Light_SESA_IND2616/
│
├── 1_codigo/
│   └── Light_ARIMAX_ADAPTED_CSVS.R        ← EL script. Hace todo (Partes 1 a 10)
│
├── 2_datos/
│   ├── serie_mensual_light_gwh.csv        ← 140 meses (ene/2015 – ago/2026). Es la que se modela
│   └── crudos_SAMP/                       ← los 12 CSV originales de Light (~2,8 GB)
│                                             No hacen falta para correr el script: son la
│                                             procedencia del dato (los procesa R1.R)
│
├── 3_resultados/
│   ├── 0_cache/                           ← pesos y rolling ya calculados. No borrar
│   ├── 1_eda/                             ← serie, estacionalidad, STL, atípicos
│   ├── 2_pesos_bmc/                       ← LOS PESOS del ensamble (salida del bootstrap)
│   ├── 3_evaluacion_test/                 ← qué tan bien predice cada modelo
│   ├── 4_rolling_origin/                  ← validación en 21 ventanas móviles
│   ├── 5_pronostico/                      ← LA PREVISIÓN sep/2026 – ago/2027
│   ├── 6_apendices/                       ← impacto 2020 y cambios estructurales
│   └── sesion_R.txt                       ← versiones de R y de cada paquete
│
└── (nada más: esta carpeta es la entrega)

Proyecto_Series_Temporales/
└── 4_archivo/                             ← todo lo viejo, nada borrado
    ├── scripts/                           ← los 10 scripts que reemplazó el script único
    ├── entregas_previas/                  ← zip y salidas que ya habías entregado
    ├── resultados_antiguos/               ← salidas de las versiones con gd_step
    ├── graficos_exploracion/              ← PNG sueltos de exploración
    ├── sesion_rstudio/                    ← .RData y .Rhistory
    └── README.md                          ← qué hacía cada script viejo
```

## Cómo correr

1. Abre `1_codigo/Light_ARIMAX_ADAPTED_CSVS.R`.
2. Botón **Source**.

Con la caché que ya está en `0_cache/` tarda **menos de 1 minuto**.
La primera vez, sin caché, tarda ~3–4 min (y ~25 min si además recalcula los 200
bootstraps, o sea con `forzar_bootstrap <- TRUE`).

Si mueves la carpeta `Light_SESA_IND2616` a otro sitio, cambia una sola línea:
`carpeta_proyecto` en la Parte 0.1 del script. Todo lo demás es relativo.

## Reglas de uso

| Carpeta | Qué hacer |
|---|---|
| `1_codigo/` | Aquí se edita. Es el único script del proyecto. |
| `2_datos/` | Solo lectura. No modificar `serie_mensual_light_gwh.csv`. |
| `3_resultados/` | Se puede borrar completa: el script la regenera. |
| `../4_archivo/` | No tocar. Es historial y está fuera de la entrega. |

## Dos advertencias

- **`0_cache/` no se borra a la ligera**: si desaparece, el script vuelve a estimar
  los 200 bootstraps (~25 min) y las 21 ventanas del rolling (~2 min).
- El script reutiliza `2_pesos_bmc/frecuencias_pesos_BMC_COVID.csv` como resultado
  del bootstrap si no hay caché. Ese CSV **es** una salida válida: no hay que
  recalcularlo.

## Resultados

Los números finales y qué archivo citar para cada uno están en
**[RESULTADOS.md](RESULTADOS.md)**.
