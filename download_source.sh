#!/bin/bash

# download source HCRIS data from CMS or NBER

# download data for the years specified below
# note that for the synthetic calendar year files, the output will run from STARTYEAR+1
# to ENDYEAR-1
STARTYEAR=1996
ENDYEAR=2021

# choose download method. options
# 1. wget-cms - download the latest HCRIS data from the CMS website
# 2. wget-nber - download processed HCRIS data from NBER website
# 3. rsync-nber - download processed HCRIS data from NBER via rsync
# if you want to download the processed files from NBER, the rsync method is likely
# faster than wget on subsequent downloads because it syncs files rather than re-
# downloading them. note if you aren't using passwordless login you'll be prompted for
# a password for every file.
# NB: the rsync method requires an NBER username!
# NB: as of today (Jan 23, 2022) the NBER data was last updated mid-2018, and is now
# out of date.

METHOD="wget-cms"

# where to put HCRIS files. by default store in the source folder, but since files
# can get quite large, you might want to store them elsewhere

OUTFOLDER="./source"

mkdir -p ${OUTFOLDER}/

if [ "$METHOD" == "wget-cms" ]
then
# method wget-cms
	for ((year=$STARTYEAR; year <= $ENDYEAR; year++))
	do
		echo "downloading reports for $year"
		if [ $year -le 2011 ]
		then
			wget http://downloads.cms.gov/Files/hcris/HOSPFY${year}.zip \
				-O ${OUTFOLDER}/HOSPFY${year}.zip

			unzip ${OUTFOLDER}/HOSPFY${year}.zip \
				-d ${OUTFOLDER}/ \
				HOSP_${year}_RPT.CSV HOSP_${year}_NMRC.CSV
		
			mv ${OUTFOLDER}/HOSP_${year}_RPT.CSV ${OUTFOLDER}/hosp_rpt2552_96_${year}.csv
			mv ${OUTFOLDER}/HOSP_${year}_NMRC.CSV ${OUTFOLDER}/hosp_nmrc2552_96_${year}_long.csv
		
			rm ${OUTFOLDER}/HOSPFY${year}.zip
		fi
	
		if [ $year -ge 2010 ]
		then
			wget http://downloads.cms.gov/Files/hcris/HOSP10FY${year}.zip \
				-O ${OUTFOLDER}/HOSP10FY${year}.zip

			unzip ${OUTFOLDER}/HOSP10FY${year}.zip \
				-d ${OUTFOLDER}/ \
				HOSP10_${year}_RPT.CSV HOSP10_${year}_NMRC.CSV
		
			mv ${OUTFOLDER}/HOSP10_${year}_RPT.CSV ${OUTFOLDER}/hosp_rpt2552_10_${year}.csv
			mv ${OUTFOLDER}/HOSP10_${year}_NMRC.CSV ${OUTFOLDER}/hosp_nmrc2552_10_${year}_long.csv
		
			rm ${OUTFOLDER}/HOSP10FY${year}.zip
		fi
	done
else
# not method wget-cms. should be either wget-nber or rsync-nber
	if [ "$METHOD" == "wget-nber" ]
	then
		cmdprefix="wget https://data.nber.org/hcris/"
		cmdpostfix="-O ${OUTFOLDER}/"
	elif [ "$METHOD" == "rsync-nber" ]
	then
		echo "Please enter your NBER username"
		read nber_username
		cmdprefix="rsync --progress -z ${nber_username}@nber4.nber.org:/home/data/hcris/"
		cmdpostfix="${OUTFOLDER}/"
	else
		echo "invalid method"
		exit
	fi

	for ((year=$STARTYEAR; year <= $ENDYEAR; year++))
	do
		echo "downloading reports for $year"
		if [ $year -le 2011 ]
		then
			${cmdprefix}/2552-96/hosp_rpt2552_96_${year}.dta \
				${cmdpostfix}/hosp_rpt2552_96_${year}.dta
			${cmdprefix}/2552-96/hosp_nmrc2552_96_${year}_long.dta \
				${cmdpostfix}/hosp_nmrc2552_96_${year}_long.dta
		fi
	
		if [ $year -ge 2010 ]
		then
			${cmdprefix}/2552-10/hosp_rpt2552_10_${year}.dta \
				${cmdpostfix}/hosp_rpt2552_10_${year}.dta
			${cmdprefix}/2552-10/hosp_nmrc2552_10_${year}_long.dta \
				${cmdpostfix}/hosp_nmrc2552_10_${year}_long.dta
		fi
	done
fi
