# CMS Hospital Cost Report (HCRIS) Data 2000-2019
Here you'll find code to process the CMS hospital cost report data, called HCRIS (Healthcare Cost Report Information System). The output includes all cost reports from 2000-2019. For more information on this data, see the NBER site:

http://www.nber.org/data/hcris.html

The code produces two datasets. In one, `hcris_merged.dta`, each record is a hospital cost report. Hospitals can file multiple cost reports in the same year, covering different periods. The coverage periods will also depend on the hospital's fiscal year, with some hospitals' fiscal years beginning earlier in the year and others later in the year.

Thus, the second dataset, `hcris_merged_hospyear.dta`, attempts to deal with this by constructing synthetic calendar year data. For variables that are flows, it takes weighted sums over the cost reports, with the weights equal to the fraction of the cost report that fell into the calendar year (the weights are not normalized). For variables that are stocks or something like stocks (e.g. bed counts and the cost-to-charge ratio), it takes a weighted average, with weights equal to the fraction of the year covered by the report and normalized to sum to 1. It also takes a min and a max over the values in the reports.

# Cautionary notes!
* **2018-2019 report data is very incomplete at this time. 2018 data in the hospital-year file is incomplete for many hospitals, but is still there for those who would like to use it***. Check the `flag_short` variable (described below).
* Cost report data is notoriously noisy and mis-measured. I strongly advise that you pre-process it to remove bizarre values, or that you use analytic methods that are less sensitive to outliers (e.g. quantile regression, trimming/winsorizing the outcome before linear regression, etc.).
* **The uncompensated care variables are untested.** Reporting of uncompensated care has changed over time. I attempted to create harmonized series of uncompensated care charges and costs, but you should make sure that my definitions match the approach that you actually want to use.
* In the synthetic calendar year data, sometimes a hospital doesn't have cost reports with enough days to cover the full year period. These observations have `flag_short` set to 1. In other cases, the cost reports have too many days, indicating that there were overlapping reports. These observations have `flag_long` set to 1.
* Because I process cost reports from 2000-2019 source files, many hospitals have incomplete calendar year coverage in the starting and terminal years (as the relevant cost reports were in / will be in 1999 or 2020 data). As a result, `hcris_merged_hospyear.dta` only includes calendar years 2001-2018. **Even 2018 data in the hospital-year file is incomplete for many hospitals*.
* Sometimes values are missing in the original cost report data. In the synthetic calendar year data, a value is set to missing if any embodied cost report had a missing value. **Note:*** dollar variables (e.g. costs, charges, etc.) are recoded to 0 in the report-level data. These values will therefore never be missing in the synthetic calendar year data, except if the reporting period or calendar year predates when hospitals were required to submit the variable. See the notes on adding new variables for more details.
* The files here source the data right from CMS, but if you process the reports yourself you will have the option to download the data from CMS or NBER. If you decide to go with NBER, note that it hasn't been updated since mid-2018. The most recent year or two of reports are therefore missing, and if reports were amended after mid-2018, the new versions are not included. For this reason I currently recommend that anyone running this code themselves use the option that downloads the source data from CMS and not NBER.

# Download the processed data

I have put the processed cost report data online at the below links:  
(Includes data in Stata v15, Stata v12, and CSV formats, plus full variable descriptions for those not using Stata.)

Report level data (`hcris_merged.dta`), 2000-2019:  
http://sacarny.com/public-files/hospital-cost-report/latest/hospital-cost-report-merged.zip

Synthetic calendar year by hospital level data (`hcris_merged_hospyear.dta`), 2001-2018:  
http://sacarny.com/public-files/hospital-cost-report/latest/hospital-cost-report-merged-hospyear.zip

