# download-source.R
# download source HCRIS data from CMS

library(tidyverse)

source("config.R")

if (
  REPORT_EXTENTS |> 
  filter(end_year>FINAL_YEAR) |>
  nrow()
) {
  stop("You're requesting report years after FINAL_YEAR")
}

# make the source folder if it doesn't exist
dir.create(SOURCE_BASE, showWarnings = FALSE)

# all potential cost report files to download
url_master_list <-
  tribble(
    ~ptype, ~year,            ~fmt,
    "hosp", 1996:2011,       "96",
    "hosp", 2010:FINAL_YEAR, "10",
    "snf",  1995:2012,       "96",
    "snf",  2011:FINAL_YEAR, "10"
  ) |>
  unnest(year) # expand so there's one obs for each year


# function to download a ptype-year-fmt ZIP, extract it, and rename
# component files
process_download <- function(ptype, year, fmt) {
  
  zip_filename <- paste0(
    toupper(ptype),
    if_else(fmt=="10","10",""),
    "FY",
    year,
    ".zip"
  )
  
  url <- paste0(
    "https://downloads.cms.gov/Files/hcris/",
    zip_filename
  )
  dest <- paste0(
    SOURCE_BASE,
    "/",
    zip_filename
  )
  
  cat(paste0(url,"\n"))
  download.file(url,dest,method=DOWNLOAD_METHOD)
  
  file_list <-
    tibble( 
      f = c("rpt","nmrc","alpha"),
      fmt = fmt,
      ptype = ptype
    ) |>
    mutate(
      form = case_when(
        ptype=="hosp" ~ "2552",
        ptype=="snf"  ~ "2540"
      ),
      file_src = paste0( # files to extract
        if_else(fmt=="96" & ptype=="snf",ptype,toupper(ptype)),
        if_else(fmt=="10","10",""),
        "_",
        year,
        "_",
        if_else(fmt=="96" & ptype=="snf",toupper(f),f),
        if_else(fmt=="96" & ptype=="snf",".CSV",".csv")
      ),
      file_dest = paste0( # new filenames for renaming
        ptype,
        "_",
        substr(f,1,4),
        form,
        "_",
        fmt,
        "_",
        year,
        if_else(f=="rpt","",paste0("_","long")),
        ".csv"
      ),
      from=paste0(SOURCE_BASE,"/",file_src), # full paths for renaming
      to=paste0(SOURCE_BASE,"/",file_dest)
    )
  
  ret <- unzip(
    zipfile=dest,
    files=file_list$file_src,
    exdir=SOURCE_BASE
  )
  
  if (is.null(ret)) {
    stop(paste0("Failed to extract zipfile ",dest))
  }
  
  unlink(dest)
  
  file_list |>
    select(from,to) |>
    pmap(file.rename)

  #cat(paste0("File src: ",file_src," File dest: ",file_dest,"\n"))
  
}

pmap(url_master_list,process_download)
