# hcris.R
# process the CMS cost reports, producing one report-level file and another
# synthetic hospital-calendar year file

library(tidyverse)
library(arrow)
library(duckdb)
library(readxl)
library(labelled)

# use cost reports from these years' data files
START_YEAR <- 1996
END_YEAR <- 2024

# with files from those years, we often (~50% of hospitals) don't observe
# reports covering the full calendar STARTYEAR. and often don't observe (~20%
# of hospitals) reports covering the full calendar ENDYEAR.
# so we shrink the extents of the hospital-year file.
START_AYEAR <- START_YEAR+1
END_AYEAR <- END_YEAR-1

# function to determine when a hospital-year starts. assume calendar year:
START_AYEAR_DATE <- function (y) { make_date(y,1,1) }
END_AYEAR_DATE <- function (y) { make_date(y,12,31) }

# this would do federal fiscal years
#AYEAR_START_DATE <- function (y) { make_date(y-1,10,1) }
#AYEAR_END_DATE <- function (y) { make_date(y,9,30) }


# where are the parquets?
STORE <- "./store"

# make the output folder if it doesn't exist
dir.create("./output", showWarnings = FALSE)

# import the lookup table
print("Importing the lookup table")
lookup_table <- read_excel("lookup.xlsx",sheet="Lookup Table")

if (
  lookup_table |> 
    select(wksht_cd,clmn_num,line_num_start,line_num_end,fmt) |> 
    anyDuplicated()
) {
  stop("duplicates in lookup table")
}

if (anyNA(lookup_table$line_num_start)) {
  stop("missing values in line_num_start")
}

# fill in missing ending line numbers
lookup_table <- lookup_table |>
    mutate(line_num_end = coalesce(line_num_end,line_num_start))

# make line and col numbers numeric, fmt numeric, enabled logical
lookup_table <- lookup_table |>
  mutate_at(c("clmn_num","line_num_start","line_num_end","fmt"),as.integer) |>
  mutate_at("enabled",as.logical)

# reduce to enabled variables
lookup_table <- lookup_table |>
  filter(enabled)

# variable types and labels
type_label <- read_excel("lookup.xlsx",sheet="Type and Label")
type_label <- type_label |> mutate_at("type",as.factor)

# vectors of the variable types
var_types <- c("stock","flow","dollar_flow","alpha")
vars <- sapply(var_types,\(v) filter(type_label,type==v)$rec)

items_wide <- function(ftype) {

  if (!(ftype %in% c("nmrc","alph"))) {
    stop("ftype must be nmrc or alph")
  }

  # bring in the data (values)
  items_pq <- open_dataset(paste(STORE,"/",ftype,sep=""))
  
  # fix up the file for merging
  items_long <- items_pq |>
    filter(year>=START_YEAR & year<=END_YEAR) |> # limit to processing years
    # some column numbers have characters, which won't convert to int. set to NA
    mutate(clmn_num = if_else(grepl("[A-Z]",clmn_num),NA,clmn_num)) |>
    mutate(across(c("clmn_num","line_num"),as.integer))

  # merge with the lookup table
  print(paste0("Merging ",ftype," data with lookup table"))
  
  by_complete <-
    join_by(wksht_cd,clmn_num,between(line_num,line_num_start,line_num_end),fmt)
  lookup_table_duckdb <- lookup_table |> to_duckdb()
  result_long <- items_long |>
    to_duckdb() |>
    inner_join(lookup_table_duckdb,by_complete) |>
    select(rpt_rec_num,any_of("itm_val_num"),any_of("itm_val_str"),rec) |>
    collect()
  
  # collapse nmrc to report-record level taking sums
  if (ftype=="nmrc") {
    
    if (anyNA(result_long$itm_val_num)) {
      stop("missing value in itm_val_num")
    }
    
    print("Collapsing to report-record level")
    result_long <- result_long |>
      group_by(rpt_rec_num,rec) |>
      summarize(val=sum(itm_val_num),.groups="drop")
  } else {

    if (anyNA(result_long$itm_val_str)) {
      stop("missing value in itm_val_str")
    }
    
    # in alph file, report-rec must already be unique id
    if (
      result_long |>
      group_by(rpt_rec_num,rec) |>
      summarize(n=n(),.groups="keep") |>
      filter(n>1) |>
      nrow()
    ) {
      stop("in alph file, rpt_rec_num,rec was not a unique id")
    }
    
    result_long <- result_long |> rename(val=itm_val_str)
  }
  

  # pivot to one row per record, reshape to one row per report, and return
  print("Pivoting to one row per record")
  result_long |>
    pivot_wider(names_from=rec,values_from=val) |>
    collect()
}

