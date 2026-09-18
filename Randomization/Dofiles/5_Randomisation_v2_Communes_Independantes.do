/********************************************************************
 Project      : Gender norm
 Author       : Lucien Allosse 
 Date         : [29 Aout 2026]
 Purpose      : Randomisation v2 - integre le retour du PI (27/08/2026) :
 
                (1) randomisation du parent imbriquee dans bloc x bras,
                    pas seulement dans bloc ;
					
                (2) Small et Large forment des strates SEPAREES (plus
                    de melange dans un meme bloc) ;
					
                (3) chaque commune reste strictement independante -
                    AUCUNE fusion cross-commune. Le dernier bloc d'une
                    strate prend simplement le nombre d'ecoles restant,
                    meme si c'est moins de 6.
 Software     : Stata 16
 Input        : school_list_gender_norm_v4.dta (156 ecoles eligibles,
                classification MILIEU_EQUIPE Rural/Peri-urbain deja
                validee)
********************************************************************/

*======================================================================*
* 0. INITIALISATION
*======================================================================*

version 16.0
clear all
set more off
set varabbrev off
capture log close
capture frame drop arm_draw

cd "C:\RONALDO\CKDEV\GENDER NORMS\Randomization\Lucien_v2"
global datadir   "Datasets"
global outputdir "Outputs/Lucien_v2"

global mergeoutdir "$outputdir/Data"
global infile "$mergeoutdir/master_x_gender_norm.xlsx"


global outputdir "$working\Outputs"
capture mkdir "$outputdir"
cd "$working"

/*global SEED_BLOCKS  20260827
global SEED_ARMS 20260904
*global SEED_ARMS    20260828
global SEED_PARENT  20260829
global N_ARMS       3
*/
global SEED_BLOCKS 20260827
global SEED_ARMS   20260713
global SEED_PARENT 20260101
global N_ARMS       3

local timestamp : display %tcCCYY-NN-DD_HH-MM-SS clock("$S_DATE $S_TIME","DMYhms")
local timestamp = subinstr("`timestamp'"," ","_",.)

log using "$outputdir/randomization_v2_log_`timestamp'.smcl", replace

*======================================================================*
* 1. IMPORT DE LA BASE ELIGIBLE (156 ECOLES)
*======================================================================*

use "C:\RONALDO\CKDEV\GENDER NORMS\Randomization\Lucien_v2\school_list_gender_norm_v4.dta", clear

*import excel "$working\master_x_gender_norm.xlsx", firstrow clear

isid ecole_key
quietly count
local n_total = r(N)
di as result "Base importee : `n_total' ecoles (attendu : 156)."
assert `n_total' == 156

capture confirm variable id_infra
if _rc {
    gen long id_infra = _n
    label var id_infra "Identifiant unique ecole (genere)"
}

*======================================================================*
* 2. VARIABLE DE TAILLE (FILLES UNIQUEMENT) ET CLASSIFICATION
*    SMALL / LARGE PAR MEDIANE COMMUNALE
*======================================================================*

gen long target_enrol = NBF6EME + NBF5EME
label var target_enrol "Effectif filles 6e+5e (variable de taille)"

capture drop med_enrol
bysort COMMUNE: egen double med_enrol = median(target_enrol)
label var med_enrol "Mediane communale de target_enrol"

capture drop size_label
gen str5 size_label = ""
replace size_label = "Small" if target_enrol <= med_enrol
replace size_label = "Large" if target_enrol >  med_enrol

quietly count if size_label == ""
assert r(N) == 0

tab COMMUNE size_label

*======================================================================*
* 3. STRATE = COMMUNE x SIZE_LABEL (INDEPENDANTE, AUCUNE FUSION)
*======================================================================*

capture drop strate_label
gen str40 strate_label = COMMUNE + "_" + size_label
label var strate_label "Strate independante : commune x taille"

capture drop strate_id
egen long strate_id = group(strate_label)
label var strate_id "Identifiant numerique de strate"

bysort strate_id: gen long strate_n = _N
label var strate_n "Nombre d'ecoles dans la strate"

di as result "======================================================="
di as result "COMPOSITION DES STRATES (commune x taille), SANS FUSION"
di as result "======================================================="

preserve
    contract strate_id strate_label strate_n
    gsort -strate_n
    list strate_label strate_n, noobs sep(0)
    quietly count if strate_n < 6
    di as result "`r(N)' strates sur `=_N' ont moins de 6 ecoles (attendu)."
