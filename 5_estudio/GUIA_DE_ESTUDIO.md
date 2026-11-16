# Guía de estudio — Light SESA · IND2616

**De la teoría a la previsión: qué hace el proyecto, por qué lo hace así y cómo defenderlo.**

Serie: consumo mensual facturado de Light SESA (TUSD CATIVO + LIVRE), 140 meses
(ene/2015 – ago/2026). Previsión oficial: sep/2026 – ago/2027.
Texto de referencia: Hyndman & Athanasopoulos, *Forecasting: Principles and
Practice*, 3.ª ed. (OTexts), <https://otexts.com/fpp3/>.

> Las secciones del libro se citan con su numeración de la edición online
> (por ejemplo, **FPP3 §9.9** = “Seasonal ARIMA models”). Si el profesor usa la
> edición impresa, los títulos son los mismos; los números pueden correrse uno.

---

## Índice

0. [Cómo usar esta guía](#0-cómo-usar-esta-guía)
1. [Panorama: el problema, el dato y el pipeline](#1-panorama)
2. [Parte 0 — Configuración, rutas y caché](#2-parte-0)
3. [Parte 1 — Carga y validación](#3-parte-1)
4. [Parte 2 — Intervención COVID y partición](#4-parte-2)
5. [Parte 3 — Análisis exploratorio](#5-parte-3)
6. [Parte 4 — ETS, ARIMA y ARIMAX](#6-parte-4)
7. [Parte 5 — Pesos del BMC por bootstrap](#7-parte-5)
8. [Parte 6 — Evaluación en test](#8-parte-6)
9. [Parte 7 — Origen rodante](#9-parte-7)
10. [Parte 8 — La previsión final, número por número](#10-parte-8)
11. [Parte 9 — Apéndices](#11-parte-9)
12. [Parte 10 — Salidas y reproducibilidad](#12-parte-10)
13. [Tabla maestra: concepto → FPP3 → código → resultado](#13-tabla-maestra)
14. [Banco de preguntas de defensa](#14-banco-de-preguntas)
15. [Ejercicios de verificación](#15-ejercicios)
16. [Plan de estudio en 10 sesiones](#16-plan-de-estudio)
17. [Glosario español ↔ inglés](#17-glosario)
18. [Erratas y correcciones importantes](#18-erratas)
19. [Qué sigue: artículo SBPO y slides](#19-qué-sigue)

---

## 0. Cómo usar esta guía

El proyecto tiene tres capas y esta guía las recorre siempre en el mismo orden:

| Capa | Qué es | Dónde está |
|---|---|---|
| **Teoría** | El método tal como lo enseña FPP3 | Libro (sección citada) |
| **Código** | La implementación | `1_codigo/Light_ARIMAX_ADAPTED_CSVS.R` |
| **Resultado** | El número, la tabla o el gráfico | `3_resultados/…` |

Cada módulo tiene la misma estructura:

1. **Objetivo** — qué tenés que poder explicar al terminar.
2. **Teoría mínima** — las fórmulas y la intuición, con la sección de FPP3.
3. **El código** — qué hace cada bloque y por qué está escrito así.
4. **Qué salió** — los números reales del proyecto.
5. **Si te preguntan** — 2 o 3 preguntas típicas con la respuesta corta.
6. **Ejercicio** — una verificación que podés correr en R.

**Rutas rápidas:**

- Si tenés **2 horas**: leé las secciones 1, 6, 10 y 14.
- Si tenés **un día**: 1 → 6 → 7 → 8 → 9 → 10 → 14.
- Si vas a **defender**: 10 + 13 + 14 + 15, con el script abierto al lado.

**Cómo correr el proyecto** (una sola vez, para tener todo fresco):

```r
# Abrir 1_codigo/Light_ARIMAX_ADAPTED_CSVS.R y pulsar Source.
# Con la caché de 0_cache/ tarda < 1 minuto.
# Sin caché pero con el CSV de pesos: ~3-4 min.
# Recalculando los 200 bootstraps (forzar_bootstrap <- TRUE): ~25 min.
```

---

## 1. Panorama

### 1.1 La pregunta

> ¿Cuánta energía va a facturar Light SESA cada mes entre septiembre de 2026 y
> agosto de 2027, y con qué incertidumbre?

Es un problema de **previsión de demanda** a 12 meses, con tres rasgos que
condicionan todo el método:

1. **Estacionalidad fuerte**: el consumo sube en verano (feb–mar) y baja en
   invierno (jul–ago). La estacionalidad explica ~60 % de la variabilidad.
2. **Tendencia descendente suave**: las medias anuales caen de 2.198 GWh (2015)
   a 1.902 GWh (2026), ≈ −27 GWh/año, por migración al mercado libre y
   generación distribuida.
3. **Un choque enorme y transitorio**: la pandemia (abr–jun/2020), con una caída
   de hasta el 20 % respecto de la base 2017–2019.

### 1.2 El dato

| Característica | Valor |
|---|---|
| Archivo de trabajo | `2_datos/serie_mensual_light_gwh.csv` |
| Columnas | `Mes`, `Consumo_GWh`, `Registros` |
| Frecuencia | mensual, sin huecos |
| Observaciones | 140 (ene/2015 – ago/2026) |
| Media | 2.041 GWh/mes |
| Desvío | 204 GWh |
| Mínimo | 1.579,3 GWh (jun/2020) |
| Máximo | 2.531,0 GWh (ene/2015) |

`Registros` (cantidad de facturas) **no se usa** en el modelo: es información de
clientes, no de consumo. Queda como posible covariable para una extensión.
Los 12 CSV crudos de `2_datos/crudos_SAMP/` (~2,9 GB) son la procedencia; el
script **no** los necesita.

### 1.3 Qué se predice y por qué 12 meses

El horizonte es 12 meses porque:

- es el horizonte de planificación tarifaria/anual de la distribuidora;
- coincide exactamente con el test fijo (sep/2025 – ago/2026) y con el horizonte
  de cada ventana del origen rodante, de modo que **todas** las métricas de
  selección se evalúan al mismo plazo que la previsión;
- con 140 observaciones, 12 pasos es un horizonte razonable para un modelo
  estacional: más allá de 12–24 meses, la incertidumbre y los cambios
  regulatorios dominan.

### 1.4 El pipeline en una imagen

```
CSV mensual (140)
   │
   ├─ Parte 1  validar tsibble (índice, huecos, NA)
   │
   ├─ Parte 2  covid = pulso abr–jun/2020
   │           train = ene/2015–ago/2025 (128)
   │           test  = sep/2025–ago/2026 (12)
   │
   ├─ Parte 3  EDA: serie, estacionalidad, STL, atípicos,
   │           Guerrero, KPSS, ACF/PACF
   │
   ├─ Parte 4  tres modelos base: ETS, ARIMA, ARIMAX(COVID)
   │
   ├─ Parte 5  bootstrap MBB + AICc → pesos del BMC
   │           (200 réplicas, bloques de 2 meses)
   │
   ├─ Parte 6  evaluar en el test fijo (h = 12)
   │           RMSE/MAE/MAPE/MASE/Winkler/cobertura
   │
   ├─ Parte 7  validar en 21 orígenes rodantes (h = 12)
   │
   ├─ Parte 8  comparar por rangos → elegir modelo
   │           reajustar con las 140 obs → previsión oficial
   │
   ├─ Parte 9  apéndices: impacto 2020, cambios estructurales
   │
   └─ Parte 10 inventario + sessionInfo
```

### 1.5 Notación

| Símbolo | Significado |
|---|---|
| \(y_t\) | consumo en el mes \(t\) (GWh) |
| \(B\) | operador de retardo: \(B y_t = y_{t-1}\) |
| \(\Delta_{12}\) | diferencia estacional: \((1-B^{12})y_t = y_t - y_{t-12}\) |
| \(m\) | período estacional = 12 |
| \(\varepsilon_t\) | innovación (error blanco) |
| \(h\) | horizonte de pronóstico (meses hacia adelante) |
| \(d, D\) | órdenes de diferenciación regular y estacional |
| \(p, q, P, Q\) | órdenes AR, MA, SAR, SMA |

---

## 2. Parte 0 — Configuración, rutas y caché

**FPP3:** §5.1 (flujo de trabajo ordenado) y Apéndice *Using R*.
**Código:** líneas 55–221.

### 2.1 Objetivo

Que todo lo que un lector necesita para reproducir esté en **un solo lugar**, y
que mover el proyecto no obligue a editar 20 rutas.

### 2.2 Qué hace el código

**(a) Rutas relativas a una raíz.** Solo hay dos rutas absolutas:

```r
carpeta_proyecto   <- "C:/Users/.../Light_SESA_IND2616"
carpeta_datos      <- file.path(carpeta_proyecto, "2_datos")
carpeta_resultados <- file.path(carpeta_proyecto, "3_resultados")
```

Todo lo demás se construye con `file.path()`. Si movés la carpeta, cambiás una
línea. Esto es lo que hace que el script sea “portable” sin depender del
directorio de trabajo de RStudio.

**(b) Un mapa de salidas.** `subcarpetas` asocia cada etapa (EDA, pesos, test…)
con su carpeta; `destino_salida` asocia cada **nombre de archivo** con su etapa.
La función `nombre_archivo()` traduce nombre → ruta final y acepta vectores, por
eso la Parte 10 puede listar todo con una sola llamada.

**(c) Parámetros metodológicos.** Todo lo que hay que reportar está arriba:

| Parámetro | Valor | Por qué |
|---|---|---|
| `semilla` | 2616 | reproducibilidad del bootstrap |
| `inicio_covid` / `fin_covid` | abr/2020 – jun/2020 | confinamiento severo |
| `fin_train` | ago/2025 | deja 12 meses para test |
| `h_test` | 12 | mismo horizonte que la previsión |
| `inicio_rolling` / `n_origenes` | dic/2022 / 21 | 21 ventanas con 12 meses futuros |
| `B_bootstrap` | 200 | precisión de las frecuencias |
| `tamano_tanda` | 25 | checkpoint y progreso |
| `B_intervalos` | 2000 | bandas empíricas estables |
| `num_cores` | 4 | 6 núcleos / 12 hilos; no saturar RAM |
| `modelo_final_forzado` | `NULL` | `NULL` = el modelo lo elige la tabla 8.1 |

**(d) Caché.** `bmc_bootstrap.rds` guarda pesos, frecuencias y advertencias;
`bmc_bootstrap_parcial.rds` permite reanudar; `rolling_cache.rds` guarda las 21
ventanas. `cache_valida()` compara la lista de parámetros con `identical()`: si
cambiaste `B`, semilla, `fin_train`, método o largo de bloque, **recalcula**. Esa
es la forma correcta de cachear: la caché no es “un archivo viejo”, es “el
resultado de estos parámetros exactos”.

**(e) Utilidades.** `guardar()` escribe CSV; `guardar_png()` guarda a 300 dpi;
`normalizar_nombre()` compara `"ARIMAX_COVID"` con `"ARIMAX_Covid"` ignorando
mayúsculas y separadores; `titulo()` imprime separadores en consola.

### 2.3 Por qué está así

- **Una sola fuente de verdad para las rutas** evita el error clásico de tener
  salidas en `D:/`, `C:/Users/...` y la carpeta de descargas a la vez.
- **Caché con validación de parámetros** evita dos errores opuestos: recalcular
  25 minutos por nada, o reutilizar un resultado de otra configuración.
- **Semilla fija** hace que el bootstrap sea determinista: misma semilla + mismos
  datos + mismo `B` → mismos pesos. Sin eso, el artículo no sería replicable.

### 2.4 Si te preguntan

> **¿Por qué no usás `setwd()`?**
> Porque `setwd()` hace que el script dependa del entorno y rompe la
> reproducibilidad. Con rutas construidas desde `carpeta_proyecto`, el script
> corre igual desde RStudio, Rscript o un notebook.

> **¿Por qué el bootstrap se cachea y el resto no?**
> Porque es lo único caro (~200 réplicas × 3 modelos). El resto tarda segundos y
> se recalcula siempre, para que los resultados reflejen el código actual.

---

## 3. Parte 1 — Carga y validación

**FPP3:** §2.1 (`tsibble`), §2.3 (patrones), §5.1 (flujo tidy).
**Código:** líneas 223–248.

### 3.1 Objetivo

Convertir un CSV en un objeto temporal **regular**, y fallar temprano si el dato
no sirve.

### 3.2 Teoría

Un `tsibble` es un data frame con:

- una **variable índice** (`index`), que define el tiempo;
- opcionalmente **claves** (`key`), para varias series;
- un **intervalo** conocido (`1M`), que permite verificar regularidad.

`yearmonth("2020 Apr")` crea un índice mensual ordenado. `has_gaps()` detecta
meses faltantes; `as_tsibble(index = Mes)` no inventa datos.

### 3.3 El código

```r
datos <- read_csv(archivo_datos, show_col_types = FALSE) %>%
  mutate(Mes = yearmonth(Mes)) %>%
  select(Mes, Consumo_GWh) %>%
  arrange(Mes) %>%
  as_tsibble(index = Mes)

if (nrow(datos) == 0 || anyNA(datos$Consumo_GWh)) stop(...)
if (has_gaps(datos)$.gaps) stop(...)
```

Tres decisiones:

1. **`select(Mes, Consumo_GWh)`**: se descarta `Registros` para que el modelo no
   lo use por accidente.
2. **`arrange(Mes)` antes de `as_tsibble()`**: el índice debe estar ordenado.
3. **Validación explícita**: si hay un NA o un hueco, el script se detiene con un
   mensaje claro, en vez de producir un modelo silenciosamente sesgado.

### 3.4 Qué salió

```
Observaciones: 140
Rango: 2015 ene. a 2026 ago.
Media: 2041 GWh/mes
```

### 3.5 Si te preguntan

> **¿Qué pasa si falta un mes?**
> `has_gaps()` lo detecta y el script aborta. La alternativa sería imputar
> (FPP3 §13.9), pero imputar el consumo antes de modelar inventa información; es
> preferible corregir la fuente.

> **¿Por qué mensual y no diario?**
> Porque la decisión de facturación y el horizonte son mensuales; además, la
> serie diaria tendría estacionalidad semanal y feriados (FPP3 §13.1), un
> problema distinto.

---

## 4. Parte 2 — Intervención COVID y partición

**FPP3:** §7.4 (variables dummy), §10.1–10.2 (regresión con errores ARIMA).
**Código:** líneas 250–275.

### 4.1 Objetivo

Representar el choque pandémico **sin confundirlo con la tendencia**, y separar
un conjunto de prueba que nunca se use para estimar.

### 4.2 Teoría: pulso vs escalón

Una intervención se modela con una dummy:

- **Pulso**: \(D_t = 1\) solo en los meses del choque (acá, abr–jun/2020).
  Captura un efecto **transitorio**.
- **Escalón** (`step`): \(D_t = 1\) desde una fecha en adelante, para siempre.
  Captura un **cambio permanente de nivel**.

El proyecto usa **pulso** porque la serie se recuperó: en jul/2020 ya estaba en
96 % de la base 2017–2019 y en oct/2020 en 104 %. Un escalón desde 2020 habría
absorbido la caída y **la tendencia posterior**, sesgando la deriva.

> Ojo: la versión vieja usaba `gd_step` (escalón). Se eliminó a pedido: el
> escalón no representa la recuperación y compite con el drift.

### 4.3 El código

```r
datos <- datos %>%
  mutate(covid = if_else(Mes >= inicio_covid & Mes <= fin_covid, 1, 0))

train_data <- datos %>% filter(Mes <= fin_train)
test_data  <- datos %>% filter(Mes >  fin_train)
```

Y dos validaciones:

- `nrow(test_data) == h_test`: si agregás datos nuevos, el test deja de tener 12
  meses y el script avisa. Es una protección contra comparar métricas de
  horizontes distintos.
- `sum(train_data$covid) > 0`: la dummy tiene que estar dentro del
  entrenamiento; si no, el coeficiente no es estimable.

### 4.4 Por qué el test es sep/2025 – ago/2026

Porque es el **último bloque de 12 meses** y deja 128 meses para estimar. Es un
test genuino: esos 12 meses no se usan en ninguna parte del ajuste, ni en la
selección de orden, ni en los pesos del BMC. (Los pesos se estiman con el train;
ver §7.)

### 4.5 Si te preguntan

> **¿Por qué no un escalón desde 2020?**
> Porque la caída fue transitoria. El escalón habría dicho “el nivel bajó para
> siempre en 2020”, y la evidencia muestra una recuperación en el mismo 2020 y
> una tendencia descendente gradual después. Además, los tests de cambio
> estructural (§11) no encuentran un quiebre nítido.

> **¿No hay fuga de información al usar el test para elegir el modelo?**
> Sí, hay una decisión post hoc: se elige el modelo con el mejor promedio de
> rangos sobre el test fijo **y** el origen rodante. Eso es una limitación de todo
> trabajo aplicado; se mitiga (a) incluyendo el origen rodante, que evalúa 21
> ventanas fuera de la muestra y no una sola, y (b) mostrando que los cinco
> modelos dan totales casi idénticos. Está discutido en §10.8.

---

## 5. Parte 3 — Análisis exploratorio

**FPP3:** §2.2–2.4 (gráficos), §2.8 (ACF), §3.1 (transformaciones/Guerrero),
§3.6 (STL), §9.1 (estacionariedad y diferenciación), §13.9 (atípicos).
**Código:** líneas 277–360.

### 5.1 Objetivo

Antes de modelar, responder cuatro preguntas:

1. ¿Hay tendencia? ¿De qué forma?
2. ¿La estacionalidad es estable o cambia de forma?
3. ¿Hay atípicos que un modelo no robusto confundiría con señal?
4. ¿Cuántas diferencias hacen falta para que la serie sea estacionaria?

### 5.2 Los gráficos

**(a) Serie completa** (`eda_serie.png`):

```r
g_serie <- autoplot(datos, Consumo_GWh) + ...
```

Muestra: tendencia descendente suave, dientes estacionales, caída de 2020 y un
pico en abr/2025 (2.455 GWh).

**(b) Gráfico estacional** (`eda_estacional.png`):

```r
datos %>% gg_season(Consumo_GWh)
```

Cada línea es un año. Se ve que:

- la forma se repite (pico en feb–mar, valle en jul–ago);
- las líneas post-2020 están por debajo de las pre-2020 (nivel, no forma);
- 2020 es la línea más baja; 2025–2026 se recuperan parcialmente.

**Por qué importa**: si la forma fuera inestable, una descomposición con
estacionalidad fija sería inválida; acá la forma es estable y el nivel cambia.

**(c) STL** (`eda_stl.png`):

```r
fit_stl <- train_data %>% model(STL(Consumo_GWh, robust = TRUE))
components(fit_stl) %>% autoplot()
```

STL = *Seasonal-Trend decomposition using Loess* (FPP3 §3.6). Separa:

- `trend`: loess sobre la serie desestacionalizada;
- `season_year`: la forma estacional (12 valores que se repiten);
- `remainder`: lo que queda.

`robust = TRUE` ajusta dos veces y **baja el peso de los atípicos** en la
estimación de tendencia y estacionalidad. Es importante acá porque 2020 tiene
caídas de 300–440 GWh que, sin robustez, arrastrarían la tendencia.

**Varianza explicada** (train): tendencia 7.998; estacionalidad 25.138;
residuo 8.936. Es decir, **~60 % de la variabilidad es estacional**, ~19 %
tendencia y ~21 % resto. De ahí que el modelo tenga que ser estacional.

**(d) Atípicos** (`eda_atipicos_stl.csv`): regla de **3 × IQR** sobre el
`remainder`:

```r
lim_inf <- quantile(rem, .25) - 3 * IQR(rem)
lim_sup <- quantile(rem, .75) + 3 * IQR(rem)
```

¿Por qué 3 y no 1,5 (Tukey)? Con 128 puntos, 1,5×IQR marcaría demasiados meses
normales; 3×IQR es conservador y deja solo los extremos genuinos. Resultado:

| Mes | Consumo | Residuo STL | Lectura |
|---|---:|---:|---|
| feb/2018 | 2.053 | −281 | ola de calor/feriado |
| may/2020 | 1.750 | −305 | COVID |
| jun/2020 | 1.579 | −337 | COVID (mínimo) |
| jul/2022 | 1.988 | +282 | rebote post-pandemia |
| abr/2025 | 2.455 | +359 | pico puntual |

**No se eliminan.** Son observaciones reales; el modelo los maneja con la dummy
COVID (2020) y con errores robustos en la descomposición. Eliminarlos sesgaría
la cola y la estimación de la incertidumbre.

### 5.3 Estacionariedad

**(a) Guerrero / Box-Cox.** `features(y, guerrero)` estima \(\lambda\) que
estabiliza la varianza (FPP3 §3.1). Resultado: **λ = 0,191**. Un valor cercano a
0 sugiere transformación logarítmica; cercano a 1, dejar en niveles. 0,19 es un
punto intermedio.

**Decisión:** se modela en **niveles**. Razones:

- el ETS usa error y estacionalidad **multiplicativos**, que ya manejan la
  heterocedasticidad proporcional al nivel;
- los residuos del ARIMA no muestran heterocedasticidad severa (Ljung-Box y ACF
  limpios);
- una transformación cambiaría la interpretación de los intervalos y de la
  dummy COVID (efecto multiplicativo vs aditivo).
  Queda como extensión: `ARIMA(log(y) ~ covid)`.

**(b) KPSS y número de diferencias.**

```r
train_data %>% features(Consumo_GWh,
  list(unitroot_kpss, unitroot_ndiffs, unitroot_nsdiffs))
```

Resultado: **KPSS = 0,707, p = 0,0129** (rechaza estacionariedad en nivel);
`ndiffs = 1`, `nsdiffs = 1`.

Lectura correcta:

- El test se corre sobre la serie **en niveles**. `nsdiffs = 1` dice “diferenciá
  estacionalmente”.
- `ndiffs = 1` sugiere una diferencia regular, pero **el modelo final usa
  d = 0**. ¿Contradicción? No: `ARIMA()` en `fable` selecciona `d` **después** de
  aplicar la diferencia estacional. Una vez que \(y_t - y_{t-12}\) es
  estacionaria, la persistencia que queda (ACF lag 1 = 0,267) la absorbe un
  AR(1); agregar otra diferencia sería sobre-diferenciar.
- Regla práctica: los tests son **asesores**; la decisión final se valida con
  AICc y con los residuos.

**(c) ACF/PACF de la serie diferenciada** (`eda_acf_pacf.png`):

```r
train_data %>% gg_tsdisplay(difference(Consumo_GWh, 12),
                            plot_type = "partial", lag_max = 36)
```

Lo que se ve (y lo que importa):

| Patrón | Valor | Implica |
|---|---:|---|
| ACF lag 1 | +0,267 | AR(1) o MA(1) de corto plazo |
| ACF lag 12 | **−0,465** | MA estacional (SMA(1)) |
| ACF decae rápido | — | no hace falta más diferenciación |

**Este es el puente entre el EDA y el modelo.** El modelo final
ARIMA(1,0,0)(1,1,1)[12] tiene exactamente eso: un AR(1) (0,296) para el lag 1 y
un SMA(1) (−0,801) para el lag 12. La ACF “vio” el modelo antes de estimarlo.

### 5.4 Si te preguntan

> **¿Por qué STL y no descomposición clásica?**
> Porque STL permite tendencia suave (loess), estacionalidad que puede cambiar
> lentamente y robustez ante atípicos. La clásica usa medias móviles y es más
> rígida (FPP3 §3.4 vs §3.6).

> **¿Por qué no se quitó 2020 de la muestra?**
> Porque es información real y el modelo debe aprender que esos shocks existen.
> Se modela con una dummy y con STL robusto; quitarlo haría que el intervalo de
> pronóstico subestime la posibilidad de otro shock.

> **λ = 0,19, ¿no deberías usar log?**
> Es defendible. No se hizo para mantener las unidades (GWh) y la dummy aditiva,
> y porque los residuos son aceptables. Si querés una mejora, probá
> `ARIMA(log(Consumo_GWh) ~ covid)` y compará MASE; no cambia la conclusión
> estacional.

---

## 6. Parte 4 — ETS, ARIMA y ARIMAX

**FPP3:** cap. 8 (ETS: §8.4 taxonomía, §8.5 modelos de espacio de estados,
§8.6 estimación/selección); cap. 9 (§9.1–9.7 ARIMA, §9.9 estacional);
§10.2 (regresión con errores ARIMA); §5.3–5.4 (residuos).
**Código:** líneas 362–407.

### 6.1 Objetivo

Estimar **tres familias** con la misma data de entrenamiento, para comparar
supuestos distintos:

| Modelo | Supuesto | Rol |
|---|---|---|
| `ETS_Auto` | suavizado exponencial, nivel + estacionalidad | referencia sin covariables |
| `ARIMA_Auto` | dinámica autorregresiva de la serie | referencia univariada |
| `ARIMAX_Covid` | ARIMA + efecto COVID | mide el choque y compite |

### 6.2 ETS: teoría mínima

El modelo elegido por AICc es **ETS(M,N,M)**:

- **M** error multiplicativo;
- **N** sin tendencia;
- **M** estacionalidad multiplicativa, período 12.

Ecuaciones (FPP3 §8.5):

\[
y_t = l_{t-1}\, s_{t-12}\,(1+\varepsilon_t)
\]
\[
l_t = l_{t-1}\,(1+\alpha \varepsilon_t)
\]
\[
s_t = s_{t-12}\,(1+\gamma \varepsilon_t)
\]

Parámetros estimados (train):

- \(\alpha = 0,167\): el nivel se actualiza moderadamente; no reacciona a cada
  punto.
- \(\gamma = 0,0001 \approx 0\): la forma estacional **no** se actualiza; queda
  fija en la estimación inicial.
- \(\sigma^2 = 0,0028\): varianza del error **relativo** (~0,28 %), consistente
  con un error multiplicativo.

Los índices estacionales (relativos, alrededor de 1), ordenados por mes:

| Ene | Feb | Mar | Abr | May | Jun | Jul | Ago | Sep | Oct | Nov | Dic |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1,073 | 1,095 | **1,112** | 1,082 | 0,987 | 0,931 | 0,897 | **0,895** | 0,927 | 0,955 | 1,001 | 1,045 |

Es decir: pico en **marzo** (+11,2 % sobre el nivel) y valle en **agosto**
(−10,5 %). Coincide con la intuición: verano con aire acondicionado, invierno
con menos actividad.

**¿Por qué N (sin tendencia)?** Porque la tendencia es suave y el AICc prefiere
un nivel adaptativo antes que una tendencia lineal; además, una tendencia
estimada sobre 128 meses sería arrastrada por la caída de 2020. El precio es que
ETS **no extrapola la tendencia**: su previsión es “nivel actual × estacionalidad”,
plana en el nivel.

### 6.3 ARIMA: teoría mínima

Un ARIMA(p,d,q)(P,D,Q)[m] se escribe con el operador de retardo (FPP3 §9.2,
§9.5, §9.9):

\[
\phi_p(B)\,\Phi_P(B^{m})\,(1-B)^d (1-B^{m})^D\, y_t
= c + \theta_q(B)\,\Theta_Q(B^{m})\,\varepsilon_t
\]

- \(d\): diferencias regulares (quitan tendencia).
- \(D\): diferencias estacionales (quitan el patrón que se repite cada 12).
- \(p,q\): AR/MA de corto plazo.
- \(P,Q\): AR/MA estacionales.

**El ARIMA sin intervención (candidato; estimado con las 140 observaciones)** es
(el modelo **oficial** es el ARIMAX, cuya ecuación está en §10.3):

\[
(1-0,296B)(1+0,104B^{12})(1-B^{12})\,y_t
= -18,76 + (1-0,801B^{12})\,\varepsilon_t
\]

Lectura de cada pieza:

| Pieza | Valor | Qué significa |
|---|---:|---|
| \(d=0\) | — | no hace falta diferencia regular |
| \(D=1\) | — | una diferencia estacional: se modela \(y_t-y_{t-12}\) |
| AR(1) | 0,296 | un mes “arrastra” al siguiente (~30 %) |
| SAR(1) | −0,104 | corrección leve respecto del mismo mes del año anterior |
| SMA(1) | **−0,801** | el error del mismo mes del año anterior se corrige fuerte |
| \(c\) | −18,76 | intercepto de la ecuación de \(\Delta_{12}\) |
| deriva implícita | **≈ −24,1 GWh/año** | \(c/[(1-\phi)(1-\Phi)]\) |

**Ojo con la deriva.** `report()` imprime `constant = −18,76`. Como el modelo
tiene \(D=1\), ese número está en **GWh por año**, no por mes; y como además hay
AR(1) y SAR(1), el cambio anual de largo plazo es
\(-18,76/[(1-0,296)(1+0,104)] = -24,1\) GWh/año (≈ −2,0 GWh/mes). La versión
anterior de `RESULTADOS.md` decía “−18,8 GWh/mes ≈ −225 GWh/año”; era un error de
unidades. Contraste empírico: las medias anuales caen ≈ −27 GWh/año.

**¿Por qué el SMA es tan negativo?** Porque después de diferenciar
estacionalmente, el ACF en el lag 12 es −0,465. Un MA(1) estacional con
\(\Theta=-0,801\) implica una autocorrelación en lag 12 de
\(\Theta/(1+\Theta^2) = -0,49\), casi exactamente lo observado. El modelo está
capturando la “memoria” del año anterior.

**Advertencia técnica:** un SMA cercano a −1 puede indicar sobre-diferenciación
estacional (la raíz del MA casi cancela la raíz unitaria). Acá \(-0,80\) está
cerca pero no en −1; el AICc y los residuos lo respaldan. Es un punto que conviene
mencionar como limitación, no ocultar (ver §10.6).

### 6.4 ARIMAX: regresión con errores ARIMA

**FPP3 §10.2.** El modelo es:

\[
y_t = \beta_0 + \beta_1\,\text{covid}_t + \eta_t,
\qquad \eta_t \sim \text{ARIMA}(1,0,0)(1,1,1)[12]
\]

Es decir: la serie tiene una parte explicada por la dummy COVID y una parte
autorregresiva. No es “regresión + ARIMA” por separado; es una sola verosimilitud
(regresión con errores correlacionados), que es lo correcto cuando los residuos
de la regresión están autocorrelacionados.

Coeficientes (train):

| Término | Estimación | EE | t | p |
|---|---:|---:|---:|---:|
| `covid` | **−315,7** | 57,4 | −5,50 | 2,3 × 10⁻⁷ |
| `intercept` | −22,3 | 3,2 | −6,94 | 2,4 × 10⁻¹⁰ |

Interpretación: en abr–jun/2020, el consumo fue **315,7 GWh/mes menor** de lo que
el modelo habría predicho sin pandemia. El intervalo del 95 % es
\(-315,7 \pm 1,96 \times 57,4 = [-428,2,\ -203,2]\), siempre negativo y lejos de
cero.

Con la serie completa (140 obs), el coeficiente es **−306,4** (EE 60,7): se
mantiene estable al agregar 12 meses, buena señal.

**¿Por qué el coeficiente no coincide con la caída bruta?** Porque es un efecto
**condicional**: descuenta la tendencia y la estacionalidad del período. La
caída bruta de mayo/2020 fue 440 GWh respecto de la base 2017–2019; el modelo
atribuye 316 a la pandemia y el resto a nivel/tendencia/estacionalidad.

### 6.5 AICc: qué es y qué premia

**FPP3 §9.6.** Para comparar modelos con distinta cantidad de parámetros:

\[
\text{AIC} = -2\ell + 2k, \qquad
\text{AICc} = \text{AIC} + \frac{2k(k+1)}{n-k-1}
\]

donde \(\ell\) es la log-verosimilitud y \(k\) el número de parámetros. El
término extra castiga \(k\) cuando \(n\) no es enorme. **Menor es mejor.**

Resultados (train, 128 obs):

| Modelo | \(k\) | AICc |
|---|---:|---:|
| ETS(M,N,M) | ~14 | 1.841,9 |
| ARIMA(0,0,2)(0,1,1)[12] + drift | 5 | 1.443,6 |
| ARIMAX(0,0,0)(0,1,1)[12] + covid | 4 | **1.425,4** |

El ARIMAX gana por AICc: la dummy COVID reduce tanto la varianza residual que
compensa el parámetro extra. **Pero AICc es ajuste in-sample**; no dice nada
sobre el test. Esa distinción es el corazón del proyecto (ver §8 y §9).

Con la serie completa, el orden se mantiene: ARIMAX 1.564,1 < ARIMA 1.582,6 <
ETS 2.015,0.

### 6.6 Diagnóstico de residuos

**FPP3 §5.4.** Un modelo es adecuado si los residuos se comportan como ruido
blanco:

- `gg_tsresiduals()`: serie, ACF y histograma.
- Ljung-Box con 24 lags: \(H_0\): no hay autocorrelación hasta el lag 24.

Resultados (train):

| Modelo | Ljung-Box (24) | p |
|---|---:|---:|
| ARIMA | 11,0 | 0,989 |
| ARIMAX | 13,3 | 0,960 |
| ETS | 18,9 | 0,758 |

Ninguno rechaza: no hay autocorrelación residual evidente. Con la serie completa
pasa lo mismo (p = 0,966 / 0,981 / 0,762). Es un chequeo necesario, no suficiente:
un modelo puede pasar Ljung-Box y aun así pronosticar mal fuera de muestra.

### 6.7 Si te preguntan

> **¿Por qué ETS(M,N,M) y no ETS(A,A,A)?**
> Porque `ETS()` prueba todas las familias y elige por AICc. La ganadora tiene
> error y estacionalidad multiplicativos (la amplitud estacional crece con el
> nivel) y no tiene tendencia (la tendencia es débil y el nivel adaptativo basta).

> **¿Por qué el ARIMA no tiene diferenciación regular si KPSS dijo 1?**
> Porque el test se corrió en niveles y `ARIMA()` decide `d` después de la
> diferenciación estacional. Sobre \(\Delta_{12}y\), el AR(1) absorbe la
> persistencia; una diferencia más sería sobre-diferenciar.

> **¿AICc elige el mejor modelo para pronosticar?**
> No. AICc elige el que mejor ajusta con penalidad por complejidad. El mejor
> pronóstico se decide con métricas fuera de muestra. Acá AICc prefiere ARIMAX,
> el test fijo prefiere ARIMA en MASE y ETS en el rolling, pero el rango medio de
> las cuatro evaluaciones (MASE y Winkler, test y rolling) elige ARIMAX.

---

## 7. Parte 5 — Pesos del BMC por bootstrap

**FPP3:** §12.5 (bootstrapping y bagging), §13.4 (combinación de pronósticos),
§3.6 (STL), §9.6 (AICc).
**Código:** líneas 409–715.

### 7.1 Objetivo

Construir un **ensamble** (BMC = *Bootstrap Model Combination*) cuyos pesos
reflejen la incertidumbre sobre **qué modelo es el correcto**, no solo el ajuste
de un único modelo.

### 7.2 La idea en cinco pasos

```
1. Quitar el efecto COVID de la serie de entrenamiento.
2. STL con estacionalidad fija → tendencia + estacionalidad + residuo.
3. Remuestrear bloques del residuo (Moving Block Bootstrap).
4. En cada réplica, rearmar la serie y ajustar ETS, ARIMA y ARIMAX.
5. Peso de cada modelo = frecuencia con que tuvo el menor AICc.
```

Es un **bootstrap de residuos**, no de la serie completa: la tendencia y la
estacionalidad se mantienen fijas y solo se perturba el resto. Eso hace que el
ensamble herede la estructura del proyecto, pero también limita lo que la
incertidumbre representa (ver §7.7).

### 7.3 Paso 1: quitar COVID

```r
serie_sin_covid <- train_data %>%
  mutate(consumo_ajustado = Consumo_GWh - coef_covid * covid)
```

Si no se quitara, el STL asignaría la caída de 2020 a la tendencia y el residuo
quedaría contaminado; el bootstrap reproduciría ese artefacto. Al restarlo, la
descomposición ve la serie “sin pandemia” y la dummy se reinserta después.

### 7.4 Paso 2: STL con estacionalidad periódica

```r
componentes_stl <- serie_sin_covid %>%
  model(STL(consumo_ajustado ~ season(window = "periodic"), robust = TRUE)) %>%
  components()
```

`season(window = "periodic")` obliga a que la forma estacional sea **la misma
todos los años** (12 coeficientes fijos). Es distinto del STL del EDA, que deja
que la forma evolucione. ¿Por qué acá fija? Porque el bootstrap necesita una
estacionalidad estable para que las réplicas sean comparables; si la forma
cambiara en cada réplica, el AICc compararía modelos con “estacionalidades”
distintas y los pesos no serían interpretables.

`robust = TRUE` evita que los atípicos contaminen la tendencia y la estacionalidad.

El residuo se **centra**:

```r
residuos_stl <- componentes_stl$remainder - mean(componentes_stl$remainder)
```

Sin centrar, cada réplica tendría un nivel distinto por el promedio del residuo.

### 7.5 Paso 3: Moving Block Bootstrap (MBB)

**¿Por qué bloques y no observaciones sueltas?** Porque los residuos pueden tener
dependencia de corto plazo; remuestrear meses sueltos la destruiría. El MBB
remuestrea **bloques consecutivos** y preserva la dependencia dentro del bloque.

**¿Cómo se elige el largo del bloque?** Con el método de Hall–Horowitz–Jing
(paquete `blocklength`):

```r
set.seed(semilla)
seleccion_bloque <- blocklength::hhj(
  series = residuos_stl, nb = 100, n_iter = 10,
  k = "two-sided", plots = FALSE, verbose = FALSE
)
largo_bloque <- as.integer(round(seleccion_bloque[["Optimal Block Length"]]))
```

Resultado: **2 meses**. Interpretación: después de quitar tendencia,
estacionalidad y COVID, el residuo tiene muy poca dependencia; un bloque de 2
basta. Es un resultado coherente con Ljung-Box (p > 0,75), pero también una
limitación: si hubiera dependencia de más largo plazo, el bootstrap la ignoraría.

El remuestreo:

```r
remuestrear_mbb <- function(residuos, largo, cantidad) {
  n_bloques <- ceiling(cantidad / largo)
  inicios <- sample.int(n - largo + 1L, size = n_bloques, replace = TRUE)
  posiciones <- unlist(lapply(inicios, function(i) seq.int(i, i + largo - 1L)))
  residuos[posiciones[seq_len(cantidad)]]
}
```

- `sample.int(..., replace = TRUE)`: bloques con reemplazo.
- `seq.int(i, i + largo - 1)`: bloque consecutivo.
- `seq_len(cantidad)`: recorta al largo exacto.

### 7.6 Paso 4: una réplica

```r
funcion_replica <- function(i) {
  set.seed(semilla + i)
  residuos_boot <- remuestrear_mbb(residuos_stl, largo_bloque, n)
  datos_replica <- train_data %>%
    mutate(Consumo_boot = tendencia + estacionalidad + residuos_boot + coef_covid * covid) %>%
    select(Mes, Consumo_boot, covid)
  aicc <- c(
    ETS_Auto     = ajustar_familia(datos_replica, "ETS_Auto"),
    ARIMA_Auto   = ajustar_familia(datos_replica, "ARIMA_Auto"),
    ARIMAX_Covid = ajustar_familia(datos_replica, "ARIMAX_Covid")
  )
  ...
}
```

Detalles que importan:

- **`set.seed(semilla + i)` dentro de la réplica**: la semilla depende solo del
  número de réplica, no del orden en que los workers la ejecutan. Así el
  resultado es reproducible **aunque cambie el paralelismo**.
- **Reconstrucción**: `tendencia + estacionalidad + residuos_boot + coef_covid * covid`.
  Se reinserta el efecto COVID para que el ARIMAX pueda reestimarlo; si no, la
  dummy sería constante y el modelo no tendría nada que estimar.
- **`ajustar_familia()` devuelve `Inf` si el ajuste falla**, para que una réplica
  problemática no rompa todo el bootstrap. Al final se exige que sobreviva al
  menos el 95 % de las réplicas.
- **`unname()`**: `fable` devuelve el AICc con nombre (`AICc.year`). Si lo
  combinás con `c()`, los nombres se contaminan (`ARIMA_Auto.year`) y
  `which.min()` devuelve un nombre que no coincide con `"ARIMA_Auto"`, dejando
  los pesos en `NA`. Es un bug real que apareció al migrar a AICc; la solución es
  `unname()` + `stats::setNames()`.

### 7.7 Paso 5: pesos

```r
frecuencias <- tibble(modelo = factor(selecciones_validas, levels = modelos_candidatos)) %>%
  count(modelo, .drop = FALSE) %>%
  mutate(frecuencia = n / sum(n), peso = frecuencia)
```

El peso es la **frecuencia de victoria** por AICc en las 200 réplicas. No es el
peso suave de Akaike (\(w_i \propto e^{-\Delta_i/2}\)); es una aproximación por
frecuencia, más robusta a réplicas con AICc extremos.

Resultado:

| Modelo | Réplicas ganadas | Peso |
|---|---:|---:|
| ETS_Auto | 0 | 0,00 |
| ARIMA_Auto | 0 | 0,00 |
| ARIMAX_Covid | 200 | **1,00** |

**El BMC es idéntico al ARIMAX.** No es un error: es el resultado. La dummy COVID
reduce tanto la varianza residual que el ARIMAX gana en las 200 réplicas, a pesar
del parámetro extra. Con pesos (0,0,1), `combination_weighted()` devuelve
exactamente el pronóstico del ARIMAX.

**Cómo se reporta (importante):**

- se dice explícitamente que los pesos están degenerados;
- se compara con `Ensamble_Simple` (promedio 1/3), que sí es un ensamble real;
- se interpreta como **evidencia de que el COVID domina la selección**, no como
  una falla del bootstrap.

### 7.8 Implementación en paralelo y caché

```r
cl <- parallel::makeCluster(num_cores)
parallel::clusterEvalQ(cl, { library(fpp3); library(dplyr); library(tidyr) })
parallel::clusterExport(cl, varlist = c("residuos_stl", ...), envir = globalenv())
parallel::parLapplyLB(cl, tanda, funcion_replica)
```

- **`clusterEvalQ`**: cada worker carga los paquetes. Sin esto, falla con “no
  existe `model`”.
- **`clusterExport`**: las funciones y objetos del entorno global no viajan solos
  a los workers; hay que exportarlos explícitamente.
- **`parLapplyLB`**: reparte dinámicamente (load balancing); las réplicas no
  tardan todas lo mismo.
- **Tandas de 25** (`tamano_tanda`): después de cada tanda se guarda
  `bmc_bootstrap_parcial.rds`; si se corta, la próxima corrida reanuda con
  `setdiff()`.
- **`num_cores = 4`**: con 6 núcleos/12 hilos, 4 workers cargan 4 copias de
  `fpp3`; más workers saturan la RAM. Es una decisión de ingeniería, no de
  estadística.

### 7.9 Limitaciones (decirlas antes de que las pregunten)

1. **Pesos degenerados** → el BMC no aporta diversificación.
2. **Bootstrap de residuos** → la incertidumbre es sobre los residuos, no sobre
   la tendencia/estacionalidad estimadas. No es un bootstrap “completo”.
3. **Un solo punto de calibración** (train hasta ago/2025) → los pesos no se
   reestiman en cada ventana del rolling.
4. **Bloque de 2 meses** → si hay dependencia más larga, se ignora.
5. **AICc como criterio** → premia ajuste in-sample; por eso el BMC no
   necesariamente gana el test.

### 7.10 Si te preguntan

> **Si los pesos son 0/0/1, ¿para qué hiciste el bootstrap?**
> Para demostrar que el resultado no depende de una elección arbitraria: en 200
> remuestras del residuo, el ARIMAX gana siempre. Es una prueba de robustez de
> la selección, aunque el ensamble colapse.

> **¿Por qué no usaste pesos iguales?**
> Se usan como contraste (`Ensamble_Simple`). El BMC es la propuesta
> metodológica; el promedio simple es el *benchmark* honesto.

> **¿El BMC puede perder contra sus componentes?**
> Sí, y de hecho pierde: en el test, ARIMA (0,473) le gana al BMC (0,520). Un
> ensamble no garantiza ganar; reduce varianza a costa de sesgo.

---

## 8. Parte 6 — Evaluación en test

**FPP3:** §5.8 (precisión puntual), §5.9 (precisión distribucional/Winkler),
§5.5 (intervalos), §5.3 (residuos).
**Código:** líneas 717–867.

### 8.1 Objetivo

Medir qué tan bien pronostica cada modelo **fuera de muestra**, en el bloque de
12 meses que nunca se usó para estimar.

### 8.2 El código clave

```r
fc_modelos <- fit_modelos %>% forecast(new_data = test_data, level = c(80, 95))
```

Dos decisiones:

- **`new_data = test_data`** (no `h = 12`): así se alinean las fechas y, para el
  ARIMAX, se le pasa la columna `covid` (que en el test es 0). Si usaras `h = 12`,
  `fable` tendría que adivinar el futuro de la covariable.
- **`level = c(80, 95)`**: dos intervalos, uno para narrar y otro para planificar.

### 8.3 Las métricas, una por una

| Métrica | Fórmula | Qué mide | Cuidado |
|---|---|---|---|
| RMSE | \(\sqrt{\frac{1}{h}\sum e_t^2}\) | error cuadrático medio | castiga fuerte los errores grandes |
| MAE | \(\frac{1}{h}\sum |e_t|\) | error absoluto medio | misma unidad (GWh) |
| MAPE | \(\frac{100}{h}\sum |e_t/y_t|\) | error porcentual | explota si \(y_t \approx 0\) |
| sMAPE | \(\frac{100}{h}\sum \frac{2|e_t|}{|y_t|+|\hat y_t|}\) | versión simétrica | acotada 0–200, asimétrica |
| MASE | \(\frac{\text{MAE}}{\frac{1}{T-m}\sum_{t=m+1}^T |y_t-y_{t-m}|}\) | error relativo al naive estacional | **la métrica principal** |
| Winkler 95 | \((u-l)+\frac{2}{\alpha}(l-y)\mathbf{1}_{y<l}+\frac{2}{\alpha}(y-u)\mathbf{1}_{y>u}\) | ancho + penalidad por no cubrir | premia intervalos angostos y bien calibrados |
| Cobertura | \(\frac{1}{h}\sum \mathbf{1}_{l \le y \le u}\) | % de valores dentro del intervalo | con 12 puntos es muy ruidosa |

**Por qué MASE y no MAPE.** MASE compara contra el **naive estacional** (repetir
el mismo mes del año anterior), que es el *benchmark* natural de una serie
estacional. MASE < 1 significa “mejor que repetir el año pasado”. MAPE no tiene
ese punto de referencia y castiga distinto según el nivel. Acá todos los MASE son
< 1: todos le ganan al naive estacional.

**Escala del MASE en el test:** el denominador es el MAE del naive estacional
**en el entrenamiento**. Para ARIMA, MAE/0,4732 = 59,4/0,4732 ≈ 125,6 GWh. O sea:
el naive estacional se equivocaba ~126 GWh en promedio in-sample; el ARIMA, ~59.

### 8.4 Resultados del test (sep/2025 – ago/2026)

| Modelo | RMSE | MAE | MAPE | MASE | Winkler 95 | Cob. 80 | Cob. 95 |
|---|---:|---:|---:|---:|---:|---:|---:|
| **ARIMA_Auto** | **71,2** | **59,4** | **3,13** | **0,473** | 458,1 | 91,7 % | 100 % |
| **ARIMAX_Covid** | 76,9 | 65,3 | 3,45 | 0,520 | **408,7** | 91,7 % | 100 % |
| BMC | 76,9 | 65,3 | 3,45 | 0,520 | **408,7** | 91,7 % | 100 % |
| Ensamble_Simple | 80,0 | 69,2 | 3,65 | 0,551 | 410,0 | 91,7 % | 100 % |
| ETS_Auto | 98,3 | 86,5 | 4,56 | 0,688 | 439,2 | 91,7 % | 100 % |

Lectura:

1. **ARIMA gana en precisión puntual** (MASE 0,473: 53 % menos error que el
   naive estacional).
2. **ARIMAX/BMC gana en Winkler** (408,7 vs 458,1): sus intervalos son más
   angostos y cubren igual (11/12 y 12/12). Es decir, **ARIMA gana el punto,
   ARIMAX gana la distribución**. Por eso el modelo oficial es el ARIMAX: gana
   el rango medio de las cuatro evaluaciones (§10.8).
3. **Todos cubren 11/12 al 80 % y 12/12 al 95 %**. Con 12 puntos, 11/12 = 91,7 %
   tiene un intervalo binomial enorme; no se puede concluir “sobre-cobertura”
   seriamente. Es una señal, no una prueba.

### 8.5 Las bandas empíricas del BMC

Además de los intervalos analíticos, el script construye bandas por **MBB sobre
los residuos STL**:

```r
simulaciones <- replicate(B_intervalos,
  remuestrear_mbb(residuos_stl, largo_bloque, nrow(media_bmc)))
simulaciones <- sweep(simulaciones, 1, media_bmc$pronostico, "+")
```

- Se remuestrean 2.000 trayectorias de 12 residuos y se **suman** al pronóstico
  puntual del BMC.
- Los cuantiles 10/90 y 2,5/97,5 dan las bandas 80/95.
- Resultado: cobertura 10/12 (83,3 %) al 80 % y 12/12 al 95 %.

**Qué es y qué no es:** es un chequeo **empírico** de la forma del error, no la
distribución predictiva del modelo. Ignora la incertidumbre de los parámetros y
la del nivel; por eso no reemplaza los intervalos de `fable`. Se reporta como
robustez.

### 8.6 Si te preguntan

> **¿Por qué el ARIMA tiene mejor MASE pero peor Winkler?**
> Porque el Winkler castiga el **ancho** del intervalo. El ARIMA tiene residuos
> más grandes (σ² = 12.474 vs 10.811 del ARIMAX en train), así que sus intervalos
> son más anchos; cubren bien, pero a un costo mayor. El ARIMAX, al absorber el
> COVID, tiene intervalos más angostos.

> **¿No es trampa comparar en 12 puntos?**
> Es una muestra chica; por eso se complementa con 21 ventanas (Parte 7) y se
> reporta la cobertura con cautela. El test fijo aporta porque son 12 meses que
> ningún modelo vio al ajustarse (aunque se usan para comparar), pero no alcanza
> por sí solo: por eso la selección promedia también el origen rodante.

> **¿Por qué el BMC y el ARIMAX tienen números idénticos?**
> Porque los pesos son (0,0,1). El BMC *es* el ARIMAX. Se mantiene en la tabla
> para mostrar el resultado del método, y se advierte que no aporta diversificación.

---

## 9. Parte 7 — Origen rodante

**FPP3:** §5.10 (validación cruzada de series temporales).
**Código:** líneas 869–1083.

### 9.1 Objetivo

Responder: **¿el ranking del test se sostiene en otras ventanas?** El test fijo es
un solo bloque; puede ser “fácil” o “difícil” por casualidad. El origen rodante
reajusta y evalúa en 21 ventanas.

### 9.2 Diseño

```r
origenes <- inicio_rolling + 0:(n_origenes - 1)   # dic/2022 ... ago/2024
```

Para cada origen \(o\):

- entrenamiento: todo hasta \(o\);
- futuro: \(o+1, \dots, o+12\);
- se reajustan ETS, ARIMA, ARIMAX, Ensamble y BMC (con los pesos de la Parte 5);
- se calculan error, cobertura y Winkler **punto a punto**.

¿Por qué dic/2022 – ago/2024?

- deja 12 meses futuros dentro de la muestra (hasta ago/2025);
- todos los entrenamientos incluyen el pulso COVID (2020), así el ARIMAX es
  estimable;
- 21 ventanas dan 252 puntos por modelo, suficiente para promediar.

### 9.3 El MASE sin fuga

```r
escala <- mean(abs(diff(as.numeric(ent$Consumo_GWh), lag = 12)))
...
error_escalado = abs_error / escala
```

La escala se calcula **solo con el entrenamiento de esa ventana**, nunca con el
futuro. Si se usara la escala global, habría fuga de información.

Nota técnica: acá el MASE es el **promedio de errores escalados por ventana**
(cada origen pesa igual), no el MASE agrupado de `accuracy()`. Es una diferencia
menor, pero conviene saberla si comparás con la tabla del test.

### 9.4 Resultados (21 ventanas, h = 12)

| Modelo | RMSE | MAE | MASE | Winkler 95 | Cob. 80 | Cob. 95 |
|---|---:|---:|---:|---:|---:|---:|
| **ETS_Auto** | **114,2** | **92,0** | **0,728** | 556,0 | 78,6 % | 93,3 % |
| Ensamble_Simple | 115,3 | 94,6 | 0,749 | 561,5 | 72,2 % | 93,7 % |
| ARIMAX_Covid | 117,0 | 97,3 | 0,770 | **542,1** | 70,2 % | 97,6 % |
| BMC | 117,0 | 97,3 | 0,770 | **542,1** | 70,2 % | 97,6 % |
| ARIMA_Auto | 128,4 | 105,6 | 0,836 | 608,0 | 77,0 % | 95,2 % |

### 9.5 La lectura central del proyecto

**El ranking se invierte.**

| Criterio | Ganador | MASE |
|---|---|---:|
| Test fijo (12 meses) | ARIMA | 0,473 |
| Origen rodante (21 ventanas) | ETS | 0,728 |

Y el ARIMA, que era el mejor en el test, queda **último** en el rolling. Eso no es
un error: es **incertidumbre de modelo**. Un solo bloque de 12 meses no alcanza
para declarar un ganador; la ventana 2025–2026 fue particularmente favorable al
ARIMA, mientras que 2023–2025 (más volátiles, con el pico de abr/2025) favorecen
al ETS, que se adapta más rápido.

**Consecuencia metodológica:** por eso existe el BMC, por eso se reportan ambos
rankings y por eso la Parte 8 **no elige con un solo criterio**: promedia los
rangos de MASE y Winkler en el test y en el rolling. La conclusión honesta no es
“gana X en todo”, sino “los cinco modelos dan totales anuales dentro del 0,3 %,
así que la cifra es robusta aunque el ranking no lo sea”.

### 9.6 Cobertura y Winkler en el rolling

- **ETS**: 78,6 % al 80 % y 93,3 % al 95 % → bien calibrado.
- **ARIMAX**: 70,2 % al 80 % (baja) y 97,6 % al 95 % (alta) → intervalos con
  forma incorrecta: demasiado anchos en la cola, demasiado angostos en el centro.
- **ARIMA**: 77,0 % / 95,2 % → razonable.

En Winkler gana ARIMAX (542,1): a pesar de la mala calibración al 80 %, sus
intervalos son más angostos y la penalidad por no cubrir es moderada. Otra señal
de que “mejor MASE” y “mejor intervalo” no son lo mismo.

### 9.7 Limitación: los pesos no se reestiman

El BMC usa los pesos de la Parte 5, calibrados con datos hasta ago/2025. En las
ventanas de 2022–2024, esos pesos miran un poco hacia adelante. Es una fuga
**solo para el BMC**; ARIMA, ETS y ARIMAX se reajustan limpios. Como el BMC es
idéntico al ARIMAX, el efecto práctico es nulo, pero hay que declararlo.

### 9.8 Si te preguntan

> **¿Por qué el MASE del rolling es peor que el del test?**
> Porque son ventanas distintas. El test (2025–2026) fue relativamente estable;
> el rolling incluye 2023–2025, con el rebote post-pandemia y el pico de abr/2025.
> No se comparan magnitudes entre tablas, solo rankings dentro de cada tabla.

> **¿Por qué ETS gana el rolling si no tiene tendencia?**
> Porque su nivel se adapta (α = 0,17) y la tendencia es suave; en ventanas
> cortas, un modelo que se adapta rápido suele ganar a uno con deriva fija. En el
> test, en cambio, la deriva del ARIMA acertó mejor.

> **¿El rolling demuestra que el ARIMA es malo?**
> No. Demuestra que **no es robustamente mejor**. Con 21 ventanas, la evidencia
> favorece al ETS; con el bloque 2025–2026, al ARIMA. La conclusión es que la
> elección es sensible al período.

---

## 10. Parte 8 — La previsión final, número por número

**FPP3:** §9.8 (pronóstico e intervalos), §9.9 (SARIMA), §5.5 (intervalos),
§5.9 (precisión distribucional).
**Código:** líneas 1099–1330 (aprox.).

### 10.1 Qué cambia respecto de la Parte 6

| Parte 6 (evaluación) | Parte 8 (previsión) |
|---|---|
| Ajusta con 128 meses (hasta ago/2025) | Ajusta con **140** meses (hasta ago/2026) |
| Pronostica el test ya observado | Pronostica **sep/2026 – ago/2027** |
| Sirve para medir error | Es el resultado final |
| `new_data = test_data` | `new_data` con `covid = 0` |

Es crucial entender que **no es el mismo ajuste**: al agregar 12 meses, el
auto-ARIMA puede elegir otro orden. De hecho, el ARIMA de evaluación era
(0,0,2)(0,1,1)[12] y el ARIMA reajustado con 140 meses es
(1,0,0)(1,1,1)[12]. Ese es correcto: el “modelo” es un **procedimiento**
(auto-ARIMA), no una ecuación fija. El ARIMAX oficial usa ese mismo orden de
errores, (1,0,0)(1,1,1)[12], más la dummy COVID.

### 10.2 El código

Primero, la **selección** (Parte 8.1). No se escribe el modelo a mano: se rankean
cuatro métricas fuera de muestra y gana el menor rango medio.

```r
comparacion_modelos <- tabla_precision %>%
  select(.model, MASE_test = MASE, Winkler_test = Winkler_95) %>%
  left_join(resumen_rolling %>%
              select(.model, MASE_rolling = MASE, Winkler_rolling = Winkler_95),
            by = ".model") %>%
  mutate(
    rango_MASE_test       = rank(MASE_test),
    rango_Winkler_test    = rank(Winkler_test),
    rango_MASE_rolling    = rank(MASE_rolling),
    rango_Winkler_rolling = rank(Winkler_rolling),
    rango_medio = (rango_MASE_test + rango_Winkler_test +
                     rango_MASE_rolling + rango_Winkler_rolling) / 4,
    es_ensamble = .model %in% c("BMC", "Ensamble_Simple")
  ) %>%
  arrange(rango_medio, es_ensamble, .model)

modelo_final <- comparacion_modelos$.model[1]   # ARIMAX_Covid
```

Y después, la **previsión**:

```r
primer_mes_futuro <- max(datos$Mes) + 1          # sep/2026
datos_futuro <- tibble(
  Mes = primer_mes_futuro + 0:(h_futuro - 1),
  covid = 0
) %>% as_tsibble(index = Mes)

ajuste_total <- datos %>% model(
  ETS_Auto = ETS(Consumo_GWh),
  ARIMA_Auto = ARIMA(Consumo_GWh),
  ARIMAX_Covid = ARIMA(Consumo_GWh ~ covid)
) %>% mutate(
  Ensamble_Simple = (ETS_Auto + ARIMA_Auto + ARIMAX_Covid) / 3,
  BMC = fabletools::combination_weighted(ETS_Auto, ARIMA_Auto, ARIMAX_Covid,
                                         weights = unname(pesos_bmc))
)

fc_futuro <- ajuste_total %>% forecast(new_data = datos_futuro, level = c(80, 95))
```

**`covid = 0` en el futuro**: la dummy no puede ser 1 porque el confinamiento no
se repite. Es una hipótesis del modelo, no un dato.

**Por qué el desempate prefiere el modelo individual**: el BMC es una combinación
lineal de los otros modelos; con pesos (0, 0, 1) sus números son idénticos a los
del ARIMAX. A igual rango medio gana el ARIMAX, que se reporta con una sola
ecuación.

### 10.3 El modelo oficial

`modelo_final = "ARIMAX_Covid"` (lo elige la tabla 8.1), que sobre las 140
observaciones es una regresión con errores ARIMA:

\[
(1-0{,}153B)(1+0{,}142B^{12})(1-B^{12})\,y_t
= -24{,}20 - 306{,}36\,\text{covid}_t + (1-0{,}788B^{12})\,\varepsilon_t
\]

| Coeficiente | Estimación | EE | t |
|---|---:|---:|---:|
| ar1 | 0,1530 | 0,0897 | 1,71 |
| sar1 | −0,1423 | 0,1227 | −1,16 |
| sma1 | −0,7877 | 0,1204 | −6,54 |
| covid | −306,3637 | 60,7206 | −5,05 |
| intercept | −24,2048 | 3,0931 | −7,82 |

AICc = 1.564,1; \(\hat\sigma^2 = 9.998\); log-verosimilitud = −775,72.

El coeficiente COVID es lo que se gana al modelar la intervención: −306 GWh/mes
en abr–jun/2020, con t = −5,05. La varianza residual (9.998) es menor que la del
ARIMA sin dummy (11.653), y por eso sus intervalos son más angostos.

### 10.4 La anatomía de los 22.812 GWh

Esta es la parte que hay que poder explicar sin mirar.

**Paso 1: el ancla.** La suma de los últimos 12 meses observados
(sep/2025 – ago/2026) es:

\[
1762 + 1797 + 1869 + 1947 + 2034 + 2038 + 1995 + 2050 + 1922 + 1747 + 1666 + 1762
= 22.588{,}5
\]

**Paso 2: el ajuste.** El modelo pronostica, para cada mes, la **diferencia
estacional** \(\hat w_{T+h} = \hat y_{T+h} - y_{T+h-12}\). La suma de esos 12
ajustes es **+223,2 GWh**.

**Paso 3: el total.**

\[
22.588{,}5 + 223{,}2 = 22.811{,}7 \text{ GWh}
\]

Es decir: **el pronóstico es “el mismo mes del año pasado + un ajuste pequeño”**.
No es “promedio + tendencia”. Esa es la naturaleza de un SARIMA con \(D=1\):
hereda la forma del año anterior y la corrige.

### 10.5 Los 12 ajustes, mes por mes

| Mes pronosticado | Mismo mes año previo | Pronóstico | Ajuste \(\delta\) | Residuo del mismo mes un año antes | \(-0,788 \times\) residuo |
|---|---:|---:|---:|---:|---:|
| sep/2026 | 1.762 | 1.775 | **+13,0** | −11,3 | +8,9 |
| oct/2026 | 1.797 | 1.823 | **+26,5** | −28,7 | +22,6 |
| nov/2026 | 1.869 | 1.901 | **+32,2** | −49,0 | +38,6 |
| dic/2026 | 1.947 | 1.980 | **+32,9** | −58,4 | +46,0 |
| ene/2027 | 2.034 | 1.995 | **−38,6** | +18,0 | −14,2 |
| feb/2027 | 2.038 | 2.094 | **+56,3** | −70,9 | +55,8 |
| mar/2027 | 1.995 | 2.116 | **+121,0** | −133,0 | +104,8 |
| abr/2027 | 2.050 | 2.118 | **+67,2** | −25,4 | +20,0 |
| may/2027 | 1.922 | 1.878 | **−44,2** | +17,2 | −13,5 |
| jun/2027 | 1.747 | 1.788 | **+41,4** | −71,6 | +56,4 |
| jul/2027 | 1.666 | 1.683 | **+16,6** | −40,0 | +31,5 |
| ago/2027 | 1.762 | 1.660 | **−101,6** | +83,2 | −65,5 |
| **Total** | **22.588,5** | **22.811,7** | **+223,2** | | |

**Cómo leer esta tabla (el “por qué” de cada mes):**

1. **La corrección dominante es el SMA(1)**: \(-0,788 \times\) el residuo del
   mismo mes del año anterior. Si en mar/2026 el modelo se quedó 133 GWh corto,
   en mar/2027 empuja +105 GWh. Si en ago/2026 se pasó 83 GWh, en ago/2027
   corrige −66. Por eso el patrón de ajustes **no es suave**: es la memoria de
   los errores de 2026. La diferencia entre el ajuste total y esa corrección son
   los términos AR(1), SAR(1) e intercepto.
2. **El AR(1) agrega impulso de corto plazo**: ago/2026 cerró en 1.762, es decir
   **+99 GWh sobre ago/2025**. Ese “momentum” positivo (coeficiente 0,153) se
   arrastra a los primeros meses y se agota.
3. **La deriva empuja hacia abajo**: ≈ −25 GWh/año (intercepto −24,2 en la
   escala de la diferencia anual). Es un efecto pequeño frente a los dos
   anteriores en el primer año.
4. **El resultado neto es +223**: el impulso positivo reciente y las correcciones
   SMA ganan a la deriva durante 12 meses.

### 10.6 La forma estacional y los intervalos

**Forma:** pico en mar–abr (2.116–2.118) y valle en jul–ago (1.683–1.660). No es
una forma impuesta: se hereda de los valores de sep/2025–ago/2026 (feb/2026 =
2.038, mar/2026 = 1.995, jul/2026 = 1.666, ago/2026 = 1.762), corregidos por
\(\delta\). Por eso el ARIMAX y el ETS coinciden tanto en la forma: ambos repiten
el año anterior; difieren en cómo extrapolan el nivel.

**Intervalos:** el ancho del 80 % va de 257 a 260 GWh; el del 95 %, de 392 a 397.
Es decir, la banda es **casi constante** (±129 y ±197 GWh alrededor de 1.775).

¿Por qué no se abre como un cono? Porque el SMA(1) = −0,79 **casi cancela** la
raíz unitaria estacional. En la práctica, el modelo se comporta como si la forma
estacional fuera estable y la incertidumbre viniera sobre todo del nivel, no de
la estacionalidad. Lo verifiqué con 2.000 simulaciones bootstrap: el ancho se
mantiene. **No es un error de `fable`.**

**Advertencia práctica:** en el rolling, la cobertura al 80 % fue 70–78 %, no
80 %. Eso sugiere que la banda del 80 % es algo optimista fuera de muestra. Para
planificar, usá la del **95 %** (±197 GWh), que en el rolling cubrió 93–98 %.

**Sobre el SMA cerca de −1:** es una señal de posible sobre-diferenciación
estacional. Acá no llega a −1 y los residuos están limpios, pero es una
limitación que conviene declarar: el modelo es, en parte, “naive estacional con
correcciones”.

### 10.7 Comparación de los cinco modelos

| Modelo | Total 12 meses | Promedio mensual | Mínimo | Máximo |
|---|---:|---:|---:|---:|
| ETS_Auto | 22.743,1 | 1.895,3 | 1.705,1 | 2.108,1 |
| ARIMA_Auto | 22.753,7 | 1.896,1 | 1.663,5 | 2.111,7 |
| Ensamble_Simple | 22.769,5 | 1.897,5 | 1.677,9 | 2.111,8 |
| **ARIMAX_Covid** | **22.811,7** | **1.901,0** | **1.660,4** | **2.117,6** |
| BMC | 22.811,7 | 1.901,0 | 1.660,4 | 2.117,6 |

Rango: 22.743,1–22.811,7 = **68,6 GWh**, o sea **0,30 %** del total. La cifra no
depende de la elección del modelo. Ese es el argumento de robustez más fuerte del
trabajo.

Diferencias cualitativas:

- **ETS** no tiene tendencia: su nivel es más alto al final (ago/2027 = 1.710 vs
  1.660 del ARIMAX), porque no extrapola la deriva.
- **ARIMAX** gana la distribución: su varianza residual es menor (9.998 vs
  11.653 del ARIMA) y sus intervalos son ~20 % más angostos; su total es el más
  alto porque su forma estacional compensa.
- **Ensamble** queda en el medio, como era de esperar.

### 10.8 ¿Por qué se elige ARIMAX y no otro?

La regla declarada es el **promedio de rangos** de cuatro métricas fuera de
muestra (1 = mejor): MASE y Winkler 95 % en el test fijo y en el origen rodante.

| Criterio | Métrica | Ganador | Valor |
|---|---|---|---:|
| Test fijo (h = 12) | MASE | ARIMA_Auto | 0,4732 |
| Test fijo (h = 12) | Winkler 95 % | ARIMAX_Covid | 408,7 |
| Origen rodante (21 ventanas) | MASE | ETS_Auto | 0,7284 |
| Origen rodante (21 ventanas) | Winkler 95 % | ARIMAX_Covid | 542,1 |
| **Rango medio (4 métricas)** | promedio de rangos | **ARIMAX_Covid** | **2,25** |
| **Modelo usado** | — | **ARIMAX_Covid** | — |

Rangos medios de los cinco modelos: **ARIMAX 2,25** · BMC 2,25 · ETS 3,25 ·
Ensamble 3,25 · ARIMA 4,00.

**Lectura:** no hay un modelo que gane todo. El ARIMA acierta mejor el número
(gana el MASE del test) pero pierde los dos Winkler; el ETS gana el MASE del
rolling pero pierde el test; el ARIMAX gana la *distribución* en las dos
evaluaciones. Promediar rangos es la forma explícita de decir: “me importa tanto
acertar el número como la calidad del intervalo, y tanto el test como el rolling”.

**Por qué no AICc.** El AICc es ajuste *dentro* de la muestra: premia siempre al
ARIMAX porque la dummy COVID baja la varianza residual (de ahí los pesos 0/0/1
del BMC). Usarlo para elegir la previsión sería confundir ajuste con pronóstico.

**El sesgo que esto evita.** El script no escribe el ganador a mano: si mañana
los datos cambiaran y el ranking diera ARIMA o ETS, `modelo_final` cambiaría
solo. Una tabla de selección que se imprime pero no se usa es decorativa; acá se
usa (`modelo_final <- comparacion_modelos$.model[1]`). El desempate ARIMAX vs BMC
está declarado: gana el modelo individual. Y si se quiere otro criterio, hay
override explícito:

```r
modelo_final_forzado <- "ARIMA_Auto"   # NULL = decide la tabla 8.1
```

Los totales difieren 0,30 %: la decisión no cambia la cifra.

**Mi recomendación para el artículo:** reportar ARIMAX como previsión oficial y
declarar que gana por rango medio, no por MASE puntual; el ARIMA es el mejor en
el número y el ETS en las ventanas móviles. Es una narrativa de incertidumbre de
modelo, no de “elegimos el que ganó”.

### 10.9 Si te preguntan

> **¿De dónde sale 22.812?**
> De sumar los últimos 12 meses observados (22.588,5) y los 12 ajustes
> estacionales que pronostica el modelo (+223,2). El ajuste no es uniforme porque
> el SMA(1) corrige cada mes con el error del mismo mes del año anterior.

> **¿Por qué el intervalo no se abre?**
> Porque el SMA(1) = −0,79 casi cancela la raíz unitaria estacional; la
> incertidumbre del primer año es casi toda del nivel, no de la forma. Lo confirmé
> con bootstrap. Para horizontes > 12 meses, la banda sí se abre (y la deriva
> domina).

> **¿Por qué el total del segundo año cae 1,6 %?**
> Por la deriva ≈ −25 GWh/año: en el primer año la compensan el impulso y las
> correcciones; en el segundo ya no (sep/2027–ago/2028 ≈ 22.437 GWh).

> **¿El modelo “sabe” que no habrá otra pandemia?**
> No. El escenario base asume `covid = 0` en el futuro. Es una hipótesis, no una
> certeza; el intervalo no incluye un shock tipo 2020. Eso se declara como
> limitación.

---

## 11. Parte 9 — Apéndices

**FPP3:** no cubre `strucchange`; se apoya en §4.1–4.3 (features) y en la
literatura de quiebres (Chow, Bai–Perron, Zeileis). Es material **complementario**,
no parte del modelo.
**Código:** líneas 1235–1315.

### 11.1 Impacto 2020

```r
base_previa <- train_data %>%
  filter(year(Mes) >= 2017, year(Mes) <= 2019) %>%
  group_by(m = month(Mes)) %>%
  summarise(media_base = mean(Consumo_GWh))
```

Compara cada mes de 2020 con la media del mismo mes en 2017–2019:

| Mes 2020 | Consumo | Base 2017–19 | % de la base |
|---|---:|---:|---:|
| ene | 2.196 | 2.339 | 93,9 % |
| feb | 2.223 | 2.268 | 98,0 % |
| mar | 2.199 | 2.390 | 92,0 % |
| **abr** | 1.965 | 2.239 | **87,8 %** |
| **may** | 1.750 | 2.190 | **79,9 %** |
| **jun** | 1.579 | 1.969 | **80,2 %** |
| jul | 1.775 | 1.848 | 96,0 % |
| ago | 1.852 | 1.890 | 98,0 % |
| sep | 1.829 | 1.869 | 97,9 % |
| oct | 2.072 | 1.994 | 103,9 % |
| nov | 1.984 | 2.103 | 94,3 % |
| dic | 2.085 | 2.218 | 94,0 % |

Lectura: el choque fue **abr–jun**, con el mínimo en junio (80,2 % de la base,
1.579 GWh). En julio ya estaba en 96 % y en octubre por encima de la base. Eso
justifica el pulso de 3 meses y descarta el escalón.

### 11.2 Cambios estructurales

Se usa la serie **desestacionalizada** (`season_adjust` del STL) y se estima:

\[
\text{desest}_t = \alpha + \beta t + \gamma\,\text{covid}_t + u_t
\]

Luego:

| Prueba | \(H_0\) | Estadístico | p | Lectura |
|---|---|---:|---:|---|
| **Chow** (corte dic/2021) | no hay quiebre en esa fecha | 2,65 | 0,052 | al borde del 5 % |
| **supF** (Bai–Perron) | no hay quiebre en fecha desconocida | 13,51 | 0,058 | al borde |
| **OLS-CUSUM** | los coeficientes son estables | 1,01 | 0,257 | no rechaza |

El mes con F máximo es **may/2023**.

**Lectura conjunta:** hay **evidencia marginal** de inestabilidad a fines de
2021/2023, pero no concluyente. El CUSUM no rechaza. Eso es coherente con una
**tendencia descendente gradual** (migración al mercado libre, generación
distribuida) más que con un escalón brusco. El drift del ARIMA es la forma
estadística de esa tendencia.

**Por qué no se cambió el modelo con estos tests:**

1. Son marginales (p ≈ 0,05), no concluyentes.
2. El modelo principal ya incluye tendencia (drift) y el pulso COVID; agregar un
   quiebre sería sobre-parametrizar con 140 puntos.
3. El objetivo es pronosticar, no testear la historia; los tests se reportan como
   robustez.

### 11.3 Si te preguntan

> **p = 0,052, ¿hay quiebre o no?**
> Al 5 %, no se rechaza. Al 10 %, sí. La conclusión honesta es “evidencia
> marginal”; se reporta el valor, no se fuerza una dicotomía.

> **¿Por qué el CUSUM dice lo contrario?**
> Porque testea otra cosa: estabilidad de los coeficientes a lo largo de toda la
> muestra, no un quiebre en una fecha. Los tres tests son complementarios, no
> equivalentes.

> **¿El quiebre de may/2023 invalida el pronóstico?**
> No: el modelo con drift ya permite que el nivel cambie lentamente. Un quiebre
> abrupto sería distinto, pero los tests no lo confirman.

---

## 12. Parte 10 — Salidas y reproducibilidad

**FPP3:** Apéndice *Using R*; §5.1 (flujo de trabajo).
**Código:** líneas 1317–1362.

### 12.1 Qué hace

- Escribe `sessionInfo()` en `sesion_R.txt`: versión de R y de cada paquete. Es
  el estándar mínimo de reproducibilidad.
- Verifica qué archivos de la lista existen y los imprime con ruta relativa.
- Imprime las cifras clave: efecto COVID, pesos, mejor MASE test/rolling y total
  previsto.

### 12.2 Mapa de archivos

| Archivo | Qué responde |
|---|---|
| `2_pesos_bmc/frecuencias_pesos_BMC_COVID.csv` | ¿cómo se repartieron los pesos? |
| `3_evaluacion_test/evaluacion_test.csv` | ¿qué tan bien predice cada modelo? |
| `3_evaluacion_test/pronosticos_test.csv` | ¿qué pronosticó mes a mes? |
| `3_evaluacion_test/cobertura_BMC_COVID.csv` | ¿las bandas empíricas cubren? |
| `4_rolling_origin/rolling_resumen.csv` | ¿el ranking se sostiene? |
| `4_rolling_origin/rolling_por_origen.csv` | ¿qué ventana fue difícil? |
| `4_rolling_origin/rolling_por_horizonte.csv` | ¿el error crece con h? |
| `5_pronostico/pronostico_2026_2027.csv` | **la previsión oficial con IC** |
| `5_pronostico/pronostico_2026_2027_ancho.csv` | los 5 modelos, lado a lado |
| `5_pronostico/seleccion_modelo.csv` | qué criterio elige qué modelo |
| `5_pronostico/comparacion_modelos.csv` | la tabla de rangos que elige el modelo |
| `6_apendices/*.csv` | impacto 2020 y cambios estructurales |
| `sesion_R.txt` | versiones para el apéndice |

### 12.3 Reproducibilidad: los cuatro controles

1. **Semilla fija** (2616) en bootstrap y bandas.
2. **Caché validada por parámetros** (`identical`).
3. **Rutas construidas**, no `setwd()`.
4. **`sessionInfo()`** guardado.

Con eso, otra persona con los mismos datos y paquetes obtiene los mismos números.

---

## 13. Tabla maestra

| Concepto | FPP3 | Dónde en el script | Dónde se ve el resultado |
|---|---|---|---|
| `tsibble`, índice, huecos | §2.1 | Parte 1, `as_tsibble`, `has_gaps` | consola |
| Gráfico temporal | §2.2 | `g_serie` | `1_eda/eda_serie.png` |
| Gráfico estacional | §2.4 | `gg_season` | `1_eda/eda_estacional.png` |
| ACF / PACF | §2.8 | `gg_tsdisplay(difference(...))` | `1_eda/eda_acf_pacf.png` |
| Transformación / Guerrero | §3.1 | `features(..., guerrero)` | consola |
| Descomposición STL | §3.6 | `model(STL(...))`, `components()` | `1_eda/eda_stl.png` |
| Atípicos | §3.6, §13.9 | regla 3×IQR | `1_eda/eda_atipicos_stl.csv` |
| Estacionariedad / KPSS | §9.1 | `unitroot_kpss`, `unitroot_ndiffs` | consola |
| Dummy / intervención | §7.4 | `covid` | Parte 2 |
| ETS: taxonomía | §8.4 | `ETS(Consumo_GWh)` | `report()` |
| ETS: espacio de estados | §8.5 | idem | `report()` |
| ETS: estimación/selección | §8.6 | idem | `glance()` AICc |
| ETS: pronóstico | §8.7 | `forecast()` | `5_pronostico/…` |
| ARIMA: diferenciación | §9.1 | `D=1` | `report()` |
| ARIMA: notación de retardos | §9.2 | ecuación del modelo | esta guía, §6.3 |
| AR / MA | §9.3–9.4 | `ar1`, `ma1`, `sma1` | `report()` |
| ARIMA estacional | §9.9 | `(1,0,0)(1,1,1)[12]` | `report()` |
| Estimación / AICc | §9.6 | `ARIMA()`, `glance()` | consola |
| ARIMA en `fable` | §9.7 | `report()`, `tidy()` | consola |
| Pronóstico / intervalos | §9.8 | `forecast(new_data, level)` | `pronostico_2026_2027.csv` |
| ARIMA vs ETS | §9.10 | los tres modelos | tablas comparativas |
| Regresión con errores ARIMA | §10.2 | `ARIMA(y ~ covid)` | `report()` |
| Residuos y Ljung-Box | §5.3–5.4 | `gg_tsresiduals`, `ljung_box` | consola |
| Intervalos de predicción | §5.5 | `hilo`, `unpack_hilo` | CSV con IC |
| Precisión puntual (MASE) | §5.8 | `accuracy()` | `evaluacion_test.csv` |
| Precisión distribucional (Winkler) | §5.9 | `winkler_score` | `evaluacion_test.csv` |
| Selección del modelo | §5.8–5.10 | `rank()` + promedio de rangos | `5_pronostico/comparacion_modelos.csv` |
| Validación cruzada | §5.10 | 21 orígenes | `4_rolling_origin/` |
| Combinación de pronósticos | §13.4 | `combination_weighted` | `2_pesos_bmc/` |
| Bootstrap / bagging | §12.5 | MBB + AICc | `2_pesos_bmc/` |
| Reproducibilidad | Apéndice R | `sessionInfo()` | `sesion_R.txt` |
| Cambio estructural | (fuera de FPP3) | `strucchange` | `6_apendices/` |

---

## 14. Banco de preguntas

**1. ¿Cuál es la pregunta del proyecto y por qué importa?**
Prever la demanda mensual de Light SESA a 12 meses para planificar compra de
energía y facturación. Importa porque un error de 3 % en 22.812 GWh son ~684 GWh,
dinero real; y porque la serie tiene estacionalidad, tendencia y un shock, así que
no alcanza con un promedio.

**2. ¿Por qué 140 observaciones y no más?**
Porque la serie mensual de consumo facturado empieza en ene/2015 y termina en
ago/2026. Los CSV crudos son la fuente, pero el análisis usa la serie mensual
consolidada.

**3. ¿Por qué el COVID es un pulso y no un escalón?**
Porque la caída fue transitoria: abr–jun/2020, con recuperación en jul (96 % de la
base) y oct (104 %). Un escalón habría absorbido la tendencia posterior.

**4. ¿Cómo se elige el orden ARIMA?**
`ARIMA()` de `fable` aplica la diferenciación estacional, selecciona `d` con
tests de raíz unitaria y busca `p,q,P,Q` minimizando AICc (Hyndman–Khandakar).
En el train (128 obs) el ARIMA eligió (0,0,2)(0,1,1)[12] con drift; sobre las 140
obs, (1,0,0)(1,1,1)[12] con drift. El ARIMAX alternativo usa errores
(1,0,0)(1,1,1)[12] con intercepto y la dummy COVID.

**5. ¿Qué significa el coeficiente −315,7?**
Que en abr–jun/2020 el consumo fue 315,7 GWh/mes menor que el contrafactual del
modelo, condicional a tendencia y estacionalidad. t = −5,50, p = 2,3e−7: muy
significativo.

**6. ¿Por qué la deriva es ≈ −24 GWh/año y no −18,8/mes?**
Porque \(D=1\): el `constant` que imprime `report()` está en la escala de la
diferencia anual. Además, con AR(1) y SAR(1), la deriva de largo plazo es
\(c/[(1-\phi)(1-\Phi)] = -18,76/(0,704 \times 1,104) \approx -24,1\).

**7. ¿Por qué ETS no tiene tendencia?**
Porque `ETS()` eligió (M,N,M) por AICc: la tendencia es débil y el nivel
adaptativo (α = 0,17) describe mejor los datos que una tendencia estimada sobre
128 meses contaminados por 2020.

**8. ¿Qué es el BMC y por qué los pesos son 0/0/1?**
BMC = combinación ponderada por la frecuencia con que cada modelo gana el AICc en
200 réplicas bootstrap. El ARIMAX gana las 200 porque la dummy COVID reduce mucho
la varianza residual. El ensamble colapsa a ARIMAX; se reporta como resultado y se
contrasta con el promedio simple.

**9. ¿Un ensamble con un solo modelo no es redundante?**
Sí, y se dice. El valor del ejercicio es mostrar que la selección es robusta a
remuestreos, no fabricar diversificación. El contraste honesto es
`Ensamble_Simple`.

**10. ¿Por qué el ranking cambia entre test y rolling?**
Porque son períodos distintos. El test 2025–2026 fue favorable al ARIMA; las
ventanas 2023–2025, más volátiles, favorecen al ETS. Es incertidumbre de modelo,
y es la razón metodológica del ensamble.

**11. ¿Cuál es el mejor modelo?**
Depende del criterio: AICc → ARIMAX; MASE test → ARIMA; MASE rolling → ETS;
Winkler test y rolling → ARIMAX. El criterio declarado es el **promedio de rangos
de las cuatro métricas fuera de muestra** (MASE y Winkler en test y rolling), y lo
gana el ARIMAX (2,25). La previsión oficial lo usa por eso. El ARIMA acierta mejor
el número (0,473 contra 0,520) pero pierde en las dos evaluaciones de intervalo.
Los totales difieren 0,30 %, así que la cifra es robusta igual.

**12. ¿Por qué MASE y no MAPE?**
MASE compara contra el naive estacional y tiene un punto de referencia claro
(<1 = mejor que repetir el año pasado). MAPE no, y es inestable cerca de cero.

**13. ¿Qué es el Winkler score?**
Ancho del intervalo más una penalidad por cada observación fuera. Premia
intervalos angostos **y** bien calibrados. Menor es mejor.

**14. ¿Por qué el ARIMA gana MASE pero pierde Winkler?**
Porque sus residuos son más grandes (σ² 12.474 vs 10.811), así que sus intervalos
son más anchos. Cubre bien, pero a costo de ancho.

**15. ¿Por qué el intervalo no se abre como un cono?**
Porque el SMA(1) = −0,80 casi cancela la raíz unitaria estacional: la
incertidumbre del primer año es del nivel, no de la forma. Verificado con
bootstrap. Más allá de h = 12, sí se abre.

**16. ¿Qué pasa si hay otra pandemia?**
El escenario base asume `covid = 0`; el intervalo no incluye un shock de esa
magnitud. Es una limitación declarada. Un escenario de estrés requeriría simular
un pulso.

**17. ¿Por qué no usás variables exógenas (PIB, temperatura, precio)?**
Porque el objetivo es un modelo univariado reproducible con la información
disponible, y porque las exógenas requieren pronosticarlas, agregando
incertidumbre. `Registros` existe pero no es consumo. Queda como extensión.

**18. ¿Cómo sé que no hay fuga de información?**
El test (sep/2025–ago/2026) no se usa para estimar ni para elegir orden; el rolling
calcula la escala solo con el train de cada ventana; los pesos del BMC se estiman
con el train. La única fuga es que los pesos del BMC se calibran hasta ago/2025 y
se usan en ventanas 2022–2024 (declarado, y sin efecto práctico porque BMC ≡
ARIMAX).

**19. ¿Qué harías distinto con más tiempo?**
(a) log-ARIMA o Box-Cox (λ = 0,19); (b) reestimar pesos por ventana; (c) agregar
covariables (temperatura, actividad); (d) intervalos por simulación completa;
(e) evaluar un umbral de 24 meses; (f) comparar con un modelo jerárquico si
hubiera submercados.

**20. ¿Qué archivo cito para cada número?**
Ver §12.2. El más importante: `5_pronostico/pronostico_2026_2027.csv`.

---

## 15. Ejercicios

1. **Verificá el ancla.** Sumá los 12 valores sep/2025–ago/2026 de
   `2_datos/serie_mensual_light_gwh.csv`. Debería dar 22.588,5. Restalo del total
   oficial (22.811,7) y comprobá que da 223,2.
2. **Reproducí un ajuste.** Corré `ARIMA(Consumo_GWh ~ covid)` sobre las 140 obs
   y compará `report()` con §10.3. Deberían coincidir orden y coeficientes.
3. **Cambiá el modelo final** con `modelo_final_forzado <- "ETS_Auto"` y corré la
   Parte 8 sola. Verificá que el total es 22.743,1 y que el mínimo es 1.705,1
   (jul/2027).
4. **Leé la ACF.** Abrí `eda_acf_pacf.png` y ubicá el lag 12 negativo. ¿Qué
   parámetro del modelo lo representa? (SMA(1).)
5. **Comprobá el pulso COVID.** Reemplazá `fin_covid` por `yearmonth("2020 Dec")`
   y mirá cómo cambia el coeficiente. ¿Se acerca a la caída bruta? ¿Por qué?
6. **MASE a mano.** Para ARIMA en el test: calculá
   `mean(abs(real - pronostico))` y dividí por 125,6. Debería dar ≈ 0,473.
7. **Cobertura.** Contá cuántos de los 12 valores reales caen dentro del IC 80 %
   de `pronosticos_test.csv`. Deberían ser 11.
8. **Winkler.** Tomá un mes, calculá el ancho del IC 95 % y sumá la penalidad si
   el real quedó fuera. Compará con `evaluacion_test.csv`.
9. **Rolling.** Abrí `rolling_por_origen.csv` y buscá la ventana con mayor MASE
   para ARIMA. ¿Coincide con el pico de abr/2025?
10. **Pesos.** Corré el bootstrap con `B_bootstrap <- 50` y `forzar_bootstrap <-
    TRUE` en una copia. ¿Siguen siendo 0/0/1? (Sí; tarda ~6 min.)
11. **Drift.** Calculá la media anual 2015–2019 y 2022–2026. ¿La diferencia por año
    es del orden de −24 GWh? (Sí, ≈ −27.)
12. **Intervalos.** Mirá `pronostico_2026_2027.csv`: ¿el ancho 95 % crece con h?
    (Casi no; explicá por el SMA.)

---

## 16. Plan de estudio

Diez sesiones de ~90 minutos. Cada una termina con una salida concreta.

| Sesión | Tema | Leer | Hacer | Producto |
|---|---|---|---|---|
| 1 | Panorama y dato | §1, §2, FPP3 §1.6, §2.1 | Correr el script; abrir `eda_serie.png` | Explicar el pipeline en 5 min |
| 2 | EDA visual | §5.1–5.2, FPP3 §2.2–2.4 | Interpretar `gg_season` y STL | 3 hallazgos escritos |
| 3 | Estacionariedad | §5.3, FPP3 §9.1 | Leer ACF/PACF; correr KPSS | Justificar d=0, D=1 |
| 4 | ETS y ARIMA | §6, FPP3 cap. 8–9 | `report()` de los 3 modelos | Escribir la ecuación del ARIMA |
| 5 | ARIMAX y AICc | §6.4–6.5, FPP3 §10.2, §9.6 | Interpretar −315,7; comparar AICc | Explicar por qué AICc ≠ test |
| 6 | BMC | §7, FPP3 §12.5, §13.4 | Seguir `funcion_replica` línea a línea | Dibujar el algoritmo en 5 pasos |
| 7 | Evaluación | §8, FPP3 §5.8–5.9 | Calcular MASE y Winkler a mano | Tabla del test explicada |
| 8 | Rolling | §9, FPP3 §5.10 | Leer `rolling_por_origen.csv` | Argumento de inestabilidad |
| 9 | Previsión | §10, FPP3 §9.8 | Reconstruir 22.812 desde el ancla | Anatomía de la cifra |
| 10 | Defensa | §11–14 | Responder el banco de preguntas | Guion de 10 min |

**Ruta express (3 h):** sesiones 1, 4, 6, 9 y 10, salteando los detalles de EDA y
rolling.

---

## 17. Glosario

| Español | Inglés | Definición breve |
|---|---|---|
| serie temporal | time series | secuencia de valores ordenados en el tiempo |
| estacionalidad | seasonality | patrón que se repite cada 12 meses |
| tendencia | trend | movimiento de largo plazo |
| estacionariedad | stationarity | propiedades invariantes en el tiempo |
| diferenciación | differencing | resta del valor anterior (o del mismo mes del año anterior) |
| ruido blanco | white noise | errores sin autocorrelación |
| ACF / PACF | autocorrelation / partial autocorrelation | correlación con los propios rezagos |
| AR / MA | autoregressive / moving average | memoria de la serie / de los errores |
| SARIMA | seasonal ARIMA | ARIMA con parte estacional |
| drift | drift | cambio medio por período |
| pulso / escalón | pulse / step | dummy transitoria / permanente |
| ETS | exponential smoothing | suavizado exponencial |
| AICc | corrected Akaike information criterion | criterio de ajuste con penalidad |
| MASE | mean absolute scaled error | error relativo al naive estacional |
| Winkler | interval score | ancho + penalidad por no cubrir |
| cobertura | coverage | % de valores dentro del intervalo |
| origen rodante | rolling origin | validación con ventanas móviles |
| ensamble | forecast combination | promedio ponderado de modelos |
| bootstrap | bootstrap | remuestreo para estimar incertidumbre |
| MBB | moving block bootstrap | remuestreo por bloques |
| BMC | bootstrap model combination | ensamble con pesos por bootstrap |
| quiebre estructural | structural break | cambio de régimen en los parámetros |
| fuga de información | leakage | usar datos del futuro en el ajuste |

---

## 18. Erratas y correcciones importantes

Estas son cosas que aparecían mal en documentos previos y que **no hay que
repetir**:

1. **Unidad de la deriva.** Decía “−18,8 GWh/mes ≈ −225 GWh/año”. Es incorrecto.
   Con \(D=1\), el `constant`/`intercept` está en la escala anual: en el ARIMA es
   −18,76 y la deriva de largo plazo ≈ −24,1 GWh/año (≈ −2,0 GWh/mes).
   `RESULTADOS.md` ya está corregido.
2. **Nivel de la serie.** El documento maestro habla de 5.000–5.400 GWh/mes. La
   serie real va de 1.579 a 2.531 GWh/mes. Si citás el maestro, corregí la escala
   o aclarás que es otra unidad/recorte.
3. **Ubicación del archivo.** `4_archivo/` está **fuera** de
   `Light_SESA_IND2616/`, en la carpeta superior. `LEEME.md` ya lo refleja.
4. **BMC ≠ ensamble diversificado.** Los pesos 0/0/1 hacen que BMC = ARIMAX. No
   es un error; se reporta como limitación.
5. **MASE test vs rolling.** No se comparan magnitudes (0,473 vs 0,836): son
   ventanas y escalas distintas. Solo se comparan rankings dentro de cada tabla.
6. **Intervalos casi constantes.** No es un bug de `fable`: es el efecto del
   SMA(1) ≈ −0,80, que casi cancela la raíz unitaria estacional.
7. **El modelo de evaluación no es el modelo final.** (0,0,2)(0,1,1) vs
   (1,0,0)(1,1,1): el auto-ARIMA re-selecciona al agregar 12 meses. Es correcto.
   El modelo oficial (ARIMAX) usa errores (1,0,0)(1,1,1)[12]; el orden se elige
   con el train, no con el test.
8. **La regla de selección cambió.** Antes el modelo oficial se escribía a mano
   (`modelo_final <- "ARIMA_Auto"`, criterio MASE del test). Ahora lo elige la
   tabla 8.1: promedio de rangos de MASE y Winkler en test y rolling. Gana
   ARIMAX (2,25). El total pasa de 22.754 a 22.812 GWh (+0,25 %).

---

## 19. Qué sigue

Cuando puedas explicar §10 sin mirar, estás listo para el artículo y las slides.

**Artículo SBPO — esqueleto sugerido:**

1. Introducción: demanda, contexto regulatorio, pregunta.
2. Datos: 140 meses, fuente, estacionalidad, COVID.
3. Metodología: ETS, ARIMA, ARIMAX, BMC; test fijo y rolling; criterio de
   selección declarado (rango medio de MASE y Winkler en ambos).
4. Resultados: tabla del test, tabla del rolling, selección por criterio, pesos,
   previsión con IC.
5. Discusión: inestabilidad del ranking, degeneración del BMC, límites del
   ARIMAX (pierde el MASE del test y la cobertura al 80 %), deriva.
6. Conclusiones: 22.812 GWh (IC 95 % ±197), robustez 0,30 %, ARIMAX elegido por el
   rango medio (2,25); el ARIMA es el mejor en el número (0,473 vs 0,520).
7. Limitaciones y trabajo futuro (regresión segmentada; covariables).

**Slides — 10 minutos (11 de contenido + 6 de anexo):**

1. Título y pregunta.
2. La serie (un gráfico, tres hallazgos).
3. El protocolo: intervención, origen móvil, BMC.
4. COVID: pulso, no escalón, y su efecto −315,7.
5. Rolling: la inversión del ranking.
6. BMC: algoritmo y pesos 0/0/1.
7. Test: tabla y lectura (ARIMA punto, ARIMAX intervalo).
8. Previsión: 22.812 y su anatomía.
9. Robustez: los cinco totales, 68,6 GWh.
10. Límites y conclusión.
11. Cierre / preguntas.

**La frase que resume el proyecto:**

> “La previsión es 22.812 GWh para sep/2026–ago/2027, con un intervalo del 95 % de
> ±197 GWh; los cinco modelos coinciden dentro del 0,30 %. Elegimos el ARIMAX
> porque gana el rango medio de las cuatro evaluaciones fuera de muestra (2,25);
> el ARIMA es el que mejor acierta el número (0,473 contra 0,520). Lo que no es
> estable es el ranking; lo que sí es estable es la cifra. Esa es la tensión
> metodológica del trabajo.”
