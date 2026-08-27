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
*   - Step 3: MANUAL CORRECTIONS of fuzzy-match errors identified by hand
*     (a few schools were matched to the WRONG Giga record; corrected here
*     using ALL the Giga columns -id, name, lon, lat, level, iso3, country-
*     so the replacement school carries its own complete GPS/metadata,
*     not just its name)
*
* -----------------------------------------------------------------------
* THIS VERSION: OUTPUT ORGANIZATION
*   All outputs now live under a single "Outputs" folder, disaggregated
*   into subfolders by type instead of being dumped flat in the working
*   directory:
*
*     Outputs/
*       Data/       ecoles_benin_fusion_finale.dta / .xlsx   (full merged dataset)
*       Unmatched/  ecoles_benin_non_matchees.xlsx           (unmatched schools)
*                   giga_noms_ambigus.xlsx                   (Giga duplicate names)
*       Subsets/    ecoles_benin_urbain.csv                  (urban schools only)
*                   ecoles_atl_zou.csv                        (Atlantique + Zou)
*       Logs/       merge_ecoles_benin.log
*
*   Folders are created automatically if they don't exist (capture mkdir),
*   so the do-file can be run on a fresh machine/clone without manual setup.
*   All globals ($out_data, $out_unmatched, $out_subsets, $out_logs) are
*   defined once in section 0 and used everywhere else - change the paths
*   there if you want a different layout.
* -----------------------------------------------------------------------
* FIX (carried over from previous version):
*   `corriger_match` is a Stata `program`, which runs in its OWN local
*   scope and does NOT inherit locals from the calling do-file - only
*   globals (and explicit program arguments) are visible inside it.
*   The reference table's path is stored in a GLOBAL ($giga_ref_path)
*   right after it is saved, and the program uses
*   `use "$giga_ref_path", clear' instead of a local tempfile macro,
*   which fixed the "invalid file specification" (r(198)) error.
* -----------------------------------------------------------------------
********************************************************************************

clear all
set more off
version 17

*===============================================================*
* 0. PARAMETERS
*===============================================================*
cd "C:\RONALDO\CKDEV\GENDER NORMS\Randomization"
global dir_data   "."   // <- folder containing both xlsx files
global f_infra    "Datasets\school_list_gender_norm.xlsx"
global f_giga      "Datasets\School_report_page_1_out_of_1_dated_07082026_220741.xlsx"
global seuil_flou  0.80  // minimum score accepted for a fuzzy match (0-1)

* --- Output folder structure (disaggregated by file type) --------------
global dir_out       "Outputs"
global out_data      "$dir_out\Data"
global out_unmatched "$dir_out\Unmatched"
global out_subsets   "$dir_out\Subsets"
global out_logs      "$dir_out\Logs"

capture mkdir "$dir_out"
capture mkdir "$out_data"
capture mkdir "$out_unmatched"
capture mkdir "$out_subsets"
capture mkdir "$out_logs"

capture log close
log using "$out_logs\merge_ecoles_benin.log", replace text

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
display as result "[Giga] " r(N) " rows share a cleaned name with at least one duplicate (set aside, see Unmatched/giga_noms_ambigus.xlsx)."

preserve
    keep if dup_giga > 0
    sort name_key giga_name
    export excel using "$out_unmatched\giga_noms_ambigus.xlsx", firstrow(variables) replace
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

label var statut_match "Match status with the Giga dataset (exact / flou[fuzzy] / manuel / non_matche[unmatched])"
label var score_flou   "Fuzzy-match similarity score (0-1); missing for exact matches; set to 1 for manual corrections"

* Keep a copy of the Giga reference table in memory-friendly form for the
* manual-correction step below (need giga_name -> all other giga_* columns).
*
* FIX: `giga_ref' is a LOCAL tempfile, only visible in THIS scope. The
* corriger_match PROGRAM (section 8) runs in its own scope and cannot see
* it, so we also stash the resolved path in a GLOBAL macro that the
* program can read explicitly.
preserve
    use `giga_clean', clear
    keep giga_id giga_name lon lat giga_level giga_iso3 giga_country
    tempfile giga_ref
    save `giga_ref'
    global giga_ref_path "`giga_ref'"   // <-- FIX: expose path to program scope
