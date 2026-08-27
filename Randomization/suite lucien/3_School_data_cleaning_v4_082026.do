/********************************************************************
 Project      : Gender norm
 Author       : Lucien Allosse — v4, reprise du nettoyage avec la
                nouvelle classification manuelle de l'equipe
                (2 milieux retenus : Rural et Peri-urbain uniquement)
 Date         : [14 Aaout 2026]
 Purpose      : Reconstruire l'echantillon eligible a partir de la
                feuille "Final_ecole_gender_norm" (classification
                manuelle) croisee avec la base brute des ecoles.
 Software     : Stata 16
 Inputs       : school_list_07162026.xlsx
                Copie_de_ecoles_gender_norms_081326.xlsx
                (feuille "Final_ecole_gender_norm")
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

global working "C:\1_CKDEV_File\1_CKDev_File\3_Projet_   Gender_ Norms_  May_2026\5_File_About_ Randomisation_ 08032026\9_School_data_ cleaning_v4_suite_ 08182026"    // TODO: adapter le chemin

global raw     "$working"
global output  "$working\clean"

capture mkdir "$output"
cd "$working"

*---------------------------------------------------------------*
* 2. Parameters

local seuil_filles = 15   // TODO: confirmer 15 ou 20 avec le PI/l'equipe

*---------------------------------------------------------------*
* 3. Open Log File

log using "$output\school_cleaning_log_v4.smcl", replace

*---------------------------------------------------------------*
* 4. Import de la classification manuelle de l'equipe
*    (feuille "Final_ecole_gender_norm")

import excel "$working\Copie_de_ecoles_gender_norms_081326.xlsx", ///
    sheet("Final_ecole_gender_norm") firstrow clear

describe
count
* Attendu : 161  (Si j eneleve la ligne du nom des variables)

* Cle de fusion robuste
gen ecole_key = strupper(strtrim(COMMUNE)) + "_" + strupper(strtrim(NOMETABLISSEMENT))

duplicates report ecole_key
* TODO: si des doublons apparaissent, verifier l'orthographe avant de continuer.

* Uniformisation de la classification (gestion de la case incoherente,
* ex. "Rural" vs "RURAL")
gen classification_std = strupper(strtrim(classification))
tab classification_std

* Generer une nouvelle variable qui contient les milieu : periubain vs rural.

/*gen MILIEU_EQUIPE = ""
replace MILIEU_EQUIPE = "Rural"       if classification_std == "RURAL"
replace MILIEU_EQUIPE = "Peri-urbain" if classification_std == "PERIURBAN"
* URBAN_SEMIDENSE et URBAN_CORE restent MILIEU_EQUIPE == "" -> hors champ
* de l'etude (ni Rural, ni Peri-urbain), seront exclus plus loin.

tab MILIEU_EQUIPE, missing

keep ecole_key MILIEU_EQUIPE classification_std
tempfile classification
save `classification'
*/
gen MILIEU_EQUIPE = ""
replace MILIEU_EQUIPE = "Rural"       if classification_std == "RURAL"
replace MILIEU_EQUIPE = "Peri-urbain" if classification_std == "PERIURBAN"
replace MILIEU_EQUIPE = "Peri-urbain" if classification_std == "URBAN_SEMIDENSE"
* URBAN_CORE reste MILIEU_EQUIPE == "" -> seule categorie encore exclue
* (confirmee par l'equipe comme hors champ Rural/Peri-urbain).

* Verification des statistiques avant d evoluer
tab MILIEU_EQUIPE, missing

keep ecole_key MILIEU_EQUIPE classification_std   // continuer avec ce je veux
tempfile classification
save `classification'


*---------------------------------------------------------------*
* 5. Import raw school data

import excel "$working\school_list_07162026.xlsx", firstrow clear
gen ecole_key = strupper(strtrim(COMMUNE)) + "_" + strupper(strtrim(NOMETABLISSEMENT))

*---------------------------------------------------------------*
* 6. Filtrage geographique et statut (inchange)

keep if inlist(DEPARTEMENT, "ATLANTIQUE", "ZOU")
keep if STATUT == "Public"
count
* Attendu : 188

*---------------------------------------------------------------*  
* 7. Fusion avec la classification manuelle de l'equipe

merge 1:1 ecole_key using `classification'

* _merge==1 : ecole de la base brute absente de la classification finale
*             de l'equipe -> exclue (a confirmer que c'est voulu, voir
*             note d'analyse - 27 ecoles attendues dans ce cas).
* _merge==2 : ne devrait jamais arriver ici (toutes les ecoles de la
*             classification proviennent de la base brute).
* _merge==3 : ecole correctement appariee -> attendu, 161 ecoles.

tab _merge
count if _merge == 2
* TODO: doit etre 0. Sinon, verifier l'orthographe cote classification.

*---------------------------------------------------------------*
* 8. Construction des indicateurs d'eligibilite (sans suppression),
*    pour permettre la tracabilite complete des exclusions.

gen elig_classification = (_merge == 3) & inlist(MILIEU_EQUIPE, "Rural", "Peri-urbain")
gen elig_filles6e = NBF6EME >= `seuil_filles'     
gen elig_filles5e = NBF5EME >= `seuil_filles'

gen byte eligible = elig_classification & elig_filles6e & elig_filles5e

gen exclusion_reason = ""
replace exclusion_reason = "Absente de la classification finale de l'equipe" if _merge == 1
replace exclusion_reason = "Classee urbaine (core), hors champ Rural/Peri-urbain" ///
    if COMMUNE == "ABOMEY" & strpos(upper(NOMETABLISSEMENT), "ELITES") > 0

replace exclusion_reason = "Classee urbaine (semi-dense ou core), hors champ Rural/Peri-urbain" ///
    if _merge == 3 & MILIEU_EQUIPE == ""
replace exclusion_reason = "Filles insuffisantes (6e et 5e)" ///
    if elig_classification & !elig_filles6e & !elig_filles5e
replace exclusion_reason = "Filles insuffisantes (6e)" ///
    if elig_classification & !elig_filles6e &  elig_filles5e
replace exclusion_reason = "Filles insuffisantes (5e)" ///
    if elig_classification &  elig_filles6e & !elig_filles5e

label var eligible "Ecole retenue dans l'echantillon final (1=oui)"
label var exclusion_reason "Raison d'exclusion si non retenue"

tab exclusion_reason, missing
count if eligible == 1

*---------------------------------------------------------------*
* 9. Journal des exclusions (export pour l'equipe / tracabilite)

preserve
    keep if eligible == 0
    keep DEPARTEMENT COMMUNE ARRONDISSEMENT NOMETABLISSEMENT MILIEU MILIEU_EQUIPE ///
         NBF6EME NBF5EME exclusion_reason
    order DEPARTEMENT COMMUNE ARRONDISSEMENT NOMETABLISSEMENT MILIEU MILIEU_EQUIPE ///
          NBF6EME NBF5EME exclusion_reason
    gsort exclusion_reason DEPARTEMENT COMMUNE
    export excel using "$output/log_exclusions_v4.xlsx", firstrow(variables) replace
    count
restore

*---------------------------------------------------------------*    
* 10. Application du filtre final (echantillon retenu)

keep if eligible == 1
count
count if DEPARTEMENT == "ZOU"
count if DEPARTEMENT == "ATLANTIQUE"
tab MILIEU_EQUIPE

*---------------------------------------------------------------*
* 11. Distribution par commune

preserve
    contract DEPARTEMENT COMMUNE, freq(nb_ecoles)
    gsort DEPARTEMENT -nb_ecoles
    order DEPARTEMENT COMMUNE nb_ecoles
    list, sepby(DEPARTEMENT) noobs
    export excel using "$output/distribution_communes_v4.xlsx", firstrow(variables) replace
restore

*---------------------------------------------------------------*

*---------------------------------------------------------------*
* 11bis. Liste des etablissements retenus, par commune
*        (complement a la section 11 qui ne donne que les comptes)

preserve
    keep DEPARTEMENT COMMUNE NOMETABLISSEMENT MILIEU_EQUIPE NBF6EME NBF5EME
    gsort DEPARTEMENT COMMUNE NOMETABLISSEMENT
    order DEPARTEMENT COMMUNE NOMETABLISSEMENT MILIEU_EQUIPE NBF6EME NBF5EME

    list DEPARTEMENT COMMUNE NOMETABLISSEMENT MILIEU_EQUIPE, sepby(COMMUNE) noobs

    export excel using "$output/liste_ecoles_retenues_par_commune_v4.xlsx", firstrow(variables) replace
restore


*---------------------------------------------------------------*
* 12. Communes favorables vs communes necessitant une decision du PI
*     (taille des blocs si decoupage en 2 categories de taille)

/*La logique : pour chaque commune, on simule le découpage en 2 catégories de taille (bloc_min = la moitié la plus petite). Si cette moitié descend sous 4 écoles (c est moi qui est fixe ce seuil), 
Avec les chiffres actuels, on devrais obtenir 13 communes "Favorable" et 
la commune est marquée "Décision PI requise" ; sinon "Favorable".


4 "Décision PI requise" (Sô-Ava, Covè, Ouinhi, Abomey — celles avec n<8)

*/

/*
local seuil_bloc_min = 6   // taille minimale acceptable pour un demi-bloc

preserve
    contract DEPARTEMENT COMMUNE, freq(nb_ecoles)

    gen bloc_min = floor(nb_ecoles/2)
    gen bloc_max = ceil(nb_ecoles/2)

    gen statut_commune = "Favorable"
    replace statut_commune = "Decision PI requise" if bloc_min < `seuil_bloc_min'

    gsort statut_commune DEPARTEMENT -nb_ecoles
    list DEPARTEMENT COMMUNE nb_ecoles bloc_min bloc_max statut_commune, sepby(statut_commune) noobs

    count if statut_commune == "Favorable"
    count if statut_commune == "Decision PI requise"

    export excel using "$output/statut_communes_blocs_v4.xlsx", firstrow(variables) replace
restore
*/

/*
*---------------------------------------------------------------*
* 13. Simulation de fusions de communes - seuil minimum de 6 par
*     demi-bloc (equivalent a 12 ecoles au total dans le groupe)
*
*     ATTENTION : regroupement PUREMENT MECANIQUE (construit par
*     taille croissante, sans connaissance de la geographie reelle).
*     A CORRIGER avec la connaissance du terrain avant validation.
*     Cas non resolu meme apres ce premier passage : BOHICON (10
*     ecoles, bloc_min=5) reste seule sous le seuil - a rattacher
*     manuellement a une vraie commune voisine.

local seuil_bloc_min = 6

preserve
    contract DEPARTEMENT COMMUNE, freq(nb_ecoles)

    gen groupe_commune = COMMUNE

    * --- Zou (a corriger selon la geographie reelle) ---
    replace groupe_commune = "COVE+OUINHI+ABOMEY" ///
        if inlist(COMMUNE,"COVE","OUINHI","ABOMEY")
    replace groupe_commune = "AGBANGNIZOUN+ZAGNANADO" ///
        if inlist(COMMUNE,"AGBANGNIZOUN","ZAGNANADO")
    replace groupe_commune = "ZA-KPOTA+DJIDJA" ///
        if inlist(COMMUNE,"ZA-KPOTA","DJIDJA")
    * BOHICON et ZOGBODOMEY laissees seules ici - BOHICON reste sous
    * le seuil (voir avertissement ci-dessus), a corriger.

    * --- Atlantique (a corriger selon la geographie reelle) ---
    replace groupe_commune = "SO-AVA+TORI-BOSSITO" ///
        if inlist(COMMUNE,"SO-AVA","TORI-BOSSITO")
    replace groupe_commune = "OUIDAH+TOFFO" ///
        if inlist(COMMUNE,"OUIDAH","TOFFO")
    replace groupe_commune = "KPOMASSE+ZE" ///
        if inlist(COMMUNE,"KPOMASSE","ZE")
    * ALLADA et ABOMEY-CALAVI deja favorables seules, non regroupees.

    collapse (sum) nb_ecoles, by(DEPARTEMENT groupe_commune)

    gen bloc_min = floor(nb_ecoles/2)
    gen statut_groupe = cond(bloc_min >= `seuil_bloc_min', "Favorable", "Decision PI requise")

    gsort statut_groupe DEPARTEMENT -nb_ecoles
    list DEPARTEMENT groupe_commune nb_ecoles bloc_min statut_groupe, sepby(statut_groupe) noobs

    count if statut_groupe == "Favorable"
    count if statut_groupe == "Decision PI requise"

    export excel using "$output/fusion_communes_v1.xlsx", firstrow(variables) replace
restore

*/

**** Fusion des ecoles par departement :

*---------------------------------------------------------------*
* 14a. Construction des blocs de fusion - ATLANTIQUE
*      (methode proposee par la coordonnatrice, validee arithmetiquement :
*      84 ecoles = 14 blocs de 6)
*
*      NOTE : le tri interne (rang) est actuellement alphabetique, car
*      la taille n'est plus utilisee comme critere de blocage dans ce
*      schema. Remplacer NOMETABLISSEMENT par taille_filles si vous
*      preferez repartir les grandes/petites ecoles plus uniformement
*      entre les blocs.

* Numéroter les établissements par commune
bysort COMMUNE (NOMETABLISSEMENT): gen rang = _n

* Générer une variable texte vide pour identifier les blocs de fusion
gen bloc_fusion = ""

* Abomey-Calavi (19) : 3 blocs purs + 1 ecole reportee vers So-Ava

* Création de 4 blocs de fusion : 3 blocs de 6 écoles à Abomey-Calavi
* et un bloc regroupant la dernière école d'Abomey-Calavi avec les 5 écoles de So-Ava
replace bloc_fusion = "ATL_B01" if COMMUNE=="ABOMEY-CALAVI" & inrange(rang,1,6)
replace bloc_fusion = "ATL_B02" if COMMUNE=="ABOMEY-CALAVI" & inrange(rang,7,12)
replace bloc_fusion = "ATL_B03" if COMMUNE=="ABOMEY-CALAVI" & inrange(rang,13,18)
replace bloc_fusion = "ATL_B04" if COMMUNE=="ABOMEY-CALAVI" & rang==19

* So-Ava (5) + leftover Abomey-Calavi (1) = 6
replace bloc_fusion = "ATL_B04" if COMMUNE=="SO-AVA"

* Ouidah (9) + Kpomasse (10) = 19 ecoles regroupees : 3 blocs + 1 reste
* Ouidah (9) + Kpomasse (10) : création de 3 blocs de 6 écoles et 1 école restante
* Le bloc ATL_B06 combine les 3 dernières écoles de Ouidah avec les 3 premières de Kpomasse.
replace bloc_fusion = "ATL_B05" if COMMUNE=="OUIDAH" & inrange(rang,1,6)
replace bloc_fusion = "ATL_B06" if COMMUNE=="OUIDAH" & inrange(rang,7,9) //
replace bloc_fusion = "ATL_B06" if COMMUNE=="KPOMASSE" & inrange(rang,1,3)
replace bloc_fusion = "ATL_B07" if COMMUNE=="KPOMASSE" & inrange(rang,4,9)
replace bloc_fusion = "ATL_B08" if COMMUNE=="KPOMASSE" & rang==10

* Tori-Bossito (8) + leftover Kpomasse (1) = 9 : 1 bloc + 3 restantes
* Tori-Bossito (8) + 1 école restante de Kpomasse (1) = 9 écoles
* Création d'un bloc complet de 6 et un reste de 3 écoles
* ATL_B08 combine 1 école de Kpomasse avec 5 écoles de Tori-Bossito.
replace bloc_fusion = "ATL_B08" if COMMUNE=="TORI-BOSSITO" & inrange(rang,1,5)
replace bloc_fusion = "ATL_B09" if COMMUNE=="TORI-BOSSITO" & inrange(rang,6,8)

* Allada (14) + leftover Tori-Bossito (3) + 1 ecole de Toffo = 18 : 3 blocs
* Allada (14) + 3 écoles restantes de Tori-Bossito + 1 école de Toffo = 18 écoles
* Création de 3 blocs complets de 6 écoles
* ATL_B09 : 3 Tori-Bossito + 3 Allada
* ATL_B10 : 6 Allada
* ATL_B11 : 5 Allada + 1 Toffo
replace bloc_fusion = "ATL_B09" if COMMUNE=="ALLADA" & inrange(rang,1,3)
replace bloc_fusion = "ATL_B10" if COMMUNE=="ALLADA" & inrange(rang,4,9)
replace bloc_fusion = "ATL_B11" if COMMUNE=="ALLADA" & inrange(rang,10,14)
replace bloc_fusion = "ATL_B11" if COMMUNE=="TOFFO" & rang==1

* Toffo : 8 écoles restantes sur 9
* Création d'un bloc complet de 6 écoles et 2 écoles restantes
* Toffo (8 restantes sur 9) : 1 bloc + 2 restantes
replace bloc_fusion = "ATL_B12" if COMMUNE=="TOFFO" & inrange(rang,2,7)
replace bloc_fusion = "ATL_B13" if COMMUNE=="TOFFO" & inrange(rang,8,9)

* Ze (10) + 2 écoles restantes de Toffo = 12 : 2 blocs complets
* Ze (10) + leftover Toffo (2) = 12 : 2 blocs
replace bloc_fusion = "ATL_B13" if COMMUNE=="ZE" & inrange(rang,1,4)
replace bloc_fusion = "ATL_B14" if COMMUNE=="ZE" & inrange(rang,5,10)

tab bloc_fusion if DEPARTEMENT=="ATLANTIQUE", missing
count if DEPARTEMENT=="ATLANTIQUE" & bloc_fusion==""
* TODO: doit etre 0 - sinon une ecole a echappe au schema.

*---------------------------------------------------------------*
* 14b. Construction des blocs de fusion - ZOU
*      (72 ecoles = 12 blocs de 6)

replace bloc_fusion = "ZOU_B01" if COMMUNE=="ZOGBODOMEY" & inrange(rang,1,6)
replace bloc_fusion = "ZOU_B02" if COMMUNE=="ZOGBODOMEY" & inrange(rang,7,12)

replace bloc_fusion = "ZOU_B03" if COMMUNE=="OUINHI"

replace bloc_fusion = "ZOU_B04" if COMMUNE=="ABOMEY"

* Agbangnizoun (8) : 1 bloc pur + 2 restantes
replace bloc_fusion = "ZOU_B05" if COMMUNE=="AGBANGNIZOUN" & inrange(rang,1,6)
replace bloc_fusion = "ZOU_B06" if COMMUNE=="AGBANGNIZOUN" & inrange(rang,7,8)

* Bohicon (10) + leftover Agbangnizoun (2) = 12 : 2 blocs
replace bloc_fusion = "ZOU_B06" if COMMUNE=="BOHICON" & inrange(rang,1,4)
replace bloc_fusion = "ZOU_B07" if COMMUNE=="BOHICON" & inrange(rang,5,10)

* Djidja (9) : 1 bloc pur + 3 restantes (tenues a part, PAS chainees)
replace bloc_fusion = "ZOU_B08" if COMMUNE=="DJIDJA" & inrange(rang,1,6)
replace bloc_fusion = "ZOU_B12a" if COMMUNE=="DJIDJA" & inrange(rang,7,9)

* Za-Kpota (8) : 1 bloc pur + 2 restantes (tenues a part)
replace bloc_fusion = "ZOU_B09" if COMMUNE=="ZA-KPOTA" & inrange(rang,1,6)
replace bloc_fusion = "ZOU_B12b" if COMMUNE=="ZA-KPOTA" & inrange(rang,7,8)

* Zagnanado (8) : 1 bloc pur + 2 restantes (tenues a part)
replace bloc_fusion = "ZOU_B10" if COMMUNE=="ZAGNANADO" & inrange(rang,1,6)
replace bloc_fusion = "ZOU_B12c" if COMMUNE=="ZAGNANADO" & inrange(rang,7,8)

* Cove (5) + les 3 groupes de restantes (Djidja3+ZaKpota2+Zagnanado2=7) = 12 : 2 blocs
* Repartition : Cove(5) + 1 ecole de Djidja = 6 pour B11
*               2 ecoles de Djidja + ZaKpota(2) + Zagnanado(2) = 6 pour B12

replace bloc_fusion = "ZOU_B11" if COMMUNE=="COVE" & inrange(rang,1,5)
replace bloc_fusion = "ZOU_B11" if COMMUNE=="DJIDJA" & rang==7
replace bloc_fusion = "ZOU_B12" if COMMUNE=="DJIDJA" & inrange(rang,8,9)
replace bloc_fusion = "ZOU_B12" if COMMUNE=="ZA-KPOTA" & inrange(rang,7,8)
replace bloc_fusion = "ZOU_B12" if COMMUNE=="ZAGNANADO" & inrange(rang,7,8)

tab bloc_fusion if DEPARTEMENT=="ZOU", missing
count if DEPARTEMENT=="ZOU" & bloc_fusion==""
* TODO: doit etre 0.

*---------------------------------------------------------------*  
* 14c. Verification finale globale

tab bloc_fusion
tabstat rang, by(bloc_fusion) stat(n) missing
* Chaque bloc_fusion doit compter exactement 6 ecoles.

* 12. Save the data

save "$output\school_list_gender_norm_v4.dta", replace
export excel using "$output/school_list_gender_norm_v4.xlsx", firstrow(variables) replace

log close

gen six_cinq = NBF5EME + NBF6EME
tab six_cinq 










