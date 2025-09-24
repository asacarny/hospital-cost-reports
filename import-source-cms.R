# import-source-cms.R
# convert source HCRIS data from CMS into parquet format for further processing

library(tidyverse)
library(arrow)

# last year cost reports are available
FINAL_YEAR <- 2024

# process cost reports from these years
REPORT_EXTENTS <- tribble(
  ~ptype,  ~start_year,  ~end_year,
  "hosp",     1996,         2024,
  "snf",      1995,         2024
)

# where is the source data?
SOURCE_BASE <- "./source"

# where to save the parquet?
STORE <- "./store"

####################################################

if (
  REPORT_EXTENTS |> 
  filter(end_year>FINAL_YEAR) |>
  nrow()
) {
  stop("You're requesting report years after FINAL_YEAR")
}

# make the parquet folder if it doesn't exist
dir.create(STORE, showWarnings = FALSE)

# all potential cost report files
file_master_list <- bind_rows(
  tibble( # 1996 format hospital files
    ptype="hosp",
    year=1996:2011,
    file=paste(
      SOURCE_BASE,
      "/hosp_rpt2552_96_",
      1996:2011,
      ".csv",
      sep=""
    )
  ),
  tibble( # 2010 format hospital files
    ptype="hosp",
    year=2010:FINAL_YEAR,
    file=paste(
      SOURCE_BASE,
      "/hosp_rpt2552_10_",
      2010:FINAL_YEAR,
      ".csv",
      sep=""
    )
  ),
  tibble( # 1996 format SNF files
    ptype="snf",
    year=1995:2012,
    file=paste(
      SOURCE_BASE,
      "/snf_rpt2540_96_",
      1995:2012,
      ".csv",
      sep=""
    )
  ),
  tibble( # 2010 format SNF files
    ptype="snf",
    year=2011:FINAL_YEAR,
    file=paste(
      SOURCE_BASE,
      "/snf_rpt2540_10_",
      2011:FINAL_YEAR,
      ".csv",
      sep=""
    )
  )
)

# report CSV files to load
files_rpt_csv <- file_master_list |>
  inner_join(
    REPORT_EXTENTS,
    join_by(ptype,between(year,start_year,end_year)),
    unmatched=c("drop","error"),
    relationship="many-to-one"
  ) |>
  pull(file)

# report parquet file to save
file_rpt_pq = paste(STORE,"/rpt",sep="")

# set up connection to load CSV files
rpt <- open_dataset(files_rpt_csv,format="csv",schema=schema(
  rpt_rec_num = int32(),
  prvdr_ctrl_type_cd = int8(),
  prvdr_num = string(),
  npi = string(),
  rpt_stus_cd = int8(),
  fy_bgn_dt = string(),
  fy_end_dt = string(),
  proc_dt = string(),
  initl_rpt_sw = string(),
  last_rpt_sw = string(),
  trnsmtl_num = string(),
  fi_num = int32(),
  adr_vndr_cd = int8(),
  fi_creat_dt = string(),
  util_cd = string(),
  npr_dt = string(),
  spec_ind = string(),
  fi_rcpt_dt = string()
))

# process reports
rpt |>
  select(rpt_rec_num,prvdr_num,rpt_stus_cd:proc_dt) |> # only need these vars
  mutate(across(ends_with("_dt"),mdy)) |> # process dates
  mutate(rpt_stus_cd=case_when( # labeled version of report status code
    rpt_stus_cd==1 ~ "1 As Submitted",
    rpt_stus_cd==2 ~ "2 Settled w/o Audit",
    rpt_stus_cd==3 ~ "3 Settled w/ Audit",
    rpt_stus_cd==4 ~ "4 Reopened",
    rpt_stus_cd==5 ~ "5 Amended"
  )) |>
  mutate(filename=add_filename()) |> # fancy footwork to pull year, fmt, ptype
  mutate(year=as.integer(str_sub(filename,-8,-5)),.before=1) |>
  mutate(fmt=as.integer(str_sub(filename,-11,-10)),.before=2) |>
  mutate(ptype=str_remove(str_sub(filename,-24,-21),"/"),.before=3) |>
  select(!filename) |>
  group_by(year,fmt,ptype) |> # partiton by year, fmt, ptype
  write_dataset(path=file_rpt_pq,format="parquet")

# function to process the numeric and alpha files
process_long <- function(ftype) {

  if (!(ftype %in% c("nmrc","alph"))) {
    stop("ftype must be nmrc or alph")
  }
  
  # nmrc/alpha CSV files to load. draw on report file list
  files_csv <- files_rpt_csv |>
    str_replace("_rpt",paste0("_",ftype)) |> # _rpt to _nmrc/_alph
    str_replace("\\.csv","_long.csv") # .csv to _long.csv
  
  # parquet file to save
  file_pq = paste(STORE,"/",ftype,sep="")

  # set up connection to load CSV files
  
  # the schema will depend on whether it's nmrc or alph
  if (ftype=="nmrc") {
    fschema <- schema(
      rpt_rec_num = int32(),
      wksht_cd = string(),
      line_num = string(),
      clmn_num = string(),
      itm_val_num = double()
    )
  } else {
    fschema <- schema(
      rpt_rec_num = int32(),
      wksht_cd = string(),
      line_num = string(),
      clmn_num = string(),
      itm_val_str = string()
    ) 
  }
  
  # now properly open the data
  src <- open_dataset(
    files_csv,
    format="csv",
    schema=fschema
  )

  # process files
  src |>
    mutate(filename=add_filename()) |> # fancy footwork to pull year, fmt, ptype
    mutate(year=as.integer(str_sub(filename,-13,-10)),.before=1) |>
    mutate(fmt=as.integer(str_sub(filename,-16,-15)),.before=2) |>
    mutate(ptype=str_remove(str_sub(filename,-30,-27),"/"),.before=3) |>
    select(!filename) |>
    group_by(year,fmt,ptype) |>
    write_dataset(path=file_pq,format="parquet")  
}

# now process the two sets of files
process_long("nmrc")
process_long("alph")
