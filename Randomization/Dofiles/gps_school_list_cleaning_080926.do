/***********************************************************************
*=======================================================================
* CLASSIFICATION DES ECOLES - ZOU
* Préparation de la base de classification
*=======================================================================
***********************************************************************/

clear all
set more off
version 17

capture log close _all


*=======================================================================
* 1. CHEMINS
*=======================================================================

global project "C:\RONALDO\CKDEV\GENDER NORMS\Randomization"

global input "$project\ecoles_alt_zou_indicateurs_v2.csv"

global output_dta  "$project\classification_nettoyee.dta"
global output_xlsx "$project\classification_nettoyee.xlsx"
global logfile    "$project\classification.log"


*=======================================================================
* 2. LOG
*=======================================================================

log using "$logfile", replace text


*=======================================================================
* 3. IMPORTATION
*=======================================================================

display "=============================================================="
display "IMPORTATION DE LA BASE"
display "=============================================================="

import delimited using "$input", clear

display "Nombre initial d'observations : " _N


*=======================================================================
* 4. VERIFICATION DES VARIABLES
*=======================================================================

describe


*=======================================================================
* 5. NETTOYAGE DES NOMS D'ETABLISSEMENTS
*=======================================================================

replace nometablissement = trim(itrim(nometablissement))


*=======================================================================
* 6. EXCLUSION DE L'ETABLISSEMENT CIBLE
*=======================================================================

display ""
display ">>> Exclusion de CPEG PRODIGES DE DIEU"

count if nometablissement == "CPEG PRODIGES DE DIEU"

display "Nombre d'observations trouvées : " r(N)

drop if nometablissement == "CPEG PRODIGES DE DIEU"


*=======================================================================
* 7. NETTOYAGE DES VARIABLES GEOGRAPHIQUES
*=======================================================================

foreach var in departement commune arrondissement quartiervillage {

    replace `var' = trim(itrim(`var'))
}


*=======================================================================
* 8. CONSERVATION DES VARIABLES NECESSAIRES
*=======================================================================

keep ///
    departement ///
    commune ///
    arrondissement ///
    quartiervillage ///
    nometablissement ///
    milieu ///
    giga_name ///
    degurba_etude_classe_2020 ///
    degurba_l1_officiel_2020


*=======================================================================
* 9. TRI
*=======================================================================

sort departement ///
     commune ///
     arrondissement ///
     quartiervillage ///
     nometablissement


*=======================================================================
* 10. CONTROLES
*=======================================================================

display ""
display "=============================================================="
display "CONTROLES DE QUALITE"
display "=============================================================="

display ""
display "Nombre final d'écoles : " _N

display ""
display "Variables finales :"

describe


display ""
display ">>> Doublons sur les établissements"

duplicates report nometablissement


display ""
display ">>> Valeurs manquantes"

misstable summarize


display ""
display ">>> MILIEU"

tab milieu, missing


display ""
display ">>> GIGA NAME"

tab giga_name, missing


display ""
display ">>> DEGURBA ETUDE"

tab degurba_etude_classe_2020, missing


display ""
display ">>> DEGURBA L1 OFFICIEL"

tab degurba_l1_officiel_2020, missing


*=======================================================================
* 11. SAUVEGARDE STATA
*=======================================================================

save "$output_dta", replace


*=======================================================================
* 12. EXPORTATION EXCEL
*=======================================================================

export excel using "$output_xlsx", ///
    firstrow(variables) ///
    replace


*=======================================================================
* 13. RESUME FINAL
*=======================================================================

display ""
display "=============================================================="
display "TRAITEMENT TERMINE AVEC SUCCES"
display "=============================================================="

display "Nombre final d'écoles : " _N

display ""
display "Fichier Stata : $output_dta"
display "Fichier Excel : $output_xlsx"
display "Log            : $logfile"

display "=============================================================="


*=======================================================================
* 14. FERMETURE
*=======================================================================

log close _all