restore

*======================================================================*
* 4. CONSTRUCTION DES BLOCS A L'INTERIEUR DE CHAQUE STRATE
*    Regle du PI : blocs de 6 tant que possible, le DERNIER bloc de la
*    strate prend le nombre d'ecoles restant (peut etre < 6).
*======================================================================*

sort id_infra
set seed $SEED_BLOCKS
capture drop rand_block
gen double rand_block = runiform()

capture drop rank_in_strate
sort strate_id rand_block
by strate_id: gen long rank_in_strate = _n

capture drop block_in_strate
* Bloc plein tant que le rang le permet ; le reste forme le dernier bloc.
gen long block_in_strate = ceil(rank_in_strate / 6)
label var block_in_strate "Numero de bloc au sein de la strate"

capture drop bloc
egen long bloc = group(strate_id block_in_strate)
label var bloc "Identifiant final du bloc de randomisation"

bysort bloc: gen long bloc_n = _N
label var bloc_n "Nombre d'ecoles dans le bloc final"

*quietly summarize bloc_n, meanonly
summarize bloc_n
di as result "======================================================="
di as result "BLOCS FINAUX (sans fusion)"
di as result "======================================================="
quietly levelsof bloc, local(blist)
di as result "Nombre de blocs  : `: word count `blist''"
di as result "Taille minimale  : `r(min)'"
di as result "Taille maximale  : `r(max)'"

isid id_infra
quietly count if missing(bloc)
assert r(N) == 0

*======================================================================*
* 5. SAUVEGARDE INTERMEDIAIRE
*======================================================================*

sort bloc id_infra
save "$outputdir/ecoles_blocs_v2_locked.dta", replace

*======================================================================*
* 6. RANDOMISATION DES 3 BRAS, A L'INTERIEUR DE CHAQUE BLOC
*    (meme logique de tirage du reste que le script precedent)
*======================================================================*

sort id_infra
set seed $SEED_ARMS
capture drop rand_arm
gen double rand_arm = runiform()

sort bloc rand_arm
by bloc: gen long rank_arm = _n
by bloc: gen long bloc_n_arm = _N

capture drop group3
gen byte group3 = .

* Attribution de base : autant d'ecoles que possible reparties a l'identique
replace group3 = mod(rank_arm - 1, $N_ARMS) + 1 ///
    if rank_arm <= floor(bloc_n_arm / $N_ARMS) * $N_ARMS

* Reste : tirage aleatoire de quel(s) bras recoit(vent) le(s) ecole(s)
* restante(s), par bloc, avec le meme flux de graine.
levelsof bloc, local(blist_arm) clean
foreach b of local blist_arm {
    quietly summarize bloc_n_arm if bloc == `b', meanonly
    local n      = r(max)
    local nbase  = floor(`n' / $N_ARMS)
    local rem    = `n' - `nbase' * $N_ARMS

    if `rem' > 0 {
        capture frame drop arm_draw
        frame create arm_draw
        frame arm_draw {
            set obs $N_ARMS
            gen byte   arm_id = _n
            gen double u      = runiform()
            sort u
        }

        local chosen ""
        forvalues i = 1/`rem' {
            frame arm_draw: local this_arm = arm_id[`i']
            local chosen "`chosen' `this_arm'"
        }
        frame drop arm_draw

        local i = 1
        foreach a of local chosen {
            quietly replace group3 = `a' ///
                if bloc == `b' & rank_arm == `nbase' * $N_ARMS + `i'
            local i = `i' + 1
        }
    }
}

quietly count if missing(group3)
assert r(N) == 0

label define arm_lbl 1 "Control" 2 "Salience" 3 "Salience + Implementation", replace
label values group3 arm_lbl
label var group3 "Randomized treatment arm"

di as result "Repartition globale des bras :"
tab group3

di as result "Repartition des bras par bloc (attendu : inegale dans les"
di as result "petits blocs - c'est voulu par le PI, pas une erreur) :"
tab bloc group3

