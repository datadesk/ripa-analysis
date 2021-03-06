library(here)
source(here::here("lib", "opp.R"))

ELIGIBLE_STATES <- tribble(
  ~state, ~city,
  # test
  "CO", "Statewide",
  "WA", "Statewide",
  # control
  "AZ", "Statewide",
  "CA", "Statewide",
  "FL", "Statewide",
  "MA", "Statewide",
  "MT", "Statewide",
  "NC", "Statewide",
  "OH", "Statewide",
  "RI", "Statewide",
  "SC", "Statewide",
  "TX", "Statewide",
  "VT", "Statewide",
  "WI", "Statewide"
  # TODO(danj): add CT and MI as additional controls
  # TODO(amyshoe): confirm eligibility matches
)


marijuana_legalization_analysis <- function() {
  tbl <- load()
  treatment <- filter(tbl, state %in% c("CO", "WA"))
  control <- filter(tbl, !(state %in% c("CO", "WA")))
  list(
    tables = list(
      search_rate_difference_in_difference_coefficients =
        calculate_search_rate_difference_in_difference_coefficients(tbl)
    ),
    plots = list(
      test_search_rates = compose_search_rate_plots(treatment),
      control_search_rates = compose_search_rate_plots(control),
      test_misdemeanor_rates = compose_misdemeanor_rate_plots(test),
      inferred_threshold_changes = compose_inferred_threshold_changes_plot(test)
    )
  )
}


load <- function() {
  opp_load_all_clean_data(ELIGIBLE_STATES) %>%
  filter(
    type == "vehicular",
    subject_race %in% c("black", "white", "hispanic"),
    year(date) >= 2011 & year(date) <= 2015,
    # TODO(danj/amyshoe): make sure CO/WA results don't change with updated
    # data, post 2015
  ) %>%
  opp_filter_out_non_highway_patrol_stops_from_states() %>%
  mutate(
    subject_race = relevel(droplevels(subject_race), "white"),
    # NOTE: default for control and WA is WA's legalization date
    legalization_date = if_else(
      state == "CO",
      as.Date("2012-12-10"),
      as.Date("2012-12-09")
    ),
    is_before_legalization = date < legalization_date,
    is_treatment_state = state %in% c("WA", "CO"),
    is_treatment = is_treatment_state & !is_before_legalization,
    violation = str_to_lower(violation),
    # NOTE: search_basis = NA is interpreted as an eligible search;
    # excludes other (non-discretionary)
    is_eligible_search = search_conducted & (is.na(search_basis)
      | search_basis %in% c("k9", "plain view", "probable cause", "consent")),
    is_drugs_infraction_or_misdemeanor = if_else(
      state == "CO",
      # NOTE: Details on Colorado's marijuana policies:
      # https://www.colorado.gov/pacific/marijuana/driving-and-traveling
      str_detect(
        violation,
        str_c(
          "possession of 1 oz or less of marijuana",
          # NOTE: these spike after legalization
          # "open marijuana container",
          sep = "|"
        )
      ),
      # NOTE: WA violations
      str_detect(
        violation,
        str_c(
          "drugs - misdemeanor",
          "drugs paraphernalia - misdemeanor",
          sep = "|"
        )
      )
    )
  )
}


calculate_search_rate_difference_in_difference_coefficients <- function(tbl) {
  tbl <- 
    tbl %>%
    filter(
      # NOTE: don't filter in global filter because violation and
      # search_conducted may be NA in different places, so filter locally
      !is.na(search_conducted)
    ) %>%
    group_by(
      state,
      date,
      subject_race,
      legalization_date,
      is_treatment
    ) %>%
    summarize(
      n_eligible_searches = sum(is_eligible_search),
      n_stops_with_search_data = n()
    ) %>%
    ungroup(
    ) %>%
    mutate(
      years_since_legalization = as.numeric(date - legalization_date) / 365
    )

  glm(
    cbind(n_eligible_searches, n_stops_with_search_data - n_eligible_searches)
      ~ state + years_since_legalization + subject_race +
        is_treatment:subject_race,
    binomial,
    tbl
  ) %>%
  tidy()
}


