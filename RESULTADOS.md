# Resultados finales — Light SESA · IND2616

Serie: consumo mensual facturado, TUSD CATIVO + LIVRE, **140 observaciones**
(ene/2015 – ago/2026). Intervención: pulso COVID abr–jun/2020.

---

## 1. La previsión oficial

**sep/2026 – ago/2027 · 12 meses · modelo ARIMAX_Covid**

Especificación estimada sobre las 140 observaciones:
**regresión con errores ARIMA(1,0,0)(1,1,1)[12]** — ar1 = 0,153; sar1 = −0,142;
sma1 = −0,788; dummy COVID = −306,4 GWh/mes; intercepto = −24,2.

| Mes | GWh | IC 80% | IC 95% |
|---|---:|---|---|
| 2026 sep | 1.775 | 1.647 – 1.904 | 1.579 – 1.972 |
| 2026 oct | 1.823 | 1.693 – 1.953 | 1.625 – 2.022 |
| 2026 nov | 1.901 | 1.771 – 2.031 | 1.703 – 2.100 |
| 2026 dic | 1.980 | 1.850 – 2.109 | 1.781 – 2.178 |
| 2027 ene | 1.995 | 1.866 – 2.125 | 1.797 – 2.194 |
| 2027 feb | 2.094 | 1.964 – 2.224 | 1.896 – 2.293 |
| 2027 mar | 2.116 | 1.986 – 2.246 | 1.917 – 2.314 |
| 2027 abr | 2.118 | 1.988 – 2.247 | 1.919 – 2.316 |
| 2027 may | 1.878 | 1.748 – 2.008 | 1.679 – 2.076 |
| 2027 jun | 1.788 | 1.659 – 1.918 | 1.590 – 1.987 |
| 2027 jul | 1.683 | 1.553 – 1.813 | 1.484 – 1.881 |
| 2027 ago | 1.660 | 1.531 – 1.790 | 1.462 – 1.859 |
| **Total** | **22.812** | | |

> Archivos: `3_resultados/5_pronostico/pronostico_2026_2027.csv` (largo, con IC),
> `..._ancho.csv` (una columna por modelo), `..._resumen.csv` (totales),
> `pronostico_2026_2027.png` (gráfico).

Robustez: los cinco modelos dan totales entre **22.743 y 22.812 GWh** (0,30 % de
diferencia), así que la cifra no depende de la elección del modelo.

---

## 2. Los pesos del BMC

| Modelo | Réplicas ganadas de 200 | Peso |
|---|---:|---:|
| ETS_Auto | 0 | 0,00 |
| ARIMA_Auto | 0 | 0,00 |
| ARIMAX_Covid | 200 | **1,00** |

> Archivo: `3_resultados/2_pesos_bmc/frecuencias_pesos_BMC_COVID.csv`

**Esto hay que decirlo en el artículo**: los pesos están degenerados, o sea que el
BMC es idéntico al ARIMAX. No es un error del método, es el resultado: el AICc
prefiere el ARIMAX en las 200 réplicas. Para mostrar un ensamble real se compara
con el promedio simple (`Ensamble_Simple`), que sí reparte 1/3 a cada modelo.

---

## 3. Evaluación fuera de muestra (test fijo, h = 12)

sep/2025 – ago/2026, 12 meses nunca usados en el ajuste.

| Modelo | RMSE | MAE | MAPE | MASE | Winkler 95 | Cob. 80 | Cob. 95 |
|---|---:|---:|---:|---:|---:|---:|---:|
| **ARIMA_Auto** | **71,2** | **59,4** | **3,13** | **0,473** | 458,1 | 91,7 % | 100 % |
| **ARIMAX_Covid** | 76,9 | 65,3 | 3,45 | 0,520 | **408,7** | 91,7 % | 100 % |
| BMC | 76,9 | 65,3 | 3,45 | 0,520 | 408,7 | 91,7 % | 100 % |
| Ensamble_Simple | 80,0 | 69,2 | 3,65 | 0,551 | 410,0 | 91,7 % | 100 % |
| ETS_Auto | 98,3 | 86,5 | 4,56 | 0,688 | 439,2 | 91,7 % | 100 % |

> Archivos: `3_resultados/3_evaluacion_test/evaluacion_test.csv`,
> `pronosticos_test.csv`, `evaluacion_test.png`.

MASE < 1 en todos: todos le ganan al naive estacional.

El ARIMA gana el punto (MASE), el ARIMAX gana la distribución (Winkler). El
modelo oficial es el ARIMAX porque gana el promedio de rangos de las cuatro
evaluaciones (ver §7).

---

## 4. Validación por origen rodante (21 ventanas, h = 12)

| Modelo | RMSE | MAE | MASE | Winkler 95 | Cob. 80 | Cob. 95 |
|---|---:|---:|---:|---:|---:|---:|
| **ETS_Auto** | **114,2** | **92,0** | **0,728** | 556,0 | 78,6 % | 93,3 % |
| Ensamble_Simple | 115,3 | 94,6 | 0,749 | 561,5 | 72,2 % | 93,7 % |
| ARIMAX_Covid | 117,0 | 97,3 | 0,770 | **542,1** | 70,2 % | 97,6 % |
| BMC | 117,0 | 97,3 | 0,770 | 542,1 | 70,2 % | 97,6 % |
| ARIMA_Auto | 128,4 | 105,6 | 0,836 | 608,0 | 77,0 % | 95,2 % |

