# Configuration for cost report processing

# Last year cost reports are available
FINAL_YEAR <- 2024

# Process cost reports from these years
REPORT_EXTENTS <- tribble(
  ~ptype,  ~start_year,  ~end_year,
  "hosp",     1996,         2024,
  "snf",      1995,         2024
)

# Where is the source data?
SOURCE_BASE <- "./source"

# What method should download.file use to download the zipfiles from cms.gov?
# This overrides the default ("auto") which I found to be unreliable.
# Valid options are: wininet (on Windows), libcurl, wget, curl, auto
DOWNLOAD_METHOD <- "curl"

# Where to save the parquet?
STORE <- "./store"

# Function to determine when a provider-year starts. Assume calendar year:
START_AYEAR_DATE <- function (y) { make_date(y,1,1) }
END_AYEAR_DATE <- function (y) { make_date(y,12,31) }

# This would do federal fiscal years
#AYEAR_START_DATE <- function (y) { make_date(y-1,10,1) }
#AYEAR_END_DATE <- function (y) { make_date(y,9,30) }
