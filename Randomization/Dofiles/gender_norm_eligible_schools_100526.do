clear all
set more off
version 17

*===============================================================*
* 0. PARAMETERS
*===============================================================*
cd "C:\RONALDO\CKDEV\GENDER NORMS\Randomization"
global dir_data     "."
global f_master     "Datasets\school_list_gender_norm.xlsx"
global f_gender_norm "Datasets\gender_norm_school_list_selected_081326.xlsx"
global sheet_gender_norm "Final_ecole_gender_norm"   // <-- sheet to use in $f_gender_norm

global dir_out   "Outputs"
global out_data  "$dir_out\Data"
global out_logs  "$dir_out\Logs"

capture mkdir "$dir_out"
capture mkdir "$out_data"
capture mkdir "$out_logs"

capture log close
log using "$out_logs\merge_master_gender_norm.log", replace text

*===============================================================*
* 1. NAME-CLEANING PROGRAM (uppercase, strip accents/punctuation)
*===============================================================*
capture program drop nettoyer_nom
program define nettoyer_nom
    syntax varname(string), generate(name)
    tempvar tmp1 tmp2
    gen `tmp1' = ustrupper(`varlist')
    gen `tmp2' = ustrnormalize(`tmp1', "nfd")
    replace `tmp2' = ustrregexra(`tmp2', "[\u0300-\u036f]", "")
    replace `tmp2' = ustrregexra(`tmp2', "[^A-Z0-9]", " ")
    replace `tmp2' = ustrregexra(`tmp2', " +", " ")
    gen `generate' = ustrtrim(`tmp2')
end

*===============================================================*
* 2. PREPARE THE "USING" DATASET (gender-norm selected schools)
*===============================================================*
import excel "$dir_data/$f_gender_norm", sheet("$sheet_gender_norm") firstrow clear

capture confirm variable NOMETABLISSEMENT
if _rc {
    display as error "Column NOMETABLISSEMENT not found in sheet $sheet_gender_norm - check the exact column name with 'describe'."
}

nettoyer_nom NOMETABLISSEMENT, generate(name_key)
nettoyer_nom COMMUNE,          generate(commune_key)
gen str200 school_id = name_key + "_" + commune_key

* Should be unique (each row = one selected school); warn if not.
duplicates tag school_id, gen(dup_gn)
quietly count if dup_gn > 0
if r(N) > 0 {
    display as error "WARNING: " r(N) " row(s) in the gender-norm selection share the same school_id - check for a real duplicate before trusting the merge."
}
drop dup_gn name_key commune_key

* Avoid clashing with master variables of the same name (MILIEU, COMMUNE,
* ARRONDISSEMENT, QUARTIERVILLAGE all exist in the master too) - prefix
* the gender-norm-specific copies so both sources stay visible/traceable.
rename MILIEU            milieu_gender_norm
rename ARRONDISSEMENT    arrondissement_gender_norm
rename COMMUNE           commune_gender_norm
rename QUARTIERVILLAGE   quartiervillage_gender_norm
* classification and giga_name keep their names (no clash with master)

tempfile gender_norm_clean
save `gender_norm_clean'

quietly count
display as result ">>> Gender-norm selection ready: " r(N) " schools, school_id built from name + commune."

*===============================================================*
* 3. PREPARE THE MASTER DATASET (school_list_gender_norm)
*===============================================================*
import excel "$dir_data/$f_master", firstrow clear

capture confirm variable NOMETABLISSEMENT
if _rc {
    * Adjust this rename if the imported header differs (e.g. spaces
    * collapsed differently by Stata) - check with 'describe'.
    capture rename NOMETABLISSEMENT NOMETABLISSEMENT
    display as error "Column NOMETABLISSEMENT not found after import - check the exact name with 'describe' (source header was 'NOM ETABLISSEMENT')."
}

nettoyer_nom NOMETABLISSEMENT, generate(name_key)
nettoyer_nom COMMUNE,          generate(commune_key)
gen str200 school_id = name_key + "_" + commune_key

* Flag (don't drop) master schools whose school_id repeats within the
* master itself - informational only, since merge keep(master match)
* preserves every master row regardless.
duplicates tag school_id, gen(dup_master)
quietly count if dup_master > 0
display as result "[Master] " r(N) " rows share a school_id with at least one other master row (see Outputs\Data\master_school_id_ambigus.xlsx)."

if r(N) > 0 {
    preserve
        keep if dup_master > 0
        sort school_id NOMETABLISSEMENT
        export excel using "$out_data\master_school_id_ambigus.xlsx", firstrow(variables) replace
    restore
}
else {
    display as result "[Master] No ambiguous school_id in the master - nothing to export."
}

drop name_key commune_key dup_master

quietly count
display as result ">>> Master dataset ready: " r(N) " schools (all variables kept)."

*===============================================================*
* 4. MERGE - master keeps ALL rows and ALL its own variables
*===============================================================*
merge m:1 school_id using `gender_norm_clean', gen(_merge_gn)

gen str20 statut_merge_gn = "matched_gender_norm" if _merge_gn == 3
replace   statut_merge_gn = "master_only"         if _merge_gn == 1
label var statut_merge_gn "Match status vs. the gender-norm selected/classified schools"

