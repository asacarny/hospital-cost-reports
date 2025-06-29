# CMS Hospital Cost Report (HCRIS) Data 1996-2024
Here you'll find code to process the CMS hospital cost report data, called HCRIS (Healthcare Cost Report Information System). The output includes all cost reports from 1996-2024.

**I have rewritten this code in R. While I've started using this code and data in my own work, please review the output carefully. You may want to think of it as beta testing!**

For more information on the data, see the NBER site:

http://www.nber.org/data/hcris.html

The code produces two datasets. In one, `hcris_merged.Rdata`, each record is a hospital cost report. Hospitals can file multiple cost reports in the same year, covering different periods. The coverage periods will also depend on the hospital's fiscal year, with some hospitals' fiscal years beginning earlier in the year and others later in the year.

Thus, the second dataset, `hcris_merged_hospyear.Rdata`, attempts to deal with this issue by constructing synthetic calendar year data. For variables that are flows, it takes weighted sums over the cost reports, with the weights equal to the fraction of the cost report that fell into the calendar year (the weights are not normalized). For variables that are stocks or something like stocks (e.g. bed counts and the cost-to-charge ratio), it takes a weighted average, with weights equal to the fraction of the year covered by the report and normalized to sum to 1.

# Cautionary notes!
* **The reports for the most recent year of data are typically very incomplete!**
* **The hospital-year records for the most recent year or two of the data may be very incomplete!** These records are still available in the file. Check the `flag_short` variable (described below).
* Cost report data is notoriously noisy and mis-measured. I strongly advise that you pre-process it to remove bizarre values, or that you use analytic methods that are less sensitive to outliers (e.g. quantile regression, trimming/winsorizing the outcome before linear regression, etc.).
* **The uncompensated care variables are untested.** Reporting of uncompensated care has changed over time. I attempted to create harmonized series of uncompensated care charges and costs, but you should make sure that my definitions match the approach that you actually want to use.
* The data includes my best attempt to calculate the Medicare inpatient operating cost-to-charge ratio (`ccr_prog`), but I give no guarantees it's correct.
* In the synthetic calendar year data, sometimes a hospital doesn't have cost reports with enough days to cover the full year period. These observations have `flag_short` set to 1. In other cases, the cost reports have too many days, indicating that there were overlapping reports. These observations have `flag_long` set to 1.
* Because I process cost reports from 1996-2024 source files, many hospitals have incomplete calendar year coverage in the starting and terminal years (as the relevant cost reports were in / will be in 1995 or 2025 data). As a result, `hcris_merged_hospyear.dta` only includes calendar years 1997-2023. *2023 data in the hospital-year file is about 5% incomplete*.
* Sometimes values are missing in the original cost report data. In the synthetic calendar year data, a value is set to NA if any embodied cost report had a missing value. **Note:** dollar variables (e.g. costs, charges, etc.) are recoded to 0 in the report-level data. These values will therefore never be missing in the synthetic calendar year data. See the notes on adding new variables for more details.

# Download the processed data

The processed cost report data is online at:

http://sacarny.com/public-files/hospital-cost-report/latest/hospital-cost-report.zip

Includes report level data (`hcris_rpt.Rdata`), 1996-2024 and synthetic calendar year by hospital level data (`hcris_hospyear.Rdata`), 1997-2023. Files in R, Stata, and CSV formats.

# Instructions for processing the data yourself
1. Download the repository using the 'Clone or download' link on github, or clone this repository with the git command:
`git clone https://github.com/asacarny/hospital-cost-reports.git`
1. Download the source data from CMS and put it into the `source/` subfolder. I recomend using the shell script to automatically download the files from the CMS website. Mac and Linux users should be able to run this with little issue. Windows users will need to install Cygwin. You will need `wget` and `unzip` installed.
	- Edit the file `download_source.sh` to set your start/end year.
	- Next, open a terminal, `cd` to your repository folder, and run `bash download_source.sh`.
	- Import the files to parquet format. Edit the file `import-source-cms.R` to set the same start/end year. In R, set the working directory to the repository and run `import-source-cms.do`.
1. Edit the `hcris.R` file so that the start/end years match the years of data you downloaded in the previous step.
1. In R, set the working directory to the repository, and run `hcris.do`

# Adding new variables

These datasets only include a handful of cost report variables. To update the code to extract more variables, here are some tips.

