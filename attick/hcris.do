* hcris.do
* process the CMS cost reports, producing one report-level file and another
* synthetic hospital-calendar year file

set more off
capture log close
clear
log using hcris.log, replace

* use cost reports from these years' data files
global STARTYEAR = 1996
global ENDYEAR = 2022

* with files from those years, we often (~50% of hospitals) don't observe
* reports covering the full calendar STARTYEAR. and often don't observe (~20%
* of hospitals) reports covering the full calendar ENDYEAR.
* so we shrink the extents of the hospital-year file.
global STARTYEAR_HY = $STARTYEAR+1
global ENDYEAR_HY = $ENDYEAR-1

* where is the source data?
global SOURCE_BASE "./source"

* make the output folder if it doesn't exist
capture mkdir output

* import the lookup table
import excel using lookup.xlsx, firstrow sheet("Lookup Table")

isid wksht_cd clmn_num line_num_start line_num_end fmt, missok

assert !missing(line_num_start)

* make numeric versions of line_num_start and line_num_end
replace line_num_end = line_num_start if missing(line_num_end)
foreach var of varlist line_num_start line_num_end {
	gen long `var'_int = real(`var')
	format %05.0f `var'_int
	assert `var'==string(`var'_int,"%05.0f")
	drop `var'
	rename `var'_int `var'
}

* create rows for each line, from line_num_start to line_num_end

gen d = line_num_end-line_num_start+1
assert d>=1 & !missing(d)

* this is the ID for the original record
gen long orig_n = _n

expand d
drop d

egen int seq = seq(), from(0) by(orig_n)
sort orig_n seq
gen long line_num = line_num_start+seq
format %05.0f line_num
drop seq

* the expanded set of rows must include the stated start and end
egen byte hits_start = max(line_num==line_num_start), by(orig_n)
egen byte hits_end = max(line_num==line_num_end), by(orig_n)
assert hits_start & hits_end
drop hits_start hits_end line_num_start line_num_end orig_n

tostring line_num, replace format("%05.0f")

order wksht_cd clmn_num line_num fmt
isid wksht_cd clmn_num line_num fmt

tempfile lookup
save `lookup'

* a list of worksheets we'll need - this will speed up loading the nmrc file
tempfile worksheets
keep wksht_cd fmt
duplicates drop
save `worksheets'

* save indicators for whether variables are enabled in either fmt
use rec enabled using `lookup'
collapse (max) enabled, by(rec) fast
tempfile enabled
save `enabled'

clear

* variable types and labels
import excel using lookup.xlsx, firstrow sheet("Type and Label")

gen orig_sort = _n

* bring in indicator for whether variable is enabled
merge 1:1 rec using `enabled', keep(master match) nogenerate
* if no match, assume the variable wasn't enabled
replace enabled = 0 if missing(enabled)

* put back in the original order
sort orig_sort

* locals to store lists of the types of variables
local type_dollar_flow
local type_flow
local type_stock

* process types & labels for each variable
qui count
forvalues i=1/`r(N)' {
	* only proceed if variable is enabled
	if (enabled[`i']) {

		local cur_rec = rec[`i']
		local cur_type = type[`i']
		local LABEL_`cur_rec' = label[`i']

		* all recs are dollar flows, flows, or stocks
		assert inlist("`cur_type'","dollar_flow","flow","stock")

		* add rec to rec type list
		local type_`cur_type' = "`type_`cur_type'' `cur_rec'"
	}
}

clear


* process each year's cost report