compose_search_rate_plots <- function(tbl) {
  # NOTE: ensure only treatment or control is passed
  stopifnot(length(unique(tbl$is_treatment_state)) == 1)

  is_treatment_state <- tbl$is_treatment_state[[1]]

  tbl <-
    tbl %>%
    filter(
      # NOTE: don't filter in global filter because violation and
      # search_conducted may be NA in different places, so filter locally
      !is.na(search_conducted)
    ) %>%
    group_by(
      state,
      date,
      subject_race,
      legalization_date,
      is_before_legalization
    ) %>%
    summarize(
      n_eligible_searches = sum(is_eligible_search),
      n_stops_with_search_data = n()
    ) %>%
    ungroup()

  endpoints <-
    tbl %>%
    group_by(state) %>%
    do(compute_search_trendline(.)) %>%
    group_by(state, subject_race, is_before_legalization) %>%
    filter(date == min(date) | date == max(date)) %>%
    mutate(position = if_else(date == min(date), "start", "end")) %>%
    select(-n_eligible_searches, -n_stops_with_search_data)

  # spread endpoints so it has cols start_date, end_date, start_rate, end_rate
  trends <-
    left_join(
      endpoints %>%
      select(-predicted_search_rate) %>%
      spread(position, date) %>%
      rename(start_date = start, end_date = end),

      endpoints %>%
      select(-date) %>%
      spread(position, predicted_search_rate) %>%
      rename(start_rate = start, end_rate = end),
    )

  tbl <-
    tbl %>%
    # NOTE: roll up to quarters to reduce noisiness
    to_rates_by_quarter(n_eligible_searches, n_stops_with_search_data) %>%
    # NOTE: remove data around legalization quarter since it will be mixed
    filter(quarter != as.Date("2012-11-15"))

  compose_timeseries_rate_plot(tbl, "Search Rate", is_treatment_state, trends)
}


compute_search_trendline <- function(tbl) {
  fit <- function(tbl) {
    glm(
      # NOTE: (n_successes, n_failures) ~ X
      # NOTE: date is interpreted numerically
      cbind(n_eligible_searches, n_stops_with_search_data - n_eligible_searches)
        ~ subject_race + date,
      binomial,
      tbl
    )
  }
  m_before <- fit(filter(tbl, is_before_legalization))
  m_after <- fit(filter(tbl, !is_before_legalization))
  score <- function(model, tbl) { predict(model, tbl, type = "response") }

  tbl %>%
  group_by(state, subject_race, is_before_legalization) %>%
  filter(date == min(date) | date == max(date)) %>%
  distinct() %>%
  ungroup() %>%
  mutate(
    predicted_search_rate = if_else(
      is_before_legalization,
      score(m_before, .),
      score(m_after, .)
    )
  )
}


to_rates_by_quarter <- function(tbl, numerator_col, denominator_col) {
  numerator_colq <- enquo(numerator_col)
  denominator_colq <- enquo(denominator_col)
  numerator_name <- quo_name(numerator_colq)
  denominator_name <- quo_name(denominator_colq)
  group_by_colnames <- c(
    setdiff(
      colnames(tbl),
      c(numerator_name, denominator_name, "date")
    ),
    "quarter"
  )
  tbl <-
    tbl %>%
    mutate(
      quarter = as.Date(str_c(
        year(date),
        c("-02-", "-05-", "-08-", "-11-")[quarter(date)],
        "15"
      ))
    ) %>%
    group_by(.dots = group_by_colnames) %>%
    summarize(rate = sum(!!numerator_colq) / sum(!!denominator_colq)) %>%
    ungroup()
}