* Using-only rows (_merge_gn == 2) would mean a selected school was NOT
* found in the master - shouldn't happen (master is the national list)
* but check and export for review just in case.
quietly count if _merge_gn == 2
if r(N) > 0 {
    display as error "WARNING: " r(N) " gender-norm-selected school(s) were NOT found in the master - see Outputs\Data\gender_norm_non_matchees.xlsx."
    preserve
        keep if _merge_gn == 2
        export excel using "$out_data\gender_norm_non_matchees.xlsx", firstrow(variables) replace
    restore
    drop if _merge_gn == 2   // these rows have no master data at all
}

drop _merge_gn

quietly count if statut_merge_gn == "matched_gender_norm"
display as result ">>> " r(N) " master schools matched to a gender-norm classification."
quietly count
display as result ">>> Final dataset: " r(N) " schools total (full master + gender-norm columns where available)."

*===============================================================*
* 5. KEEP ONLY MATCHED SCHOOLS + RENAME MILIEU VARIABLES
*===============================================================*
quietly count if statut_merge_gn != "matched_gender_norm"
display as result ">>> Dropping " r(N) " master-only (unmatched) school(s) before export."
keep if statut_merge_gn == "matched_gender_norm"

* MILIEU (from the master) = administrative/declared status -> keep it,
* but rename to avoid ambiguity with the DEGURBA-based classification.
rename MILIEU        MILIEU_ADMIN
* classification (from the gender-norm/DEGURBA step) becomes the new MILIEU.
rename classification MILIEU


*======================================================================*
* 6. ELIGIBILITY BASED ON CLASS SIZE
*======================================================================*
* Create variable: total number of girls in 6th and 5th grade
//gen elig_school = NBF6EME + NBF5EME
gen elig_school = NBF5EME

* Define eligibility: each class must have at least 15 girls
gen eligible = 1 if NBF5EME >= 15
replace eligible = 0 if eligible == .
count if eligible==1

* Add labels for clarity
label define eliglbl 0 "Not eligible" 1 "Eligible"
label values eligible eliglbl

* Quick summary of results
tab eligible

*Eligibility per department
tab DEPARTEMENT if eligible == 1
*Eligibility per commune
tab COMMUNE if eligible == 1



*===============================================================*
* 7. EXPORT
*===============================================================*

* Keep only eligible schools before export
keep if eligible == 1

*Drop the extra school before export
drop if NOMETABLISSEMENT == "CEG ELITES D'ABOMEY"

*Replace the "URBAN_SEMIDENSE" schools by "PERIURBAN"
*replace MILIEU = "PERIURBAN" if MILIEU == "URBAN_SEMIDENSE"
/*Due to the inconsistency of the gps coordinates,
in those areas we keep the administrative classification
*/
replace MILIEU = "RURAL" if MILIEU == "URBAN_SEMIDENSE"
replace MILIEU = "RURAL" if MILIEU == "Rural"

order school_id, first
order MILIEU MILIEU_ADMIN milieu_gender_norm giga_name arrondissement_gender_norm ///
      commune_gender_norm quartiervillage_gender_norm statut_merge_gn, last

save "$out_data\master_x_gender_norm.dta", replace
export excel using "$out_data\master_x_gender_norm.xlsx", firstrow(variables) replace

* Global view
tab MILIEU

* Loop for all communes in the department ZOU
* This extracts all communes belonging to ZOU and runs a tabulation of MILIEU for each
levelsof COMMUNE if DEPARTEMENT == "ZOU", local(communes)

foreach c of local communes {
    di "---- Commune: `c' ----"
    tab MILIEU if COMMUNE == "`c'" & DEPARTEMENT == "ZOU"
}

* Loop for all communes in the department ATLANTIQUE
* Same logic as above, but restricted to ATLANTIQUE
levelsof COMMUNE if DEPARTEMENT == "ATLANTIQUE", local(communes)

foreach c of local communes {
    di "---- Commune: `c' ----"
    tab MILIEU if COMMUNE == "`c'" & DEPARTEMENT == "ATLANTIQUE"
}




log close

********************************************************************************
* NOTES
* - school_id = cleaned(NOMETABLISSEMENT) + "_" + cleaned(COMMUNE), built
*   identically on both files. With this 180-school master, school_id has
*   0 duplicates (checked in section 3), so name+commune and name-alone
*   give identical results here - the commune is kept in the key purely
*   as a general safeguard in case the master changes again later.
* - If you want a strictly NAME-ONLY school_id, replace
*   "gen str200 school_id = name_key + "_" + commune_key" with
*   "gen str200 school_id = name_key" in BOTH sections 2 and 3 - safe to
*   do with this particular master, since there are no duplicate names.
* - Master rows without a gender-norm match keep every master variable;
*   classification / milieu_gender_norm / giga_name are simply missing
*   for them (statut_merge_gn == "master_only").
* - Outputs\Data\master_school_id_ambigus.xlsx is only created if section
*   3 finds duplicate school_id's in the master; with 0 duplicates
*   (as here) that step is skipped and nothing is written - this was the
*   fix for the r(198) "observations must be between 1 and 1048576"
*   error (export excel on an empty 0-observation dataset).
********************************************************************************
