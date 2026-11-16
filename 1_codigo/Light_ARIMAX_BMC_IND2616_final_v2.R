# =====================================================================
# Demanda de energía de Light SESA – ARIMAX (Pilar 1) + BMC (Pilar 2)
# IND2616 – Análise de Séries Temporais – PUC-Rio
# Versión adaptada para ejecución directa desde 'serie_mensual_light_gwh.csv'
# Paquetes requeridos: fpp3, readr, urca, strucchange
# =====================================================================

# ---- Parte 0 – Librerías necesarias ----
# Si no las tienes instaladas, ejecuta previamente:
# install.packages(c("fpp3", "readr", "urca", "strucchange"))
library(fpp3)
library(readr)

# ---- Parte 1 – Carga y preparación del tsibble desde el CSV optimizado ----
ruta_csv <- "C:/Users/yennz/Downloads/Proyecto_Series_Temporales/Light_SESA_IND2616/1_codigo/serie_mensual_light_gwh.csv"
raw_csv <- read_csv(ruta_csv, show_col_types = FALSE)

# Convertir la columna de fecha a yearmonth de fpp3 y definir el tsibble
datos_light <- raw_csv %>%
  mutate(Mes = yearmonth(Mes)) %>%
  select(Mes, Consumo_GWh) %>%
  as_tsibble(index = Mes)

# Verificación de estructura e integridad temporal
print(datos_light)
cat("¿Existen vacíos (gaps) en la serie?:", has_gaps(datos_light)$.gaps, "\n")
cat("Total de observaciones mensuales:", nrow(datos_light), "\n")

# ---- Parte 2 – Variable de intervención COVID y partición Train / Test ----
# Intervención tipo pulso: abril a junio de 2020 (meses de confinamiento severo)
datos_light <- datos_light %>%
  mutate(covid_pulse = if_else(Mes >= yearmonth("2020 Apr") & Mes <= yearmonth("2020 Jun"), 1, 0))

# Partición temporal:
# Entrenamiento: Ene/2015 a Ago/2025 (128 meses)
# Prueba fuera de muestra: Sep/2025 a Ago/2026 (12 meses, h = 12)
train_data <- datos_light %>% filter(Mes <= yearmonth("2025 Aug"))
test_data  <- datos_light %>% filter(Mes > yearmonth("2025 Aug"))
cat("Dimensiones: Train =", nrow(train_data), "meses | Test =", nrow(test_data), "meses\n")

# ---- Parte 3 – Análisis Exploratorio de Datos (EDA) en Train ----
autoplot(train_data, Consumo_GWh) + 
  labs(title = "Demanda de Energía Eléctrica - Light SESA", y = "GWh/mes", x = NULL)

train_data %>% gg_season(Consumo_GWh) + 
  labs(title = "Patrón Estacional por Año", y = "GWh/mes")

fit_stl <- train_data %>% model(STL(Consumo_GWh, robust = TRUE))
components(fit_stl) %>% autoplot()

train_data %>% features(Consumo_GWh, feat_stl)

componentes <- components(fit_stl)
limite_inf <- quantile(componentes$remainder, 0.25, na.rm = TRUE) - 3 * IQR(componentes$remainder, na.rm = TRUE)
limite_sup <- quantile(componentes$remainder, 0.75, na.rm = TRUE) + 3 * IQR(componentes$remainder, na.rm = TRUE)
componentes %>% filter(remainder < limite_inf | remainder > limite_sup) %>% select(Mes, Consumo_GWh, remainder)

train_data %>% features(Consumo_GWh, guerrero)

por_ano <- train_data %>%
  as_tibble() %>%
  mutate(Ano = year(Mes)) %>%
  group_by(Ano) %>%
  summarise(meses = n(), media = mean(Consumo_GWh), desvio = sd(Consumo_GWh)) %>%
  filter(meses == 12)
print(por_ano)
summary(lm(log(desvio) ~ log(media), data = por_ano))

train_data %>% features(Consumo_GWh, list(unitroot_kpss, unitroot_ndiffs, unitroot_nsdiffs))
train_data %>% gg_tsdisplay(difference(Consumo_GWh, 12), plot_type = "partial", lag_max = 36)

# ---- Parte 4 – Pilar 1: ETS, ARIMA y ARIMAX con el pulso COVID ----
fit_modelos <- train_data %>%
  model(
    ETS_Auto   = ETS(Consumo_GWh),
    ARIMA_Auto = ARIMA(Consumo_GWh),
    ARIMAX_Covid = ARIMA(Consumo_GWh ~ covid_pulse)
  )
