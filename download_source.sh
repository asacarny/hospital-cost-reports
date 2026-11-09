#!/bin/bash

# download source HCRIS data from CMS

# download data for the years specified below
# note that for the synthetic calendar year files, the output will run from STARTYEAR+1
# to ENDYEAR-1
STARTYEAR=1996
ENDYEAR=2024

# where to put HCRIS files. by default store in the source folder, but since files
# can get quite large, you might want to store them elsewhere

OUTFOLDER="./source"

# check that wget is installed
if ! [ -x "$(command -v wget)" ]; then
  echo 'error: wget is not installed.' >&2
  exit 1
fi

# check that unzip is installed
if ! [ -x "$(command -v unzip)" ]; then
  echo 'error: unzip is not installed.' >&2
  exit 1
fi

# credit to user nyuszika7h on stackoverflow
# https://stackoverflow.com/questions/592620/how-can-i-check-if-a-program-exists-from-a-bash-script

mkdir -p ${OUTFOLDER}/

# CMS is not consistent about the case of the file names inside the zips (and on
# case-insensitive filesystems such as the macOS default, unzip hides the problem
# entirely). So resolve the member name from the archive listing instead of asking
# unzip for a name whose case we guessed, then write the stream straight to its
# final name. Returns non-zero when the member is absent.
extract_member() {
	local zip="$1" want="$2" dest="$3" member
	member=$(unzip -Z1 "$zip" | grep -ixF "$want" | head -n 1)
	if [ -z "$member" ]; then
		echo "error: $want not found in $zip" >&2
		return 1
	fi
	unzip -p "$zip" "$member" > "$dest"
}

for ((year=$STARTYEAR; year <= $ENDYEAR; year++))
do
	echo "downloading reports for $year"
	if [ $year -le 2011 ]
	then
		wget -q https://downloads.cms.gov/Files/hcris/HOSPFY${year}.zip \
			-O ${OUTFOLDER}/HOSPFY${year}.zip || continue

		extract_member ${OUTFOLDER}/HOSPFY${year}.zip HOSP_${year}_rpt.csv \
			${OUTFOLDER}/hosp_rpt2552_96_${year}.csv &&
		extract_member ${OUTFOLDER}/HOSPFY${year}.zip HOSP_${year}_nmrc.csv \
			${OUTFOLDER}/hosp_nmrc2552_96_${year}_long.csv &&
		extract_member ${OUTFOLDER}/HOSPFY${year}.zip HOSP_${year}_alpha.csv \
			${OUTFOLDER}/hosp_alph2552_96_${year}_long.csv &&
		rm ${OUTFOLDER}/HOSPFY${year}.zip
	fi

	if [ $year -ge 2010 ]
	then
		wget -q https://downloads.cms.gov/Files/hcris/HOSP10FY${year}.zip \
			-O ${OUTFOLDER}/HOSP10FY${year}.zip || continue

		extract_member ${OUTFOLDER}/HOSP10FY${year}.zip HOSP10_${year}_rpt.csv \
			${OUTFOLDER}/hosp_rpt2552_10_${year}.csv &&
		extract_member ${OUTFOLDER}/HOSP10FY${year}.zip HOSP10_${year}_nmrc.csv \
			${OUTFOLDER}/hosp_nmrc2552_10_${year}_long.csv &&
		extract_member ${OUTFOLDER}/HOSP10FY${year}.zip HOSP10_${year}_alpha.csv \
			${OUTFOLDER}/hosp_alph2552_10_${year}_long.csv &&
		rm ${OUTFOLDER}/HOSP10FY${year}.zip
	fi
done