compose_timeseries_rate_plot <- function(
  tbl,
  y_axis_label,
  is_treatment_state = T,
  trends = NULL
) {

  p <-
    ggplot(
      tbl,
      aes(
        x = quarter,
        y = rate,
        color = subject_race,
        group = interaction(subject_race, is_before_legalization)
      )
    ) +
    geom_line(
    ) +
    geom_vline(
      xintercept = tbl$legalization_date,
      linetype = "longdash"
    ) +
    facet_wrap(
      state ~ .,
      scales = "free_y"
    ) +
    scale_color_manual(
      values = c("blue", "black", "red"),
      labels = c("White", "Black", "Hispanic")
    ) +
    scale_y_continuous(
      y_axis_label,
      labels = function(x) scales::percent(x, accuracy = 0.01),
      expand = c(0, 0)
    ) +
    expand_limits(
      y = -0.0001
    ) +
    theme_bw(
      base_size = 15
    ) +
    theme(
      # NOTE: remove the title
      plot.title = element_blank(),
      # NOTE: make the background white
      panel.background = element_rect(fill = "white", color = "white"),
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      # NOTE: minimize margins
      plot.margin = unit(rep(0.2, 4), "cm"),
      panel.margin = unit(0.25, "lines"),
      # NOTE: tiny space between axis labels and tick marks
      axis.title.x = element_text(margin = ggplot2::margin(t = 6.0)),
      axis.title.y = element_text(margin = ggplot2::margin(t = 6.0)),
      # NOTE: simplify legend
      legend.key = element_blank(),
      legend.background = element_rect(fill = "transparent"),
      legend.title = element_blank(),
      # NOTE: ifelse and if_else can't return vectors
      legend.position = if (is_treatment_state) c(0.88, 0.88) else c(0.96, 0.95),
      axis.title.x = element_blank(),
      panel.spacing = unit(0.5, "lines"),
      plot.margin = unit(c(0.1, 0.2, 0.1, 0.1), "in")
    )
                  
  # TODO(danj): try to do this with geom_smooth
  # p <-
  #   p +
  #   geom_smooth(
  #     data = trends,
  #     method = "lm",
  #     formula =
  #       cbind(
  #         n_eligible_searches,
  #         n_stops_with_search_data - n_eligible_searches
  #       ) ~ state + date + subject_race
  #   )

  if (!is.null(trends)) {
    p <-
      p +
      geom_segment(
        data = trends,
        aes(
          x = start_date,
          xend = end_date,
          y = start_rate,
          yend = end_rate,
          color = subject_race,
          group = interaction(subject_race, is_before_legalization)
        ),
        linetype = "longdash",
        size = 0.8
      )
  }

  p
}


compose_misdemeanor_rate_plots <- function(tbl) {
  tbl %>%
  filter(
    !is.na(violation)
  ) %>%
  group_by(
    state,
    date,
    subject_race,
    legalization_date,
    is_before_legalization
  ) %>%
  summarize(
    n_drugs_infraction_or_misdemeanor = sum(is_drugs_infraction_or_misdemeanor),
    n_stops_with_violation_data = n()
  ) %>%
  ungroup(
  ) %>%
  # NOTE: roll up to quarters to reduce noisiness
  to_rates_by_quarter(
    n_drugs_infraction_or_misdemeanor,
    n_stops_with_violation_data
  ) %>%
  # NOTE: remove data around legalization quarter since it will be mixed
  filter(
    quarter != as.Date("2012-11-15")
  ) %>%
  compose_timeseries_rate_plot("Drugs Infraction & Misdemeanor Rate")
}


compose_inferred_threshold_changes_plot <- function(tbl) {
  bind_rows(
    collect_aggregate_thresholds_for_state(tbl, "CO"),
    collect_aggregate_thresholds_for_state(tbl, "WA")
  ) %>% 
  plot_threshold_changes()
}


collect_aggregate_thresholds_for_state <- function(tbl, s) {
  data_summary <- summarise_for_stan(filter(tbl, state == s)) 
  stan_data <- format_data_summary_for_stan(data_summary)
  fit <- stan_marijuana_threshold_test(stan_data)
  posteriors <- rstan::extract(fit)
  data_with_thresholds <- add_thresholds(data_summary, posteriors)
  summary_stats(data_with_thresholds, posteriors, s)
}


summarise_for_stan <- function(tbl) {
  filter(
    tbl,
    !is.na(subject_race), 
    !is.na(county_name)
  ) %>% 
  mutate(
    # NOTE: excludes consent and other (non-discretionary)
    eligible_search_conducted = search_conducted & (is.na(search_basis) | 
      search_basis %in% c("k9", "consent", "plain view", "probable cause")),
    race_cd = as.integer(subject_race),
    county_cd = as.integer(as.factor(county_name)),
    legal = !is_before_legalization
  ) %>% 
  group_by(
    state, county_name, county_cd,
    race_cd, subject_race, legal
  ) %>%
  summarize(
    num_stops = n(),
    num_searches = sum(eligible_search_conducted, na.rm = T),
    num_hits = sum(eligible_search_conducted & contraband_found, na.rm = T)
  ) %>% 
  ungroup()
}