# Instructions for processing the data yourself
1. Download the repository using the 'Clone or download' link on github, or clone this repository with the git command:
`git clone https://github.com/asacarny/hospital-cost-reports.git`
1. Download the source data from NBER and put it into the `source/` subfolder. You have two options for this.
	1. **Recommended** Use the shell script to automatically download the files. Mac and Linux users should be able to run this with little issue. Windows users will need to install Cygwin.
		- Edit the file `download_source.sh` to set your start/end year and the method you'll use to retrieve the data (`wget-cms`, `wget-nber` or `rsync-nber`). For the moment, I recommend `wget-cms`, which downloads the source data from the CMS website.
		- The other options download from NBER, and as of my writing, those files were last updated in Mid-2018. `wget-nber` downloads the data right from the NBER website, and `rsync-nber` downloads it over rsync from NBER, which is faster especially for refreshing already-downloaded data, but will only work for those with an NBER username.
		- Next, open a terminal, `cd` to your repository folder, and run `bash download_source.sh`.
		- Finally, if you chose the `wget-cms` method, you'll need to convert the files to stata format. Open stata, change its working directory to the repository, and run `do import-source-cms.do`.
	1. By hand: Make a folder in the repository called `source/`. Go to http://www.nber.org/data/hcris.html and download the "Numeric Table" (`hosp_nmrc_2552_...`) and "Report Table" (`hosp_rpt2552_...`) Stata .dta files for the cost report years you want. NB: As of my writing, this data was last updated in mid-2018.
1. Edit the `hcris.do` file so that the start/end years match the years of data you downloaded in the previous step.
1. Open stata, change its working directory to the repository, and run `do hcris.do`

# Adding new variables

These datasets only include a handful of cost report variables. To update the code to extract more variables, here are some tips.

* CMS provides documentation for the [2010 format](http://www.cms.gov/Regulations-and-Guidance/Guidance/Manuals/Downloads/P152_40.zip) and [1996 format](http://www.cms.gov/Regulations-and-Guidance/Guidance/Manuals/Downloads/P152_36.zip) files.
* If you want to extract a new variable, you'll need to know the worksheet, row, and column in which it appears. One shortcut I've used: search for a hospital on https://www.costreportdata.com/search.php and view one of the reports. The website won't show you any real values unless you pay, but the visualization here should be enough.
* Keep in mind that the cost report format changed around 2010 and there was a brief period where hospitals seemed to file reports in either format. If you want a panel that goes back to around that time, you'll need to figure out the variable's worksheet, row, and column in both the 1996 and 2010 formats.
* Once you know the worksheet, row, and column of the variable, open up `misc/lookup.xlsx` and add the info as a new row to the worksheet `Lookup Table`. Make sure that `clmn_num` and `line_num` are both stored as text format (i.e. the leading zeroes should appear). Set `fmt` to `10` if the variable is from 2010 format reports and `96` if it's from 1996 format reports. Make sure to set `enabled` to 1.
* Finally, add a new row to the worksheet `Type and Label`. Note the column `type`, for which you should put one of the below three options:
  1. `stock` - in the synthetic calendar year dataset, produce three variables: `_min`, with the minimum value this variable took on among all the hospital's cost reports falling into that year; `_max`, with the maximum value; and `_wtd`, or the weighted average of the variable across all the cost reports covering that year with weights equal to the fraction of the year covered by the report. If any of the values in the collection of reports being aggregated over was missing, all three of these variables are set to missing.
  1. `flow` - in the synthetic calendar year dataset, this variable is produced by scaling its value in each of the hospital's cost reports by the fraction of that report that fell into the year. Then sum the scaled values. If any of the values in the collection of reports being summed over was missing, the variable is set to missing.
  1. `dollar_flow` - when creating the report-level dataset, if the hospital does not submit the variable/it is set to missing, reset the value to zero. If no hospital submitted the variable in the NBER source data for that year, missing values *are not* zeroed out. After this missingness algorithm is applied to the report-level data, the construction of the synthetic calendar year data proceeds identically to the `flow` approach.
  * An additional note about the `dollar_flow` approach: since each source data year contains reports spanning multiple calendar years, *all* reports in a source data year with partial coverage of a new variable will have the variable zeroed out. That includes reports for periods before hospitals had to submit that variable, for which missing is likely more appropriate. In my code there is one variable where this comes up: `chguccare` in 1996 format reports. The code explicitly sets this variable to missing (not zero) in any report filed before hospitals were supposed to submit it.

# Todo
* Better disaggregation of critical care beds.
* Better treatment of setting variables to missing for cost reporting periods when the variables were not supposed to be submitted.

# Change log
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