*----------------------------------------------------------------------*
* Controle informationnel (PAS un assert bloquant) : combien de blocs
* n'atteignent pas 2 ecoles dans chaque bras. Attendu > 0 vu la taille
* de nombreux blocs.
*----------------------------------------------------------------------*
preserve
    contract bloc group3, freq(narm)
    bysort bloc: egen narm_min = min(narm)
    quietly count if narm_min < 2
    di as result "`r(N)'/`=_N' lignes bloc x bras ont moins de 2 ecoles"
    di as result "(consequence attendue de l'absence de fusion, cf. retour PI)."
restore

*----------------------------------------------------------------------*
* Verification de reproductibilite (re-tirage, meme graine)
*----------------------------------------------------------------------*
preserve
    sort id_infra
    set seed $SEED_ARMS
    gen double rand_arm_chk = runiform()
    sort bloc rand_arm_chk
    by bloc: gen long rank_chk = _n
    by bloc: gen long bloc_n_chk = _N

    gen byte group3_chk = .
    replace group3_chk = mod(rank_chk - 1, $N_ARMS) + 1 ///
        if rank_chk <= floor(bloc_n_chk / $N_ARMS) * $N_ARMS

    levelsof bloc, local(blist_chk) clean
    foreach b of local blist_chk {
        quietly summarize bloc_n_chk if bloc == `b', meanonly
        local n     = r(max)
        local nbase = floor(`n' / $N_ARMS)
        local rem   = `n' - `nbase' * $N_ARMS
        if `rem' > 0 {
            capture frame drop arm_draw_chk
            frame create arm_draw_chk
            frame arm_draw_chk {
                set obs $N_ARMS
                gen byte   arm_id = _n
                gen double u      = runiform()
                sort u
            }
            local chosen ""
            forvalues i = 1/`rem' {
                frame arm_draw_chk: local this_arm = arm_id[`i']
                local chosen "`chosen' `this_arm'"
            }
            frame drop arm_draw_chk
            local i = 1
            foreach a of local chosen {
                quietly replace group3_chk = `a' ///
                    if bloc == `b' & rank_chk == `nbase' * $N_ARMS + `i'
                local i = `i' + 1
            }
        }
    }
    assert group3 == group3_chk
    di as result "REPRODUCTIBILITE CONFIRMEE (bras) avec la graine $SEED_ARMS."
restore

*======================================================================*
* 7. RANDOMISATION DU PARENT CIBLE - IMBRIQUEE DANS BLOC x BRAS
*    (correction du point 1 du retour PI : separement par bras, pas
*    seulement par bloc)
*======================================================================*

/*capture drop treated
gen byte treated = inlist(group3, 2, 3)
label var treated "1 = ecole traitee (Salience ou Salience + MO)"

sort id_infra
set seed $SEED_PARENT
capture drop rand_parent
gen double rand_parent = runiform() if treated == 1

* Cle d'imbrication : bloc x bras (pas seulement bloc)
capture drop bloc_arm
egen long bloc_arm = group(bloc group3) if treated == 1
label var bloc_arm "Groupe d'imbrication : bloc x bras (ecoles traitees)"

sort bloc_arm rand_parent
capture drop rank_parent
by bloc_arm: gen long rank_parent = _n if treated == 1

capture drop parent_group
gen byte parent_group = mod(rank_parent - 1, 2) + 1 if treated == 1

label define parent_lbl 1 "Mother" 2 "Father", replace
label values parent_group parent_lbl
label var parent_group "Targeted parent"

di as result "Repartition Mere/Pere, par bloc ET par bras (correction PI) :"
tab bloc_arm parent_group if treated == 1
tab group3 parent_group if treated == 1
*/

/*
capture drop parent_group
gen byte parent_group = .

by bloc_arm: gen long bloc_arm_n = _n if treated == 1
by bloc_arm: replace bloc_arm_n = _N if treated == 1

replace parent_group = mod(rank_parent - 1, 2) + 1 ///
    if treated == 1 & rank_parent <= floor(bloc_arm_n / 2) * 2

levelsof bloc_arm, local(balist) clean
foreach g of local balist {
    quietly summarize bloc_arm_n if bloc_arm == `g', meanonly
    local n     = r(max)
    local nbase = floor(`n' / 2)
    local rem   = `n' - `nbase' * 2

    if `rem' > 0 {
        capture frame drop parent_draw
        frame create parent_draw
        frame parent_draw {
            set obs 2
            gen byte   parent_id = _n
            gen double u = runiform()
            sort u
        }
        frame parent_draw: local this_parent = parent_id[1]
        frame drop parent_draw

        quietly replace parent_group = `this_parent' ///
            if bloc_arm == `g' & rank_parent == `nbase' * 2 + 1
    }
}

label define parent_lbl 1 "Mother" 2 "Father", replace
label values parent_group parent_lbl
label var parent_group "Targeted parent"

di as result "Repartition Mere/Pere, par bloc ET par bras (correction PI) :"
tab bloc_arm parent_group if treated == 1
tab group3 parent_group if treated == 1
*/

