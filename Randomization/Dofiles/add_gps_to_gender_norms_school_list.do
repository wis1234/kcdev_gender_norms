********************************************************************************
* MERGE BENIN SCHOOLS
* Combines:
*   1) school_list_gender_norm.xlsx   -> infrastructure/gender data (CEG, 180 obs)
*   2) School_report_..._Giga.xlsx    -> GPS coordinates (Giga, ~7,670 obs)
*
* No common ID between the two datasets -> join on school NAME, normalized:
*   - Step 1: EXACT match on cleaned name
*   - Step 2: FUZZY match (reclink) to catch spelling variants
*     (spacing, hyphens, accents, numbering)
*
* Outputs:
*   - ecoles_benin_fusion_finale.dta / .xlsx  (full merged dataset, with match status)
*   - ecoles_benin_non_matchees.xlsx          (unmatched schools, to check/complete manually)
*   - giga_noms_ambigus.xlsx                  (Giga schools with duplicate names, excluded from auto-matching)
*   - ecoles_benin_urbain.csv                 (urban schools only, matching/technical vars dropped)
********************************************************************************

clear all
set more off
version 15
capture log close
log using "merge_ecoles_benin.log", replace text

*===============================================================*
* 0. PARAMETERS
*===============================================================*
cd "C:\RONALDO\CKDEV\GENDER NORMS\Randomization"
global dir_data   "."   // <- folder containing both xlsx files
global f_infra    "Datasets\school_list_gender_norm.xlsx"
global f_giga      "Datasets\School_report_page_1_out_of_1_dated_07082026_220741.xlsx"
global seuil_flou  0.80  // minimum score accepted for a fuzzy match (0-1)

*===============================================================*
* 1. INSTALL RECLINK (fuzzy matching) - one-time
*===============================================================*
capture which reclink
if _rc != 0 {
    ssc install reclink, replace
}

*===============================================================*
* 2. NAME-CLEANING PROGRAM (reused on both datasets)
*    - uppercase, accents stripped, punctuation -> space,
*      multiple spaces collapsed, trimmed
*===============================================================*
capture program drop nettoyer_nom
program define nettoyer_nom
    syntax varname(string), generate(name)
    tempvar tmp1 tmp2
    gen `tmp1' = ustrupper(`varlist')
    * Unicode decomposition, then strip diacritical marks (accents)
    gen `tmp2' = ustrnormalize(`tmp1', "nfd")
    replace `tmp2' = ustrregexra(`tmp2', "[\u0300-\u036f]", "")
    * Punctuation / hyphens / apostrophes -> space
    replace `tmp2' = ustrregexra(`tmp2', "[^A-Z0-9]", " ")
    * Multiple spaces -> single space, then trim
    replace `tmp2' = ustrregexra(`tmp2', " +", " ")
    gen `generate' = ustrtrim(`tmp2')
end

*===============================================================*
* 3. IMPORT GIGA DATASET (GPS coordinates)
*===============================================================*
import excel "$dir_data/$f_giga", firstrow clear

rename SchoolGigaID     giga_id
rename SchoolName       giga_name
rename Longitude        lon
rename Latitude         lat
rename EducationLevel   giga_level
rename CountryISO3Code  giga_iso3
rename CountryName      giga_country
capture rename SchoolDataSource giga_source

destring lon lat, replace force

nettoyer_nom giga_name, generate(name_key)

* Duplicate names on the Giga side: several schools can share the EXACT
* same cleaned name (e.g. same school name in two different communes).
* merge m:1 requires the "using" dataset to be unique on the key -> these
* ambiguous cases are removed from the automatic matching pool and set
* aside for manual review (we can't guess which one is correct without
* extra info such as the commune).
duplicates tag name_key, gen(dup_giga)
quietly count if dup_giga > 0
display as result "[Giga] " r(N) " rows share a cleaned name with at least one duplicate (set aside, see giga_noms_ambigus.xlsx)."

preserve
    keep if dup_giga > 0
    sort name_key giga_name
    export excel using "giga_noms_ambigus.xlsx", firstrow(variables) replace
restore

drop if dup_giga > 0   // keep only unique names for automatic matching

