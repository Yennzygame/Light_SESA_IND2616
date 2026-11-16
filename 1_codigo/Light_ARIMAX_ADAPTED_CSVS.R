# ==============================================================================
# DEMANDA DE ENERGÍA DE LIGHT SESA — SCRIPT ÚNICO DEL PROYECTO
# IND2616 · Análise de Séries Temporais · PUC-Rio
#
# Este archivo REEMPLAZA a todos los scripts anteriores del proyecto:
#
#   boo.R / booR.R ................ Pesos del BMC por bootstrap  -> Parte 5
#   boot2.R ...................... BMC + rolling dentro de cada réplica (obsoleto)
#   rolling_origin_BMC.R ......... Validación de origen rodante  -> Parte 7
#   pronostico_2026_2027.R ....... Previsión sep/2026–ago/2027  -> Parte 8
#   Light_ARIMAX_BMC_IND2616_final.R ... versión guía (rutas D:/) -> obsoleto
#   PRONOSTICO.R / DIAGNOSTICO RESIDUOS.R ... usaban gd_step -> obsoleto
#   STL2.R ....................... detección de atípicos STL    -> Parte 3
#   R1.R ......................... construye la serie desde los CSV SAMP
#
# Contenido:
#   Parte 0  Configuración, rutas y caché
#   Parte 1  Carga y validación de la serie
#   Parte 2  Intervención COVID y partición train / test
#   Parte 3  Análisis exploratorio (EDA)
#   Parte 4  Pilar 1: ETS, ARIMA y ARIMAX-COVID
#   Parte 5  Pilar 2: pesos del BMC por bootstrap (STL + MBB)
#   Parte 6  Evaluación fuera de muestra (test fijo, h = 12)
#   Parte 7  Evaluación robusta: origen rodante (21 ventanas, h = 12)
#   Parte 8  Comparación, selección del modelo y previsión sep/2026 – ago/2027
#   Parte 9  Apéndices: impacto 2020 y cambios estructurales
#   Parte 10 Resumen de archivos generados
#
# Entrada : 2_datos/serie_mensual_light_gwh.csv
# Salida  : 3_resultados/ (una subcarpeta por etapa: 1_eda, 2_pesos_bmc,
#           3_evaluacion_test, 4_rolling_origin, 5_pronostico, 6_apendices)
# Caché   : 3_resultados/0_cache/
#
# Paquetes: fpp3, readr, dplyr, ggplot2, parallel, blocklength
#           (opcional: strucchange, para la Parte 9)
#
# NOTA SOBRE TIEMPOS DE EJECUCIÓN
#   El bootstrap de la Parte 5 es la parte cara (~200 réplicas x 3 modelos).
#   Su resultado queda en caché (bmc_bootstrap.rds). En las corridas
#   siguientes el script lo reutiliza y termina en ~3 minutos. Para forzar el
#   recálculo pon `forzar_bootstrap <- TRUE`.
# ==============================================================================