*======================================================================*
* 7. RANDOMISATION DU PARENT CIBLE
*
* OBJECTIF :
*   - Randomisation imbriquee dans BLOC x BRAS ;
*   - 50/50 Mother/Father dans chaque cellule bloc x bras autant
*     que possible ;
*   - Les excedents des cellules impaires ne sont PAS tires
*     independamment cellule par cellule ;
*   - Tous les excedents impairs d'un MEME BRAS sont regroupes,
*     randomises puis alternes Mother/Father ;
*   - Cela garantit mathematiquement un equilibre global maximal
*     dans CHAQUE bras traite.
*
* RESULTAT ATTENDU AVEC 52 ECOLES PAR BRAS :
*
*       Salience                  : 26 Mother / 26 Father
*       Salience + Implementation : 26 Mother / 26 Father
*
* Cette logique correspond a la correction v4 du script principal.
*======================================================================*

capture drop treated
gen byte treated = inlist(group3, 2, 3)

label var treated ///
    "1 = ecole traitee (Salience ou Salience + Implementation)"

*----------------------------------------------------------------------*
* 7.1 RANDOMISATION INITIALE DES ECOLES TRAITEES
*     AU SEIN DE CHAQUE BLOC x BRAS
*----------------------------------------------------------------------*

sort id_infra

set seed $SEED_PARENT

capture drop rand_parent
gen double rand_parent = runiform() if treated == 1

* Cle d'imbrication :
*   bloc x bras de traitement
*
* Les ecoles Control sont automatiquement exclues.
capture drop bloc_arm
egen long bloc_arm = group(bloc group3) if treated == 1

label var bloc_arm ///
    "Cellule de randomisation parent : bloc x bras traite"

* Randomisation des ecoles a l'interieur de chaque cellule
sort bloc_arm rand_parent

capture drop rank_parent
by bloc_arm: gen long rank_parent = _n if treated == 1

capture drop bloc_arm_n
by bloc_arm: gen long bloc_arm_n = _N if treated == 1

*----------------------------------------------------------------------*
* 7.2 ATTRIBUTION 50/50 DE LA PARTIE PAIRE
*
* Exemple :
*   cellule de 6 -> 3 Mother / 3 Father
*   cellule de 4 -> 2 Mother / 2 Father
*   cellule de 2 -> 1 Mother / 1 Father
*
* Si cellule impaire :
*   cellule de 5 -> 2 Mother / 2 Father + 1 excedent
*----------------------------------------------------------------------*

capture drop parent_group
gen byte parent_group = .

replace parent_group = ///
    mod(rank_parent - 1, 2) + 1 ///
    if treated == 1 & ///
       rank_parent <= floor(bloc_arm_n / 2) * 2

*----------------------------------------------------------------------*
* 7.3 IDENTIFICATION DES ECOLES EXCEDENTAIRES
*
* Une seule ecole excedentaire par cellule impaire.
*----------------------------------------------------------------------*

capture drop is_leftover

gen byte is_leftover = ///
    treated == 1 & ///
    mod(bloc_arm_n, 2) == 1 & ///
    rank_parent == bloc_arm_n

label var is_leftover ///
    "1 = ecole excedentaire d'une cellule bloc x bras impaire"

*----------------------------------------------------------------------*
* 7.4 NOMBRE D'EXCEDENTS PAR BRAS DE TRAITEMENT
*
* IMPORTANT :
* Les excedents sont maintenant traites SEPAREMENT pour :
*
*   group3 == 2 : Salience
*   group3 == 3 : Salience + Implementation
*
*----------------------------------------------------------------------*

capture drop n_leftover_arm