restore

tempfile apres_fusion
save `apres_fusion'

*===============================================================*
* 8. MANUAL CORRECTIONS - known fuzzy-match errors
*===============================================================*
* A handful of schools were matched (by reclink) to the WRONG Giga record.
* For each one, we look up the CORRECT Giga school (by its real giga_name)
* in the reference table, and copy ALL of its columns (giga_id, giga_name,
* lon, lat, giga_level, giga_iso3, giga_country) onto the affected row(s) -
* not just the name - so the corrected school comes with its own complete,
* consistent GPS/metadata, and does not end up with a mismatched name/GPS
* pair. score_flou is set to 1 and statut_match to "manuel" so these rows
* are traceable to a human-verified correction rather than an automatic
* match.
*
* This section runs AFTER the final merge and BEFORE any export, so the
* corrections flow through to every downstream file, including
* Subsets/ecoles_benin_urbain.csv, where the fuzzy-match mistakes were
* spotted.
*===============================================================*
use `apres_fusion', clear

capture program drop corriger_match
program define corriger_match
    * nom      : (optionnel) NOMETABLISSEMENT exact de la ligne infra a corriger
    * ancien   : (optionnel) giga_name actuel (errone) de cette ligne, comme
    *            verification supplementaire de securite
    * correct  : (obligatoire) le vrai giga_name a aller chercher dans le
    *            referentiel Giga pour recopier TOUTES ses colonnes
    * Au moins un de nom()/ancien() doit etre fourni pour identifier la ligne.
    syntax , correct(string) [nom(string) ancien(string)]

    if "`nom'" == "" & "`ancien'" == "" {
        display as error "corriger_match: precisez au moins nom() ou ancien() pour identifier la ligne a corriger."
        exit 198
    }

    tempvar hit
    quietly gen byte `hit' = 1
    if "`nom'" != "" {
        quietly replace `hit' = 0 if ustrupper(ustrtrim(NOMETABLISSEMENT)) != ustrupper(ustrtrim("`nom'"))
    }
    if "`ancien'" != "" {
        quietly replace `hit' = 0 if ustrupper(ustrtrim(giga_name)) != ustrupper(ustrtrim("`ancien'"))
    }

    quietly count if `hit' == 1
    if r(N) == 0 {
        display as error "corriger_match: aucune ligne trouvee pour nom()='`nom'' ancien()='`ancien'' - rien n'a ete modifie. Verifiez l'orthographe/l'espacement."
        exit 198
    }
    if r(N) > 1 {
        display as error "corriger_match: " r(N) " lignes trouvees pour nom()='`nom'' ancien()='`ancien'' - condition trop large, precisez-la avant de continuer (aucune modification appliquee)."
        exit 198
    }

    * Look up the correct Giga record in the reference table
    local new_giga_id   ""
    local new_giga_name ""
    local new_lon        = .
    local new_lat         = .
    local new_level     ""
    local new_iso3      ""
    local new_country   ""

    preserve
        * FIX: use the GLOBAL path instead of the (invisible-here) local
        * `giga_ref' tempfile macro. This is the line that previously
        * failed with "invalid file specification" (r(198)).
        use "$giga_ref_path", clear
        keep if ustrupper(ustrtrim(giga_name)) == ustrupper(ustrtrim("`correct'"))
        quietly count
        if r(N) == 0 {
            display as error "corriger_match: aucune ecole Giga nommee '`correct'' n'a ete trouvee dans le referentiel giga_ref - correction ignoree."
            restore
            exit 198
        }
        if r(N) > 1 {
            display as error "corriger_match: plusieurs ecoles Giga partagent le nom '`correct'' - desambiguisez par giga_id avant de continuer - correction ignoree."
            restore
            exit 198
        }
        local new_giga_id   = giga_id[1]
        local new_giga_name = giga_name[1]
        local new_lon       = lon[1]
        local new_lat       = lat[1]
        local new_level     = giga_level[1]
        local new_iso3      = giga_iso3[1]
        local new_country   = giga_country[1]
    restore

    replace giga_id      = "`new_giga_id'"   if `hit' == 1
    replace giga_name    = "`new_giga_name'" if `hit' == 1
    replace lon           = `new_lon'         if `hit' == 1
    replace lat            = `new_lat'         if `hit' == 1
    replace giga_level   = "`new_level'"     if `hit' == 1
    replace giga_iso3    = "`new_iso3'"      if `hit' == 1
    replace giga_country = "`new_country'"   if `hit' == 1
    replace score_flou   = 1                  if `hit' == 1
    replace statut_match = "manuel"          if `hit' == 1

    display as result "corriger_match: 1 ligne corrigee (nom='`nom'' ancien='`ancien'') -> giga_name = '`new_giga_name'' (giga_id = `new_giga_id'')."
