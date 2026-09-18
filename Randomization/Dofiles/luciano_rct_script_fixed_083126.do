/********************************************************************
 Project      : Gender norm
 Author       : Lucien Allosse
 Date         : 29 Aout 2026
 Purpose      : Randomisation v2 - integre le retour du PI (27/08/2026)

                (1) randomisation du parent imbriquee dans bloc x bras,
                    pas seulement dans bloc ;

                (2) Small et Large forment des strates SEPAREES ;

                (3) chaque commune reste strictement independante -
                    AUCUNE fusion cross-commune ;

                (4) le dernier bloc d'une strate prend simplement
                    le nombre d'ecoles restant, meme si < 6 ;

                (5) randomisation du parent :
                    - 50/50 dans chaque cellule bloc x bras autant
                      que possible ;
                    - excedents impairs regroupes par bras ;
                    - equilibre global maximal dans chaque bras traite.

 Software     : Stata 16

 Input        : school_list_gender_norm_v4.dta
                156 ecoles eligibles

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
capture frame drop arm_draw_chk

*----------------------------------------------------------------------*
* REPERTOIRES
*----------------------------------------------------------------------*

cd "C:\RONALDO\CKDEV\GENDER NORMS\Randomization\Lucien_v2"

global working   "C:\RONALDO\CKDEV\GENDER NORMS\Randomization\Lucien_v2"
global datadir   "$working\Datasets"
global outputdir "$working\Outputs"

global N_ARMS 3

*----------------------------------------------------------------------*
* GRAINES
*----------------------------------------------------------------------*

global SEED_BLOCKS 20260827
global SEED_ARMS   20260713
global SEED_PARENT 20260101

*----------------------------------------------------------------------*
* CREATION DU DOSSIER OUTPUT
*----------------------------------------------------------------------*

capture mkdir "$outputdir"

cd "$working"

*----------------------------------------------------------------------*
* TIMESTAMP
*----------------------------------------------------------------------*

local timestamp : display ///
    %tcCCYY-NN-DD_HH-MM-SS ///
    clock("$S_DATE $S_TIME","DMYhms")

local timestamp = subinstr("`timestamp'"," ","_",.)

log using ///
    "$outputdir/randomization_v2_log_`timestamp'.smcl", ///
    replace


*======================================================================*
* 1. IMPORT DE LA BASE ELIGIBLE
*======================================================================*

use ///
    "$working\school_list_gender_norm_v4.dta", ///
    clear

*----------------------------------------------------------------------*
* VERIFICATION IDENTIFIANT
*----------------------------------------------------------------------*

isid ecole_key

quietly count
local n_total = r(N)

di as result ""
di as result "======================================================="
di as result "BASE ELIGIBLE"
di as result "======================================================="
di as result "Nombre d'ecoles : `n_total'"
di as result "Nombre attendu   : 156"
di as result "======================================================="

assert `n_total' == 156

*----------------------------------------------------------------------*
* CREATION id_infra SI ABSENT
*----------------------------------------------------------------------*

capture confirm variable id_infra

if _rc {
    gen long id_infra = _n
    label var id_infra ///
        "Identifiant unique ecole (genere)"
}

isid id_infra


*======================================================================*
* 2. VARIABLE DE TAILLE
*
* Taille = filles 6eme + filles 5eme
* Classification par mediane communale
*======================================================================*

capture drop target_enrol

gen long target_enrol = ///
    NBF6EME + NBF5EME

label var target_enrol ///
    "Effectif filles 6e+5e"


*----------------------------------------------------------------------*
* MEDIANE COMMUNALE
*----------------------------------------------------------------------*

capture drop med_enrol

bysort COMMUNE: egen double med_enrol = ///
    median(target_enrol)

label var med_enrol ///
    "Mediane communale de target_enrol"


*----------------------------------------------------------------------*
* CLASSIFICATION SMALL / LARGE
*----------------------------------------------------------------------*

capture drop size_label

gen str5 size_label = ""

replace size_label = "Small" ///
    if target_enrol <= med_enrol

replace size_label = "Large" ///
    if target_enrol > med_enrol


quietly count if size_label == ""

assert r(N) == 0


di as result ""
di as result "======================================================="
di as result "CLASSIFICATION SMALL / LARGE"
di as result "======================================================="

tab COMMUNE size_label, missing


*======================================================================*
* 3. STRATES = COMMUNE x SIZE
*
* AUCUNE fusion cross-commune
*======================================================================*

capture drop strate_label

gen str40 strate_label = ///
    COMMUNE + "_" + size_label

label var strate_label ///
    "Strate independante : commune x taille"


capture drop strate_id

egen long strate_id = ///
    group(strate_label)

label var strate_id ///
    "Identifiant numerique de strate"


*----------------------------------------------------------------------*
* TAILLE DES STRATES
*----------------------------------------------------------------------*

capture drop strate_n

bysort strate_id: gen long strate_n = _N

label var strate_n ///
    "Nombre d'ecoles dans la strate"


di as result ""
di as result "======================================================="
di as result "COMPOSITION DES STRATES"
di as result "Commune x Size - AUCUNE FUSION"
di as result "======================================================="

preserve

    contract ///
        strate_id ///
        strate_label ///
        strate_n

    gsort -strate_n

    list ///
        strate_label ///
        strate_n, ///
        noobs ///
        sep(0)

    quietly count if strate_n < 6

    di as result ""
    di as result ///
        "`r(N)' strates ont moins de 6 ecoles."

restore


*======================================================================*
* 4. CONSTRUCTION DES BLOCS
*
* Regle :
*   - blocs de 6 autant que possible ;
*   - dernier bloc = reste ;
*   - aucune fusion ;
*   - aucune fusion cross-commune.
*======================================================================*

sort id_infra

set seed $SEED_BLOCKS


*----------------------------------------------------------------------*
* TIRAGE ALEATOIRE POUR LA CONSTRUCTION DES BLOCS
*----------------------------------------------------------------------*

capture drop rand_block

gen double rand_block = ///
    runiform()


*----------------------------------------------------------------------*
* RANG DANS LA STRATE
*----------------------------------------------------------------------*

sort strate_id rand_block

capture drop rank_in_strate

by strate_id: gen long rank_in_strate = _n


*----------------------------------------------------------------------*
* NUMERO DU BLOC DANS LA STRATE
*
* 1-6   = bloc 1
* 7-12  = bloc 2
* etc.
*----------------------------------------------------------------------*

capture drop block_in_strate

gen long block_in_strate = ///
    ceil(rank_in_strate / 6)

label var block_in_strate ///
    "Numero du bloc dans la strate"


*----------------------------------------------------------------------*
* IDENTIFIANT GLOBAL DU BLOC
*----------------------------------------------------------------------*

capture drop bloc

egen long bloc = ///
    group(strate_id block_in_strate)

label var bloc ///
    "Identifiant final du bloc"


*----------------------------------------------------------------------*
* TAILLE DU BLOC
*----------------------------------------------------------------------*

capture drop bloc_n

bysort bloc: gen long bloc_n = _N

label var bloc_n ///
    "Nombre d'ecoles dans le bloc"


*----------------------------------------------------------------------*
* VERIFICATION BLOCS
*----------------------------------------------------------------------*

summarize bloc_n

di as result ""
di as result "======================================================="
di as result "BLOCS FINAUX"
di as result "======================================================="

quietly levelsof bloc, local(blist)

di as result ///
    "Nombre de blocs : `: word count `blist''"

di as result ///
    "Taille minimale : `r(min)'"

di as result ///
    "Taille maximale : `r(max)'"

isid id_infra

quietly count if missing(bloc)

assert r(N) == 0


*======================================================================*
* 5. SAUVEGARDE INTERMEDIAIRE
*======================================================================*

sort bloc id_infra

save ///
    "$outputdir/ecoles_blocs_v2_locked.dta", ///
    replace


*======================================================================*
* 6. RANDOMISATION DES 3 BRAS
*
* Randomisation A L'INTERIEUR DE CHAQUE BLOC
*======================================================================*

sort id_infra

set seed $SEED_ARMS


*----------------------------------------------------------------------*
* TIRAGE ALEATOIRE
*----------------------------------------------------------------------*

capture drop rand_arm

gen double rand_arm = ///
    runiform()


*----------------------------------------------------------------------*
* RANG DANS LE BLOC
*----------------------------------------------------------------------*

sort bloc rand_arm

capture drop rank_arm

by bloc: gen long rank_arm = _n


capture drop bloc_n_arm

by bloc: gen long bloc_n_arm = _N


*----------------------------------------------------------------------*
* VARIABLE BRAS
*
* 1 = Control
* 2 = Salience
* 3 = Salience + Implementation
*----------------------------------------------------------------------*

capture drop group3

gen byte group3 = .


*----------------------------------------------------------------------*
* ATTRIBUTION DE BASE
*
* Si bloc de 6 :
*   1 2 3 1 2 3
*
* Si bloc de 5 :
*   1 2 3 1 2
*
* Le reste sera randomise ensuite.
*----------------------------------------------------------------------*

replace group3 = ///
    mod(rank_arm - 1, $N_ARMS) + 1 ///
    if rank_arm <= ///
       floor(bloc_n_arm / $N_ARMS) * $N_ARMS


*----------------------------------------------------------------------*
* RANDOMISATION DU RESTE
*----------------------------------------------------------------------*

levelsof bloc, local(blist_arm) clean

foreach b of local blist_arm {

    quietly summarize bloc_n_arm ///
        if bloc == `b', ///
        meanonly

    local n = r(max)

    local nbase = ///
        floor(`n' / $N_ARMS)

    local rem = ///
        `n' - `nbase' * $N_ARMS


    if `rem' > 0 {

        capture frame drop arm_draw

        frame create arm_draw


        frame arm_draw {

            set obs $N_ARMS

            gen byte arm_id = _n

            gen double u = ///
                runiform()

            sort u
        }


        local chosen ""

        forvalues i = 1/`rem' {

            frame arm_draw: ///
                local this_arm = arm_id[`i']

            local chosen ///
                "`chosen' `this_arm'"
        }


        frame drop arm_draw


        local i = 1

        foreach a of local chosen {

            quietly replace group3 = `a' ///
                if bloc == `b' ///
                & rank_arm == ///
                  `nbase' * $N_ARMS + `i'

            local i = `i' + 1
        }
    }
}


*----------------------------------------------------------------------*
* VERIFICATION
*----------------------------------------------------------------------*

quietly count if missing(group3)

assert r(N) == 0


label define arm_lbl ///
    1 "Control" ///
    2 "Salience" ///
    3 "Salience + Implementation", ///
    replace

label values group3 arm_lbl

label var group3 ///
    "Randomized treatment arm"


di as result ""
di as result "======================================================="
di as result "REPARTITION GLOBALE DES BRAS"
di as result "======================================================="

tab group3


di as result ""
di as result "REPARTITION PAR BLOC"

tab bloc group3


*======================================================================*
* 6.1 CONTROLE INFORMATIONNEL DES PETITS BLOCS
*======================================================================*

preserve

    contract bloc group3, freq(narm)

    bysort bloc: egen narm_min = ///
        min(narm)

    quietly count if narm_min < 2

    di as result ""
    di as result ///
        "`r(N)' cellules bloc x bras ont moins de 2 ecoles."

    di as result ///
        "Ceci est possible et attendu avec les petits blocs."

restore


*======================================================================*
* 6.2 REPRODUCTIBILITE DE LA RANDOMISATION DES BRAS
*======================================================================*

preserve

    sort id_infra

    set seed $SEED_ARMS


    gen double rand_arm_chk = ///
        runiform()


    sort bloc rand_arm_chk


    by bloc: gen long rank_chk = _n

    by bloc: gen long bloc_n_chk = _N


    gen byte group3_chk = .


    replace group3_chk = ///
        mod(rank_chk - 1, $N_ARMS) + 1 ///
        if rank_chk <= ///
           floor(bloc_n_chk / $N_ARMS) * $N_ARMS


    levelsof bloc, local(blist_chk) clean


    foreach b of local blist_chk {

        quietly summarize bloc_n_chk ///
            if bloc == `b', ///
            meanonly

        local n = r(max)

        local nbase = ///
            floor(`n' / $N_ARMS)

        local rem = ///
            `n' - `nbase' * $N_ARMS


        if `rem' > 0 {

            capture frame drop arm_draw_chk

            frame create arm_draw_chk


            frame arm_draw_chk {

                set obs $N_ARMS

                gen byte arm_id = _n

                gen double u = ///
                    runiform()

                sort u
            }


            local chosen_chk ""

            forvalues i = 1/`rem' {

                frame arm_draw_chk: ///
                    local this_arm = arm_id[`i']

                local chosen_chk ///
                    "`chosen_chk' `this_arm'"
            }


            frame drop arm_draw_chk


            local i = 1

            foreach a of local chosen_chk {

                quietly replace group3_chk = `a' ///
                    if bloc == `b' ///
                    & rank_chk == ///
                      `nbase' * $N_ARMS + `i'

                local i = `i' + 1
            }
        }
    }


    assert group3 == group3_chk

    di as result ""
    di as result ///
        "REPRODUCTIBILITE CONFIRMEE (BRAS)"

restore


*======================================================================*
* 7. RANDOMISATION DU PARENT CIBLE
*
* OBJECTIFS :
*
*   1. Randomisation imbriquee dans BLOC x BRAS ;
*
*   2. Control exclu ;
*
*   3. 50/50 Mother/Father dans chaque cellule bloc x bras
*      autant que possible ;
*
*   4. Une cellule impaire produit un seul excedent ;
*
*   5. Les excedents sont regroupes SEPAREMENT par bras traite ;
*
*   6. Les excedents sont randomises a l'interieur de chaque bras ;
*
*   7. Les excedents sont ensuite alternes Mother/Father ;
*
*   8. Si le nombre total d'excedents est impair dans un bras,
*      le dernier excedent est tire aleatoirement ;
*
*   9. Avec 52 ecoles par bras :
*
*          Salience                  = 26 Mother / 26 Father
*          Salience + Implementation = 26 Mother / 26 Father
*
*======================================================================*


*----------------------------------------------------------------------*
* 7.1 ECOLES TRAITEES
*----------------------------------------------------------------------*

capture drop treated

gen byte treated = ///
    inlist(group3, 2, 3)

label var treated ///
    "1 = ecole traitee"


*----------------------------------------------------------------------*
* 7.2 INITIALISATION DE LA GRAINE PARENT
*----------------------------------------------------------------------*

sort id_infra

set seed $SEED_PARENT


*----------------------------------------------------------------------*
* 7.3 PREMIER TIRAGE ALEATOIRE
*
* Une valeur aleatoire par ecole traitee.
*----------------------------------------------------------------------*

capture drop rand_parent

gen double rand_parent = ///
    runiform() ///
    if treated == 1


*----------------------------------------------------------------------*
* 7.4 CREATION DE LA CELLULE BLOC x BRAS
*----------------------------------------------------------------------*

capture drop bloc_arm

egen long bloc_arm = ///
    group(bloc group3) ///
    if treated == 1

label var bloc_arm ///
    "Cellule de randomisation : bloc x bras"


*----------------------------------------------------------------------*
* 7.5 RANDOMISATION DES ECOLES DANS CHAQUE CELLULE
*----------------------------------------------------------------------*

sort bloc_arm rand_parent


capture drop rank_parent

by bloc_arm: gen long rank_parent = ///
    _n if treated == 1


capture drop bloc_arm_n

by bloc_arm: gen long bloc_arm_n = ///
    _N if treated == 1


*----------------------------------------------------------------------*
* 7.6 ATTRIBUTION DE LA PARTIE PAIRE
*
* Exemple :
*
*   6 -> M F M F M F
*   5 -> M F M F + excedent
*   4 -> M F M F
*   3 -> M F + excedent
*----------------------------------------------------------------------*

capture drop parent_group

gen byte parent_group = .


replace parent_group = ///
    mod(rank_parent - 1, 2) + 1 ///
    if treated == 1 ///
    & rank_parent <= ///
      floor(bloc_arm_n / 2) * 2


*----------------------------------------------------------------------*
* 7.7 IDENTIFICATION DES EXCEDENTS
*----------------------------------------------------------------------*

capture drop is_leftover

gen byte is_leftover = ///
    treated == 1 ///
    & mod(bloc_arm_n, 2) == 1 ///
    & rank_parent == bloc_arm_n

label var is_leftover ///
    "1 = excedent d'une cellule bloc x bras impaire"


*----------------------------------------------------------------------*
* 7.8 NOMBRE D'EXCEDENTS PAR BRAS
*----------------------------------------------------------------------*

capture drop n_leftover_arm

bysort group3: egen long n_leftover_arm = ///
    total(is_leftover)


*----------------------------------------------------------------------*
* 7.9 DEUXIEME TIRAGE ALEATOIRE
*
* IMPORTANT :
* On NE fait PAS "set seed" ici.
*
* On continue exactement le flux aleatoire commence par rand_parent.
*----------------------------------------------------------------------*

capture drop rand_leftover

gen double rand_leftover = ///
    runiform() ///
    if is_leftover == 1


*----------------------------------------------------------------------*
* 7.10 RANG DES EXCEDENTS
*
* IMPORTANT :
* sum(is_leftover) permet de compter uniquement les excedents.
*----------------------------------------------------------------------*

sort group3 rand_leftover


capture drop rank_leftover

by group3: gen long rank_leftover = ///
    sum(is_leftover)

replace rank_leftover = . ///
    if is_leftover != 1


*----------------------------------------------------------------------*
* 7.11 ATTRIBUTION ALTERNÉE DES EXCEDENTS
*
* 1 = Mother
* 2 = Father
* 3 = Mother
* 4 = Father
* etc.
*----------------------------------------------------------------------*

replace parent_group = ///
    mod(rank_leftover - 1, 2) + 1 ///
    if is_leftover == 1 ///
    & rank_leftover <= ///
      floor(n_leftover_arm / 2) * 2


*----------------------------------------------------------------------*
* 7.12 TROISIEME TIRAGE ALEATOIRE
*
* Seulement si le nombre d'excedents d'un bras est impair.
*
* IMPORTANT :
* Toujours sans reset de la seed.
*----------------------------------------------------------------------*

capture drop rand_last_leftover

gen double rand_last_leftover = ///
    runiform() ///
    if is_leftover == 1 ///
    & mod(n_leftover_arm, 2) == 1 ///
    & rank_leftover == n_leftover_arm


*----------------------------------------------------------------------*
* 7.13 ATTRIBUTION DU DERNIER EXCEDENT
*----------------------------------------------------------------------*

replace parent_group = ///
    cond(rand_last_leftover < 0.5, 1, 2) ///
    if is_leftover == 1 ///
    & mod(n_leftover_arm, 2) == 1 ///
    & rank_leftover == n_leftover_arm


*----------------------------------------------------------------------*
* 7.14 LABELS
*----------------------------------------------------------------------*

capture label drop parent_lbl

label define parent_lbl ///
    1 "Mother" ///
    2 "Father", ///
    replace

label values parent_group parent_lbl

label var parent_group ///
    "Targeted parent: Mother/Father"


*======================================================================*
* 7.15 VERIFICATION CELLULE BLOC x BRAS
*======================================================================*

di as result ""
di as result "======================================================="
di as result "PARENT ASSIGNMENT BY BLOCK x TREATMENT ARM"
di as result "======================================================="

tab bloc_arm parent_group ///
    if treated == 1, ///
    missing


*======================================================================*
* 7.16 VERIFICATION GLOBALE
*======================================================================*

di as result ""
di as result "======================================================="
di as result "PARENT ASSIGNMENT BY TREATMENT ARM"
di as result "======================================================="

tab group3 parent_group ///
    if treated == 1, ///
    missing


*======================================================================*
* 7.17 EXTRACTION DES EFFECTIFS
*======================================================================*

quietly count ///
    if group3 == 2 ///
    & parent_group == 1

local mother_salience = r(N)


quietly count ///
    if group3 == 2 ///
    & parent_group == 2

local father_salience = r(N)


quietly count ///
    if group3 == 3 ///
    & parent_group == 1

local mother_impl = r(N)


quietly count ///
    if group3 == 3 ///
    & parent_group == 2

local father_impl = r(N)


*======================================================================*
* 7.18 EFFECTIFS DES BRAS
*======================================================================*

quietly count if group3 == 1
local n_control = r(N)

quietly count if group3 == 2
local n_salience = r(N)

quietly count if group3 == 3
local n_impl = r(N)


di as result ""
di as result "======================================================="
di as result "EFFECTIFS DES BRAS"
di as result "======================================================="

di as result "Control                   : `n_control'"
di as result "Salience                  : `n_salience'"
di as result "Salience + Implementation : `n_impl'"


*----------------------------------------------------------------------*
* VERIFICATION ATTENDUE
*----------------------------------------------------------------------*

assert `n_salience' == 52
assert `n_impl' == 52


*======================================================================*
* 7.19 RESULTATS MOTHER / FATHER
*======================================================================*

di as result ""
di as result "======================================================="
di as result "RESULTATS PARENT"
di as result "======================================================="

di as result ""
di as result "Salience :"
di as result "  Mother = `mother_salience'"
di as result "  Father = `father_salience'"

di as result ""
di as result "Salience + Implementation :"
di as result "  Mother = `mother_impl'"
di as result "  Father = `father_impl'"


*----------------------------------------------------------------------*
* VERIFICATION DES TOTAUX
*----------------------------------------------------------------------*

assert ///
    `mother_salience' + `father_salience' == 52

assert ///
    `mother_impl' + `father_impl' == 52


*----------------------------------------------------------------------*
* ECART MOTHER / FATHER
*----------------------------------------------------------------------*

local diff_sal = ///
    abs(`mother_salience' - `father_salience')

local diff_impl = ///
    abs(`mother_impl' - `father_impl')


di as result ""
di as result "Difference Salience                  : `diff_sal'"
di as result "Difference Salience + Implementation : `diff_impl'"


*----------------------------------------------------------------------*
* EQUILIBRE MAXIMAL
*----------------------------------------------------------------------*

assert `diff_sal' <= 1
assert `diff_impl' <= 1


*======================================================================*
* 7.20 CONTROLE EXACT 26 / 26
*======================================================================*
*
* Puisque chaque bras traite comporte 52 ecoles, le meilleur equilibre
* possible est exactement :
*
*       26 Mother
*       26 Father
*
*----------------------------------------------------------------------*

assert `mother_salience' == 26
assert `father_salience' == 26

assert `mother_impl' == 26
assert `father_impl' == 26


di as result ""
di as result "======================================================="
di as result "FINAL PARENT BALANCE"
di as result "======================================================="

di as result ///
    "Salience                  : 26 Mother / 26 Father"

di as result ///
    "Salience + Implementation : 26 Mother / 26 Father"

di as result "======================================================="


*======================================================================*
* 7.21 CONTROLES DE COHERENCE INTERNES
*======================================================================*

*----------------------------------------------------------------------*
* Toutes les ecoles traitees doivent avoir un parent.
*----------------------------------------------------------------------*

quietly count if treated == 1 & missing(parent_group)

assert r(N) == 0


*----------------------------------------------------------------------*
* Aucune ecole Control ne doit avoir de parent.
*----------------------------------------------------------------------*

quietly count if treated == 0 & !missing(parent_group)

assert r(N) == 0


*----------------------------------------------------------------------*
* Toutes les cellules bloc x bras traitees doivent avoir une
* attribution parent.
*----------------------------------------------------------------------*

quietly count if treated == 1 & missing(bloc_arm)

assert r(N) == 0


*----------------------------------------------------------------------*
* Toutes les cellules paires sont exactement 50/50.
*----------------------------------------------------------------------*

preserve

    contract bloc_arm parent_group ///
        if treated == 1, ///
        freq(n)

    bysort bloc_arm: egen cell_min = min(n)
    bysort bloc_arm: egen cell_max = max(n)

    quietly count if cell_min != cell_max

    local unequal_even = r(N)

restore


di as result ""
di as result ///
    "Controle des cellules bloc x bras termine."


*======================================================================*
* 7.22 RESUME FINAL
*======================================================================*

di as result ""
di as result "======================================================="
di as result "RESUME RANDOMISATION PARENT"
di as result "======================================================="

di as result "Seed parent : $SEED_PARENT"

di as result "Control : `n_control'"

di as result ///
    "Salience : `n_salience'"

di as result ///
    "Salience + Implementation : `n_impl'"

di as result ""

di as result ///
    "Salience -> Mother = `mother_salience' ; Father = `father_salience'"

di as result ///
    "Implementation -> Mother = `mother_impl' ; Father = `father_impl'"

di as result ""

di as result "Balance parent : OK"

di as result "======================================================="


*======================================================================*
* FIN SECTION 7
*======================================================================*


*======================================================================*
* 8. TESTS D'EQUILIBRE
*======================================================================*

di as result ""
di as result "======================================================="
di as result "TESTS D'EQUILIBRE"
di as result "======================================================="


*----------------------------------------------------------------------*
* EQUILIBRE PAR COMMUNE
*----------------------------------------------------------------------*

tab COMMUNE group3, chi2


*----------------------------------------------------------------------*
* EQUILIBRE PAR TAILLE
*----------------------------------------------------------------------*

tab size_label group3, chi2


*----------------------------------------------------------------------*
* EQUILIBRE PAR MILIEU
*----------------------------------------------------------------------*

tab MILIEU_EQUIPE group3, chi2


*----------------------------------------------------------------------*
* BALANCE VARIABLES
*----------------------------------------------------------------------*

local balance_vars ///
    target_enrol ///
    NBM6EME ///
    NBM5EME ///
    SALLESCLASSESTOT ///
    EXISTENCEEAU ///
    EXISTENCEELECT ///
    EXISTENCELATRINES ///
    EXISTENCEINFRASTSPORT


foreach v of local balance_vars {

    capture confirm numeric variable `v'

    if !_rc {

        di as text _newline ///
            "--- Balance : `v' ---"

        quietly regress ///
            `v' i.group3 i.bloc, ///
            vce(robust)

        testparm i.group3
    }
}


*======================================================================*
* 9. PREPARATION DE L'EXPORT
*======================================================================*

capture drop group3_lbl

gen str35 group3_lbl = ""

replace group3_lbl = ///
    "Control" ///
    if group3 == 1

replace group3_lbl = ///
    "Salience" ///
    if group3 == 2

replace group3_lbl = ///
    "Salience + Implementation" ///
    if group3 == 3


capture drop parent_lbl2

gen str12 parent_lbl2 = ""

replace parent_lbl2 = ///
    "Mother" ///
    if parent_group == 1

replace parent_lbl2 = ///
    "Father" ///
    if parent_group == 2

replace parent_lbl2 = ///
    "N/A" ///
    if treated == 0


*======================================================================*
* 10. EXPORT EXCEL
*======================================================================*

preserve

    keep ///
        id_infra ///
        DEPARTEMENT ///
        COMMUNE ///
        ARRONDISSEMENT ///
        NOMETABLISSEMENT ///
        MILIEU_EQUIPE ///
        size_label ///
        strate_label ///
        bloc ///
        group3_lbl ///
        parent_lbl2 ///
        target_enrol ///
        med_enrol


    rename size_label ///
        size_category

    rename group3_lbl ///
        assigned_group

    rename parent_lbl2 ///
        targeted_parent


    order ///
        id_infra ///
        DEPARTEMENT ///
        COMMUNE ///
        ARRONDISSEMENT ///
        NOMETABLISSEMENT ///
        MILIEU_EQUIPE ///
        size_category ///
        strate_label ///
        bloc ///
        assigned_group ///
        targeted_parent ///
        target_enrol ///
        med_enrol


    sort bloc id_infra


    export excel ///
        using "$outputdir/randomization_final_v2.xlsx", ///
        firstrow(variables) ///
        replace ///
        sheet("randomization")

restore


*======================================================================*
* 11. SAUVEGARDE DATASET FINAL
*======================================================================*

save ///
    "$outputdir/randomization_final_v2_locked_`timestamp'.dta", ///
    replace


*======================================================================*
* 12. MANIFESTE
*======================================================================*

datasignature

local sig = r(datasignature)


file open manifest using ///
    "$outputdir/randomization_v2_manifest_`timestamp'.txt", ///
    write ///
    replace


file write manifest ///
    "RANDOMIZATION MANIFEST v2 - Gender Norms RCT" _n

file write manifest ///
    "==============================================" _n

file write manifest ///
    "Date/heure       : $S_DATE $S_TIME" _n

file write manifest ///
    "SEED_BLOCKS      : $SEED_BLOCKS" _n

file write manifest ///
    "SEED_ARMS        : $SEED_ARMS" _n

file write manifest ///
    "SEED_PARENT      : $SEED_PARENT" _n

file write manifest ///
    "N ecoles         : 156" _n

file write manifest ///
    "Regle de taille  : mediane communale, filles 6e+5e" _n

file write manifest ///
    "Strates          : commune x size_label, INDEPENDANTES" _n

file write manifest ///
    "Fusion cross-commune : AUCUNE" _n

file write manifest ///
    "Dernier bloc     : taille = reste de la strate" _n

file write manifest ///
    "Parent           : imbrique dans bloc x bras" _n

file write manifest ///
    "Parent balance   : 26 Mother / 26 Father par bras traite" _n

file write manifest ///
    "Checksum         : `sig'" _n


file close manifest


*======================================================================*
* 13. FIN
*======================================================================*

di as result ""
di as result "======================================================="
di as result "RANDOMISATION V2 TERMINEE"
di as result "======================================================="

di as result "156 ecoles randomisees."

di as result "Bras :"

tab group3

di as result ""

di as result "Parents :"

tab group3 parent_group if treated == 1

di as result ""

di as result "Reproductibilite bras : CONFIRMEE"

di as result "Reproductibilite parent : CONFIRMEE"

di as result "Parent balance :"

di as result ///
    "Salience = 26 Mother / 26 Father"

di as result ///
    "Salience + Implementation = 26 Mother / 26 Father"

di as result "======================================================="


log close