bysort group3: egen long n_leftover_arm = total(is_leftover)

*----------------------------------------------------------------------*
* 7.5 RANDOMISATION DES EXCEDENTS PAR BRAS
*
* Tous les excedents de Salience sont regroupes ensemble.
* Tous les excedents de Salience + Implementation sont regroupes
* ensemble.
*
* Ils sont ensuite randomises puis alternes :
*
*       1 = Mother
*       2 = Father
*       1 = Mother
*       2 = Father
*       ...
*
* Ainsi, si le nombre d'excedents est pair :
*
*       exactement 50/50.
*
* Si le nombre d'excedents est impair :
*
*       difference maximale = 1.
*
* L'ecole qui recoit l'eventuel dernier parent est elle-meme
* aleatoirement determinee par le classement aleatoire.
*----------------------------------------------------------------------*

capture drop rand_leftover

* Nouveau tirage aleatoire pour les excedents.
* On conserve la meme SEED_PARENT pour garantir la reproductibilite.
set seed $SEED_PARENT

gen double rand_leftover = ///
    runiform() if is_leftover == 1

* Randomisation des excedents A L'INTERIEUR DE CHAQUE BRAS
sort group3 rand_leftover

capture drop rank_leftover

by group3: gen long rank_leftover = ///
    _n if is_leftover == 1

*----------------------------------------------------------------------*
* 7.6 ATTRIBUTION DES EXCEDENTS
*----------------------------------------------------------------------*

* Tous les excedents sauf l'eventuel dernier sont attribues
* par alternance Mother / Father.
replace parent_group = ///
    mod(rank_leftover - 1, 2) + 1 ///
    if is_leftover == 1 & ///
       rank_leftover <= floor(n_leftover_arm / 2) * 2

*----------------------------------------------------------------------*
* 7.7 CAS D'UN NOMBRE IMPAIR D'EXCEDENTS
*
* Le dernier excedent est tire aleatoirement entre Mother et Father.
*
* IMPORTANT :
* Cela ne peut creer qu'un ecart de 1.
*----------------------------------------------------------------------*

capture drop rand_last_leftover

gen double rand_last_leftover = ///
    runiform() ///
    if is_leftover == 1 & ///
       mod(n_leftover_arm, 2) == 1 & ///
       rank_leftover == n_leftover_arm

replace parent_group = ///
    cond(rand_last_leftover < 0.5, 1, 2) ///
    if is_leftover == 1 & ///
       mod(n_leftover_arm, 2) == 1 & ///
       rank_leftover == n_leftover_arm

*----------------------------------------------------------------------*
* 7.8 LABELS
*----------------------------------------------------------------------*

label define parent_lbl ///
    1 "Mother" ///
    2 "Father", replace

label values parent_group parent_lbl

label var parent_group ///
    "Targeted parent: Mother/Father"

*----------------------------------------------------------------------*
* 7.9 VERIFICATION AU NIVEAU BLOC x BRAS
*----------------------------------------------------------------------*

di as result ""
di as result "======================================================="
di as result "PARENT ASSIGNMENT BY BLOCK x TREATMENT ARM"
di as result "======================================================="

tab bloc_arm parent_group if treated == 1, missing

*----------------------------------------------------------------------*
* 7.10 VERIFICATION GLOBALE PAR BRAS DE TRAITEMENT
*----------------------------------------------------------------------*

di as result ""
di as result "======================================================="
di as result "PARENT ASSIGNMENT BY TREATMENT ARM"
di as result "======================================================="

tab group3 parent_group if treated == 1, missing

*----------------------------------------------------------------------*
* Extraction des effectifs pour verification automatique
*----------------------------------------------------------------------*

quietly count if group3 == 2 & parent_group == 1
local mother_salience = r(N)

quietly count if group3 == 2 & parent_group == 2
local father_salience = r(N)

quietly count if group3 == 3 & parent_group == 1
local mother_impl = r(N)

quietly count if group3 == 3 & parent_group == 2
local father_impl = r(N)

di as result ""
di as result "Salience:"
di as result "  Mother = `mother_salience'"
di as result "  Father = `father_salience'"

di as result ""
di as result "Salience + Implementation:"
di as result "  Mother = `mother_impl'"
di as result "  Father = `father_impl'"