end

* --- Correction 1 ------------------------------------------------------
* CEG 1 BERTRAND DAGNON (infra) avait ete rattache par erreur a
* "CEG 1 BONOU" (giga_name) ; le bon etablissement Giga est "CEG 1 OUIDAH".
corriger_match, nom("CEG 1 BERTRAND DAGNON") ancien("CEG 1 BONOU") correct("CEG 1 OUIDAH")

* --- Corrections 2a et 2b -----------------------------------------------
* Deux etablissements infra distincts avaient tous les deux ete rattaches
* au meme enregistrement Giga "LYCEE DES JEUNES FILLES MC"
* (giga_id = 890a1f61-6627-3d08-980f-a1938c181158). Distingues ici par leur
* NOMETABLISSEMENT exact.
corriger_match, nom("LYCEE DES JEUNES FILLES ATL/LIT")     correct("LYCEE TECHNIQUE DE OUIDAH")
corriger_match, nom("LYCEE DES JEUNES FILLES ZOU COLLINES") correct("LYCEE DES JEUNES FILLES D'ABOMEY")

* --- Correction 3 -------------------------------------------------------
* "CEG LANTA" (giga_name, mauvais rattachement) doit etre remplace par
* "CEG 1 COVE".
corriger_match, ancien("CEG LANTA") correct("CEG 1 COVE")

* Cleanup: drop the helper global now that all corrections are applied,
* so re-running this do-file in the same session can't accidentally reuse
* a stale path from a previous run.
global giga_ref_path ""

tempfile apres_corrections
save `apres_corrections'

quietly count if statut_match == "manuel"
display as result ">>> Corrections manuelles appliquees: " r(N) " lignes (statut_match == 'manuel')."

*===============================================================*
* 9. EXPORTS - full merged dataset (Outputs/Data)
*===============================================================*
use `apres_corrections', clear

* Full dataset, with a match-quality indicator
save "$out_data\ecoles_benin_fusion_finale.dta", replace
export excel using "$out_data\ecoles_benin_fusion_finale.xlsx", firstrow(variables) replace

* On-screen summary
tab statut_match
display as result "Note: Giga schools with ambiguous (duplicate) names were excluded from automatic matching -> see Unmatched/giga_noms_ambigus.xlsx to link them manually if needed."

* Separate file of unmatched schools, to check/complete manually (Outputs/Unmatched)
preserve
    keep if statut_match == "non_matche"
    export excel using "$out_unmatched\ecoles_benin_non_matchees.xlsx", firstrow(variables) replace
    quietly count
    display as result ">>> " r(N) " schools WITHOUT GPS coordinates after matching -> see Unmatched/ecoles_benin_non_matchees.xlsx"
restore

log close

*===============================================================*
* 10. FINAL VARIABLE CLEANUP + URBAN SUBSET EXPORT (Outputs/Subsets)
*===============================================================*
use "$out_data\ecoles_benin_fusion_finale.dta", clear

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