forvalues year=$STARTYEAR/$ENDYEAR {

	if (`year'>= 2012) {
		local formats "10"
	}
	else if (`year'==2010 | `year'==2011) {
		local formats "96 10"
	}
	else {
		local formats "96"
	}
	
	foreach fmt in `formats' {
		// process numeric file to pull in components of margins
		
		display "processing hosp_nmrc2552_`fmt'_`year'_long.dta"
		
		// load the list of worksheets we'll need
		// this will speed up the loading of the nmrc file by omitting
		// records from worksheets we aren't processing
		use `worksheets'
		keep if fmt==`fmt'
		drop fmt
		sort wksht_cd
		isid wksht_cd
		
		merge 1:m wksht_cd ///
			using "$SOURCE_BASE/hosp_nmrc2552_`fmt'_`year'_long.dta", ///
			keep(match) ///
			keepusing(rpt_rec_num itm_val_num wksht_cd clmn_num line_num)
				
		// identify the variables we need and label the rows
		
		// merge with the lookup table
		gen fmt = `fmt'
		merge m:1 wksht_cd clmn_num line_num fmt using `lookup', ///
			keep(match) nogenerate
		
		// drop entries we've disabled
		drop if enabled==0
		
		drop enabled fmt
		
		keep rpt_rec_num rec itm_val_num

		assert !missing(itm_val_num)
		
		gen count = 1
		collapse (sum) itm_val_num count, by(rpt_rec_num rec) fast
		
		tab count
		drop count
		
		// reshape to one row per report
		rename itm_val_num val_
		reshape wide val, i(rpt_rec_num) j(rec) string
		
		// rename all the stock and flow variables
		foreach var in `type_dollar_flow' `type_flow' `type_stock' {
			capture confirm variable val_`var'
			if (!_rc) {
				rename val_`var' `var'

			}
		}
		
		// save for merging into report level data
		tempfile nmrc
		save `nmrc', replace

		clear
	
		// process report index file
		use "$SOURCE_BASE/hosp_rpt2552_`fmt'_`year'"
		keep rpt_rec_num prvdr_num rpt_stus_cd fy_bgn_dt fy_end_dt proc_dt
	
		// bring in components of margins
		merge 1:1 rpt_rec_num using `nmrc'

		// deal with components that didn't correspond to any records in the index file!
		tab _merge
		qui count if _merge==2
		local Nusing = r(N)
		if (`Nusing'!=0) {
			display "*** there were values for some reports that were never filed! ***"
			display "...dropping `Nusing' records"
			drop if _merge==2
		}

		drop _merge
		
		****** TBD: SHOULD WE ZERO THEM OUT?! ******
		
		// zero out $ variables if they were blank
		// skip variables that are not currently defined (e.g. uncompensated
		// care variables that weren't available in that year/format)
		// note that in data years 2002 and 2003, this will blank out
		// the uncompensated care charges even if the report was filed at a
		// time when these were not supposed to be reported. we will fix this
		// momentarily.
		foreach var in `type_dollar_flow' {
			capture confirm variable `var'
			if (!_rc) {
				replace `var' = 0 if `var'==.
			}
		}

		// charity care vars differ between versions. create blank variables.
		
		// we do this after the above blanking of missing dollar
		// flows so that the charity care variables stay missing if we had to
		// generate them here
		// thus e.g. for years prior to 2002, or 2010 format reports,
		// the uncompensated care charges variable will indeed be missing
		if (`fmt'==10 | (`fmt'==96 & `year' < 2002)) {
			foreach var in chguccare {
				gen `var' = .
			}
		}
		// and for 1996 format reports, the uncompensated care care components
		// introduced in the 2010 format report will be missing
		if (`fmt'==96) {
			foreach var in totinitchcare ppaychcare nonmcbaddebt costuccare_v2010 {
				gen `var' = .
			}
		}
		
		* let's re-blank the uncompensated care variable...
		* "Complete lines 17 through 32 for cost reporting periods ending on or after April 30, 2003."
		* - Medicare v1996 documentation section 3609.4
		if (inlist(`year',2002,2003)) {
			* data years 2002 and 2003 have cost reports that could in theory
			* end before Apr 30 2003
			* these should really have the variable set to missing but we've
			* blanked it to zero for all reports if it was missing. fix this.
			
			* how often did this variable have non-zero values before
			* it was allowed to be reported?! (shouldn't happen but does like
			* once)
			display "In data year `year', there were this many reports with"
			display "non-zero uncompensated care charges before Apr 30 2003"
			count if chguccare!=0 & fy_end_dt < mdy(4,30,2003)
			
			replace chguccare = . if fy_end_dt < mdy(4,30,2003)
		}
	
		gen year = `year'
		
		gen fmt = `fmt'
		
		save output/merged`year'_`fmt'.dta, replace
	}
	
	* some years have multiple files of cost reports because they are reported in
	* 1996 and 2010 formats
	* append together the cost reports for each year and save as one file
	
	clear
	foreach fmt in `formats' {
		if (_N==0) {
			use output/merged`year'_`fmt'.dta
		}
		else {
			append using output/merged`year'_`fmt'.dta
		}
		
		rm output/merged`year'_`fmt'.dta
	}
	
	save output/merged`year'.dta, replace
	clear

}


* append together the cost reports for all the years

forvalues year=$STARTYEAR/$ENDYEAR {
	if (_N==0) {
		use output/merged`year'.dta
	}
	else {
		append using output/merged`year'.dta
	}
	
	rm output/merged`year'.dta

}