print(fit_modelos)

fit_modelos %>% select(ETS_Auto) %>% report()
fit_modelos %>% select(ARIMA_Auto) %>% report()
fit_modelos %>% select(ARIMAX_Covid) %>% report()

tidy(fit_modelos) %>% filter(term == "covid_pulse") %>% mutate(t = estimate / std.error)
glance(fit_modelos) %>% select(.model, AICc)

fit_modelos %>% select(ARIMAX_Covid) %>% gg_tsresiduals()
fit_modelos %>% select(ETS_Auto) %>% augment() %>% features(.innov, ljung_box, lag = 24)
fit_modelos %>% select(ARIMA_Auto) %>% augment() %>% features(.innov, ljung_box, lag = 24, dof = 3)
fit_modelos %>% select(ARIMAX_Covid) %>% augment() %>% features(.innov, ljung_box, lag = 24, dof = 1)
fit_modelos %>% augment() %>% filter(Mes >= yearmonth("2016 Jan")) %>% as_tibble() %>% group_by(.model) %>% summarise(shapiro_p = shapiro.test(.innov)$p.value)

# ---- Parte 5 – Pilar 2: Bootstrap Model Combination (BMC) ----
B <- 100
beta_covid <- tidy(fit_modelos) %>% filter(.model == "ARIMAX_Covid", term == "covid_pulse") %>% pull(estimate)
train_ajustada <- train_data %>% mutate(y_ajustada = Consumo_GWh - beta_covid * covid_pulse)

set.seed(2616)
replicas <- train_ajustada %>%
  model(STL(y_ajustada)) %>%
  generate(new_data = train_ajustada, times = B, bootstrap_block_size = 24)

replicas <- replicas %>% as_tibble() %>% select(-.model) %>% as_tsibble(index = Mes, key = .rep)
replicas <- replicas %>% mutate(y_replica = .sim + beta_covid * covid_pulse)

replicas %>% filter(.rep %in% c("1", "2", "3")) %>% autoplot(y_replica) + 
  autolayer(train_data, Consumo_GWh, colour = "black") + 
  labs(y = "GWh/mes", x = NULL)

ganador <- character(B)
for (r in 1:B) {
  una <- replicas %>% filter(.rep == as.character(r))
  ent <- una %>% filter(Mes <= yearmonth("2024 Aug"))
  val <- una %>% filter(Mes > yearmonth("2024 Aug"))
  ajuste <- ent %>% model(
    ETS_Auto = ETS(y_replica), 
    ARIMA_Auto = ARIMA(y_replica), 
    ARIMAX_Covid = ARIMA(y_replica ~ covid_pulse)
  )
  pron <- ajuste %>% forecast(new_data = val)
  errores <- accuracy(pron, una)
  ganador[r] <- errores$.model[which.min(errores$MAE)]
}
print(table(ganador))

pesos <- c(mean(ganador == "ETS_Auto"), mean(ganador == "ARIMA_Auto"), mean(ganador == "ARIMAX_Covid"))

fit_modelos <- fit_modelos %>%
  mutate(
    Ensamble_Simple = (ETS_Auto + ARIMA_Auto + ARIMAX_Covid) / 3,
    BMC = combination_weighted(ETS_Auto, ARIMA_Auto, ARIMAX_Covid, weights = pesos)
  )

# ---- Parte 6 – Evaluación en la prueba (sep/2025–ago/2026): puntual e intervalos ----
fc_modelos <- fit_modelos %>% forecast(new_data = test_data)

accuracy(fc_modelos, datos_light) %>% select(.model, RMSE, MAE, MAPE, MASE) %>% arrange(MASE)

comparacion <- fc_modelos %>%
  as_tibble() %>%
  select(.model, Mes, pronostico = .mean) %>%
  left_join(as_tibble(test_data) %>% select(Mes, real = Consumo_GWh), by = "Mes")

comparacion %>% group_by(.model) %>% summarise(sMAPE = mean(200 * abs(real - pronostico) / (abs(real) + abs(pronostico))))

accuracy(fc_modelos, datos_light, measures = list(winkler = winkler_score), level = 95) %>% arrange(winkler)

intervalos <- fc_modelos %>%
  hilo(level = c(80, 95)) %>%
  unpack_hilo(c(`80%`, `95%`)) %>%
  as_tibble() %>%
  left_join(as_tibble(test_data) %>% select(Mes, real = Consumo_GWh), by = "Mes")

