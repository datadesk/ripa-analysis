# run every line of code in these files
source('lib/opp.R')
source('lib/threshold_test.R')

# Testing on OPP San Jose data

# jose = read_csv('../tr137st9964_ca_san_jose_2019_02_25.csv/share/data/opp-for-archive/ca_san_jose_2019_02_25.csv')

#head(jose)

## This works

# tt <- threshold_test(jose %>% mutate(city='San Jose'))

## This gets the thresholds
# tt$results$aggregate_thresholds


# Now back to our LAPD data

# tweak the function so it doesn't create summary_stats

source('lib/threshold_test.R')

exclude_probation9 = read_csv('../ripa_unique_4_10_19_exclude_other_probation_ALLv3.csv')
names(exclude_probation9) <- c('subject_race', 'search_conducted','contraband_found', 'precinct')


# 1: 1.46% of data was inconsistent: outcome was positive but no action was taken 
# 1: There were 2183 transitions after warmup that exceeded the maximum treedepth. Increase max_treedepth above 12. See
# http://mc-stan.org/misc/warnings.html#maximum-treedepth-exceeded 

# https://github.com/stanford-policylab/opp/blob/master/lib/threshold_test.R#L240-L245

# checking this in data
# data %>% group_by(search_conducted, contraband_found) %>% count()

#metro <- data %>% filter(precinct=='METROPOLITAN DIVISN')
# glimpse(metro)


# seven <- data %>% filter(precinct=='SEVENTY-SEVENTH')
# glimpse(seven)
# 
# seven.lapd <- threshold_test(seven)

glimpse(exclude_probation9)

tt.exclude_probation9 <- threshold_test(exclude_probation9)

write_csv(tt.exclude_probation9$results$aggregate_thresholds, '../lapd_threshold_division_results_exclude_probation9.csv')

