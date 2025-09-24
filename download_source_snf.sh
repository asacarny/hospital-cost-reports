#!/bin/bash

# download source HCRIS data from CMS

# download data for the years specified below
# note that for the synthetic calendar year files, the output will run from STARTYEAR+1
# to ENDYEAR-1
STARTYEAR=1995
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

for ((year=$STARTYEAR; year <= $ENDYEAR; year++))
do
	echo "downloading reports for $year"
	if [ $year -le 2012 ]
	then
		wget http://downloads.cms.gov/Files/hcris/SNFFY${year}.zip \
			-O ${OUTFOLDER}/SNFFY${year}.zip

		unzip ${OUTFOLDER}/SNFFY${year}.zip \
			-d ${OUTFOLDER}/ \
			snf_${year}_RPT.CSV snf_${year}_NMRC.CSV snf_${year}_ALPHA.CSV
	
		mv ${OUTFOLDER}/snf_${year}_RPT.CSV ${OUTFOLDER}/snf_rpt2540_96_${year}.csv
		mv ${OUTFOLDER}/snf_${year}_NMRC.CSV ${OUTFOLDER}/snf_nmrc2540_96_${year}_long.csv
		mv ${OUTFOLDER}/snf_${year}_ALPHA.CSV ${OUTFOLDER}/snf_alph2540_96_${year}_long.csv
	
		rm ${OUTFOLDER}/SNFFY${year}.zip
	fi

	if [ $year -ge 2011 ]
	then
		wget http://downloads.cms.gov/Files/hcris/SNF10FY${year}.zip \
			-O ${OUTFOLDER}/SNF10FY${year}.zip

		unzip ${OUTFOLDER}/SNF10FY${year}.zip \
			-d ${OUTFOLDER}/ \
			SNF10_${year}_rpt.csv SNF10_${year}_nmrc.csv SNF10_${year}_alpha.csv
	
		mv ${OUTFOLDER}/SNF10_${year}_rpt.csv ${OUTFOLDER}/snf_rpt2540_10_${year}.csv
		mv ${OUTFOLDER}/SNF10_${year}_nmrc.csv ${OUTFOLDER}/snf_nmrc2540_10_${year}_long.csv
		mv ${OUTFOLDER}/SNF10_${year}_alpha.csv ${OUTFOLDER}/snf_alph2540_10_${year}_long.csv
	
		rm ${OUTFOLDER}/SNF10FY${year}.zip
	fi
done