format_data_summary_for_stan <- function(d) {
  list(
    n_groups = nrow(d),
    n_sub_geographies = n_distinct(pull(d, county_name)),
    n_races = n_distinct(pull(d, subject_race)),
    sub_geography = pull(d, county_cd),
    legal = pull(d, as.integer(legal)),
    race = pull(d, race_cd),
    stop_count = pull(d, num_stops),
    search_count = pull(d, num_searches),
    hit_count = pull(d, num_hits)
  )
}


stan_marijuana_threshold_test <- function(
  data,
  n_iter = 5000,
  n_cores = min(5, parallel::detectCores() / 2)
) {
  # NOTE: defaults; may expose more of these in the future
  allow_adaptive_step_size <- T
  initialization_method <- "random"
  min_acceptable_divergence_rate <- 0.05
  n_iter_per_progress_update <- 50
  n_iter_warmup <- min(2500, round(n_iter / 2))
  n_markov_chains <- 5
  nuts_max_tree_depth <- 12
  path_to_stan_model <- here::here("stan", "threshold_test_marijuana.stan")
  
  rstan::sampling(
    stan_model(path_to_stan_model),
    data,
    chains = n_markov_chains,
    control = list(
      adapt_delta = 1 - min_acceptable_divergence_rate,
      adapt_engaged = allow_adaptive_step_size,
      max_treedepth = nuts_max_tree_depth
    ),
    cores = n_cores,
    init = initialization_method,
    iter = n_iter,
    refresh = n_iter_per_progress_update,
    warmup = n_iter_warmup
  )
}


add_thresholds <- function(
  data_summary,
  posteriors
) {
  data_summary %>%
    mutate(
      threshold = colMeans(signal_to_percent(
        posteriors$threshold, 
        posteriors$phi, 
        posteriors$delta
      ))
    )
}


summary_stats <- function(obs, post, state) {
  threshold_cis(
    obs, post,
    groups = c('legal', 'subject_race'),
    weights = obs %>% 
      group_by(county_name, legal) %>%
      mutate(w=sum(num_stops)) %>%
      with(w)
  ) %>% 
  mutate(state = state)
}


threshold_cis = function(
  obs,
  post,
  groups = 'subject_race',
  weights = NULL,
  probs = c(0.025, 0.5, 0.975)
) {
  if (is.null(weights)) {
    weights <-
      group_by(obs, county_name) %>%
      mutate(w = sum(num_stops)) %>%
      with(w)
  }
  
  t <- t(signal_to_percent(
    post$threshold,
    post$phi,
    post$delta
  ))
  
  mutate(obs, idx = row_number()) %>%
  group_by_(.dots = groups) %>%
  do(
    as.data.frame(t(quantile(
      colSums(weights[.$idx] * t[.$idx,]) / sum(weights[.$idx]), 
      probs = probs
    )))
  ) %>% 
  left_join(
    group_by_(obs, .dots = groups) %>% summarize(mean = mean(threshold)),
    by = groups
  )
}

signal_to_percent <- function(x, phi, delta) {
  # converts the threshold signal into a percent value (0, 1)
  phi * dnorm(x, delta, 1) / 
    (phi * dnorm(x, delta, 1) + (1 - phi) * dnorm(x, 0, 1))
}


plot_threshold_changes <- function(tbl) {
  ungroup(tbl) %>% 
  mutate(
    legal = factor(
      if_else(legal, "Post", "Pre"), 
      levels = c("Pre", "Post")
    ),
    subject_race = factor(
      subject_race, 
      levels = c("white", "black", "hispanic")
    )
  ) %>%
  ggplot(aes(legal, `50%`, color = subject_race)) +
  geom_line(aes(group = subject_race)) +
  geom_segment(aes(xend = legal, y = `2.5%`, yend = `97.5%`)) +
  scale_colour_manual(
    values = c("blue", "black", "red"), 
    labels = c("White", "Black", "Hispanic")
  ) +
  scale_y_continuous(
    "Inferred Threshold", 
    limits = c(.25, .75), 
    labels = scales::percent, 
    expand = c(0,0)
  ) +
  theme_bw() +
  facet_grid(cols = vars(state)) +
  labs(
    color = "",
    x = "Legalization Period"
  )
}
