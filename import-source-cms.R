# import-source-cms.R
# convert source HCRIS data from CMS into parquet format for further processing

library(tidyverse)
library(arrow)

# process cost reports from these years
START_YEAR <- 1996
END_YEAR <- 2022

# where is the source data?
SOURCE_BASE <- "./source"

# where to save the parquet?
STORE <- "./store"

# make the parquet folder if it doesn't exist
dir.create(STORE, showWarnings = FALSE)

# years with 96 and 10 format data
years_96 <- intersect(START_YEAR:END_YEAR,1996:2011)
years_10 <- (START_YEAR:END_YEAR)[START_YEAR:END_YEAR >= 2010]

# report CSV files to load
files_rpt_csv <- c(
  years_96 |>
    sapply(\(y) paste(SOURCE_BASE,"/hosp_rpt2552_96_",y,".csv",sep="")),
  years_10 |>
    sapply(\(y) paste(SOURCE_BASE,"/hosp_rpt2552_10_",y,".csv",sep=""))
)
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
  mutate(filename=add_filename()) |> # fancy footwork to pull year & fmt
  mutate(year=as.integer(str_sub(filename,-8,-4)),.before=1) |>
  mutate(fmt=as.integer(str_sub(filename,-11,-9)),.before=2) |>
  select(!filename) |>
  group_by(year,fmt) |> # partiton by year and fmt
  write_dataset(path=file_rpt_pq,format="parquet")

# nmrc CSV files to load
files_nmrc_csv <- c(
  years_96 |>
    sapply(\(y) paste(SOURCE_BASE,"/hosp_nmrc2552_96_",y,"_long.csv",sep="")),
  years_10 |>
    sapply(\(y) paste(SOURCE_BASE,"/hosp_nmrc2552_10_",y,"_long.csv",sep=""))
)
# nmrc parquet file to save
file_nmrc_pq = paste(STORE,"/nmrc",sep="")

# set up connection to load CSV files
nmrc <- open_dataset(files_nmrc_csv,format="csv",schema=schema(
  rpt_rec_num = int32(),
  wksht_cd = string(),
  line_num = string(),
  clmn_num = string(),
  itm_val_num = double()
))

# process nmrc files
nmrc |>
  mutate(filename=add_filename()) |> # fancy footwork to pull year & fmt
  mutate(year=as.integer(str_sub(filename,-13,-9)),.before=1) |>
  mutate(fmt=as.integer(str_sub(filename,-16,-14)),.before=2) |>
  select(!filename) |>
  group_by(year,fmt) |>
  write_dataset(path=file_nmrc_pq,format="parquet")