items_nmrc <- items_wide("nmrc")
items_alph <- items_wide("alph")

# process report index file
rpt_pq <- open_dataset(paste(STORE,"/rpt",sep=""))

# merge with the results from the numeric and alpha files
print("Merging in report index file")
hcris_rpt <- rpt_pq |>
  filter(year>=START_YEAR & year<=END_YEAR) |> # limit to processing years
  left_join( # bring in numeric items
    items_nmrc,
    join_by(rpt_rec_num),
    unmatched="error",
    relationship="one-to-one"
  ) |>
  left_join( # bring in alpha items
    items_alph,
    join_by(rpt_rec_num),
    unmatched="error",
    relationship="one-to-one"
  ) |>
  rename(pn=prvdr_num) |>
  collect()

# now we can delete the items from nmrc/alph
rm(items_nmrc,items_alph)

print("Processing variables")

# zero out $ variables if they were blank and make indicators for doing so
vars_zero_out <- intersect(vars$dollar_flow,names(hcris_rpt))
hcris_rpt <- hcris_rpt |>
  mutate(across(all_of(vars_zero_out),is.na,.names="{.col}.was.na")) |>
  mutate(across(all_of(vars_zero_out),~ coalesce(.x,0)))

# make rpt_stus_cd a factor
hcris_rpt <- hcris_rpt |>
  mutate(rpt_stus_cd = as.factor(rpt_stus_cd))

# add some dollar flow vars we generate ourselves
hcris_rpt <- hcris_rpt |>
  mutate(
    income = netpatrev+othinc,
    totcost = opexp+othexp,
    margin = (income-totcost)/income,
    prog_chg = prog_rt_chg+prog_net_chg,
    ccr_prog = if_else(
      prog_op_cost > 0 & prog_chg > 0,
      prog_op_cost/prog_chg,
      NA
    ),
    uccare_chg_harmonized = case_when(
      fmt==96 ~ chguccare,
      fmt==10 ~ totinitchcare-ppaychcare+nonmcbaddebt,
      .default=NA
    ),
    uccare_cost_harmonized = ccr*uccare_chg_harmonized
  )
vars$dollar_flow <- vars$dollar_flow |>
  c("income","totcost","prog_chg",
    "uccare_chg_harmonized","uccare_cost_harmonized"
  )

# sort the data
hcris_rpt <- hcris_rpt |> arrange(pn,year,fy_bgn_dt,fmt)

# order the columns
hcris_rpt <- hcris_rpt |>
  relocate(
    rpt_rec_num,pn,year,fmt,fy_bgn_dt,fy_end_dt,rpt_stus_cd,proc_dt,
    intersect(vars$alpha,names(hcris_rpt)),
    intersect(vars$stock,names(hcris_rpt)),ccr_prog,
    intersect(vars$flow,names(hcris_rpt)),
    intersect(vars$dollar_flow,names(hcris_rpt)),margin,
    paste(vars_zero_out,".was.na",sep="")
)