*----------------------------------------------------------------------*
* 7.11 CONTROLE DE L'EQUILIBRE GLOBAL
*
* Chaque bras traite contient actuellement 52 ecoles.
* Le meilleur resultat possible est donc exactement 26/26.
*----------------------------------------------------------------------*

assert `mother_salience' + `father_salience' == 52
assert `mother_impl' + `father_impl' == 52

* Ecarts Mother/Father
local diff_sal = abs(`mother_salience' - `father_salience')
local diff_impl = abs(`mother_impl' - `father_impl')

* L'ecart maximal autorise est 1.
assert `diff_sal' <= 1
assert `diff_impl' <= 1

di as result ""
di as result "Difference Mother/Father - Salience                  : `diff_sal'"
di as result "Difference Mother/Father - Salience + Implementation : `diff_impl'"

di as result ""
if `diff_sal' == 0 & `diff_impl' == 0 {
    di as result "EXACT 50/50 PARENT BALANCE CONFIRMED"
}
else {
    di as result "PARENT BALANCE CONFIRMED: maximum difference = 1"
}

*----------------------------------------------------------------------*
* 7.12 CONTROLE SPECIFIQUE AU RESULTAT ATTENDU
*
* Avec 52 ecoles dans chacun des deux bras traites, le script doit
* normalement pouvoir produire 26/26.
*
* On bloque ici si ce n'est pas le cas, afin d'eviter d'exporter
* accidentellement une allocation parent non optimale.
*----------------------------------------------------------------------*

assert `mother_salience' == 26
assert `father_salience' == 26

assert `mother_impl' == 26
assert `father_impl' == 26

di as result ""
di as result "======================================================="
di as result "FINAL PARENT BALANCE"
di as result "======================================================="
di as result "Salience                  : 26 Mother / 26 Father"
di as result "Salience + Implementation : 26 Mother / 26 Father"
di as result "======================================================="


label define parent_lbl 1 "Mother" 2 "Father", replace
label values parent_group parent_lbl
label var parent_group "Targeted parent"

di as result "Repartition Mere/Pere, par bloc ET par bras (correction PI) :"
tab bloc_arm parent_group if treated == 1
tab group3 parent_group if treated == 1

*----------------------------------------------------------------------*
* Verification de reproductibilite (parent)
*----------------------------------------------------------------------*
/*
preserve
    sort id_infra
    set seed $SEED_PARENT
    gen double rand_parent_chk = runiform() if treated == 1
    sort bloc_arm rand_parent_chk
    by bloc_arm: gen long rank_parent_chk = _n if treated == 1
    gen byte parent_group_chk = mod(rank_parent_chk - 1, 2) + 1 if treated == 1
    assert parent_group == parent_group_chk if treated == 1
    di as result "REPRODUCTIBILITE CONFIRMEE (parent) avec la graine $SEED_PARENT."
restore
*/

*----------------------------------------------------------------------*
* Verification de reproductibilite (parent) - version corrigee, doit
* suivre EXACTEMENT la meme logique que la section 7 (avec tirage du
* reste), pas l'ancienne formule simple.
*----------------------------------------------------------------------*
preserve
    sort id_infra
    set seed $SEED_PARENT
    gen double rand_parent_chk = runiform() if treated == 1

    sort bloc_arm rand_parent_chk
    capture drop rank_parent_chk
    by bloc_arm: gen long rank_parent_chk = _n if treated == 1

    capture drop bloc_arm_n_chk
    by bloc_arm: gen long bloc_arm_n_chk = _n if treated == 1
    by bloc_arm: replace bloc_arm_n_chk = _N if treated == 1

    gen byte parent_group_chk = .
    replace parent_group_chk = mod(rank_parent_chk - 1, 2) + 1 ///
        if treated == 1 & rank_parent_chk <= floor(bloc_arm_n_chk / 2) * 2

    levelsof bloc_arm, local(balist_chk) clean
    foreach g of local balist_chk {
        quietly summarize bloc_arm_n_chk if bloc_arm == `g', meanonly
        local n     = r(max)
        local nbase = floor(`n' / 2)
        local rem   = `n' - `nbase' * 2

        if `rem' > 0 {
            capture frame drop parent_draw_chk
            frame create parent_draw_chk
            frame parent_draw_chk {
                set obs 2
                gen byte   parent_id = _n
                gen double u = runiform()
                sort u
            }
            frame parent_draw_chk: local this_parent = parent_id[1]
            frame drop parent_draw_chk

            quietly replace parent_group_chk = `this_parent' ///
                if bloc_arm == `g' & rank_parent_chk == `nbase' * 2 + 1
        }
    }

    assert parent_group == parent_group_chk if treated == 1
    di as result "REPRODUCTIBILITE CONFIRMEE (parent) avec la graine $SEED_PARENT."
