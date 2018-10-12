set more off
capture log close
clear
log using hcris.log, replace

global STARTYEAR = 2000
global ENDYEAR = 2015

* import the lookup table
import excel using misc/lookup.xlsx, firstrow
tempfile lookup

save `lookup'

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
	
		use rpt_rec_num itm_val_num wksht_cd clmn_num line_num ///
			if inlist(wksht_cd,"G300000","G200000","S100000","S300001") ///
			using source/hosp_nmrc2552_`fmt'_`year'_long.dta
	
		// identify the variables we need and label the rows
		
		// merge with the lookup table
		gen fmt = `fmt'
		merge m:1 wksht_cd clmn_num line_num fmt using `lookup', ///
			keep(match) nogenerate
		
		// drop entries we've disabled
		drop if enabled==0
		
		drop enabled fmt

		keep rpt_rec_num rec itm_val_num

		// reshape to one row per report
		rename itm_val_num val_
		reshape wide val, i(rpt_rec_num) j(rec) string
		
		// charity care vars differ between versions. create blank variables
		
		if (`fmt'==10 | (`fmt'==96 & `year' < 2002)) {
			foreach var in chguccare {
				gen val_`var' = .
			}
		}
		if (`fmt'==96) {
			foreach var in totinitchcare ppaychcare nonmcbaddebt costuccare_v2010 {
				gen val_`var' = .
			}
		}
		
		// zero out $ variables if they were blank
		foreach var in ///
			netpatrev othinc opexp othexp donations invinc ///
			iphosprev ipgenrev ipicrev iprcrev ipancrev ipoprev iptotrev ///
			opancrev opoprev optotrev tottotrev ///
			chguccare totinitchcare ppaychcare nonmcbaddebt costuccare_v2010 ///
			{
			rename val_`var' `var'
			replace `var' = 0 if `var'==.
		}
		
		* don't zero out CCR & beds variables
		foreach var in ///
			ccr beds_adultped availbeddays_adultped ipbeddays_adultped ///
			ipdischarges_adultped beds_totadultped beds_total ///
			{
			rename val_`var' `var'
		}
	
		// save for merging into report level data
		tempfile nmrc
		save `nmrc', replace

		clear
	
		// process report index file
		use source/hosp_rpt2552_`fmt'_`year'
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

isid rpt_rec_num

rename prvdr_num pn

gen income = netpatrev + othinc
gen totcost = opexp + othexp

gen margin = (income-totcost)/income

gen uccare_chg_harmonized = chguccare if fmt==96
replace uccare_chg_harmonized = totinitchcare-ppaychcare+nonmcbaddebt if fmt==10

gen uccare_cost_harmonized = ccr*uccare_chg_harmonized

sort pn year fy_bgn_dt fmt
order rpt_rec_num pn year fy_bgn_dt fmt

label var year "year"
label var fmt "report format (96=1996 10=2010)"
label var beds_adultped "beds - adults & peds"
label var availbeddays_adultped "bed days available in rpt period"
label var ipbeddays_adultped "inpatient bed days utilized"
label var ipdischarges_adultped "inpatient discharges"
label var beds_totadultped "beds - total adults & peds incl swing beds"
label var beds_total "beds - total (inc swing + spec care beds e.g. icu, ccu, nicu)"
label var donations "donations"
label var invinc "investment income"
label var iphosprev "inpatient hospital revenue"
label var ipgenrev "inpatient general revenue (total of hosp, ipf, irf, snf, etc.)"
label var ipicrev "inpatient intensive care type revenue (total of icu, ccu, etc.)"
label var iprcrev "inpatient routine care revenue (sum of ipgenrev and ipicrev)"
label var ipancrev "inpatient ancillary services revenue"
label var ipoprev "inpatient outpatient services revenue"
label var iptotrev "inpatient total patient revenue"
label var opancrev "outpatient ancillary services revenue"
label var opoprev "outpatient outpatient services revenue"
label var optotrev "outpatient total patient revenues"
label var tottotrev "total patient revenue (sum of iptotrev and optotrev)"
label var ccr "cost to charge ratio"
label var chguccare "other uncompensated care charges (1996 format only)"
label var totinitchcare "total initial obligation of patients for charity care (2010 format only)"
label var ppaychcare "partial payment by patients approved for charity care (2010 format only)"
label var nonmcbaddebt "non-medicare & non-reimbursable medicare bad debt expense (2010 format only)"
label var costuccare_v2010 "cost of uncompensated care (2010 format only)"
label var netpatrev "net patient revenues (total revenues minus allowances & discounts)"
label var othinc "other income"
label var opexp "total operating expenses"
label var othexp "total other expenses"
label var income "total income (sum of netpatrev and othinc)"
label var totcost "total cost (sum of opexp and othexp)"
label var margin "total all-payer margin i.e. profit margin (income-totcost)/income"
label var uccare_chg_harmonized "uncompensated care charges (harmonized across formats)"
label var uccare_cost_harmonized "uncompensated care costs (harmonized across formats)"

order ///
	rpt_rec_num pn year fmt fy_bgn_dt fy_end_dt rpt_stus_cd proc_dt ///
	beds_adultped beds_totadultped beds_total ///
	availbeddays_adultped ipbeddays_adultped ipdischarges_adultped ///
	income totcost margin ///
	uccare_chg_harmonized uccare_cost_harmonized ///
	netpatrev othinc opexp othexp donations invinc ///
	iphosprev ipgenrev ipicrev iprcrev ipancrev ipoprev iptotrev ///
	opancrev opoprev optotrev ///
	tottotrev ///
	ccr chguccare totinitchcare ppaychcare nonmcbaddebt costuccare_v2010  

save output/hcris_merged.dta, replace

* now construct the hospital-year synthetic file

* apportion each report to the years it spans

rename year hcris_year

gen year_base = year(fy_bgn_dt)
gen years_spanned = year(fy_end_dt) - year(fy_bgn_dt) + 1
isid rpt_rec_num
expand years_spanned

egen seq = seq(), from(0) by(rpt_rec_num)
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
egen totfrac = sum(frac_rpt_in_year), by(rpt_rec_num)
assert totfrac==1
drop totfrac

* share of the target year's days that were covered by the report
gen double frac_year_covered = days_in_year/(mdy(12,31,year)-mdy(1,1,year)+1)

* scale the flows by the share of the report that was in the target year
foreach var of varlist ///
	availbeddays_adultped ipbeddays_adultped ipdischarges_adultped ///
	donations invinc netpatrev opexp othexp othinc income totcost ///
	iphosprev ipgenrev ipicrev iprcrev ipancrev ipoprev iptotrev ///
	opancrev opoprev optotrev tottotrev ///
	chguccare totinitchcare ppaychcare nonmcbaddebt costuccare_v2010 ///
	uccare_chg_harmonized uccare_cost_harmonized ///
	{
	replace `var' = `var'*frac_rpt_in_year
}

gen nreports = 1
gen nfmt96 = fmt==96
gen nfmt10 = fmt==10

* did report exclude uncompensated care data?
* "Complete lines 17 through 32 for cost reporting periods ending on or after April 30, 2003."
* - Medicare v1996 documentation section 3609.4
gen nno_uncomp = fy_end_dt<mdy(4,30,2003)

* make weighted averages of the CCR & bed counts from the reports
* each report gets weight: fraction of target year covered
foreach var of varlist ccr beds_* {
	egen `var'_wtd = wtmean(`var'), weight(frac_year_covered) by(pn year)
}

* down to the hospital-year level

collapse ///
	(sum) ///
	availbeddays_adultped ipbeddays_adultped ipdischarges_adultped ///
	donations invinc netpatrev opexp othexp othinc income totcost ///
	iphosprev ipgenrev ipicrev iprcrev ipancrev ipoprev iptotrev ///
	opancrev opoprev optotrev tottotrev ///
	chguccare totinitchcare ppaychcare nonmcbaddebt costuccare_v2010 ///
	uccare_chg_harmonized uccare_cost_harmonized ///
	frac_year_covered nreports nfmt96 nfmt10 nno_uncomp ///
	(min) covg_begin_dt=first_day_in_year ccr_min=ccr beds_total_min=beds_total ///
	(max) covg_end_dt=last_day_in_year ccr_max=ccr beds_total_max=beds_total ///
	(mean) ccr_wtd beds_*_wtd, ///
	by(pn year)

* get rid of years outside the startyear / endyear window
* (some reports in the endyear file run through the following year)
drop if year < $STARTYEAR | year > $ENDYEAR

gen byte flag_short = frac_year_covered<1
gen byte flag_long = frac_year_covered>1

gen margin = (income-totcost)/income

sort pn year

label var year "year"
label var beds_adultped_wtd "beds - adults & peds (weighted avg over reports)"
label var beds_totadultped_wtd "beds - total adults & peds incl swing beds (weighted avg over reports)"
label var beds_total_wtd "beds - total (inc swing + spec care beds e.g. icu, ccu, nicu) (weighted avg over reports)"
label var beds_total_min "beds - total (inc swing + spec care beds e.g. icu, ccu, nicu) (min of reports)"
label var beds_total_max "beds - total (inc swing + spec care beds e.g. icu, ccu, nicu) (max of reports)"
label var availbeddays_adultped "bed days available in rpt period"
label var ipbeddays_adultped "inpatient bed days utilized"
label var ipdischarges_adultped "inpatient discharges"
label var donations "donations"
label var invinc "investment income"
label var iphosprev "inpatient hospital revenue"
label var ipgenrev "inpatient general revenue (total of hosp, ipf, irf, snf, etc.)"
label var ipicrev "inpatient intensive care type revenue (total of icu, ccu, etc.)"
label var iprcrev "inpatient routine care revenue (sum of ipgenrev and ipicrev)"
label var ipancrev "inpatient ancillary services revenue"
label var ipoprev "inpatient outpatient services revenue"
label var iptotrev "inpatient total patient revenue"
label var opancrev "outpatient ancillary services revenue"
label var opoprev "outpatient outpatient services revenue"
label var optotrev "outpatient total patient revenues"
label var tottotrev "total patient revenue (sum of iptotrev and optotrev)"
label var ccr_wtd "cost to charge ratio (weighted avg over reports)"
label var ccr_min "cost to charge ratio (min of reports)"
label var ccr_max "cost to charge ratio (max of reports)"
label var chguccare "other uncompensated care charges (1996 format only)"
label var totinitchcare "total initial obligation of patients for charity care (2010 format only)"
label var ppaychcare "partial payment by patients approved for charity care (2010 format only)"
label var nonmcbaddebt "non-medicare & non-reimbursable medicare bad debt expense (2010 format only)"
label var costuccare_v2010 "cost of uncompensated care (2010 format only)"
label var netpatrev "net patient revenues (total revenues minus allowances & discounts)"
label var othinc "other income"
label var opexp "total operating expenses"
label var othexp "total other expenses"
label var income "total income (sum of netpatrev and othinc)"
label var totcost "total cost (sum of opexp and othexp)"
label var margin "total all-payer margin i.e. profit margin (income-totcost)/income"
label var uccare_chg_harmonized "uncompensated care charges (harmonized across formats)"
label var uccare_cost_harmonized "uncompensated care costs (harmonized across formats)"

label var frac_year_covered "sum of days in reports / days in year"
label var nreports "number of cost reports included in row"
label var nfmt96 "number of 1996 format cost reports included in row"
label var nfmt10 "number of 2010 format cost reports included in row"
label var nno_uncomp "number of cost reports included in row that lack uncompensated care data"
label var covg_begin_dt "first day in year with cost report coverage in row"
label var covg_end_dt "last day in year with cost report coverage in row"
label var flag_short "flag for fewer total days in cost reports than days in year"
label var flag_long "flag for more total days in cost reports than days in year"

order ///
	pn year ///
	beds_adultped_wtd beds_totadultped_wtd beds_total_* ///
	availbeddays_adultped ipbeddays_adultped ipdischarges_adultped ///
	income totcost margin ///
	uccare_chg_harmonized uccare_cost_harmonized ///
	netpatrev othinc opexp othexp donations invinc ///
	iphosprev ipgenrev ipicrev iprcrev ipancrev ipoprev iptotrev ///
	opancrev opoprev optotrev ///
	tottotrev ///
	ccr_* chguccare totinitchcare ppaychcare nonmcbaddebt costuccare_v2010 ///
	nreports nfmt96 nfmt10 nno_uncomp ///
	frac_year_covered covg_begin_dt covg_end_dt flag_short flag_long


save output/hcris_merged_hospyear.dta, replace

log close
