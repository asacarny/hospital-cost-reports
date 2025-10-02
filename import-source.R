# import-source.R
# convert source HCRIS data from CMS into parquet format for further processing

library(tidyverse)
library(arrow)

source("config.R")

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
file_master_list <-
  tribble(
    ~ptype, ~year,            ~fmt,
    "hosp", 1996:2011,       "96",
    "hosp", 2010:FINAL_YEAR, "10",
    "snf",  1995:2012,       "96",
    "snf",  2011:FINAL_YEAR, "10"
  ) |>
  mutate(
    form = case_when(
      ptype=="hosp" ~ "2552",
      ptype=="snf"  ~ "2540"
    )    
  ) |>
  unnest(year) |> # expand so there's one obs for each year
  mutate( # generate file names
    file=paste0(
      SOURCE_BASE,"/",ptype,"_rpt",form,"_",fmt,"_",year,".csv"
    )
  ) |>
  select(-form)


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
file_rpt_pq = paste0(STORE,"/rpt")

# delete the report parquet file if it already exists
unlink(file_rpt_pq,recursive=TRUE)

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
  
  # delete the parquet file if it already exists
  unlink(file_pq,recursive=TRUE)

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