> Archivos: `3_resultados/4_rolling_origin/rolling_resumen.csv`,
> `rolling_por_origen.csv`, `rolling_por_horizonte.csv`, `rolling_pronosticos.csv`,
> `rolling_MASE.png`, `rolling_Winkler.png`.

**El resultado más interesante del proyecto**: el ranking **no es estable**.
En el test gana ARIMA (0,473); en 21 ventanas gana ETS (0,728) y ARIMA queda
último (0,836). Eso es exactamente el argumento de incertidumbre de modelo, y es
la razón metodológica del BMC (que aquí no lo capitaliza por los pesos 0/0/1).

---

## 5. La intervención COVID

| Parámetro | Valor |
|---|---|
| Coeficiente | **−315,7 GWh/mes** |
| Error estándar | 57,4 |
| t | −5,50 |
| p-valor | 2,3 × 10⁻⁷ |

En abril 2020 el consumo fue 87,8 % de la base 2017–2019; en **mayo 79,9 %** y en
**junio 80,2 %** (el mínimo de la serie: 1.579 GWh).

> Archivos: Parte 4 del script (consola) y
> `3_resultados/6_apendices/apendice_impacto_2020.csv`.

---

## 6. Cambios estructurales (apéndice)

| Prueba | Estadístico | p-valor | Lectura |
|---|---:|---:|---|
| Chow, corte dic/2021 | 2,65 | 0,052 | Quiebre en el umbral del 5 % |
| supF (estabilidad) | 13,51 | 0,058 | Igual: evidencia marginal |
| F máximo | — | — | may/2023 |
| OLS-CUSUM | 1,01 | 0,257 | No rechaza estabilidad |

> Archivo: `3_resultados/6_apendices/apendice_cambios_estructurales.csv`

Lectura: la caída **no** es un escalón brusco en 2022, es una tendencia
descendente. Los dos ARIMA la capturan con una **deriva de ≈ −24 a −25 GWh/año**:
el ARIMA_Auto con `constant` −18,8 y el ARIMAX con intercepto −24,2 (ambos en la
escala de la diferencia anual; el AR(1) y el SAR(1) los amplifican). Es la
contraparte estadística de la migración al mercado libre y de la generación
distribuida. Contraste: las medias anuales caen de 2.198 GWh (2015) a 1.902 GWh
(2026), ≈ −27 GWh/año.

---

## 7. Qué modelo se usa y por qué

> Archivos: `3_resultados/5_pronostico/seleccion_modelo.csv` y
> `3_resultados/5_pronostico/comparacion_modelos.csv`

| Criterio | Métrica | Ganador | Valor |
|---|---|---|---:|
| Test fijo (h = 12) | MASE | ARIMA_Auto | 0,4732 |
| Test fijo (h = 12) | Winkler 95 % | ARIMAX_Covid | 408,7 |
| Origen rodante (21 ventanas) | MASE | ETS_Auto | 0,7284 |
| Origen rodante (21 ventanas) | Winkler 95 % | ARIMAX_Covid | 542,1 |
| **Rango medio (4 métricas)** | promedio de rangos | **ARIMAX_Covid** | **2,25** |
| **Usado en la previsión oficial** | — | **ARIMAX_Covid** | — |

La regla es el **promedio de rangos** sobre las cuatro métricas (1 = mejor). El
ARIMA acierta mejor el número (gana el MASE del test), pero el ARIMAX gana los
dos Winkler — intervalos más angostos sin perder cobertura — y sostiene ese
resultado en las 21 ventanas. Promediando los cuatro rangos: ARIMAX 2,25 · BMC
2,25 · ETS 3,25 · Ensamble 3,25 · ARIMA 4,00. El BMC empata con el ARIMAX porque
sus pesos son (0, 0, 1); el desempate prefiere el modelo individual.

**Por qué no AICc.** El AICc mide ajuste *dentro* de la muestra y la dummy COVID
lo inclina siempre hacia el ARIMAX (por eso los pesos del BMC colapsan). Para
elegir la previsión se usan métricas *fuera* de muestra.

**El modelo se elige, no se escribe.** En el script, `modelo_final` sale de la
tabla 8.1; la comparación es ejecutable:

```r
modelo_final_forzado <- NULL      # NULL = decide la tabla de la Parte 8.1
# modelo_final_forzado <- "ARIMA_Auto"   # override manual (el script avisa)
```

Los totales anuales de los cinco modelos difieren 0,30 % (22.743–22.812 GWh), así
que la cifra no depende de esta elección.

---

## 8. Archivos que **no** son resultados

- `1_eda/` y `6_apendices/`: soporte descriptivo para el artículo.
- `0_cache/`: intermedios del cálculo.
- `sesion_R.txt`: versiones para el apéndice de reproducibilidad.
- `4_archivo/`: todo lo anterior a la consolidación.
