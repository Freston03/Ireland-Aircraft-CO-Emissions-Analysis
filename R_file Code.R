  
  # ---- Load Required Libraries ----
  library(tidyverse)
  library(readr)
  library(dplyr)
  library(ggplot2)
  library(ggrepel)
  library(plotly)
  library(DT)
  
  # ---- Set Path ----
  path <- "C:/Users/Asus/Downloads/project/project"
  
  # ---- Read and Combine All CSV Files ----
  files <- list.files(path, pattern = "^states_2022-06-27-.*\\.csv$", full.names = TRUE)
  
  set.seed(42)
  options(dplyr.summarise.inform = FALSE)
  
  df_ireland <- map_dfr(files, function(f) {
    df <- tryCatch(read_csv(f, show_col_types = FALSE), error = function(e) return(NULL))
    if (is.null(df)) return(NULL)
    
    names(df) <- tolower(names(df))
    if ("lon" %in% names(df)) df <- df %>% rename(longitude = lon)
    if ("lat" %in% names(df)) df <- df %>% rename(latitude = lat)
    
    if (!all(c("longitude", "latitude", "icao24", "time") %in% names(df))) return(NULL)
    
    df %>%
      filter(longitude >= -11, longitude <= -5,
             latitude >= 51, latitude <= 56)
  })
  
  # ---- Convert Time and Read Metadata ----
  df_ireland$time <- as.POSIXct(df_ireland$time, origin = "1970-01-01", tz = "UTC")
  meta <- read_csv(file.path(path, "aircraftDatabase.csv"), show_col_types = FALSE)
  
  # ---- Join Metadata and Add Flight Phase ----
  df_ireland_Icao <- df_ireland %>%
    left_join(meta, by = "icao24") %>%
    mutate(
      phase = case_when(
        onground == TRUE ~ "ground",
        baroaltitude < 1000 ~ "climb",
        baroaltitude >= 1000 & baroaltitude < 6000 ~ "descent",
        baroaltitude >= 6000 ~ "cruise",
        TRUE ~ "unknown"
      )
    )
  
  # ---- Define Fuel Flow Table ----
  fuel_flow_table <- tribble(
    ~typecode, ~phase, ~fuel_flow,
    "A320", "ground", 0.4,
    "A320", "climb", 2.6,
    "A320", "cruise", 2.0,
    "A320", "descent", 0.8,
    "B738", "ground", 0.45,
    "B738", "climb", 2.8,
    "B738", "cruise", 2.1,
    "B738", "descent", 0.9,
    "A333", "ground", 1.0,
    "A333", "climb", 6.0,
    "A333", "cruise", 4.5,
    "A333", "descent", 2.0
  )
  
  # ---- Calculate CO2 Emissions ----
  CO2_factor <- 3.16
  df_ireland_Icao <- df_ireland_Icao %>%
    left_join(fuel_flow_table, by = c("typecode", "phase")) %>%
    mutate(emissions_kgCO2 = ifelse(is.na(fuel_flow), 0, fuel_flow * 10 * CO2_factor))
  
  # ---- Descriptive Statistics ----
  summary_stats <- df_ireland_Icao %>%
    summarise(
      total_points = n(),
      total_planes = n_distinct(icao24),
      total_emission_kg = sum(emissions_kgCO2, na.rm = TRUE),
      avg_emission_per_plane = mean(emissions_kgCO2, na.rm = TRUE)
    )
  
  print("Summary Statistics:")
  print(summary_stats)
  
  top_types <- df_ireland_Icao %>%
    group_by(typecode) %>%
    summarise(total_emission = sum(emissions_kgCO2, na.rm = TRUE)) %>%
    arrange(desc(total_emission)) %>%
    head(5)
  
  print("Top 3 Aircraft by CO2 Emission:")
  print(top_types)
  
  # ---- Visualization: Number of Planes by Type ----
  p1 <- df_ireland_Icao %>%
    group_by(typecode) %>%
    summarise(
      points = n(),
      emissions = sum(emissions_kgCO2, na.rm = TRUE)
    ) %>%
    filter(emissions > 0) %>%                     # Remove planes with no emissions
    arrange(desc(emissions)) %>%
    slice_head(n = 15) %>%                        # Show only top 15 emitters
    ggplot(aes(x = reorder(typecode, emissions), y = emissions, fill = typecode)) +
    geom_bar(stat = "identity", alpha = 0.9, show.legend = FALSE) +
    scale_fill_brewer(palette = "Set3") +
    coord_flip() +                                # Flip for readability
    theme_minimal(base_size = 13) +
    labs(
      title = "Top 3 Aircraft Types by CO₂ Emissions",
      subtitle = "Filtered to show only aircraft with recorded emissions",
      x = "Aircraft Type",
      y = "Total CO₂ Emissions (kg)"
    ) +
    theme(
      plot.title = element_text(face = "bold", size = 16, color = "#333333"),
      plot.subtitle = element_text(size = 12, color = "#555555"),
      axis.text.x = element_text(color = "#333333"),
      axis.text.y = element_text(color = "#333333"),
      panel.grid.major.y = element_blank(),
      panel.grid.minor = element_blank(),
      plot.background = element_rect(fill = "#fafafa", color = NA)
    )
  
  # Interactive version
  ggplotly(p1, tooltip = c("x", "y"))
  
  # ---- Emission Distribution ----
  p2 <- ggplot(df_ireland_Icao, aes(x = emissions_kgCO2)) +
    geom_histogram(bins = 40, fill = "steelblue", color = "white") +
    theme_minimal() +
    labs(title = "Distribution of CO2 Emissions", x = "Emissions (kgCO2)", y = "Frequency")
  
  ggplotly(p2)
  
  # ---- Emission by Flight Phase ----
  p3 <- ggplot(df_ireland_Icao, aes(x = phase, y = emissions_kgCO2, fill = phase)) +
    geom_boxplot(outlier.color = "#e41a1c", outlier.shape = 21, outlier.size = 2, alpha = 0.8) +
    scale_fill_brewer(palette = "Set2") +
    labs(
      title = "CO₂ Emissions by Flight Phase",
      subtitle = "Distribution of emissions across different flight stages",
      x = "Flight Phase",
      y = "Emissions (kgCO2)"
    ) +
    theme_minimal(base_size = 13) +
    theme(
      plot.title = element_text(face = "bold", size = 16, color = "#333333"),
      plot.subtitle = element_text(size = 12, color = "#555555"),
      axis.text.x = element_text(angle = 25, hjust = 1, color = "#222222"),
      axis.text.y = element_text(color = "#222222"),
      legend.position = "none",
      panel.grid.major.x = element_blank(),
      panel.grid.minor = element_blank(),
      plot.background = element_rect(fill = "#fafafa", color = NA),
      panel.background = element_rect(fill = "#fafafa", color = NA)
    )
  
  # Convert to interactive Plotly chart
  ggplotly(p3, tooltip = c("x", "y"))
  
  # ---- Interactive Data Table ----
  datatable(df_ireland_Icao %>% select(icao24, typecode, phase, emissions_kgCO2) %>% head(100),
            options = list(pageLength = 10), caption = 'Sample of Ireland CO2 Emission Data')
  
  # ---- Emission Projection (2022–2050) ----
  years <- 0:28
  r_traffic <- 0.027
  r_tech_var <- 0.005 + 0.001 * years
  r_tech_atm_var <- 0.003 + 0.0005 * years
  
  sim_trajectory <- function(E0) {
    E_baseline <- E0 * (1 + r_traffic)^years
    E_tech <- E0 * cumprod(1 + r_traffic - r_tech_var)
    E_atm  <- E0 * cumprod(1 + r_traffic - r_tech_atm_var)
    data.frame(year = 2022 + years, Baseline = E_baseline, Tech = E_tech, ATM = E_atm)
  }
  
  n_boot <- 200
  icao_list <- unique(df_ireland_Icao$icao24)
  
  all_boot_trajectories <- replicate(n_boot, {
    sampled_icao <- sample(icao_list, length(icao_list), replace = TRUE)
    E0_boot <- sum(df_ireland_Icao %>% filter(icao24 %in% sampled_icao) %>% pull(emissions_kgCO2), na.rm = TRUE)
    sim_trajectory(E0_boot)
  }, simplify = FALSE)
  
  traj_array <- simplify2array(lapply(all_boot_trajectories, function(df) as.matrix(df[, -1])))
  
  ci_lower <- function(x) quantile(x, 0.025)
  ci_upper <- function(x) quantile(x, 0.975)
  
  df_ci <- data.frame(
    year = 2022 + years,
    Baseline_mean = apply(traj_array[,1,], 1, mean),
    Baseline_lower = apply(traj_array[,1,], 1, ci_lower),
    Baseline_upper = apply(traj_array[,1,], 1, ci_upper),
    Tech_mean = apply(traj_array[,2,], 1, mean),
    Tech_lower = apply(traj_array[,2,], 1, ci_lower),
    Tech_upper = apply(traj_array[,2,], 1, ci_upper),
    ATM_mean = apply(traj_array[,3,], 1, mean),
    ATM_lower = apply(traj_array[,3,], 1, ci_lower),
    ATM_upper = apply(traj_array[,3,], 1, ci_upper)
  )
  
  df_ci_long <- df_ci %>%
    pivot_longer(cols = -year, names_to = c("Scenario", ".value"), names_pattern = "(.*)_(.*)") %>%
    bind_rows(data.frame(
      year = 2022:2050,
      Scenario = "NetZero2050",
      mean = df_ci$Baseline_mean[1],
      lower = df_ci$Baseline_mean[1],
      upper = df_ci$Baseline_mean[1]
    ))
  
  # ---- Interactive Projection Plot ----
  p4 <- ggplot(df_ci_long, aes(x = year, y = mean, color = Scenario, fill = Scenario)) +
    geom_line(size = 1.2) +
    geom_ribbon(aes(ymin = lower, ymax = upper), alpha = 0.2, color = NA) +
    labs(
      title = "Projected CO2 Emissions until 2050",
      subtitle = "Mean of Bootstrapped 95% Confidence Intervals",
      x = "Year", y = "CO2 Emissions (kg/day)"
    ) +
    theme_minimal()
  
  ggplotly(p4)
  
  # ---- Save Outputs ----
  write_csv(df_ireland_Icao, file.path(path, "ireland_emissions.csv"))
  ggsave(file.path(path, "CO2_projection.png"), plot = p4, width = 10, height = 6)
