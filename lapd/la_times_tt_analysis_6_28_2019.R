setwd("~/opp/lib")
source("opp.R")
source("threshold_test.R")
# NOTE: comment out line 399 in this file;
# it's hard codes colors for 3 races; we have 4.
source("disparity.R")

# TODO
# Look at hierarchy for search_basis
# Include metro in subgeo

# LOAD DATA
ripa <- read_csv("~/ripa/la/RIPA_MASTER_July_April.csv",
                 col_types = cols(Basis_for_Search = "c"))
colnames(ripa) <- make_ergonomic(colnames(ripa))
lapd <- read_csv("~/ripa/la/LAPD_online_data_since_July_2018.csv")
colnames(lapd) <- make_ergonomic(colnames(lapd))

# Get table of just vehicle stops and divisions
veh_frns <- lapd %>% 
  filter(stop_type == "VEH") %>%
  mutate(division = if_else(
    officer_1_division_number > 0 & officer_1_division_number <= 27,
    division_description_1,
    "OTHER")
  ) %>% 
  select(frn, division, division_description_1, officer_1_division_number) %>% 
  unique()

tr_race <- c(
  Latino = "hispanic",
  Black = "black",
  White = "white",
  Asian = "other",
  MiddleEastSouthAsian = "other",
  multiracial = "other",
  `Pacific Islander` = "other",
  `Native American` = "other"
)

# Get RIPA vehicle stops
ripa_veh <- ripa %>% 
  select(frn, race, search, basis_for_search, contraband) %>% 
  filter(frn %in% veh_frns$frn) %>% 
  left_join(veh_frns, by = "frn") %>% 
  mutate(
    search_conducted = search == "TRUE", 
    basis_for_search_single = case_when(
      # Plain view (visible contraband) = 6
      str_detect(basis_for_search, "6") ~ 6,
      # Plain smell (odor of contraband) = 7
      str_detect(basis_for_search, "7") ~ 7,
      # Consent = 1
      str_detect(basis_for_search, "(^1$)|(^1,)|(,1,)|(,1$)") ~ 1,
      # Safety = 2
      str_detect(basis_for_search, "(^2$)|(^2,)|(,2,)|(,2$)") ~ 2,
      # Suspected weapon = 5
      str_detect(basis_for_search, "5") ~ 5,
      # Evidence of crime = 9
      str_detect(basis_for_search, "9") ~ 9,
      # Suspected violation of school policy = 13
      str_detect(basis_for_search, "13") ~ 13,
      # Exigent circumstances/emergency = 11
      str_detect(basis_for_search, "11") ~ 11,
      # K9 detection = 8
      str_detect(basis_for_search, "8") ~ 8,
      # Warrant = 3
      str_detect(basis_for_search, "(^3$)|(^3,)|(,3,)|(,3$)") ~ 2,
      # Probation/parole = 4
      str_detect(basis_for_search, "4") ~ 4,
      # Incident to arrest = 10
      str_detect(basis_for_search, "10") ~ 10,
      # Vehicle inventory = 12
      str_detect(basis_for_search, "12") ~ 12,
      TRUE ~ NA_real_
    ),
    # Non-discretionary searches:
    # 4 = probation/parole, 10 = incident to arrest, 
    # 12 = vehicle inventory (impound?)
    non_discretionary_search = basis_for_search_single %in% c(3, 4, 10, 12),
    any_non_discretionary_search = str_detect(
      basis_for_search, 
      "(^3$)|(^3,)|(,3,)|(,3$)|4|(10)|(12)"
    ),
    contraband_found = contraband == "TRUE",
    contraband_found = if_else(!search_conducted, FALSE, contraband_found),
    subject_race = as.factor(tr_race[race]),
    sub_geography = division,
    geography = "LA"
  ) 

# Run threshold test
tt_results_all_searches <- threshold_test(
  ripa_veh,
  sub_geography,
  geography_col = geography
)
write_rds(tt_results_all_searches, "~/ripa/tt_results_all_searches.rds")

tt_results_discretionary_searches <- threshold_test(
  ripa_veh %>% filter(!non_discretionary_search),
  sub_geography,
  geography_col = geography
)
write_rds(
  tt_results_discretionary_searches, 
  "~/ripa/tt_results_discretionary_searches.rds"
)

tt_results_no_non_discretionary_searches <- threshold_test(
  ripa_veh %>% filter(!any_non_discretionary_search),
  sub_geography,
  geography_col = geography
)
write_rds(
  tt_results_no_non_discretionary_searches, 
  "~/ripa/tt_results_no_nondiscretionary_searches.rds"
)

# Function wrapper for convergence checks and ppcs
model_checks <- function(model_result) {
  fit <- model_result$metadata$fit
  summary <- summary(fit)$summary
  # Want this to be < 1.05
  print("max Rhat")
  print(summary[,'Rhat'] %>% max(na.rm = T))
  # Want this to be > 0.001
  print("min n_eff")
  print(summary[,'n_eff'] %>% min(na.rm = T) / nrow(tbl))

  search_rate_ppc <- plt_ppc_rates(
    model_result$results$thresholds,
    rstan::extract(model_result$metadata$fit),
    "search_rate",
    numerator_col = n_action,
    denominator_col = n,
    title = str_c("LA threshold ppc - search rates")
  )

  hit_rate_ppc <- plt_ppc_rates(
    model_result$results$thresholds,
    rstan::extract(model_result$metadata$fit),
    "hit_rate",
    numerator_col = n_outcome,
    denominator_col = n_action,
    title = str_c("LA threshold ppc - hit rates")
  )

  list(
    search_rate_ppc = search_rate_ppc,
    hit_rate_ppc = hit_rate_ppc
  )
}

all_search_checks <- model_checks(tt_results_all_searches)
disc_search_checks <- model_checks(tt_results_discretionary_searches)
no_non_disc_search_checks <- model_checks(tt_results_no_non_discretionary_searches)

tt_results_all_searches$results$aggregate_thresholds
tt_results_discretionary_searches$results$aggregate_thresholds
tt_results_no_non_discretionary_searches$results$aggregate_thresholds
