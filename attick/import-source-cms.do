* import-source-cms.do
* convert source HCRIS data from CMS into stata format for further processing

set more off
capture log close
clear
log using import-source-cms.log, replace

* process cost reports from these years' data files
global STARTYEAR = 1996
global ENDYEAR = 2022

* where is the source data?
global SOURCE_BASE "./source"

* delete the CSV files after processing them?
global DELETE_CSV = 1

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
		
		// load the report data
		import delimited ///
			rpt_rec_num ///
			prvdr_ctrl_type_cd ///
			prvdr_num ///
			npi ///
			rpt_stus_cd ///
			fy_bgn_dt ///
			fy_end_dt ///
			proc_dt ///
			initl_rpt_sw ///
			last_rpt_sw ///
			trnsmtl_num ///
			fi_num ///
			adr_vndr_cd ///
			fi_creat_dt ///
			util_cd ///
			npr_dt ///
			spec_ind ///
			fi_rcpt_dt ///
		using "$SOURCE_BASE/hosp_rpt2552_`fmt'_`year'.csv", ///
			stringcols(3) varnames(nonames)
		
		// process date variables
		tempvar temp_date
		foreach var of varlist *_dt {
			gen `temp_date' = date(`var',"MDY")
			format `temp_date' %tdD_m_Y 
			drop `var'
			rename `temp_date' `var'
		}
		
		// recode the switch variables to dummies
		// occasionally the switch is set to X, code to -1
		foreach var of varlist *_sw {
			replace `var' = "1" if `var'=="Y"
			replace `var' = "0" if `var'=="N"
			// sometimes last report switch is X?
			replace `var' = "-1" if `var'=="X"
			assert inlist(`var',"0","1","-1","")
			destring `var', replace
		}
		
		// make the utilization code numeric
		// apparently blank means full utilization. set to 5
		replace util_cd = "2" if util_cd=="L"
		replace util_cd = "3" if util_cd=="N"
		replace util_cd = "4" if util_cd=="F"
		replace util_cd = "5" if util_cd==""
		assert inlist(util_cd,"2","3","4","5")
		destring util_cd, replace
		
		// bring in labels for variables
		// based on Jean Roth's code
		// https://data.nber.org/docs/hcris/read_hosp_rpt.sas
		// + HCRIS documentation
		
		// NB: couldn't find the def of this field in HCRIS docs, but this
		// is how it was labeled in Jean's code
		label define prvdr_ctrl_type_cd ///
			1 "1 Voluntary Nonprofit, Church" ///
			2 "2 Voluntary Nonprofit, Other" ///
			3 "3 Proprietary, Individual" ///
			4 "4 Proprietary, Corporation" ///
			5 "5 Proprietary, Partnership" ///
			6 "6 Proprietary, Other" ///
			7 "7 Governmental, Federal" ///
			8 "8 Governmental, City-County" ///
			9 "9 Governmental, County" ///
			10 "10 Governmental, State" ///
			11 "11 Governmental Hospital District" ///
			12 "12 Governmental, City" ///
			13 "13 Governmental, Other"
		
		label define rpt_stus_cd ///              
			1 "1 As Submitted" ///
			2 "2 Settled w/o Audit" ///
			3 "3 Settled with Audit" ///
			4 "4 Reopened" ///
			5 "5 Amended"
		
		label define initl_rpt_sw ///
			1 "Y first cost report filed for this provider" ///
			0 "N 2nd+ report for this provider" ///
			-1 "X unknown value"
		
		label define last_rpt_sw ///
			1 "Y last cost report filed for this provider" ///
			0 "N not last report for this provider" ///
			-1 "X unknown value"
		
		label define adr_vndr_cd ///
			2 "2 E & Y" ///
			3 "3 KPMG" ///
			4 "4 HFS"
		
		label define util_cd ///
			2 "L Low Medicare Util" ///
			3 "N No Medicare Util" ///
			4 "F Full Medicare Util" ///
			5 "(blank) Full Medicare Util"
		
		// apply labels
		foreach l in prvdr_ctrl_type_cd rpt_stus_cd initl_rpt_sw last_rpt_sw adr_vndr_cd util_cd {
			label values `l' `l'
		}
		
		// label variables based on HCRIS documentation
		label variable adr_vndr_cd "Automated Desk Review Vendor Code"
		label variable fi_creat_dt "Fiscal Intermediary Create Date"
		label variable fi_num "Fiscal Intermediary Number"
		label variable fi_rcpt_dt "Fiscal Intermediary Receipt Date"
		label variable fy_bgn_dt "Fiscal Year Begin Date"
		label variable fy_end_dt "Fiscal Year End Date"
		label variable initl_rpt_sw "Initial Report Switch"
		label variable last_rpt_sw "Last Report Switch"
		label variable npr_dt "Notice of Program Reimbursement Date"
		label variable npi "National Provider Identifier"
		label variable proc_dt "Process Date"
		label variable prvdr_ctrl_type_cd "Provider Control Type Code"
		label variable prvdr_num "Provider Number"
		label variable rpt_rec_num "Report Record Number"
		label variable rpt_stus_cd "Report Status Code"
		label variable spec_ind "Special Indicator"
		label variable trnsmtl_num "The current transmittal or version number in effect for each sub-system."
		label variable util_cd "Utilization Code"
				
		compress
		
		save "$SOURCE_BASE/hosp_rpt2552_`fmt'_`year'.dta", replace
		clear
		
		// import the numeric fields
		import delimited ///
			rpt_rec_num ///
			wksht_cd ///
			line_num ///
			clmn_num ///
			itm_val_num ///
		using "$SOURCE_BASE/hosp_nmrc2552_`fmt'_`year'_long.csv", ///
			numericcols(1 5) stringcols(2 3 4) asdouble varnames(nonames)

		// label the variables based on HCRIS documentation
		label variable clmn_num "Column Number"
		label variable itm_val_num "Item Value Number"
		label variable line_num "Line Number"
		label variable rpt_rec_num "Report Record Number"
		label variable wksht_cd "Worksheet Identifier"
			
		compress
		save "$SOURCE_BASE/hosp_nmrc2552_`fmt'_`year'_long.dta", replace
		clear
		
		if ($DELETE_CSV) {
			rm "$SOURCE_BASE/hosp_rpt2552_`fmt'_`year'.csv"
			rm "$SOURCE_BASE/hosp_nmrc2552_`fmt'_`year'_long.csv"
		}
	}
}

log close
	