intervalos %>% group_by(.model) %>% summarise(
  cobertura_80 = mean(real >= `80%_lower` & real <= `80%_upper`), 
  cobertura_95 = mean(real >= `95%_lower` & real <= `95%_upper`)
)

fc_modelos %>% filter(.model %in% c("ARIMA_Auto", "ARIMAX_Covid", "BMC")) %>% 
  autoplot(datos_light %>% filter(Mes >= yearmonth("2023 Jan")), level = NULL) + 
  labs(y = "GWh/mes", x = NULL)

fc_modelos %>% filter(.model == "BMC") %>% 
  autoplot(datos_light %>% filter(Mes >= yearmonth("2023 Jan"))) + 
  labs(y = "GWh/mes", x = NULL)

# ---- Parte 7 – Robustez: rolling-origin con el BMC y los intervalos ----
datos_bmc <- datos_light %>% filter(Mes <= yearmonth("2022 Dec"))
beta_bmc <- datos_bmc %>% model(ARIMA(Consumo_GWh ~ covid_pulse)) %>% tidy() %>% filter(term == "covid_pulse") %>% pull(estimate)
ajustada_bmc <- datos_bmc %>% mutate(y_ajustada = Consumo_GWh - beta_bmc * covid_pulse)

set.seed(2616)
replicas_bmc <- ajustada_bmc %>%
  model(STL(y_ajustada)) %>%
  generate(new_data = ajustada_bmc, times = B, bootstrap_block_size = 24)

replicas_bmc <- replicas_bmc %>% as_tibble() %>% select(-.model) %>% as_tsibble(index = Mes, key = .rep)
replicas_bmc <- replicas_bmc %>% mutate(y_replica = .sim + beta_bmc * covid_pulse)

ganador_bmc <- character(B)
for (r in 1:B) {
  una <- replicas_bmc %>% filter(.rep == as.character(r))
  ent <- una %>% filter(Mes <= yearmonth("2021 Dec"))
  val <- una %>% filter(Mes > yearmonth("2021 Dec"))
  ajuste <- ent %>% model(
    ETS_Auto = ETS(y_replica), 
    ARIMA_Auto = ARIMA(y_replica), 
    ARIMAX_Covid = ARIMA(y_replica ~ covid_pulse)
  )
  pron <- ajuste %>% forecast(new_data = val)
  errores <- accuracy(pron, una)
  ganador_bmc[r] <- errores$.model[which.min(errores$MAE)]
}
pesos_rolling <- c(mean(ganador_bmc == "ETS_Auto"), mean(ganador_bmc == "ARIMA_Auto"), mean(ganador_bmc == "ARIMAX_Covid"))

origenes <- yearmonth("2022 Dec") + 0:20
resultados <- list()
for (i in seq_along(origenes)) {
  o <- origenes[i]
  ent <- datos_light %>% filter(Mes <= o)
  fut <- datos_light %>% filter(Mes > o, Mes <= o + 12)
  escala <- mean(abs(diff(ent$Consumo_GWh, lag = 12)))
  ajuste <- ent %>%
    model(
      ETS_Auto = ETS(Consumo_GWh), 
      ARIMA_Auto = ARIMA(Consumo_GWh), 
      ARIMAX_Covid = ARIMA(Consumo_GWh ~ covid_pulse)
    ) %>%
    mutate(
      Ensamble_Simple = (ETS_Auto + ARIMA_Auto + ARIMAX_Covid) / 3,
      BMC = combination_weighted(ETS_Auto, ARIMA_Auto, ARIMAX_Covid, weights = pesos_rolling)
    )
  pron <- ajuste %>%
    forecast(new_data = fut) %>%
    hilo(level = c(80, 95)) %>%
    unpack_hilo(c(`80%`, `95%`)) %>%
    as_tibble() %>%
    select(.model, Mes, pronostico = .mean, `80%_lower`, `80%_upper`, `95%_lower`, `95%_upper`) %>%
    left_join(as_tibble(fut) %>% select(Mes, real = Consumo_GWh), by = "Mes")
  pron$error_escalado <- abs(pron$real - pron$pronostico) / escala
  pron$origen <- o
  resultados[[i]] <- pron
}
rolling <- bind_rows(resultados)
rolling <- rolling %>%
  mutate(
    dentro_80 = real >= `80%_lower` & real <= `80%_upper`,
    dentro_95 = real >= `95%_lower` & real <= `95%_upper`,
    winkler_95 = (`95%_upper` - `95%_lower`) + (2 / 0.05) * pmax(`95%_lower` - real, 0) + (2 / 0.05) * pmax(real - `95%_upper`, 0)
  )