isid rpt_rec_num year

rename prvdr_num pn

* some dollar flow variables we generate ourselves from variables in the
* reports

gen income = netpatrev + othinc
gen totcost = opexp + othexp

gen margin = (income-totcost)/income

egen prog_chg = rowtotal( prog_rt_chg prog_net_chg )
gen ccr_prog = prog_op_cost/prog_chg ///
	if prog_op_cost>0 & !missing(prog_op_cost) & prog_chg>0 & !missing(prog_chg)

gen uccare_chg_harmonized = chguccare if fmt==96
replace uccare_chg_harmonized = totinitchcare-ppaychcare+nonmcbaddebt if fmt==10

gen uccare_cost_harmonized = ccr*uccare_chg_harmonized

sort pn year fy_bgn_dt fmt
order rpt_rec_num pn year fy_bgn_dt fmt

label data "cms hospital cost report data"

label var year "year"
label var fmt "report format (96=1996 10=2010)"

* label the variables
foreach var of varlist `type_dollar_flow' `type_flow' `type_stock' {
	label var `var' "`LABEL_`var''"
}

label var income "total income (sum of netpatrev and othinc)"
label var totcost "total cost (sum of opexp and othexp)"
label var margin "total all-payer margin i.e. profit margin (income-totcost)/income"
label var uccare_chg_harmonized "uncompensated care charges (harmonized across formats)"
label var uccare_cost_harmonized "uncompensated care costs (harmonized across formats)"
label var prog_chg "medicare inpatient program charges (routine service + ancillary)"
label var ccr_prog "medicare inpatient program cost to charge ratio"

order ///
	rpt_rec_num pn year fmt fy_bgn_dt fy_end_dt rpt_stus_cd proc_dt ///
	`type_stock' ccr_prog ///
	`type_flow' prog_chg ///
	income totcost margin ///
	uccare_chg_harmonized uccare_cost_harmonized ///
	`type_dollar_flow'

compress

save output/hcris_merged.dta, replace
saveold output/hcris_merged.v12.dta, replace version(11)
export delimited output/hcris_merged.csv, replace

log close

quietly {
    log using output/hcris_merged_codebook.txt, text replace
    noisily describe, fullnames
    log close
}

log using hcris.log, append


* now construct the hospital-year synthetic file

* apportion each report to the years it spans

rename year hcris_year

gen year_base = year(fy_bgn_dt)
gen years_spanned = year(fy_end_dt) - year(fy_bgn_dt) + 1
isid rpt_rec_num hcris_year
expand years_spanned

egen seq = seq(), from(0) by(rpt_rec_num hcris_year)
gen year = year_base+seq
drop year_base seq

* days of the target year covered by the cost report
assert year(fy_bgn_dt)<=year & year(fy_end_dt)>=year
gen first_day_in_year = max(mdy(1,1,year),fy_bgn_dt)
format first_day_in_year %td
gen last_day_in_year = min(mdy(12,31,year),fy_end_dt)
format last_day_in_year %td

gen days_in_year = last_day_in_year-first_day_in_year+1
gen days_spanned = fy_end_dt-fy_bgn_dt+1

* share of the report's days that fell into the target year
gen frac_rpt_in_year = days_in_year/days_spanned
egen totfrac = sum(frac_rpt_in_year), by(rpt_rec_num hcris_year)
assert totfrac==1
drop totfrac

* share of the target year's days that were covered by the report
gen double frac_year_covered = days_in_year/(mdy(12,31,year)-mdy(1,1,year)+1)

gen nreports = 1
gen nfmt96 = fmt==96
gen nfmt10 = fmt==10

* did report exclude uncompensated care data?
* "Complete lines 17 through 32 for cost reporting periods ending on or after April 30, 2003."
* - Medicare v1996 documentation section 3609.4
gen nno_uncomp = fy_end_dt<mdy(4,30,2003)

* collapse flow variables to the hospital-year level
* scale them by the share of the target year's days covered by the report
* to scale, we use the 'share target year's days covered' variable as an
* importance weight - iweights are not normalized in collapse (sum)
preserve

collapse ///
	(sum) ///
	`type_flow' ///
	`type_dollar_flow' ///
	income totcost ///
	uccare_chg_harmonized uccare_cost_harmonized ///
	[iweight=frac_rpt_in_year], ///
	by(pn year)

sort pn year
tempfile collapsed_flows
save `collapsed_flows'

restore

* collapse stock variables to the hospital-year level
* we produce three versions: weighted (by fraction of target year covered),
* min, and max

foreach stat in wtd min max {

	if ("`stat'"=="wtd") {
		local collapse_stat "mean"
		local collapse_weight "[aweight=frac_year_covered]"
	}
	else {
		local collapse_stat "`stat'"
		local collapse_weight ""
	}
	
	preserve
	
	collapse ///
		(`collapse_stat') ///
		`type_stock' ///
		`collapse_weight', ///
		by(pn year)
	
	* add postfix to the vars
	rename (`type_stock') =_`stat'
	
	sort pn year
	tempfile collapsed_stocks_`stat'
	save `collapsed_stocks_`stat''
	
	restore
}

* some variables should never be missing
foreach var of varlist ///
	frac_year_covered nreports nfmt96 nfmt10 nno_uncomp ///
	first_day_in_year last_day_in_year ///
	pn year ///
{
	assert !missing(`var')
}