# label the variables
label_list <- split(x=type_label$label,f=type_label$rec)
var_label(hcris_rpt) <- list(
  rpt_rec_num="Report Record Number",
  pn="Provider Number",
  year="year",
  fmt="report format (96=1996 10=2010)",
  fy_bgn_dt="Fiscal Year Begin Date",
  fy_end_dt="Fiscal Year End Date",
  rpt_stus_cd="Report Status Code",
  proc_dt="Process Date",
  ccr_prog="medicare inpatient program cost to charge ratio",
  income="total income (sum of netpatrev and othinc)",
  totcost="total cost (sum of opexp and othexp)",
  prog_chg="medicare inpatient program charges (routine service + ancillary)",
  uccare_chg_harmonized="uncompensated care charges (harmonized across formats)",
  uccare_cost_harmonized="uncompensated care costs (harmonized across formats)",
  margin="total all-payer margin i.e. profit margin (income-totcost)/income"
)
var_label(hcris_rpt) <- c(
  label_list[intersect(vars$alpha,names(hcris_rpt))],
  label_list[intersect(vars$stock,names(hcris_rpt))],
  label_list[intersect(vars$flow,names(hcris_rpt))],
  label_list[vars_zero_out]
)

labels.was.na <- sapply(
  vars_zero_out,
  \(v) paste("Was",v,"originally missing"),
  simplify=FALSE
)
names(labels.was.na) <- paste(names(labels.was.na),".was.na",sep="")
var_label(hcris_rpt) <- labels.was.na

print("Saving report level file")
save(hcris_rpt,file = "output/hcris_rpt.Rdata")

# now construct the hospital-year synthetic file

# list of hospital-years to be merged with the report data
ayears <- 
  tibble(ayear=START_AYEAR:END_AYEAR) |>
  mutate(
    ayear_start = START_AYEAR_DATE(ayear),
    ayear_end = END_AYEAR_DATE(ayear)
  )
#|> as.data.table()

# merge together the files
print("Interacting reports with coverage years")
by_overlap <- join_by(overlaps(fy_bgn_dt,fy_end_dt,ayear_start,ayear_end))
hcrisXyear <- hcris_rpt |>
  rename(fyear=year) |>
  inner_join(ayears,by_overlap)

# calculate relevant variables to conduct apportionment of report to years
hcrisXyear <- hcrisXyear |>
  mutate(
      report_interval = interval(fy_bgn_dt,fy_end_dt),
      ayear_interval = interval(ayear_start,ayear_end),
      overlap = intersect(report_interval,ayear_interval),
      days_in_report = report_interval/days(1) + 1,
      days_in_ayear = ayear_interval/days(1) + 1,
      days_overlap = overlap/days(1) + 1,
      share_report_in_ayear = days_overlap/days_in_report,
      share_ayear_in_report = days_overlap/days_in_ayear
  ) |>
  group_by(pn,ayear)
  

vars_wsum_collapse <- intersect(
  union(vars$flow,vars$dollar_flow),
  names(hcrisXyear)
)
vars_wmean_collapse <- intersect(vars$stock,names(hcrisXyear))

vars_first_collapse <- intersect(vars$alpha,names(hcrisXyear))

print("Collapsing to hospital-year level")
hcris_ayear <- hcrisXyear |>
  summarize(
    across( # for strings, take value from first report
      all_of(vars_first_collapse),
      first
    ),
    across( # scale flows by share of report that fell into year
      all_of(vars_wsum_collapse),
      ~ sum(.x*share_report_in_ayear)
    ),
    across( # weight stocks by share of the year that fell into report
      all_of(vars_wmean_collapse),
      ~ weighted.mean(.x,share_ayear_in_report)
    ),
    across( # count number of missings zeroed out
      all_of(paste(vars_zero_out,".was.na",sep="")),
      sum
    ),
    # other report stats
    share_ayear_covered = sum(share_ayear_in_report),
    flag_short = share_ayear_covered < 1,
    flag_long = share_ayear_covered > 1,
    nreports = n(),
    nfmt96 = sum(fmt==96),
    nfmt10 = sum(fmt==10),
    covg_begin_dt = min(int_start(overlap)),
    covg_end_dt = max(int_end(overlap)),
    .groups="drop"
  )

print("Saving hospital-year level file")
save(hcris_ayear,file = "output/hcris_hospyear.Rdata")
