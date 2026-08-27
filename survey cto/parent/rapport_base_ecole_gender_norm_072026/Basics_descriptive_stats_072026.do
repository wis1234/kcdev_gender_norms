/********************************************************************
 Project      : Gender norm
 Authors      : KCDev Research Assistants
 Date         : 07/20/2026
 Purpose      : Basics Descriptive stats
 Software     : Stata 17 MP
********************************************************************/

*---------------------------------------------------------------*
* 0. Initialization




version 17.0
clear all
set more off
set varabbrev off
capture log close


/*---------------------------------------
Basics descriptive statistics
1-Total number of school per department (zou and Atlantique)

2- Total number of school per municipality(commune)

3- Total number of eligible schools
  3.1- With at least 15 students 6e and 5e (also per department)
  3.2- With at least 10 students 6e and 5e
  
4- Number of urban and rural schools per department

Question: How do you caracterize semi-rural schools ?



---------------------------------------*/

* 1. Define Project Directory


global working"C:\Users\moust\RONALDO DROPBOX\Dropbox\KCDev_TvauxDomestiques\Team_CKDEV\Danfi\Randomization"
global raw     "$working"
global output  "$working\clean"

* Create output folder if it does not exist
capture mkdir "$output"

cd "$working"

* Log file
log using "$output\basic_descriptive_statistic_log.smcl", replace

* Import the clean dataset produced by Danfi
use "$output\school_list_gender_norm.dta", replace 

*import excel "$output/school_list_gender_norm.xlsx", firstrow clear

br

*1-Total number of school per department (zou and Atlantique)
tab NOMETABLISSEMENT

tab NOMETABLISSEMENT if DEPARTEMENT == "ZOU"
tab NOMETABLISSEMENT if DEPARTEMENT == "ATLANTIQUE"

*2- Total number of school per municipality(commune) 

  *List the municipalities of Zou department
  tab COMMUNE if DEPARTEMENT == "ZOU"
  
  *ABOMEY
  des COMMUNE
  tab NOMETABLISSEMENT if COMMUNE == "ABOMEY"
  *AGBANGNIZOUN
    tab NOMETABLISSEMENT if COMMUNE == "AGBANGNIZOUN"
  *BOHICON
      tab NOMETABLISSEMENT if COMMUNE == "BOHICON"
  *COVE
       tab NOMETABLISSEMENT if COMMUNE == "COVE"
	   
/*We notice here that CEG4 and CEG5 are missing
Reason:
a- CEG5 has been excluded because of the eligibility condition (NBF6EME>=10 & NBF5EME>=10)
b- CEG4 does not exist in the raw dataset(to be invesgate)
*/   
  *DJIDJA
       tab NOMETABLISSEMENT if COMMUNE == "DJIDJA"
  *OUINHI
       tab NOMETABLISSEMENT if COMMUNE == "OUINHI"
  *ZA-KPOTA
       tab NOMETABLISSEMENT if COMMUNE == "ZA-KPOTA"
  *ZAGNANADO
       tab NOMETABLISSEMENT if COMMUNE == "ZAGNANADO" 
  *ZOGBODOMEY
       tab NOMETABLISSEMENT if COMMUNE == "ZOGBODOMEY"  
	   
  *List the municipalities of Atlantique department
   tab COMMUNE if DEPARTEMENT == "ATLANTIQUE"
   *ABOMEY-CALAVI
   tab NOMETABLISSEMENT if COMMUNE =="ABOMEY-CALAVI" 
   *ALLADA
   tab NOMETABLISSEMENT if COMMUNE =="ALLADA" 
   *KPOMASSE
   tab NOMETABLISSEMENT if COMMUNE == "KPOMASSE"
   *OUIDAH
   tab NOMETABLISSEMENT if COMMUNE == "OUIDAH"
   *SO-AVA
   tab NOMETABLISSEMENT if COMMUNE == "SO-AVA"
   *TOFFO
   tab NOMETABLISSEMENT if COMMUNE == "TOFFO"
   *TORI-BOSSITO
   tab NOMETABLISSEMENT if COMMUNE == "TORI-BOSSITO"
   *ZE
   tab NOMETABLISSEMENT if COMMUNE == "ZE"
      
   
  
*3- Total number of eligible schools
  *3.1- With at least 15 students 6e and 5e 
  tab NOMETABLISSEMENT if NBF6EME>=15 & NBF5EME>=15
  *-At least 15 students 6e and 5e in Zou department
  tab NOMETABLISSEMENT if (NBF6EME>=15 & NBF5EME>=15) & DEPARTEMENT == "ZOU"
  *-At least 15 students 6e and 5e in Atlantique department
  tab NOMETABLISSEMENT if (NBF6EME>=15 & NBF5EME>=15) & DEPARTEMENT == "ATLANTIQUE"  

  *3.2- With at least 10 students 6e and 5e	 
    tab NOMETABLISSEMENT if NBF6EME>=10 & NBF5EME>=10
    *-At least 10 students 6e and 5e in Zou department
  tab NOMETABLISSEMENT if (NBF6EME>=10 & NBF5EME>=10) & DEPARTEMENT == "ZOU"
	*-At least 10 students 6e and 5e in Atlantique department
  tab NOMETABLISSEMENT if (NBF6EME>=10 & NBF5EME>=10) & DEPARTEMENT == "ATLANTIQUE"
 
 *4- Number of urban and rural schools per department
  tab NOMETABLISSEMENT if MILIEU == "Rural"
   tab NOMETABLISSEMENT if MILIEU == "Urbain"
   *4.1- Number of urban and rural schools in Zou department
   tab NOMETABLISSEMENT if (MILIEU == "Rural" & DEPARTEMENT == "ZOU")
   *4.2- Number of urban and rural schools in Atlantique department
    tab NOMETABLISSEMENT if (MILIEU == "Rural" & DEPARTEMENT == "ATLANTIQUE")
  
  
