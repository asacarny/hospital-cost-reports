# CMS Hospital Cost Report (HCRIS) Data 2000-2017
Here you'll find code to process the CMS hospital cost report data, called HCRIS (Healthcare Cost Report Information System). The output includes all cost reports from 2000-2017. For more information on this data, see the NBER site:

http://www.nber.org/data/hcris.html

The code produces two datasets. In one, `hcris_merged.dta`, each record is a hospital cost report. Hospitals can file multiple cost reports in the same year, covering different periods. The coverage periods will also depend on the hospital's fiscal year, with some hospitals' fiscal years beginning earlier in the year and others later in the year.

Thus, the second dataset, `hcris_merged_hospyear.dta`, attempts to deal with this by constructing synthetic calendar year data. For variables that are flows, it takes weighted sums over the cost reports, with the weights equal to the fraction of the cost report that fell into the calendar year (the weights are not normalized). For bed counts and the cost-to-charge ratio, it takes a weighted average using the same formula for the weights, but in this case the weights are normalized to sum to 1.

# Cautionary notes!

* Cost report data is notoriously noisy and mis-measured. I strongly advise that you pre-process it to remove bizarre values, or that you use analytic methods that are less sensitive to outliers (e.g. quantile regression, trimming/winsorizing the outcome before linear regression, etc.).
* **The uncompensated care variables are untested.** Reporting of uncompensated care has changed over time. I attempted to create harmonized series of uncompensated care charges and costs, but you should make sure that my definitions match the approach that you actually want to use.
* In the synthetic calendar year data, sometimes a hospital doesn't have cost reports with enough days to cover the full year period. These observations have `flag_short` set to 1. In other cases, the cost reports have too many days, indicating that there were overlapping reports. These observations have `flag_long` set to 1.
* Because I process cost reports in the 2000-2017 files, many hospitals have incomplete calendar year 2000 and 2017 coverage. As a result, `hcris_merged_hospyear.dta` only includes calendar years 2001-2016.

# Download the processed data

I have put the processed cost report data online at the below links:  
(Includes data in Stata v15, Stata v12, and CSV formats, plus full variable descriptions for those not using Stata.)

Report level data (`hcris_merged.dta`), 2000-2017:  
http://sacarny.com/public-files/hospital-cost-report/latest/hospital-cost-report-merged.zip

Synthetic calendar year by hospital level data (`hcris_merged_hospyear.dta`), 2001-2016:  
http://sacarny.com/public-files/hospital-cost-report/latest/hospital-cost-report-merged-hospyear.zip

# Instructions for processing the data yourself
1. Download the repository using the 'Clone or download' link on github, or clone this repository with the git command:
`git clone https://github.com/asacarny/hospital-cost-reports.git`
1. Download the source data from NBER and put it into the `source/` subfolder. You have two options for this.
	1. Shell script: If you are on Mac/Linux/Cygwin, I made a shell script to download the files. Edit the file `download_source.sh` to set your start/end year and the method you'll use to retrieve the data (wget or rsync, though rsync will only work for those with an NBER username). Then open a terminal, `cd` to your repository folder, and run `bash download_source.sh`.
	2. By hand: Make a folder in the repository called `source/`. Go to http://www.nber.org/data/hcris.html and download the "Numeric Table" (`hosp_nmrc_2552_...`) and "Report Table" (`hosp_rpt2552_...`) Stata .dta files for the cost report years you want.
1. Edit the `hcris.do` file so that the start/end years match the years of data you downloaded in the previous step.
1. Open stata, change its working directory to the repository, and run `do hcris.do`

# Adding new variables

These datasets only include a handful of cost report variables. To update the code to extract more variables, here are some tips.

* CMS provides documentation for the [2010 format](http://www.cms.gov/Regulations-and-Guidance/Guidance/Manuals/Downloads/P152_40.zip) and [1996 format](http://www.cms.gov/Regulations-and-Guidance/Guidance/Manuals/Downloads/P152_36.zip) files.
* If you want to extract a new variable, you'll need to know the worksheet, row, and column in which it appears. One shortcut I've used: search for a hospital on https://www.costreportdata.com/search.php and view one of the reports. The website won't show you any real values unless you pay, but the visualization here should be enough.
* Keep in mind that the cost report format changed around 2010 and there was a brief period where hospitals seemed to file reports in either format. If you want a panel that goes back to around that time, you'll need to figure out the variable's worksheet, row, and column in both the 1996 and 2010 formats.
* Once you know the worksheet, row, and column of the variable, modify the file `misc/lookup.xlsx` and add the info as a new row. Then modify `hcris.do` to keep and process that variable. Unfortunately the process is not as easy as it should be yet.

# Todo
* Make it easier to add new variables
