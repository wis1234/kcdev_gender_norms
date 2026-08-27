/********************************************************************
 Project      : Gender norm
 Author       : DANFI David
 Date         : 17 juillet 2026
 Purpose      : Cleaning school data base
 Software     : Stata 16
********************************************************************/

*---------------------------------------------------------------*
* 0. Initialization




version 16.0
clear all
set more off
set varabbrev off
capture log close

*---------------------------------------------------------------*
* 1. Define Project Directory


global working"C:\Users\moust\RONALDO DROPBOX\Dropbox\KCDev_TvauxDomestiques\Team_CKDEV\Danfi\Randomization"
global raw     "$working"
global output  "$working\clean"

* Create output folder if it does not exist
capture mkdir "$output"

cd "$working"

*---------------------------------------------------------------*
* 2. Open Log File (Saved in output folder)


log using "$output\school_cleaning_log.smcl", replace


import excel "$working\school_list_07162026.xlsx", firstrow clear

describe
browse
browse DEPARTEMENT

*---------------------------------------------------------------*
*3. Keep only the school from Atlantique and Zou 
keep if inlist(DEPARTEMENT, "ATLANTIQUE", "ZOU")
br

*---------------------------------------------------------------*
*4. Keep only public school from Atlantique and Zou
br STATUT
tab STATUT
keep if STATUT == "Public"
br
count

*---------------------------------------------------------------*
*5. check if there is duplicate*
br NOMETABLISSEMENT 
tab NOMETABLISSEMENT 
duplicates report NOMETABLISSEMENT

*---------------------------------------------------------------*
*6. Check if the school have a sufficient number of girl for the survey

tab MILIEU
browse 

*br if NBF6EME<15
*br if NBF5EME<15

br if NBF6EME<10  
count if NBF6EME<10 

br if NBF5EME<10
count if NBF5EME<10

*count if NBF6EME>=15 & NBF5EME>=15

count if NBF6EME>=10 & NBF5EME>=10

*keep if NBF6EME>=10 & NBF5EME>=10

keep if NBF6EME>=10 & NBF5EME>=10

count if DEPARTEMENT == "ZOU"
count if DEPARTEMENT == "ATLANTIQUE"
*---------------------------------------------------------------*
*7. Save the data
save "$output\school_list_gender_norm.dta", replace

export excel using "$output/school_list_gender_norm.xlsx", firstrow(variables) replace

log close