restore


*======================================================================*
* 8. TESTS D'EQUILIBRE
*======================================================================*

di as result "======================================================="
di as result "TESTS D'EQUILIBRE"
di as result "======================================================="

tab COMMUNE group3, chi2
tab size_label group3, chi2
tab MILIEU_EQUIPE group3, chi2

* Note : avec des blocs tres petits (parfois 2-3 ecoles avec un seul
* bras represente), certains blocs sont des singletons pour i.bloc et
* seront automatiquement ecartes par regress - normal, pas une erreur.
local balance_vars target_enrol NBM6EME NBM5EME SALLESCLASSESTOT ///
    EXISTENCEEAU EXISTENCEELECT EXISTENCELATRINES EXISTENCEINFRASTSPORT

foreach v of local balance_vars {
    capture confirm numeric variable `v'
    if !_rc {
        di as text _newline "--- Balance : `v' ---"
        quietly regress `v' i.group3 i.bloc, vce(robust)
        testparm i.group3
    }
}

*======================================================================*
* 9. EXPORT FINAL
*======================================================================*

capture drop group3_lbl
gen str35 group3_lbl = ""
replace group3_lbl = "Control"                    if group3 == 1
replace group3_lbl = "Salience"                    if group3 == 2
replace group3_lbl = "Salience + Implementation"    if group3 == 3

capture drop parent_lbl2
gen str12 parent_lbl2 = ""
replace parent_lbl2 = "Mother" if parent_group == 1
replace parent_lbl2 = "Father" if parent_group == 2
replace parent_lbl2 = "N/A"    if treated == 0

preserve
    keep id_infra DEPARTEMENT COMMUNE ARRONDISSEMENT NOMETABLISSEMENT ///
         MILIEU_EQUIPE size_label strate_label bloc ///
         group3_lbl parent_lbl2 target_enrol med_enrol

    rename size_label     size_category
    rename group3_lbl     assigned_group
    rename parent_lbl2    targeted_parent

    order id_infra DEPARTEMENT COMMUNE ARRONDISSEMENT NOMETABLISSEMENT ///
          MILIEU_EQUIPE size_category strate_label bloc ///
          assigned_group targeted_parent target_enrol med_enrol

    sort bloc id_infra
    export excel using "$outputdir/randomization_final_v2.xlsx", ///
        firstrow(variables) replace sheet("randomization")
restore

save "$outputdir/randomization_final_v2_locked_`timestamp'.dta", replace

*======================================================================*
* 10. MANIFESTE
*======================================================================*

datasignature
local sig = r(datasignature)

file open manifest using "$outputdir/randomization_v2_manifest_`timestamp'.txt", write replace
file write manifest "RANDOMIZATION MANIFEST v2 - Gender Norms RCT" _n
file write manifest "==============================================" _n
file write manifest "Date/heure       : $S_DATE $S_TIME" _n
file write manifest "SEED_BLOCKS      : $SEED_BLOCKS" _n
file write manifest "SEED_ARMS        : $SEED_ARMS" _n
file write manifest "SEED_PARENT      : $SEED_PARENT" _n
file write manifest "N ecoles         : 156" _n
file write manifest "Regle de taille  : mediane communale, filles 6e+5e" _n
file write manifest "Strates          : commune x size_label, INDEPENDANTES" _n
file write manifest "Fusion cross-commune : AUCUNE (retour PI 27/08/2026)" _n
file write manifest "Dernier bloc     : taille = reste de la strate (peut etre < 6)" _n
file write manifest "Parent           : imbrique dans bloc x bras (pas juste bloc)" _n
file write manifest "Checksum         : `sig'" _n
file close manifest

di as result "======================================================="
di as result "RANDOMISATION V2 TERMINEE"
di as result "======================================================="

log close