* CMS provides documentation for the [2010 format](http://www.cms.gov/Regulations-and-Guidance/Guidance/Manuals/Downloads/P152_40.zip) and [1996 format](http://www.cms.gov/Regulations-and-Guidance/Guidance/Manuals/Downloads/P152_36.zip) files.
* If you want to extract a new variable, you'll need to know the worksheet, row, and column in which it appears. One shortcut I've used: search for a hospital on https://www.costreportdata.com/search.php and view one of the reports. The website won't show you any real values unless you pay, but the visualization here should be enough.
* Keep in mind that the cost report format changed around 2010 and so there are some years with reports in both formats. If you want a panel that goes back to around that time, you'll need to figure out the variable's worksheet, row, and column in both the 1996 and 2010 formats.
* Once you know the worksheet, row, and column of the variable, open up `lookup.xlsx` and add the info as a new row to the worksheet `Lookup Table`. Make sure that `clmn_num` and `line_num_start` are stored as text format (i.e. the leading zeroes should appear). Set `fmt` to `10` if the variable is from 2010 format reports and `96` if it's from 1996 format reports. Make sure to set `enabled` to 1.
* If you would like the variable to sum over consecutive cost report lines, fill in a value for `line_num_end`. For instance, the lookup file includes an entry for `icu_beds` with `line_num_start=00800` and `line_num_end=00899`, ensuring that the variable sums ICU beds from line 8 and all its subscripts. If you leave `line_num_end` blank, the code just loads the line given by `line_num_start`.
* If you would like the variable to sum over non-consecutive lines, add additional entries to the table with the same `rec` and `fmt`. For an example, see  `othspec_beds` for 1996 format reports in the lookup table.
* Finally, add a new row to the worksheet `Type and Label`. Note the column `type`, for which you should put one of the below four options:
  1. `stock` - in the synthetic calendar-year dataset, this will produce a variable with the weighted average across all the cost reports covering that year. The weights equal to the fraction of the year covered by the report. If any of the values in the collection of reports being aggregated over was NA, the variable is set to NA.
  1. `flow` - in the synthetic calendar-year dataset, this variable is produced by scaling its value in each of the hospital's cost reports by the fraction of that report that fell into the year. Then, it sums the scaled values. If any of the values in the collection of reports being summed over was NA, the variable is set to NA.
  1. `dollar_flow` - when creating the report-level dataset, if the hospital does not submit the variable or it is missing, the code sets the value to zero. An indicator variable `{var}.was.na` is created to track whether the record was recoded to 0. Following the replacement of NA with 0, the construction of the synthetic calendar-year data proceeds identically to the `flow` approach. In that data, the variables `{var}.was.na` count the number of embodied values recoded to 0.
  1. `alpha` - the only `type` suitable for alphanumeric values, though it also works for numeric values. In the calendar-year data, take the value from the first embodied report (the one with the earliest `fy_bgn_dt`).
* An additional note about the `dollar_flow` approach: since each source data year contains reports spanning multiple calendar years, *all* reports in a source data year with partial coverage of a new variable will have missing values zeroed out. That includes reports for periods before hospitals had to submit that variable, for which missing is likely more appropriate.

# Change log
June 27, 2025

* Switch over to R code! This does bring some other changes, so please re-read the documentation carefully
* Import the alphanumeric files and add an `alpha` option to bring variables from those files into the report and calendar-year data

September 22, 2022

* New approach to including variables that easily allows summing them across lines and subscripts
* Use this new approach to easily pull critical care beds instead of hardcoding them in the code
* Calculate Medicare inpatient operating cost-to-charge ratio
* Fix occasional bug in flagging synthetic years with under- or over-coverage
* Refreshed data

May 16, 2022

* Removed NBER option from downloader script (the files on NBER are quite out of date)
* Downloader script now checks if wget and unzip are installed
* Fixed bug where script tried to label disabled variables, which did not exist
* Correct bug that led Stata to drop first line of CSV files
* Enable cost of charity care variable
* Corrected label for nonmcbaddebt field (thank you Ken Michelson for finding this bug)
* Added labels for disabled uncompensated care variables should they eventually be enabled.
* Enabled cost of charity care variable
* Refreshed data

January 19, 2022

* Refreshed data through 2022 and added data years 1996-1999

March 21, 2020

* *Bug fixes*
  * If a hospital had no matching variables in the NMRC table at all (i.e. it didn't report any of the variables being loaded), its dollar flows weren't being zeroed out.
  * Uncompensated care variables were set to zero even in years where those variables were not reported and thus should have been missing. This meant that in the synthetic calendar year file, the harmonized uncompensated care variables were set to zero rather than missing in early years when this data was not even reported.
  * Ensure that the 1996 format uncompensated care variable is missing when, in report-level data, the field was sometimes submitted in the source data year but the cost report covered a period when the field was not supposed to be submitted
* *New functionality:*
  * New scripts to download data directly from CMS website
  * Much easier to add new variables by just modifying the lookup table
  * Better collapse code
* *New data:*
  * Now pulling data from the CMS website to include more recent reports.
  * Report data now runs through 2019 (but is very incomplete in that year)
  * Calendar year data now runs through 2018 (but is often incomplete in that year)
  * Added critical care beds variables