save "$out_data\ecoles_benin_fusion_finale.dta", replace
export excel using "$out_data\ecoles_benin_fusion_finale.xlsx", firstrow(variables) replace
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

    * "quote" force les champs texte a etre entoures de guillemets s'ils
    * contiennent le delimiteur (virgule). SANS cette option, un nom
    * d'ecole/commune/departement contenant une virgule decale les colonnes
    * suivantes dans le CSV -> tres problematique pour tout import externe
    * (ex: Google Earth Engine, qui peut alors interpreter "lon"/"lat"
    * comme une LISTE au lieu d'un NOMBRE -> erreur
    * "GeometryConstructors.Point: Inputs must be Number, List, or Geometry.
    * Found type 'List<Object>'.").
    export delimited using "$out_subsets\ecoles_benin_urbain.csv", replace quote

    quietly count
    display as result ">>> " r(N) " urban schools -> Subsets/ecoles_benin_urbain.csv (technical/matching variables removed, fuzzy-match errors corrected)"
restore

*===============================================================*
* 11. ATLANTIQUE + ZOU SUBSET EXPORT (Outputs/Subsets)
*===============================================================*
* NOTE: the original script dropped the ambiguous school and exported
* "ecoles_atl_zou.csv" WITHOUT actually filtering on DEPARTEMENT, so the
* file contained every department, not just Atlantique/Zou. Fixed below:
* the department filter is applied and the export is done from a clean
* reload of the corrected, full dataset (not from whatever happened to be
* left in memory).
*----------------------------------------------------------------*
use "$out_data\ecoles_benin_fusion_finale.dta", clear

* Drop the ambiguous public school (name matches two real establishments,
* cannot be disambiguated automatically)
drop if ustrupper(ustrtrim(NOMETABLISSEMENT)) == ustrupper(ustrtrim("CPEG PRODIGES DE DIEU"))

* Keep only Atlantique and Zou departments
* A ADAPTER si l'orthographe exacte de DEPARTEMENT differe (accents,
* majuscules) dans votre fichier infra - verifiez avec: tab DEPARTEMENT
gen departement_norm = ustrupper(ustrtrim(DEPARTEMENT))
keep if inlist(departement_norm, "ATLANTIQUE", "ZOU")
drop departement_norm

export delimited using "$out_subsets\ecoles_atl_zou.csv", replace quote
quietly count
display as result ">>> " r(N) " ecoles (Atlantique + Zou) -> Subsets/ecoles_atl_zou.csv"

********************************************************************************

* NOTES
* - Adjust $dir_data if your files are not in the current folder.
* - Output layout (all under "$dir_out" = "Outputs"):
*     Outputs/Data/       -> ecoles_benin_fusion_finale.dta / .xlsx
*     Outputs/Unmatched/  -> ecoles_benin_non_matchees.xlsx, giga_noms_ambigus.xlsx
*     Outputs/Subsets/    -> ecoles_benin_urbain.csv, ecoles_atl_zou.csv
*     Outputs/Logs/       -> merge_ecoles_benin.log
*   Change the $out_data / $out_unmatched / $out_subsets / $out_logs
*   globals in section 0 to relocate any of these.
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
*   They are exported to Outputs/Unmatched/giga_noms_ambigus.xlsx: link
*   them manually based on commune/department if you have that info on
*   both sides.
* - If you have commune/department available on both sides, a better
*   long-term solution is to add it as an extra blocking variable
*   (allows automatic disambiguation of homonyms) -> let me know and
*   I'll adapt the script.
* - Section 8 (manual corrections) fixes 4 known fuzzy-match errors.
*   Each correction copies ALL Giga columns (id, name, lon, lat, level,
*   iso3, country) from the CORRECT school, not just the name, so the
*   corrected row is fully self-consistent. If you spot more mismatches,
*   duplicate one of the "corriger_match, nom(...) ancien(...) correct(...)"
*   lines and adjust nom()/ancien()/correct() to the schools concerned.
* - For the two "LYCEE DES JEUNES FILLES MC" cases (same giga_id used
*   twice), the two infra schools are now distinguished by their exact
*   NOMETABLISSEMENT ("LYCEE DES JEUNES FILLES ATL/LIT" and
*   "LYCEE DES JEUNES FILLES ZOU COLLINES").
* - corriger_match reads the Giga reference table via the global
*   $giga_ref_path instead of a local `giga_ref' tempfile macro, which
*   programs cannot see - this is what fixed the r(198) error.
* - All "capture mkdir" calls in section 0 are silent no-ops if the
*   folder already exists, so re-running the do-file repeatedly is safe.
********************************************************************************