rolling %>% group_by(.model) %>% 
  summarise(MASE = mean(error_escalado), Winkler_95 = mean(winkler_95), cobertura_80 = mean(dentro_80), cobertura_95 = mean(dentro_95)) %>% 
  arrange(MASE)

por_origen <- rolling %>% group_by(.model, origen) %>% summarise(MASE = mean(error_escalado), Winkler_95 = mean(winkler_95), .groups = "drop")
por_origen %>% ggplot(aes(x = origen, y = MASE, colour = .model)) + geom_line() + labs(x = "Origen")
por_origen %>% ggplot(aes(x = origen, y = Winkler_95, colour = .model)) + geom_line() + labs(x = "Origen", y = "Winkler 95 %")

# ---- Parte 8 – Elección del modelo y pronóstico sep/2026–ago/2027 ----
resumen_prueba <- accuracy(fc_modelos, datos_light, measures = list(MASE = MASE, Winkler = winkler_score), level = 95)
resumen_rolling <- rolling %>% group_by(.model) %>% summarise(MASE_rolling = mean(error_escalado), Winkler_rolling = mean(winkler_95))

seleccion <- resumen_prueba %>%
  select(.model, MASE_prueba = MASE, Winkler_prueba = Winkler) %>%
  left_join(resumen_rolling, by = ".model") %>%
  mutate(rango_medio = (rank(MASE_prueba) + rank(Winkler_prueba) + rank(MASE_rolling) + rank(Winkler_rolling)) / 4) %>%
  arrange(rango_medio)
print(seleccion)

futuro <- new_data(datos_light, 12) %>% mutate(covid_pulse = 0)
modelo_final <- datos_light %>% model(ARIMAX_Covid = ARIMA(Consumo_GWh ~ covid_pulse))
modelo_final %>% report()
modelo_final %>% augment() %>% features(.innov, ljung_box, lag = 24, dof = 3)
modelo_final %>% augment() %>% filter(Mes >= yearmonth("2016 Jan")) %>% as_tibble() %>% summarise(shapiro_p = shapiro.test(.innov)$p.value)

pronostico_final <- modelo_final %>% forecast(new_data = futuro)
pronostico_final %>%
  hilo(level = c(80, 95)) %>%
  unpack_hilo(c(`80%`, `95%`)) %>%
  as_tibble() %>%
  select(Mes, pronostico = .mean, `80%_lower`, `80%_upper`, `95%_lower`, `95%_upper`)

pronostico_final %>% autoplot(datos_light %>% filter(Mes >= yearmonth("2023 Jan"))) + labs(y = "GWh/mes", x = NULL)

set.seed(2616)
trayectorias <- modelo_final %>% generate(new_data = futuro, times = 5000)
totales <- trayectorias %>% as_tibble() %>% group_by(.rep) %>% summarise(total = sum(.sim))
c(media = mean(totales$total), quantile(totales$total, c(0.025, 0.1, 0.9, 0.975)))
sum(test_data$Consumo_GWh)

# ---- Apéndice A.1 – Forma del choque COVID ----
base <- train_data %>%
  as_tibble() %>%
  filter(year(Mes) >= 2017, year(Mes) <= 2019) %>%
  mutate(mes = month(Mes)) %>%
  group_by(mes) %>%
  summarise(media_base = mean(Consumo_GWh))

train_data %>%
  as_tibble() %>%
  filter(year(Mes) == 2020) %>%
  mutate(mes = month(Mes)) %>%
  left_join(base, by = "mes") %>%
  mutate(porcentaje = 100 * Consumo_GWh / media_base)

# ---- Apéndice A.3 – Pruebas de cambio estructural ----
library(strucchange)
desestac <- train_data %>%
  model(STL(Consumo_GWh ~ season(window = "periodic"), robust = TRUE)) %>%
  components()

quiebres <- tibble(desest = desestac$season_adjust, t = 1:nrow(desestac), covid = train_data$covid_pulse)
corte <- which(train_data$Mes == yearmonth("2021 Dec"))

sctest(desest ~ t + covid, data = quiebres, type = "Chow", point = corte)
bp <- breakpoints(desest ~ t + covid, data = quiebres, h = 0.15)
summary(bp)$RSS
fs <- Fstats(desest ~ t + covid, data = quiebres, from = 0.15)
sctest(fs, type = "supF")
train_data$Mes[fs$breakpoint]
sctest(efp(desest ~ t + covid, data = quiebres, type = "OLS-CUSUM"))