* make missing values flags so we can reset collapsed variables to missing,
* since collapse does not track missing values

* first for flow and dollar flow variables
foreach var of varlist ///
	`type_flow' ///
	`type_dollar_flow' ///
	income totcost ///
	uccare_chg_harmonized uccare_cost_harmonized ///
{
	generate miss_`var' = missing(`var')
}

* then for each stat of each stock variable
foreach var of varlist `type_stock' {
	foreach stat in wtd min max {
		generate miss_`var'_`stat' = missing(`var')
	}
}


* now go down to the hospital-year level
* we take the report stats (e.g. frac year covered, number of reports)
* and the missing indicators

collapse ///
	(sum) frac_year_covered nreports nfmt96 nfmt10 nno_uncomp ///
	(min) covg_begin_dt=first_day_in_year ///
	(max) covg_end_dt=last_day_in_year ///
	(max) miss_*, ///
	by(pn year)

* merge in previously collapsed flow and stock variables

foreach collapsed_file in ///
	collapsed_flows collapsed_stocks_wtd ///
	collapsed_stocks_min collapsed_stocks_max ///
{
	merge 1:1 pn year using ``collapsed_file'', assert(match) nogenerate
}

* we now have, for every stock & flow var, an indicator for whether any
* embodied observation was missing

* replace variables as missing if any of the embodied observations in the
* collapsed value were missing

foreach missvar of varlist miss_* {
	local basevar = regexr("`missvar'","^miss_","")
	replace `basevar' = . if `missvar'
	drop `missvar'
}

* get rid of years outside the startyear / endyear window
* (some reports in the endyear file run through the following year)
drop if year < $STARTYEAR_HY | year > $ENDYEAR_HY

* indicators for whether the year was under-covered or over-covered by
* the embodied reports
* use a tolerance of 0.0001 just in case there is an error due to precision
gen byte flag_short = frac_year_covered<(1-0.0001)
gen byte flag_long = frac_year_covered>(1+0.0001)

gen margin = (income-totcost)/income

egen prog_chg = rowtotal(prog_rt_chg prog_net_chg)
gen ccr_prog = prog_op_cost/prog_chg ///
	if prog_op_cost>0 & !missing(prog_op_cost) & prog_chg>0 & !missing(prog_chg)

sort pn year

label data "cms hospital cost report data (synthetic calendar year)"

label var year "year"

foreach var of varlist `type_dollar_flow' `type_flow' {
	label var `var' "`LABEL_`var''"
}

foreach base in `type_stock' {
	label var `base'_wtd "`LABEL_`base'' (weighted avg over reports)"
	label var `base'_min "`LABEL_`base'' (min of reports)"
	label var `base'_max "`LABEL_`base'' (max of reports)"
}

label var income "total income (sum of netpatrev and othinc)"
label var totcost "total cost (sum of opexp and othexp)"
label var margin "total all-payer margin i.e. profit margin (income-totcost)/income"
label var uccare_chg_harmonized "uncompensated care charges (harmonized across formats)"
label var uccare_cost_harmonized "uncompensated care costs (harmonized across formats)"
label var prog_chg "medicare inpatient program charges (routine service + ancillary)"
label var ccr_prog "medicare inpatient program cost to charge ratio"

label var frac_year_covered "sum of days in reports / days in year"
label var nreports "number of cost reports included in row"
label var nfmt96 "number of 1996 format cost reports included in row"
label var nfmt10 "number of 2010 format cost reports included in row"
label var nno_uncomp "number of cost reports included in row that lack uncompensated care data"
label var covg_begin_dt "first day in year with cost report coverage in row"
label var covg_end_dt "last day in year with cost report coverage in row"
label var flag_short "flag for fewer total days in cost reports than days in year"
label var flag_long "flag for more total days in cost reports than days in year"

* order the variables
* by using a series of order statements and the last option, we treat the
* order like a stack, shifting variables off the bottom of the stack and
* pushing them onto the end. we shift all variables off so this will totally
* re-order the stack in the order we specify

* so pn year will come first, ultimately
order pn year, last

* then the stock variables
foreach base in `type_stock' {
	order `base'_wtd `base'_min `base'_max, last
}

order ccr_prog, last

* then the flow variables
order ///
	`type_flow' ///
	income totcost margin ///
	uccare_chg_harmonized uccare_cost_harmonized ///
	`type_dollar_flow' prog_chg, ///
	last

* finally the report stats
order ///
	nreports nfmt96 nfmt10 nno_uncomp ///
	frac_year_covered covg_begin_dt covg_end_dt flag_short flag_long, ///
	last

compress

save output/hcris_merged_hospyear.dta, replace
saveold output/hcris_merged_hospyear.v12.dta, replace version(11)
export delimited output/hcris_merged_hospyear.csv, replace

log close

quietly {
    log using output/hcris_merged_hospyear_codebook.txt, text replace
    noisily describe, fullnames
    log close
}

log using hcris.log, append

log close