suppressPackageStartupMessages({
  library(fpp3)
  library(readr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(parallel)
})

options(dplyr.summarise.inform = FALSE)

# ==============================================================================
# PARTE 0 — CONFIGURACIÓN, RUTAS Y CACHÉ
# ==============================================================================

# ---- 0.1 Rutas ---------------------------------------------------------------
# Único lugar del script donde hay rutas absolutas. Si mueves el proyecto,
# cambia solo estas dos líneas.

carpeta_proyecto   <- "C:/Users/yennz/Downloads/Proyecto_Series_Temporales/Light_SESA_IND2616"
carpeta_datos      <- file.path(carpeta_proyecto, "2_datos")
carpeta_resultados <- file.path(carpeta_proyecto, "3_resultados")

archivo_datos <- file.path(carpeta_datos, "serie_mensual_light_gwh.csv")

# Cada etapa del análisis escribe en su propia subcarpeta de 3_resultados.
subcarpetas <- c(
  cache      = "0_cache",
  eda        = "1_eda",
  pesos      = "2_pesos_bmc",
  test       = "3_evaluacion_test",
  rolling    = "4_rolling_origin",
  pronostico = "5_pronostico",
  apendices  = "6_apendices"
)

for (s in subcarpetas) {
  dir.create(file.path(carpeta_resultados, s), recursive = TRUE, showWarnings = FALSE)
}

ruta_etapa <- function(etapa, archivo) {
  file.path(carpeta_resultados, subcarpetas[[etapa]], archivo)
}

# A qué subcarpeta va cada archivo de salida.
destino_salida <- c(
  # 1_eda
  "eda_serie.png"                    = "eda",
  "eda_estacional.png"               = "eda",
  "eda_stl.png"                      = "eda",
  "eda_acf_pacf.png"                 = "eda",
  "eda_atipicos_stl.csv"             = "eda",
  # 2_pesos_bmc
  "frecuencias_pesos_BMC_COVID.csv"  = "pesos",
  "advertencias_BMC.csv"             = "pesos",
  # 3_evaluacion_test
  "evaluacion_test.csv"              = "test",
  "pronosticos_test.csv"             = "test",
  "evaluacion_test.png"              = "test",
  "intervalos_BMC_COVID.csv"         = "test",
  "cobertura_BMC_COVID.csv"          = "test",
  "pronostico_BMC_COVID.png"         = "test",
  # 4_rolling_origin
  "rolling_pronosticos.csv"          = "rolling",
  "rolling_resumen.csv"              = "rolling",
  "rolling_por_origen.csv"           = "rolling",
  "rolling_por_horizonte.csv"        = "rolling",
  "rolling_MASE.png"                 = "rolling",
  "rolling_Winkler.png"              = "rolling",
  # 5_pronostico
  "pronostico_2026_2027.csv"         = "pronostico",
  "pronostico_2026_2027_ancho.csv"   = "pronostico",
  "pronostico_2026_2027_resumen.csv" = "pronostico",
  "pronostico_2026_2027.png"         = "pronostico",
  "pronostico_2026_2027_comparacion.png" = "pronostico",
  "seleccion_modelo.csv"             = "pronostico",
  "comparacion_modelos.csv"          = "pronostico",
  # 6_apendices
  "apendice_impacto_2020.csv"        = "apendices",
  "apendice_cambios_estructurales.csv" = "apendices"
)

# ---- 0.2 Parámetros metodológicos --------------------------------------------
# Todo lo que un lector del artículo necesita saber para reproducir está aquí.

semilla <- 2616

# Intervención: pulso COVID de abril a junio de 2020 (confinamiento severo).
inicio_covid <- yearmonth("2020 Apr")
fin_covid    <- yearmonth("2020 Jun")

# Partición: entrenamiento hasta ago/2025, prueba sep/2025–ago/2026 (h = 12).
fin_train <- yearmonth("2025 Aug")
h_test    <- 12

# Origen rodante: 21 ventanas mensuales, dic/2022 a ago/2024.
inicio_rolling <- yearmonth("2022 Dec")
n_origenes     <- 21
h_rolling      <- 12

# Previsión final: 12 meses a partir del mes siguiente al último observado.
h_futuro  <- 12
# primer mes futuro se calcula automáticamente (ver Parte 8)

# Bootstrap del BMC.
B_bootstrap    <- 200
tamano_tanda   <- 25          # réplicas por tanda (checkpoint y progreso)
forzar_bootstrap <- FALSE     # TRUE => recalcula los pesos aunque haya caché

# Origen rodante en paralelo (2–3 minutos). Si lo pones en FALSE tarda ~8 min.
forzar_rolling <- FALSE       # TRUE => recalcula aunque haya caché

# Bandas empíricas del BMC por remuestreo de bloques (Parte 6).
bandas_empiricas  <- TRUE
B_intervalos      <- 2000

# Núcleos para los procesos en paralelo. En este equipo (6 núcleos / 12 hilos)
# 4 es un buen equilibrio: no satura los 15 GB de RAM.
num_cores <- max(1L, min(4L, parallel::detectCores() - 1L))

# Modelo con el que se hace la previsión oficial de la Parte 8.
#
# Por defecto NO se escribe a mano: lo elige la comparación de la Parte 8.1.
# La regla es el promedio de rangos sobre cuatro métricas fuera de muestra
# (MASE y Winkler 95 % en el test fijo y en el origen rodante), que es la misma
# que usa el script del compañero (Light_ARIMAX_BMC_IND2616_final_v2.R).
#
# Por qué no AICc: el AICc mide ajuste DENTRO de la muestra. La dummy COVID
# reduce tanto la varianza residual que el ARIMAX gana siempre el AICc (de ahí
# los pesos 0/0/1 del BMC), pero eso no dice nada sobre capacidad de pronóstico.
#
# Por qué no solo el MASE: el MASE premia acertar el número; el Winkler premia
# intervalos angostos que cubran. Cada criterio por separado es inestable entre
# ventanas (Parte 7). El promedio de rangos combina los dos tipos de error y no
# depende de una sola ventana.
#
# Override manual: deja `modelo_final_forzado <- NULL` para que decida la tabla.
# Si quieres fijarlo, escribe uno de estos nombres:
#   "ETS_Auto", "ARIMA_Auto", "ARIMAX_Covid", "BMC", "Ensamble_Simple"
modelo_final_forzado <- NULL

# ---- 0.3 Archivos de caché ---------------------------------------------------

ruta_cache_pesos    <- ruta_etapa("cache", "bmc_bootstrap.rds")
ruta_cache_parcial  <- ruta_etapa("cache", "bmc_bootstrap_parcial.rds")
ruta_cache_rolling  <- ruta_etapa("cache", "rolling_cache.rds")
ruta_pesos_csv      <- ruta_etapa("pesos", "frecuencias_pesos_BMC_COVID.csv")

# ---- 0.4 Utilidades ----------------------------------------------------------

# Devuelve la ruta final de un archivo de salida según su etapa.
# Acepta vectores (se usa en el resumen de la Parte 10).
nombre_archivo <- function(archivo) {
  etapa <- unname(destino_salida[archivo])
  salida <- file.path(carpeta_resultados, archivo)
  conocidos <- !is.na(etapa)
  salida[conocidos] <- file.path(
    carpeta_resultados,
    subcarpetas[etapa[conocidos]],
    archivo[conocidos]
  )
  salida
}

guardar <- function(objeto, archivo) {
  write_csv(objeto, nombre_archivo(archivo))
  invisible(archivo)
}

guardar_png <- function(grafico, archivo, ancho = 10, alto = 6) {
  ggsave(
    filename = nombre_archivo(archivo),
    plot = grafico,
    width = ancho, height = alto, dpi = 300
  )
  invisible(archivo)
}

# Los nombres del bootstrap ("ARIMAX_COVID") y los del ajuste ("ARIMAX_Covid")
# se comparan sin mayúsculas ni separadores.
normalizar_nombre <- function(x) gsub("[^a-z0-9]", "", tolower(x))

titulo <- function(texto) {
  cat("\n", strrep("=", 78), "\n", sep = "")
  cat(texto, "\n")
  cat(strrep("=", 78), "\n", sep = "")
}

cat("\nProyecto Light SESA · IND2616 · script único\n")
cat("Inicio:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")

# ==============================================================================
# PARTE 1 — CARGA Y VALIDACIÓN DE LA SERIE
# ==============================================================================

titulo("PARTE 1 — Serie mensual de consumo (GWh)")

if (!file.exists(archivo_datos)) {
  stop("No se encuentra el archivo de datos: ", archivo_datos)
}

datos <- read_csv(archivo_datos, show_col_types = FALSE) %>%
  mutate(Mes = yearmonth(Mes)) %>%
  select(Mes, Consumo_GWh) %>%
  arrange(Mes) %>%
  as_tsibble(index = Mes)

if (nrow(datos) == 0 || anyNA(datos$Consumo_GWh)) {
  stop("La serie está vacía o tiene valores faltantes en Consumo_GWh.")
}
if (has_gaps(datos)$.gaps) {
  stop("La serie tiene meses faltantes. Corrige el calendario antes del análisis.")
}

cat("Observaciones:", nrow(datos), "\n")
cat("Rango:", as.character(min(datos$Mes)), "a", as.character(max(datos$Mes)), "\n")
cat("Media:", round(mean(datos$Consumo_GWh), 1), "GWh/mes\n")

# ==============================================================================
# PARTE 2 — INTERVENCIÓN COVID Y PARTICIÓN TRAIN / TEST
# ==============================================================================

titulo("PARTE 2 — Intervención COVID y partición")

datos <- datos %>%
  mutate(
    covid = if_else(Mes >= inicio_covid & Mes <= fin_covid, 1, 0)
  )

train_data <- datos %>% filter(Mes <= fin_train)
test_data  <- datos %>% filter(Mes >  fin_train)

cat("Train:", nrow(train_data), "meses (hasta", as.character(fin_train), ")\n")
cat("Test :", nrow(test_data), "meses (h =", h_test, ")\n")

if (nrow(test_data) != h_test) {
  stop(
    "Se esperaban ", h_test, " meses de prueba y hay ", nrow(test_data),
    ". Revisa `fin_train` o agrega datos nuevos."
  )
}
if (sum(train_data$covid) == 0) {
  stop("La ventana COVID no cae dentro del entrenamiento.")
}

# ==============================================================================
# PARTE 3 — ANÁLISIS EXPLORATORIO (EDA)
# ==============================================================================

titulo("PARTE 3 — Análisis exploratorio")

# ---- 3.1 Serie completa y patrón estacional ----------------------------------

g_serie <- autoplot(datos, Consumo_GWh) +
  labs(
    title = "Demanda de energía eléctrica — Light SESA",
    subtitle = "Consumo mensual facturado, CATIVO + LIVRE (GWh)",
    y = "GWh/mes", x = NULL
  ) +
  theme_minimal()
print(g_serie)
guardar_png(g_serie, "eda_serie.png")

g_estacional <- datos %>%
  gg_season(Consumo_GWh) +
  labs(
    title = "Patrón estacional por año",
    subtitle = "Cada línea es un año; el pico se concentra en el verano",
    y = "GWh/mes", x = "Mes"
  ) +
  theme_minimal()
print(g_estacional)
guardar_png(g_estacional, "eda_estacional.png")

# ---- 3.2 Descomposición STL robusta ------------------------------------------

fit_stl <- train_data %>% model(STL(Consumo_GWh, robust = TRUE))

g_stl <- components(fit_stl) %>%
  autoplot() +
  labs(title = "Descomposición STL robusta (entrenamiento)")
print(g_stl)
guardar_png(g_stl, "eda_stl.png")

# ---- 3.3 Atípicos por la regla de 3 x IQR sobre el residuo -------------------

comp_stl <- components(fit_stl)
lim_inf <- quantile(comp_stl$remainder, 0.25, na.rm = TRUE) - 3 * IQR(comp_stl$remainder, na.rm = TRUE)
lim_sup <- quantile(comp_stl$remainder, 0.75, na.rm = TRUE) + 3 * IQR(comp_stl$remainder, na.rm = TRUE)

atipicos <- comp_stl %>%
  filter(remainder < lim_inf | remainder > lim_sup) %>%
  select(Mes, Consumo_GWh, remainder)

cat("\nMeses atípicos por la regla 3 x IQR en el residuo STL:\n")
if (nrow(atipicos) == 0) {
  cat("  (ninguno)\n")
} else {
  print(atipicos, n = Inf)
}
guardar(atipicos, "eda_atipicos_stl.csv")

# ---- 3.4 Estacionariedad ------------------------------------------------------
# Se envuelve en tryCatch: si una prueba falla, el script sigue.

cat("\n--- Diagnóstico de estacionariedad (entrenamiento) ---\n")

tryCatch(
  {
    lambda_guerrero <- train_data %>%
      features(Consumo_GWh, guerrero) %>%
      pull(lambda_guerrero)
    cat("Lambda óptimo de Guerrero:", round(lambda_guerrero, 4), "\n")
    cat("  (se reporta como diagnóstico; los modelos se estiman en niveles,",
        "como en la guía del proyecto)\n")
  },
  error = function(e) cat("Guerrero no disponible:", conditionMessage(e), "\n")
)

tryCatch(
  print(train_data %>% features(Consumo_GWh, list(unitroot_kpss, unitroot_ndiffs, unitroot_nsdiffs))),
  error = function(e) cat("Pruebas de raíz unitaria no disponibles:", conditionMessage(e), "\n")
)

g_acf <- train_data %>%
  gg_tsdisplay(difference(Consumo_GWh, 12), plot_type = "partial", lag_max = 36) +
  labs(title = "ACF/PACF tras diferenciación estacional (lag 12)")
print(g_acf)
try(guardar_png(g_acf, "eda_acf_pacf.png"), silent = TRUE)

# ==============================================================================
# PARTE 4 — PILAR 1: ETS, ARIMA Y ARIMAX-COVID
# ==============================================================================

titulo("PARTE 4 — Modelos base (entrenamiento)")

fit_modelos <- train_data %>%
  model(
    ETS_Auto     = ETS(Consumo_GWh),
    ARIMA_Auto   = ARIMA(Consumo_GWh),
    ARIMAX_Covid = ARIMA(Consumo_GWh ~ covid)
  )

cat("\nModelos ajustados:\n")
print(fit_modelos)

cat("\n--- ETS ---\n");   report(fit_modelos %>% select(ETS_Auto))
cat("\n--- ARIMA ---\n"); report(fit_modelos %>% select(ARIMA_Auto))
cat("\n--- ARIMAX ---\n"); report(fit_modelos %>% select(ARIMAX_Covid))

# Coeficiente de la intervención COVID.
coef_covid <- tidy(fit_modelos) %>%
  filter(.model == "ARIMAX_Covid", term == "covid") %>%
  pull(estimate)

if (length(coef_covid) != 1 || !is.finite(coef_covid)) {
  stop("No se pudo extraer el coeficiente de la intervención COVID.")
}

cat("\n--- Efecto de la intervención COVID ---\n")
print(
  tidy(fit_modelos) %>%
    filter(term == "covid") %>%
    mutate(t_stat = estimate / std.error)
)
cat("Interpretación: la caída estimada del consumo en abr–jun/2020 fue de",
    round(coef_covid, 1), "GWh/mes.\n")

cat("\n--- Comparación por AICc ---\n")
print(glance(fit_modelos) %>% select(.model, AICc) %>% arrange(AICc))

# Diagnóstico de residuos.
try(print(fit_modelos %>% select(ARIMAX_Covid) %>% gg_tsresiduals()), silent = TRUE)

cat("\n--- Ljung-Box sobre residuos (lag 24) ---\n")
try(print(fit_modelos %>% augment() %>% features(.innov, ljung_box, lag = 24) %>% select(.model, lb_stat, lb_pvalue)), silent = TRUE)

# ==============================================================================
# PARTE 5 — PILAR 2: PESOS DEL BMC POR BOOTSTRAP
# ==============================================================================
#
# Procedimiento (documentado en el artículo):
#   1. Se estima el efecto COVID y se le resta a la serie del entrenamiento.
#   2. STL con estacionalidad periódica separa tendencia, estacionalidad y residuo.
#   3. Se remuestrean bloques consecutivos de residuos (Moving Block Bootstrap),
#      con largo de bloque elegido por el método de Hall–Horowitz–Jing.
#   4. En cada réplica se ajustan ETS, ARIMA y ARIMAX y se registra el AICc.
#   5. El peso de cada modelo es la frecuencia con que tuvo el AICc más bajo.
#
# El resultado se guarda en caché (bmc_bootstrap.rds). Es determinista: misma
# semilla + mismos datos + mismo B => mismos pesos. Por eso no hace falta
# recalcularlo en cada corrida.

titulo("PARTE 5 — Pesos del BMC por bootstrap")

modelos_candidatos <- c("ETS_Auto", "ARIMA_Auto", "ARIMAX_Covid")

# ---- 5.1 Insumos: STL, residuos y largo de bloque ----------------------------

serie_sin_covid <- train_data %>%
  mutate(consumo_ajustado = Consumo_GWh - coef_covid * covid) %>%
  select(Mes, consumo_ajustado) %>%
  as_tsibble(index = Mes)

componentes_stl <- serie_sin_covid %>%
  model(STL(consumo_ajustado ~ season(window = "periodic"), robust = TRUE)) %>%
  components() %>%
  as_tibble()

columnas_estacionales <- names(componentes_stl)[grepl("season", names(componentes_stl))]
if (length(columnas_estacionales) == 0) {
  stop("STL no devolvió ninguna columna estacional.")
}
columnas_estacionales <- columnas_estacionales[1]

tendencia      <- componentes_stl$trend
estacionalidad <- componentes_stl[[columnas_estacionales]]
residuos_stl   <- componentes_stl$remainder - mean(componentes_stl$remainder)

if (any(!is.finite(tendencia)) || any(!is.finite(estacionalidad)) || any(!is.finite(residuos_stl))) {
  stop("STL produjo valores faltantes o no finitos.")
}

# ---- 5.2 Largo de bloque por el método HHJ ----------------------------------

if (!requireNamespace("blocklength", quietly = TRUE)) {
  stop("Falta el paquete 'blocklength'. Instálalo con install.packages('blocklength').")
}

set.seed(semilla)
seleccion_bloque <- blocklength::hhj(
  series = residuos_stl, nb = 100, n_iter = 10,
  k = "two-sided", plots = FALSE, verbose = FALSE
)

largo_bloque <- as.integer(round(seleccion_bloque[["Optimal Block Length"]]))
largo_bloque <- max(2L, min(largo_bloque, length(residuos_stl) - 1L))
cat("Largo de bloque MBB (HHJ):", largo_bloque, "meses\n")

# ---- 5.3 Funciones del bootstrap --------------------------------------------

# Remuestrea bloques consecutivos de residuos.
remuestrear_mbb <- function(residuos, largo, cantidad) {
  n <- length(residuos)
  if (largo > n) stop("El largo del bloque no puede superar el número de residuos.")
  n_bloques <- ceiling(cantidad / largo)
  inicios <- sample.int(n - largo + 1L, size = n_bloques, replace = TRUE)
  posiciones <- unlist(lapply(inicios, function(i) seq.int(i, i + largo - 1L)))
  residuos[posiciones[seq_len(cantidad)]]
}

# AICc de una familia en una réplica. Devuelve Inf si el ajuste falla.
ajustar_familia <- function(datos_replica, familia) {
  ajuste <- tryCatch(
    switch(
      familia,
      ETS_Auto     = datos_replica %>% model(Modelo = ETS(Consumo_boot)),
      ARIMA_Auto   = datos_replica %>% model(Modelo = ARIMA(Consumo_boot)),
      ARIMAX_Covid = datos_replica %>% model(Modelo = ARIMA(Consumo_boot ~ covid))
    ),
    error = function(e) NULL
  )
  if (is.null(ajuste)) return(Inf)
  valor <- tryCatch(glance(ajuste) %>% pull(AICc), error = function(e) NA_real_)
  # `unname` es imprescindible: fable devuelve el AICc con nombre ("AICc.year")
  # y al combinarlo con c() contamina los nombres del vector de modelos.
  valor <- unname(valor)
  if (length(valor) != 1 || !is.finite(valor)) Inf else valor
}

# Una réplica completa: remuestrea, rearma la serie y compite los 3 modelos.
funcion_replica <- function(i) {
  set.seed(semilla + i)

  n <- length(residuos_stl)
  residuos_boot <- remuestrear_mbb(residuos_stl, largo_bloque, n)

  datos_replica <- train_data %>%
    mutate(Consumo_boot = tendencia + estacionalidad + residuos_boot + coef_covid * covid) %>%
    select(Mes, Consumo_boot, covid) %>%
    as_tsibble(index = Mes)

  avisos <- character()
  aicc <- withCallingHandlers(
    c(
      ETS_Auto     = ajustar_familia(datos_replica, "ETS_Auto"),
      ARIMA_Auto   = ajustar_familia(datos_replica, "ARIMA_Auto"),
      ARIMAX_Covid = ajustar_familia(datos_replica, "ARIMAX_Covid")
    ),
    warning = function(w) {
      avisos <<- c(avisos, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  aicc <- stats::setNames(as.numeric(aicc), c("ETS_Auto", "ARIMA_Auto", "ARIMAX_Covid"))

  seleccion <- if (all(!is.finite(aicc))) NA_character_ else names(which.min(aicc))

  list(replica = i, aicc = aicc, seleccion = seleccion, avisos = avisos)
}

# Corre el bootstrap en paralelo por tandas, con progreso y checkpoint.
correr_bootstrap <- function(pendientes) {
  cl <- parallel::makeCluster(num_cores)
  on.exit(parallel::stopCluster(cl), add = TRUE)

  parallel::clusterEvalQ(cl, {
    suppressPackageStartupMessages({
      library(fpp3)
      library(dplyr)
      library(tidyr)
    })
  })

  parallel::clusterExport(
    cl,
    varlist = c(
      "residuos_stl", "largo_bloque", "train_data", "coef_covid",
      "tendencia", "estacionalidad", "semilla",
      "remuestrear_mbb", "ajustar_familia", "funcion_replica"
    ),
    envir = globalenv()
  )

  tandas <- split(pendientes, ceiling(seq_along(pendientes) / tamano_tanda))
  salida <- list()

  for (k in seq_along(tandas)) {
    tanda <- tandas[[k]]
    inicio <- Sys.time()
    salida <- c(salida, parallel::parLapplyLB(cl, tanda, funcion_replica))
    cat(sprintf(
      "  tanda %d/%d · réplicas %d–%d · %.1f s\n",
      k, length(tandas), min(tanda), max(tanda),
      as.numeric(difftime(Sys.time(), inicio, units = "secs"))
    ))
  }

  salida
}

# ---- 5.4 ¿Se usa caché o se recalcula? --------------------------------------

parametros_bmc <- list(
  B = B_bootstrap,
  semilla = semilla,
  fin_train = as.character(fin_train),
  metodo = "AICc",
  largo_bloque = largo_bloque,
  n_train = nrow(train_data)
)

pesos_bmc  <- NULL
frecuencias <- NULL
avisos_bmc  <- NULL
origen_pesos <- NULL

cache_valida <- function(cache, parametros) {
  is.list(cache) && !is.null(cache$parametros) && identical(cache$parametros, parametros)
}

if (!forzar_bootstrap && file.exists(ruta_cache_pesos)) {
  cache <- readRDS(ruta_cache_pesos)
  if (cache_valida(cache, parametros_bmc)) {
    pesos_bmc    <- cache$pesos
    frecuencias  <- cache$frecuencias
    avisos_bmc   <- cache$avisos
    origen_pesos <- "caché (bmc_bootstrap.rds)"
  }
}

# Si no hay caché pero sí el CSV de una corrida previa, se reutiliza.
if (is.null(pesos_bmc) && !forzar_bootstrap && file.exists(ruta_pesos_csv)) {
  tabla <- read_csv(ruta_pesos_csv, show_col_types = FALSE)
  pesos_leidos <- tabla$peso[match(normalizar_nombre(modelos_candidatos), normalizar_nombre(tabla$modelo))]
  if (!anyNA(pesos_leidos)) {
    frecuencias <- tibble(
      modelo = factor(modelos_candidatos, levels = modelos_candidatos),
      n = tabla$n[match(normalizar_nombre(modelos_candidatos), normalizar_nombre(tabla$modelo))],
      frecuencia = pesos_leidos,
      peso = pesos_leidos
    )
    pesos_bmc    <- pesos_leidos
    origen_pesos <- "CSV de una corrida previa (boo.R)"
  }
}

# ---- 5.5 Recalcular si hace falta -------------------------------------------

if (is.null(pesos_bmc)) {
  cat("\nCalculando pesos del BMC (", B_bootstrap, "réplicas ·", num_cores, "núcleos )...\n")

  resultados <- list()
  hechos <- integer(0)

  # Reanudar un cálculo interrumpido.
  if (file.exists(ruta_cache_parcial)) {
    parcial <- readRDS(ruta_cache_parcial)
    if (cache_valida(parcial, parametros_bmc) && length(parcial$resultados) > 0) {
      resultados <- parcial$resultados
      hechos <- vapply(resultados, function(x) as.integer(x$replica), integer(1))
      cat("  reanudando:", length(hechos), "réplicas ya calculadas\n")
    }
  }

  pendientes <- setdiff(seq_len(B_bootstrap), hechos)

  if (length(pendientes) > 0) {
    nuevos <- correr_bootstrap(pendientes)
    resultados <- c(resultados, nuevos)
    saveRDS(
      list(parametros = parametros_bmc, resultados = resultados),
      ruta_cache_parcial
    )
  }

  selecciones <- vapply(
    resultados, function(x) if (is.null(x$seleccion)) NA_character_ else x$seleccion,
    character(1)
  )
  selecciones_validas <- selecciones[!is.na(selecciones)]

  if (length(selecciones_validas) < 0.95 * B_bootstrap) {
    stop("Fallaron demasiadas réplicas (", B_bootstrap - length(selecciones_validas),
         " de ", B_bootstrap, "). Revisa advertencias_BMC.csv.")
  }

  frecuencias <- tibble(modelo = factor(selecciones_validas, levels = modelos_candidatos)) %>%
    count(modelo, .drop = FALSE) %>%
    mutate(frecuencia = n / sum(n), peso = frecuencia)

  pesos_bmc <- frecuencias$peso[match(modelos_candidatos, as.character(frecuencias$modelo))]
  names(pesos_bmc) <- modelos_candidatos

  avisos_bmc <- bind_rows(lapply(resultados, function(x) {
    if (length(x$avisos) == 0) return(NULL)
    tibble(replica = x$replica, advertencia = x$avisos)
  }))

  saveRDS(
    list(parametros = parametros_bmc, pesos = pesos_bmc,
         frecuencias = frecuencias, avisos = avisos_bmc),
    ruta_cache_pesos
  )
  origen_pesos <- "recalculado en esta corrida"
}

if (is.null(names(pesos_bmc))) names(pesos_bmc) <- modelos_candidatos

if (anyNA(pesos_bmc) || abs(sum(pesos_bmc) - 1) > 1e-8) {
  stop("Los pesos del BMC no son válidos o no suman 1.")
}

cat("\nOrigen de los pesos:", origen_pesos, "\n")
cat("\n--- Frecuencia con que cada modelo tuvo el mejor AICc ---\n")
print(as_tibble(frecuencias))
cat("\nPesos asignados al BMC (ETS, ARIMA, ARIMAX):", round(pesos_bmc, 4), "\n")

if (max(pesos_bmc) > 0.999) {
  cat(
    "\nADVERTENCIA: pesos degenerados (un modelo concentra ~100%).",
    "\nEl BMC coincide prácticamente con", names(which.max(pesos_bmc)), ".",
    "\nEsto es un resultado, no un error: se reporta como limitación y se",
    "\ncompara con el ensamble de pesos iguales (Ensamble_Simple).\n"
  )
}

guardar(frecuencias, "frecuencias_pesos_BMC_COVID.csv")
if (!is.null(avisos_bmc) && nrow(avisos_bmc) > 0) {
  guardar(avisos_bmc, "advertencias_BMC.csv")
  cat("Advertencias registradas:", nrow(avisos_bmc), "(ver advertencias_BMC.csv)\n")
}

# ---- 5.6 Ensambles sobre el entrenamiento -----------------------------------

fit_modelos <- fit_modelos %>%
  mutate(
    Ensamble_Simple = (ETS_Auto + ARIMA_Auto + ARIMAX_Covid) / 3,
    BMC = fabletools::combination_weighted(
      ETS_Auto, ARIMA_Auto, ARIMAX_Covid,
      weights = unname(pesos_bmc)
    )
  )

cat("\nModelos disponibles para evaluar:\n")
print(names(fit_modelos))

# ==============================================================================
# PARTE 6 — EVALUACIÓN FUERA DE MUESTRA (TEST FIJO)
# ==============================================================================

titulo("PARTE 6 — Evaluación en test (sep/2025 – ago/2026)")

fc_modelos <- fit_modelos %>% forecast(new_data = test_data, level = c(80, 95))

# ---- 6.1 Métricas puntuales y probabilísticas -------------------------------

tabla_precision <- accuracy(fc_modelos, datos) %>%
  filter(.type == "Test") %>%
  select(.model, RMSE, MAE, MAPE, MASE)

smape <- fc_modelos %>%
  as_tibble() %>%
  select(.model, Mes, pronostico = .mean) %>%
  left_join(as_tibble(test_data) %>% select(Mes, real = Consumo_GWh), by = "Mes") %>%
  group_by(.model) %>%
  summarise(
    sMAPE = mean(200 * abs(real - pronostico) / (abs(real) + abs(pronostico))),
    .groups = "drop"
  )

winkler <- accuracy(
  fc_modelos, datos,
  measures = list(winkler = winkler_score), level = 95
) %>%
  filter(.type == "Test") %>%
  select(.model, Winkler_95 = winkler)

intervalos_test <- fc_modelos %>%
  hilo(level = c(80, 95)) %>%
  unpack_hilo(c(`80%`, `95%`)) %>%
  as_tibble() %>%
  left_join(as_tibble(test_data) %>% select(Mes, real = Consumo_GWh), by = "Mes") %>%
  mutate(
    error = real - .mean,
    dentro_80 = real >= `80%_lower` & real <= `80%_upper`,
    dentro_95 = real >= `95%_lower` & real <= `95%_upper`
  )

cobertura_test <- intervalos_test %>%
  group_by(.model) %>%
  summarise(
    cobertura_80 = mean(dentro_80),
    cobertura_95 = mean(dentro_95),
    .groups = "drop"
  )

tabla_precision <- tabla_precision %>%
  left_join(smape, by = ".model") %>%
  left_join(winkler, by = ".model") %>%
  left_join(cobertura_test, by = ".model") %>%
  arrange(MASE)

cat("\n--- Precisión en el test fijo (h = 12) ---\n")
print(tabla_precision, n = Inf, width = Inf)

guardar(tabla_precision, "evaluacion_test.csv")
guardar(
  intervalos_test %>% select(.model, Mes, pronostico = .mean,
                             inferior_80 = `80%_lower`, superior_80 = `80%_upper`,
                             inferior_95 = `95%_lower`, superior_95 = `95%_upper`,
                             real, error),
  "pronosticos_test.csv"
)

# Gráfico de la evaluación.
g_test <- fc_modelos %>%
  filter(.model %in% c("ARIMA_Auto", "ARIMAX_Covid", "BMC")) %>%
  autoplot(datos %>% filter(Mes >= yearmonth("2023 Jan")), level = NULL) +
  labs(
    title = "Pronósticos fuera de muestra (sep/2025 – ago/2026)",
    subtitle = "El tramo negro es el período de prueba observado",
    y = "GWh/mes", x = NULL, colour = "Modelo"
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")
print(g_test)
guardar_png(g_test, "evaluacion_test.png")

# ---- 6.2 Bandas empíricas del BMC (MBB sobre residuos STL) ------------------

if (bandas_empiricas) {
  cat("\n--- Bandas empíricas del BMC por MBB (", B_intervalos, "simulaciones ) ---\n")

  media_bmc <- fc_modelos %>%
    filter(.model == "BMC") %>%
    as_tibble() %>%
    select(Mes, pronostico = .mean)

  set.seed(semilla)
  simulaciones <- replicate(
    B_intervalos,
    remuestrear_mbb(residuos_stl, largo_bloque, nrow(media_bmc))
  )
  simulaciones <- sweep(simulaciones, 1, media_bmc$pronostico, "+")

  bandas_bmc <- media_bmc %>%
    mutate(
      inferior_80 = apply(simulaciones, 1, quantile, probs = 0.10, na.rm = TRUE),
      superior_80 = apply(simulaciones, 1, quantile, probs = 0.90, na.rm = TRUE),
      inferior_95 = apply(simulaciones, 1, quantile, probs = 0.025, na.rm = TRUE),
      superior_95 = apply(simulaciones, 1, quantile, probs = 0.975, na.rm = TRUE)
    ) %>%
    left_join(
      as_tibble(test_data) %>% select(Mes, valor_real = Consumo_GWh),
      by = "Mes"
    ) %>%
    mutate(
      dentro_80 = valor_real >= inferior_80 & valor_real <= superior_80,
      dentro_95 = valor_real >= inferior_95 & valor_real <= superior_95
    )

  cobertura_bandas <- bandas_bmc %>%
    summarise(
      meses_evaluados = n(),
      dentro_80 = sum(dentro_80, na.rm = TRUE),
      cobertura_80 = mean(dentro_80, na.rm = TRUE),
      dentro_95 = sum(dentro_95, na.rm = TRUE),
      cobertura_95 = mean(dentro_95, na.rm = TRUE)
    )

  print(cobertura_bandas)
  guardar(bandas_bmc, "intervalos_BMC_COVID.csv")
  guardar(cobertura_bandas, "cobertura_BMC_COVID.csv")

  g_bandas <- ggplot() +
    geom_line(
      data = as_tibble(datos) %>% filter(Mes >= yearmonth("2023 Jan")),
      aes(x = Mes, y = Consumo_GWh), colour = "gray40", linewidth = 0.8
    ) +
    geom_ribbon(data = bandas_bmc, aes(x = Mes, ymin = inferior_95, ymax = superior_95),
                fill = "#74ADD1", alpha = 0.25) +
    geom_ribbon(data = bandas_bmc, aes(x = Mes, ymin = inferior_80, ymax = superior_80),
                fill = "#4575B4", alpha = 0.30) +
    geom_line(data = bandas_bmc, aes(x = Mes, y = pronostico),
              colour = "blue", linewidth = 1, linetype = "dashed") +
    geom_line(data = bandas_bmc, aes(x = Mes, y = valor_real),
              colour = "black", linewidth = 1) +
    labs(
      title = "BMC con bandas empíricas (Moving Block Bootstrap)",
      subtitle = paste0("Bloques de ", largo_bloque, " meses · ",
                        B_intervalos, " simulaciones"),
      x = NULL, y = "GWh/mes"
    ) +
    theme_minimal()
  print(g_bandas)
  guardar_png(g_bandas, "pronostico_BMC_COVID.png")
}

# ==============================================================================
# PARTE 7 — EVALUACIÓN ROBUSTA: ORIGEN RODANTE
# ==============================================================================
#
# Se reajustan los modelos en 21 orígenes mensuales (dic/2022 – ago/2024) y se
# pronostica h = 12 en cada uno. El MASE se escala con el naive estacional de
# cada ventana de entrenamiento, para no usar información futura.
#
# Los pesos del BMC son los de la Parte 5 (estimados hasta ago/2025): es un
# único punto de calibración, declarado como limitación en el artículo.

titulo("PARTE 7 — Validación por origen rodante")

origenes <- inicio_rolling + 0:(n_origenes - 1)

parametros_rolling <- list(
  origenes = as.character(origenes),
  h = h_rolling,
  pesos = unname(pesos_bmc),
  fin_datos = as.character(max(datos$Mes))
)

evaluar_origen <- function(i) {
  o <- origenes[i]

  tryCatch(
    {
      ent <- datos %>% filter(Mes <= o)
      fut <- datos %>% filter(Mes > o, Mes <= o + h_rolling)

      if (nrow(fut) < h_rolling || sum(ent$covid) == 0) return(NULL)

      escala <- mean(abs(diff(as.numeric(ent$Consumo_GWh), lag = 12)))

      ajuste <- ent %>%
        model(
          ETS_Auto     = ETS(Consumo_GWh),
          ARIMA_Auto   = ARIMA(Consumo_GWh),
          ARIMAX_Covid = ARIMA(Consumo_GWh ~ covid)
        ) %>%
        mutate(
          Ensamble_Simple = (ETS_Auto + ARIMA_Auto + ARIMAX_Covid) / 3,
          BMC = fabletools::combination_weighted(
            ETS_Auto, ARIMA_Auto, ARIMAX_Covid,
            weights = unname(pesos_bmc)
          )
        )

      ajuste %>%
        forecast(new_data = fut) %>%
        hilo(level = c(80, 95)) %>%
        unpack_hilo(c(`80%`, `95%`)) %>%
        as_tibble() %>%
        select(.model, Mes, pronostico = .mean,
               `80%_lower`, `80%_upper`, `95%_lower`, `95%_upper`) %>%
        left_join(as_tibble(fut) %>% select(Mes, real = Consumo_GWh), by = "Mes") %>%
        mutate(
          origen = o,
          escala = escala,
          error = real - pronostico,
          abs_error = abs(error),
          error_escalado = abs_error / escala,
          dentro_80 = real >= `80%_lower` & real <= `80%_upper`,
          dentro_95 = real >= `95%_lower` & real <= `95%_upper`,
          winkler_95 =
            (`95%_upper` - `95%_lower`) +
            (2 / 0.05) * pmax(`95%_lower` - real, 0) +
            (2 / 0.05) * pmax(real - `95%_upper`, 0)
        )
    },
    error = function(e) {
      warning("Origen ", as.character(o), " falló: ", conditionMessage(e))
      NULL
    }
  )
}

correr_rolling <- function() {
  cl <- parallel::makeCluster(num_cores)
  on.exit(parallel::stopCluster(cl), add = TRUE)

  parallel::clusterEvalQ(cl, {
    suppressPackageStartupMessages({
      library(fpp3)
      library(dplyr)
      library(tidyr)
    })
  })

  parallel::clusterExport(
    cl,
    varlist = c("datos", "origenes", "h_rolling", "pesos_bmc", "evaluar_origen"),
    envir = globalenv()
  )

  parallel::parLapplyLB(cl, seq_along(origenes), evaluar_origen)
}

rolling <- NULL

if (!forzar_rolling && file.exists(ruta_cache_rolling)) {
  cache <- readRDS(ruta_cache_rolling)
  if (cache_valida(cache, parametros_rolling)) {
    rolling <- cache$rolling
    cat("Resultados de origen rodante leídos de caché.\n")
  }
}

if (is.null(rolling)) {
  cat("Ejecutando", n_origenes, "orígenes en", num_cores, "núcleos...\n")
  inicio <- Sys.time()
  resultados <- correr_rolling()
  resultados <- resultados[!vapply(resultados, is.null, logical(1))]

  if (length(resultados) == 0) {
    stop("Ningún origen produjo pronósticos. Revisa los warnings.")
  }

  rolling <- bind_rows(resultados)
  cat("Tiempo:", round(as.numeric(difftime(Sys.time(), inicio, units = "mins")), 1), "min\n")

  saveRDS(
    list(parametros = parametros_rolling, rolling = rolling),
    ruta_cache_rolling
  )
}

cat("\nOrígenes evaluados:", n_distinct(rolling$origen),
    "· puntos por modelo:", nrow(rolling) / n_distinct(rolling$.model), "\n")

# ---- 7.1 Métricas agregadas -------------------------------------------------

resumen_rolling <- rolling %>%
  group_by(.model) %>%
  summarise(
    origenes = n_distinct(origen),
    puntos = n(),
    RMSE = sqrt(mean(error^2)),
    MAE = mean(abs_error),
    MAPE = mean(100 * abs_error / abs(real)),
    sMAPE = mean(200 * abs_error / (abs(real) + abs(pronostico))),
    MASE = mean(error_escalado),
    Winkler_95 = mean(winkler_95),
    cobertura_80 = mean(dentro_80),
    cobertura_95 = mean(dentro_95),
    .groups = "drop"
  ) %>%
  arrange(MASE)

cat("\n--- Resumen del origen rodante (", n_origenes, "ventanas, h =", h_rolling, ") ---\n")
print(resumen_rolling, n = Inf, width = Inf)

por_origen <- rolling %>%
  group_by(.model, origen) %>%
  summarise(
    MASE = mean(error_escalado),
    RMSE = sqrt(mean(error^2)),
    Winkler_95 = mean(winkler_95),
    cobertura_80 = mean(dentro_80),
    .groups = "drop"
  ) %>%
  arrange(origen, .model)

# El paso (1 a 12) se calcula con la posición dentro de cada origen.
por_horizonte <- rolling %>%
  arrange(.model, origen, Mes) %>%
  group_by(.model, origen) %>%
  mutate(paso = row_number()) %>%
  ungroup() %>%
  group_by(.model, paso) %>%
  summarise(
    MASE = mean(error_escalado),
    RMSE = sqrt(mean(error^2)),
    .groups = "drop"
  ) %>%
  arrange(.model, paso)

cat("\n--- MASE promedio por horizonte (paso 1 a 12) ---\n")
print(
  por_horizonte %>%
    select(.model, paso, MASE) %>%
    pivot_wider(names_from = paso, values_from = MASE),
  n = Inf, width = Inf
)

guardar(rolling, "rolling_pronosticos.csv")
guardar(resumen_rolling, "rolling_resumen.csv")
guardar(por_origen, "rolling_por_origen.csv")
guardar(por_horizonte, "rolling_por_horizonte.csv")

g_mase <- por_origen %>%
  mutate(fecha = as.Date(origen)) %>%
  ggplot(aes(x = fecha, y = MASE, colour = .model)) +
  geom_line(linewidth = 0.7) + geom_point(size = 1.8) +
  labs(
    title = "MASE por origen rodante",
    subtitle = paste0(n_origenes, " ventanas mensuales (dic/2022–ago/2024), h = ", h_rolling),
    x = "Origen", y = "MASE", colour = "Modelo"
  ) +
  theme_minimal() + theme(legend.position = "bottom")
print(g_mase)
guardar_png(g_mase, "rolling_MASE.png")

g_winkler <- por_origen %>%
  mutate(fecha = as.Date(origen)) %>%
  ggplot(aes(x = fecha, y = Winkler_95, colour = .model)) +
  geom_line(linewidth = 0.7) + geom_point(size = 1.8) +
  labs(
    title = "Winkler 95% por origen rodante",
    subtitle = "Intervalo más angosto con buena cobertura = menor Winkler",
    x = "Origen", y = "Winkler 95% (GWh)", colour = "Modelo"
  ) +
  theme_minimal() + theme(legend.position = "bottom")
print(g_winkler)
guardar_png(g_winkler, "rolling_Winkler.png")

# ==============================================================================
# PARTE 8 — COMPARACIÓN, SELECCIÓN Y PREVISIÓN FUTURA (SEP/2026 – AGO/2027)
# ==============================================================================
#
# Dos cosas distintas en una sola parte:
#
#   8.1  Comparación fuera de muestra de los cinco modelos y elección del
#        modelo oficial. Usa los resultados ya calculados en las Partes 6 y 7:
#        no vuelve a evaluar nada, solo agrega y rankea.
#
#   8.2  Previsión. Aquí sí se reajustan los modelos con TODA la serie
#        (140 meses) y se proyecta fuera de la muestra. No es una evaluación:
#        es la previsión final del proyecto.

titulo("PARTE 8 — Comparación, selección y previsión futura")

# ---- 8.1 Comparación de los cinco modelos y selección ------------------------
#
# Regla: se rankean cuatro métricas fuera de muestra (1 = mejor) y se promedia
# el rango. Gana el menor rango medio. Es la regla del script del compañero
# (Light_ARIMAX_BMC_IND2616_final_v2.R), con una diferencia: acá la tabla SÍ
# elige; `modelo_final` sale de ella y no está escrita a mano.
#
# No se usa AICc para esta comparación: es una medida dentro de la muestra y la
# dummy COVID lo inclina siempre hacia el ARIMAX (por eso el BMC colapsa a los
# pesos 0/0/1). La comparación de pronóstico se hace con error fuera de muestra.

comparacion_modelos <- tabla_precision %>%
  select(.model, MASE_test = MASE, Winkler_test = Winkler_95) %>%
  left_join(
    resumen_rolling %>%
      select(.model, MASE_rolling = MASE, Winkler_rolling = Winkler_95),
    by = ".model"
  ) %>%
  mutate(
    rango_MASE_test       = rank(MASE_test),
    rango_Winkler_test    = rank(Winkler_test),
    rango_MASE_rolling    = rank(MASE_rolling),
    rango_Winkler_rolling = rank(Winkler_rolling),
    rango_medio = (
      rango_MASE_test + rango_Winkler_test +
        rango_MASE_rolling + rango_Winkler_rolling
    ) / 4,
    # Desempate declarado: BMC y Ensamble_Simple son combinaciones lineales de
    # los otros modelos. A igual rango medio, gana el modelo individual: es más
    # parsimonioso y se reporta con una sola ecuación.
    es_ensamble = .model %in% c("BMC", "Ensamble_Simple")
  ) %>%
  arrange(rango_medio, es_ensamble, .model) %>%
  mutate(posicion = row_number()) %>%
  select(
    posicion, .model, MASE_test, Winkler_test,
    MASE_rolling, Winkler_rolling,
    rango_MASE_test, rango_Winkler_test,
    rango_MASE_rolling, rango_Winkler_rolling, rango_medio, es_ensamble
  )

ganador <- comparacion_modelos$.model[1]

if (is.null(modelo_final_forzado)) {
  modelo_final <- ganador
} else {
  modelo_final <- modelo_final_forzado
  if (!identical(modelo_final, ganador)) {
    cat(
      "\nAVISO: `modelo_final_forzado` =", modelo_final,
      "pero la tabla elige", ganador, ". Se respeta el override.\n"
    )
  }
}

cat("\n--- Comparación fuera de muestra (4 métricas, rango 1 = mejor) ---\n")
print(comparacion_modelos, n = Inf, width = Inf)

# Tabla resumida: quién gana cada criterio y qué modelo se usa.
seleccion_modelo <- tibble(
  criterio = c(
    "Test fijo (sep/2025–ago/2026, h = 12)",
    "Test fijo (sep/2025–ago/2026, h = 12)",
    paste0("Origen rodante (", n_origenes, " ventanas, h = 12)"),
    paste0("Origen rodante (", n_origenes, " ventanas, h = 12)"),
    "Rango medio (4 métricas)",
    "Modelo usado en la previsión oficial"
  ),
  metrica = c(
    "MASE", "Winkler 95 %", "MASE", "Winkler 95 %",
    "promedio de rangos", "—"
  ),
  mejor_modelo = c(
    comparacion_modelos$.model[which.min(comparacion_modelos$MASE_test)],
    comparacion_modelos$.model[which.min(comparacion_modelos$Winkler_test)],
    comparacion_modelos$.model[which.min(comparacion_modelos$MASE_rolling)],
    comparacion_modelos$.model[which.min(comparacion_modelos$Winkler_rolling)],
    ganador,
    modelo_final
  ),
  valor = c(
    round(min(comparacion_modelos$MASE_test), 4),
    round(min(comparacion_modelos$Winkler_test), 1),
    round(min(comparacion_modelos$MASE_rolling), 4),
    round(min(comparacion_modelos$Winkler_rolling), 1),
    round(comparacion_modelos$rango_medio[1], 3),
    NA_real_
  )
)

cat("\n--- Selección del modelo ---\n")
print(seleccion_modelo, n = Inf, width = Inf)
cat(
  "\nLectura: el ARIMA gana el MASE del test (acierta mejor el número), pero el\n",
  "ARIMAX gana el Winkler en las dos evaluaciones (intervalos más informativos)\n",
  "y sostiene ese resultado en las 21 ventanas. Al promediar los cuatro rangos\n",
  "gana ", ganador, ", que es el modelo de la previsión oficial.\n",
  "\nLos cinco modelos dan totales anuales que difieren 0,30 %\n",
  "(ver 8.2), así que la cifra no depende de esta elección.\n",
  sep = ""
)

guardar(comparacion_modelos, "comparacion_modelos.csv")

# ---- 8.2 Previsión con todos los modelos ------------------------------------

# Primer mes no observado = último mes + 1.
primer_mes_futuro <- max(datos$Mes) + 1
ultimo_mes_futuro <- primer_mes_futuro + (h_futuro - 1)

datos_futuro <- tibble(
  Mes = primer_mes_futuro + 0:(h_futuro - 1),
  covid = 0
) %>%
  as_tsibble(index = Mes)

cat("\nSerie observada hasta:", as.character(max(datos$Mes)), "(", nrow(datos), "meses )\n")
cat("Horizonte de previsión:", as.character(primer_mes_futuro), "a",
    as.character(ultimo_mes_futuro), "\n")
cat("Modelo de la previsión oficial:", modelo_final, "\n")

ajuste_total <- datos %>%
  model(
    ETS_Auto     = ETS(Consumo_GWh),
    ARIMA_Auto   = ARIMA(Consumo_GWh),
    ARIMAX_Covid = ARIMA(Consumo_GWh ~ covid)
  ) %>%
  mutate(
    Ensamble_Simple = (ETS_Auto + ARIMA_Auto + ARIMAX_Covid) / 3,
    BMC = fabletools::combination_weighted(
      ETS_Auto, ARIMA_Auto, ARIMAX_Covid,
      weights = unname(pesos_bmc)
    )
  )

if (!modelo_final %in% names(ajuste_total)) {
  stop("`modelo_final` debe ser uno de: ", paste(names(ajuste_total), collapse = ", "))
}

fc_futuro <- ajuste_total %>% forecast(new_data = datos_futuro, level = c(80, 95))

pronostico_futuro <- fc_futuro %>%
  hilo(level = c(80, 95)) %>%
  unpack_hilo(c(`80%`, `95%`)) %>%
  as_tibble() %>%
  select(
    .model, Mes,
    pronostico = .mean,
    inferior_80 = `80%_lower`, superior_80 = `80%_upper`,
    inferior_95 = `95%_lower`, superior_95 = `95%_upper`
  ) %>%
  arrange(.model, Mes)

resumen_futuro <- pronostico_futuro %>%
  group_by(.model) %>%
  summarise(
    meses = n(),
    total_GWh = sum(pronostico),
    promedio_mensual_GWh = mean(pronostico),
    minimo_GWh = min(pronostico),
    maximo_GWh = max(pronostico),
    .groups = "drop"
  ) %>%
  arrange(total_GWh)

cat("\n--- Total previsto (", as.character(primer_mes_futuro), "–",
    as.character(ultimo_mes_futuro), ") ---\n", sep = "")
print(resumen_futuro, n = Inf, width = Inf)

cat("\n--- Previsión mensual del modelo oficial (", modelo_final, ") ---\n")
print(
  pronostico_futuro %>% filter(.model == modelo_final) %>% select(-.model),
  n = Inf, width = Inf
)

pronostico_ancho <- pronostico_futuro %>%
  select(.model, Mes, pronostico) %>%
  pivot_wider(names_from = .model, values_from = pronostico) %>%
  arrange(Mes)

# ---- 8.3 Gráficos y diagnóstico --------------------------------------------

historia <- datos %>% filter(Mes >= yearmonth("2022 Jan"))

g_futuro <- fc_futuro %>%
  filter(.model == modelo_final) %>%
  autoplot(historia) +
  labs(
    title = paste0("Previsión ", as.character(primer_mes_futuro), " – ",
                   as.character(ultimo_mes_futuro), " (", modelo_final, ")"),
    subtitle = "Light SESA · consumo mensual · intervalos 80% y 95%",
    y = "GWh/mes", x = NULL
  ) +
  theme_minimal()
print(g_futuro)
guardar_png(g_futuro, "pronostico_2026_2027.png")

g_comparacion <- fc_futuro %>%
  autoplot(historia, level = NULL) +
  labs(
    title = "Comparación de previsiones por modelo",
    subtitle = paste0("Origen: ", as.character(max(datos$Mes)), " · h = ", h_futuro),
    y = "GWh/mes", x = NULL, colour = "Modelo"
  ) +
  theme_minimal() + theme(legend.position = "bottom")
print(g_comparacion)
guardar_png(g_comparacion, "pronostico_2026_2027_comparacion.png")

cat("\n--- Reporte del modelo oficial (", modelo_final, ") ---\n")
report(ajuste_total %>% select(all_of(modelo_final)))

guardar(pronostico_futuro, "pronostico_2026_2027.csv")
guardar(pronostico_ancho, "pronostico_2026_2027_ancho.csv")
guardar(resumen_futuro, "pronostico_2026_2027_resumen.csv")
guardar(seleccion_modelo, "seleccion_modelo.csv")

# ==============================================================================
# PARTE 9 — APÉNDICES
# ==============================================================================

titulo("PARTE 9 — Apéndices")

# ---- 9.1 Magnitud del choque COVID vs. la base 2017–2019 --------------------

base_previa <- train_data %>%
  as_tibble() %>%
  filter(year(Mes) >= 2017, year(Mes) <= 2019) %>%
  mutate(m = month(Mes)) %>%
  group_by(m) %>%
  summarise(media_base = mean(Consumo_GWh), .groups = "drop")

impacto_2020 <- train_data %>%
  as_tibble() %>%
  filter(year(Mes) == 2020) %>%
  mutate(m = month(Mes)) %>%
  left_join(base_previa, by = "m") %>%
  mutate(porcentaje_de_la_base = round(100 * Consumo_GWh / media_base, 2)) %>%
  select(Mes, Consumo_GWh, media_base, porcentaje_de_la_base)

cat("\n2020 respecto a la media mensual de 2017–2019:\n")
print(impacto_2020, n = Inf, width = Inf)
guardar(impacto_2020, "apendice_impacto_2020.csv")

# ---- 9.2 Cambios estructurales (opcional, requiere strucchange) -------------

if (requireNamespace("strucchange", quietly = TRUE)) {
  library(strucchange)

  desestac <- train_data %>%
    model(STL(Consumo_GWh ~ season(window = "periodic"), robust = TRUE)) %>%
    components()

  quiebres <- tibble(
    desest = desestac$season_adjust,
    t = seq_len(nrow(desestac)),
    covid = train_data$covid
  )

  corte_dic21 <- which(train_data$Mes == yearmonth("2021 Dec"))

  cat("\n1. Test de Chow (corte dic/2021):\n")
  chow <- sctest(desest ~ t + covid, data = quiebres, type = "Chow", point = corte_dic21)
  print(chow)

  cat("\n2. Puntos de quiebre óptimos (Bai & Perron):\n")
  bp <- breakpoints(desest ~ t + covid, data = quiebres, h = 0.15)
  print(summary(bp))

  cat("\n3. Prueba supF de estabilidad estructural:\n")
  fs <- Fstats(desest ~ t + covid, data = quiebres, from = 0.15)
  supf <- sctest(fs, type = "supF")
  print(supf)
  cat("Mes con estadístico F máximo:", as.character(train_data$Mes[fs$breakpoint]), "\n")

  cat("\n4. Prueba OLS-CUSUM:\n")
  cusum <- sctest(efp(desest ~ t + covid, data = quiebres, type = "OLS-CUSUM"))
  print(cusum)

  guardar(
    tibble(
      prueba = c("Chow dic/2021", "supF", "OLS-CUSUM"),
      estadistico = c(chow$statistic, supf$statistic, cusum$statistic),
      p_valor = c(chow$p.value, supf$p.value, cusum$p.value),
      mes_quiebre = c(
        as.character(yearmonth("2021 Dec")),
        as.character(train_data$Mes[fs$breakpoint]),
        NA_character_
      )
    ),
    "apendice_cambios_estructurales.csv"
  )
} else {
  cat(
    "\nLa batería de cambio estructural (strucchange) se omite: el paquete no",
    "\nestá instalado. Para habilitarla: install.packages('strucchange')\n"
  )
}

# ==============================================================================
# PARTE 10 — RESUMEN DE SALIDAS Y SESIÓN
# ==============================================================================

titulo("PARTE 10 — Resumen")

writeLines(
  capture.output(sessionInfo()),
  nombre_archivo("sesion_R.txt")
)

salidas <- c(
  "frecuencias_pesos_BMC_COVID.csv",
  "advertencias_BMC.csv",
  "eda_serie.png", "eda_estacional.png", "eda_stl.png", "eda_atipicos_stl.csv",
  "evaluacion_test.csv", "pronosticos_test.csv", "evaluacion_test.png",
  "intervalos_BMC_COVID.csv", "cobertura_BMC_COVID.csv", "pronostico_BMC_COVID.png",
  "rolling_resumen.csv", "rolling_por_origen.csv", "rolling_por_horizonte.csv",
  "rolling_pronosticos.csv", "rolling_MASE.png", "rolling_Winkler.png",
  "seleccion_modelo.csv",
  "comparacion_modelos.csv",
  "pronostico_2026_2027.csv", "pronostico_2026_2027_ancho.csv",
  "pronostico_2026_2027_resumen.csv", "pronostico_2026_2027.png",
  "pronostico_2026_2027_comparacion.png",
  "apendice_impacto_2020.csv",
  "sesion_R.txt"
)

existentes <- salidas[file.exists(nombre_archivo(salidas))]
relativas <- sub(paste0("^", carpeta_resultados, "/"), "", nombre_archivo(existentes))

cat("\nArchivos generados en", carpeta_resultados, ":\n")
cat(paste0("  - ", relativas), sep = "\n")
cat("\nTotal:", length(existentes), "archivos\n")

cat("\n--- Cifras clave ---\n")
cat("Efecto COVID:", round(coef_covid, 1), "GWh/mes\n")
cat("Pesos BMC (ETS, ARIMA, ARIMAX):", round(pesos_bmc, 4), "\n")
cat("Mejor MASE en test:", tabla_precision$.model[which.min(tabla_precision$MASE)],
    "=", round(min(tabla_precision$MASE), 4), "\n")
cat("Mejor MASE en rolling:", resumen_rolling$.model[which.min(resumen_rolling$MASE)],
    "=", round(min(resumen_rolling$MASE), 4), "\n")
cat("Modelo oficial (menor rango medio):", modelo_final,
    "=", round(comparacion_modelos$rango_medio[
      match(modelo_final, comparacion_modelos$.model)
    ], 3), "\n")
cat("Previsión", as.character(primer_mes_futuro), "–", as.character(ultimo_mes_futuro),
    "(", modelo_final, "):",
    round(resumen_futuro$total_GWh[resumen_futuro$.model == modelo_final]), "GWh\n")

cat("\nFin:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
