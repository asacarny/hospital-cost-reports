#!/bin/bash

# data start and end
STARTYEAR=2000
ENDYEAR=2016

# choose method wget or rsync (requires NBER username)
METHOD="rsync"

if [ "$METHOD" == "wget" ]
then
	cmdprefix="wget http://www.nber.org/hcris/"
	cmdpostfix="-O source/"
elif [ "$METHOD" == "rsync" ]
then
	echo "Please enter your NBER username"
	read nber_username
	cmdprefix="rsync --progress -z ${nber_username}@nber4.nber.org:/home/data/hcris/"
	cmdpostfix="source/"
else
	echo "invalid method"
	exit
fi

mkdir -p source/

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