tempfile giga_clean
save `giga_clean'

*===============================================================*
* 4. IMPORT INFRASTRUCTURE DATASET (gender_norm)
*===============================================================*
import excel "$dir_data/$f_infra", firstrow clear

capture confirm variable NOMETABLISSEMENT
if _rc {
    * If the imported column name differs slightly, fix it here:
    * rename <ActualColumnName> NOMETABLISSEMENT
    display as error "Column NOM ETABLISSEMENT not found after import - check the exact name with 'describe'."
}

nettoyer_nom NOMETABLISSEMENT, generate(name_key)

duplicates tag name_key, gen(dup_infra)
quietly count if dup_infra > 0
display as result "[Infra] " r(N) " rows share a cleaned name with at least one duplicate."

gen long id_infra = _n   // technical identifier used for reclink

tempfile infra_clean
save `infra_clean'

*===============================================================*
* 5. STEP 1 - EXACT MATCH on name_key
*===============================================================*
use `infra_clean', clear
merge m:1 name_key using `giga_clean', gen(_merge_exact) keep(master match)

gen str10 statut_match = "exact" if _merge_exact == 3
replace statut_match = "non_matche" if _merge_exact == 1

tempfile apres_exact
save `apres_exact'

quietly count if statut_match == "exact"
display as result ">>> EXACT matches: " r(N) " out of " _N

*===============================================================*
* 6. STEP 2 - FUZZY MATCH (reclink) on unmatched rows
*===============================================================*
use `apres_exact', clear
keep if statut_match == "non_matche"
count
if r(N) > 0 {
    keep id_infra name_key
    tempfile a_matcher
    save `a_matcher'

    use `giga_clean', clear
    keep giga_id name_key
    tempfile giga_pour_reclink
    save `giga_pour_reclink'

    use `a_matcher', clear
    * IMPORTANT: reclink requires the compared variable to have the SAME
    * name in the master and in the using dataset -> keep "name_key" as is
    * on both sides (do not rename).

    * reclink: fuzzy matching based on Jaro-Winkler string distance
    * generates a score variable (0 = no resemblance, 1 = identical)
    reclink name_key using `giga_pour_reclink', ///
        idmaster(id_infra) idusing(giga_id) ///
        gen(score_flou)

    keep if score_flou >= $seuil_flou
    keep id_infra giga_id score_flou
    duplicates drop id_infra, force   // keep the best score per infra school

    tempfile matches_flous
    save `matches_flous'

    * Bring back Giga info (lat/lon) for these fuzzy matches
    use `giga_clean', clear
    keep giga_id giga_name lon lat giga_level giga_iso3 giga_country
    tempfile giga_infos
    save `giga_infos'

    use `matches_flous', clear
    merge m:1 giga_id using `giga_infos', keep(match) nogen

    tempfile flous_avec_gps
    save `flous_avec_gps'

    quietly count
    display as result ">>> FUZZY matches (score >= $seuil_flou): " r(N)
}
else {
    display as result "No unmatched row left to process with fuzzy matching."
}

*===============================================================*
* 7. FINAL MERGE: exact + fuzzy + remaining unmatched
*===============================================================*
use `apres_exact', clear

capture confirm file "`flous_avec_gps'"
if _rc == 0 {
    * Merge the fuzzy-matching results back into the main dataset
    merge 1:1 id_infra using `flous_avec_gps', ///
        keepusing(giga_id giga_name lon lat giga_level giga_iso3 giga_country score_flou) ///
        update replace nogen

    replace statut_match = "flou" if score_flou < . & statut_match == "non_matche"
}

label var statut_match "Match status with the Giga dataset (exact / flou[fuzzy] / non_matche[unmatched])"
label var score_flou   "Fuzzy-match similarity score (0-1), missing for exact matches"

*===============================================================*
* 8. EXPORTS
*===============================================================*
* Full dataset, with a match-quality indicator
save "ecoles_benin_fusion_finale.dta", replace
export excel using "ecoles_benin_fusion_finale.xlsx", firstrow(variables) replace

* On-screen summary
tab statut_match
display as result "Note: Giga schools with ambiguous (duplicate) names were excluded from automatic matching -> see giga_noms_ambigus.xlsx to link them manually if needed."

* Separate file of unmatched schools, to check/complete manually
preserve
    keep if statut_match == "non_matche"
    export excel using "ecoles_benin_non_matchees.xlsx", firstrow(variables) replace
    quietly count
    display as result ">>> " r(N) " schools WITHOUT GPS coordinates after matching -> see ecoles_benin_non_matchees.xlsx"
restore

log close

*===============================================================*
* 9. FINAL VARIABLE CLEANUP + URBAN SUBSET EXPORT (CSV)
*===============================================================*
use "ecoles_benin_fusion_finale.dta", clear

* Drop technical variables that were only needed for matching
* (no longer useful once the merge is done)
drop name_key dup_infra dup_giga _merge_exact

* Reorder: identification -> location -> establishment ->
* infrastructure/gender variables -> GPS & matching quality
order id_infra DEPARTEMENT COMMUNE ARRONDISSEMENT QUARTIERVILLAGE ///
      NOMETABLISSEMENT STATUT MILIEU REGIME, first
order giga_id giga_name giga_level lon lat giga_iso3 giga_country ///
      statut_match score_flou, last

label var id_infra "Internal technical identifier (infra dataset)"

save "ecoles_benin_fusion_finale.dta", replace
export excel using "ecoles_benin_fusion_finale.xlsx", firstrow(variables) replace
display as result ">>> Final cleaned dataset: " _N " schools, " c(k) " variables."

* Check the exact values of MILIEU before filtering (useful in case the
* spelling differs from "URBAIN": accents, case, extra spaces, etc.)
tab MILIEU

*----------------------------------------------------------------*
* Urban subset only, exported to CSV, WITHOUT merge/matching or
* other technical variables (id_infra, statut_match, score_flou,
* and the redundant Giga country fields, since all rows are Benin)
*----------------------------------------------------------------*
preserve
    gen milieu_norm = ustrupper(ustrtrim(MILIEU))
    keep if milieu_norm == "URBAIN"
    drop milieu_norm

    * Drop merge/matching and other non-essential technical variables
    drop id_infra statut_match score_flou giga_iso3 giga_country

    export delimited using "ecoles_benin_urbain.csv", replace

    quietly count
    display as result ">>> " r(N) " urban schools -> ecoles_benin_urbain.csv (technical/matching variables removed)"
restore

********************************************************************************

*drop the ambiguis public school
drop if NOMETABLISSEMENT == "CPEG PRODIGES DE DIEU"

    export delimited using "ecoles_atl_zou.csv", replace
	
* NOTES
* - Adjust $dir_data if your files are not in the current folder.
* - Adjust the NOMETABLISSEMENT variable name if Stata imported it
*   differently (check with `describe` right after importing the infra
*   dataset if the do-file stops with an error at that step).
* - $seuil_flou = 0.80 is a reasonable starting point; lower it carefully
*   (e.g. 0.75) if too many schools remain unmatched, but then manually
*   review the new fuzzy matches to avoid false positives
*   (e.g. "CEG 1 ADJARRA" vs "CEG 2 ADJARRA" are close but different schools).
* - Giga schools with a duplicate cleaned name (dup_giga > 0, e.g. same
*   name in two different communes) are EXCLUDED from automatic matching
*   (both exact AND fuzzy) because merge m:1 requires a unique "using"
*   dataset, and fuzzy-matching an ambiguous name would be a gamble.
*   They are exported to giga_noms_ambigus.xlsx: link them manually based
*   on commune/department if you have that info on both sides.
* - If you have commune/department available on both sides, a better
*   long-term solution is to add it as an extra blocking variable
*   (allows automatic disambiguation of homonyms) -> let me know and
*   I'll adapt the script.
********************************************************************************


*updates
/*CEG 1 BONOU de giga_name va etre remplacer par CEG 1 OUIDAH car CEG 1 BERTRAND DAGNON est le CEG 1 OUIDAH

LYCEE TECHNIQUE DE OUIDAH va remplacer LYCEE DES JEUNES FILLES MC (890a1f61-6627-3d08-980f-a1938c181158) le premier cas

LYCEE DES JEUNES FILLES MC(890a1f61-6627-3d08-980f-a1938c181158) le second cas sera remplacer par LYCEE DES JEUNES FILLES D'ABOMEY

CEG LANTA sera remplacer par CEG 1 COVE

pour les remplacement soit efficace
remplace entenant compte de toutes les colonnes afin que la nouvelle ecole remplacer puisse avoir toutes les informations qui accompagnent
*/



