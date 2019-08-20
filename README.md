# LAPD Search Threshold Test

## Developed by the Stanford Open Policing Project

###

<b>By Ben Poston and Ryan Menezes</b>

In consultation with the Stanford Open Policing Project, a Los Angeles Times analysis found that LAPD officers search black and Latinos far more often than whites during traffic stops even though whites are more likely to be found with illegal items.

To report the story, we filed an open records request and obtained 10 months worth of traffic stop data collected by the LAPD under the California Racial and Identity Profiling Act, which went into effect last summer.

We used a statistical model — known as a threshold test — that combines data from search rates of each racial group and the rate at which those searches were successful in finding contraband. The model was developed by the Stanford Open Policing Project, which has analyzed traffic stop data at dozens of law enforcement agencies across the nation.

The analysis showed that officers had a lower standard of evidence when deciding to search Latino and black vehicle occupants. This was true, even when excluding non-discretionary searches as the primary reason for the police action. 

Such searches — conducted as condition of probation or parole, after an arrest was made, as part of a search warrant or during an inventory of an impounded vehicle — don’t capture whether officers demonstrate bias, experts said. Those "non-discretionary" searches can also lower the rates at which officers find contraband during searches.

We cloned the Stanford repository and ran our own analysis. We then later shared the LAPD data with Stanford data scientist Amy Shoemaker who was kind enough to run the LAPD through the threshold test model. She created a hierarchy filter to flag searches as discretionary or non-discretionary. The filter excludes stops where non-discretionary searches were the primary reason for the police action and categorizes those with multiple reasons for a search. So if a stop included both a consent search and a vehicle inventory search it was included in the analysis because a consent search is considered discretionary and given a higher rank in the hierarchy model. Shoemaker's findings for all searches and discretionary searches were consistent with our initial results, which showed lower search thresholds for non-whites.

The code contained in this notebook was written by the SOPP and customized for the LAPD dataset by Shoemaker. We downloaded the SOPP code from their <a href=https://github.com/stanford-policylab/opp>Github page</a>.

This code uses two data sets. The first one was the <a href=https://www.dropbox.com/s/hxqglesiofk3o0z/RIPA_MASTER_July_April.csv?dl>detailed data</a> collected by LAPD to comply with the state's Racial and Identity Profiling Act, which went effect in 2018. 

The second is a data set -- available on the city's <a href=https://data.lacity.org/A-Safe-City/Vehicle-and-Pedestrian-Stop-Data-2010-to-Present/ci25-wgt7>data portal</a> -- includes information on the division of the responding officer. The Threshold Test requires a subgeography like a police division to be able to identify differences in search thresholds across an entire city.

<img src= "https://github.com/datadesk/ripa-analysis/blob/master/LAPD%20Search%20Graphic.png" width="281" height="500">
