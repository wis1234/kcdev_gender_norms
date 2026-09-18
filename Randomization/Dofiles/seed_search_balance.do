*======================================================================*
*  SEARCH OPTIMISE DES SEEDS DE RANDOMISATION
*
*  OBJECTIF
*  --------
*  Trouver :
*    1. SEED_ARMS donnant exactement 52/52/52 écoles
*    2. un excellent équilibre des covariables de base
*    3. en utilisant EXACTEMENT le même modèle que Section 7 :
*
*         regress outcome i.group3 i.bloc, vce(robust)
*
*    4. puis SEED_PARENT donnant exactement 26/26 Mere/Pere
*       dans chacun des deux bras traités.
*
*  IMPORTANT :
*  Le programme NE S'ARRETE PAS au premier seed acceptable.
*  Il parcourt TOUS les seeds candidats et conserve le meilleur.
*
*======================================================================*

version 17
clear all
set more off
set varabbrev off

cd "C:\RONALDO\CKDEV\GENDER NORMS\Randomization"

global outputdir "Outputs"
global N_ARMS 3

global BALANCE_VARS "target_enrol NBM6EME NBF6EME NBM5EME NBF5EME SALLESCLASSESTOT EXISTENCEEAU EXISTENCEELECT EXISTENCELATRINES EXISTENCEINFRASTSPORT"

global BALANCE_VARS_CAT "MILIEU"

global BALANCE_PVAL_MIN 0.10

*----------------------------------------------------------------------*
* FICHIER SOURCE
*----------------------------------------------------------------------*

capture confirm file "$outputdir/ecoles_blocs_locked.dta"

if _rc {
    di as error "ecoles_blocs_locked.dta introuvable."
    exit 601
}

use "$outputdir/ecoles_blocs_locked.dta", clear

*----------------------------------------------------------------------*
* VERIFICATIONS
*----------------------------------------------------------------------*

foreach v of global BALANCE_VARS {

    capture confirm variable `v'

    if _rc {
        di as error "Variable `v' absente."
        exit 111
    }
}

foreach v of global BALANCE_VARS_CAT {

    capture confirm variable `v'

    if _rc {
        di as error "Variable `v' absente."
        exit 111
    }

    capture confirm string variable `v'

    if _rc {
        di as error "`v' doit etre une variable string."
        exit 111
    }
}

isid id_infra

*----------------------------------------------------------------------*
* ENCODAGE DES VARIABLES CATEGORIELLES
*----------------------------------------------------------------------*

foreach v of global BALANCE_VARS_CAT {

    capture drop `v'_num
    encode `v', gen(`v'_num)
}

*----------------------------------------------------------------------*
* LISTE DES SEEDS
* Format AAAAMMJJ
*----------------------------------------------------------------------*

local date_start = date("01jan2026","DMY")
local date_end   = date("31dec2028","DMY")

local seed_list ""
local d = `date_start'

while `d' <= `date_end' {

    local yyyy = year(`d')
    local mm   = string(month(`d'), "%02.0f")
    local dd   = string(day(`d'),   "%02.0f")

    local seed_list "`seed_list' `yyyy'`mm'`dd'"

    local d = `d' + 1
}

local n_candidates : word count `seed_list'

di as result "============================================================"
di as result "RECHERCHE OPTIMISEE DES SEEDS"
di as result "Nombre de candidats : `n_candidates'"
di as result "Seuil p-value      : $BALANCE_PVAL_MIN"
di as result "============================================================"

*----------------------------------------------------------------------*
* VARIABLES POUR LE MEILLEUR SEED
*----------------------------------------------------------------------*

local best_arms_seed .
local best_min_pval  = -1
local best_joint_pval = -1
local best_worst_var ""

local n_effectifs_ok = 0
local n_balance_ok   = 0

*----------------------------------------------------------------------*
* BOUCLE SEED_ARMS
*----------------------------------------------------------------------*

foreach s_arm of local seed_list {

    use "$outputdir/ecoles_blocs_locked.dta", clear

    foreach v of global BALANCE_VARS_CAT {
        capture drop `v'_num
        encode `v', gen(`v'_num)
    }

    isid id_infra

    *--------------------------------------------------------------*
    * Randomisation des 3 bras
    *--------------------------------------------------------------*

    sort id_infra

    set seed `s_arm'

    capture drop rand_arm
    gen double rand_arm = runiform()

    sort bloc rand_arm

    capture drop rank_arm
    by bloc: gen long rank_arm = _n

    capture drop bloc_n_arm
    by bloc: gen long bloc_n_arm = _N

    capture drop group3
    gen byte group3 = .

    * Partie divisible par 3
    replace group3 = mod(rank_arm - 1, $N_ARMS) + 1 ///
        if rank_arm <= floor(bloc_n_arm / $N_ARMS) * $N_ARMS

    * Gestion des restes
    levelsof bloc, local(blist) clean

    foreach b of local blist {

        quietly summarize bloc_n_arm if bloc == `b', meanonly

        local n     = r(max)
        local nbase = floor(`n' / $N_ARMS)
        local rem   = `n' - `nbase' * $N_ARMS

        if `rem' > 0 {

            capture frame drop arm_draw
            frame create arm_draw

            frame arm_draw {

                set obs $N_ARMS

                gen byte arm_id = _n
                gen double u = runiform()

                sort u
            }

            local chosen ""

            forvalues i = 1/`rem' {

                frame arm_draw: ///
                    local this_arm = arm_id[`i']

                local chosen "`chosen' `this_arm'"
            }

            frame drop arm_draw

            local i = 1

            foreach a of local chosen {

                quietly replace group3 = `a' ///
                    if bloc == `b' ///
                    & rank_arm == `nbase'*$N_ARMS + `i'

                local i = `i' + 1
            }
        }
    }

    *--------------------------------------------------------------*
    * TEST 52 / 52 / 52
    *--------------------------------------------------------------*

    quietly count if group3 == 1
    local n1 = r(N)

    quietly count if group3 == 2
    local n2 = r(N)

    quietly count if group3 == 3
    local n3 = r(N)

    if !(`n1' == 52 & `n2' == 52 & `n3' == 52) {
        continue
    }

    local n_effectifs_ok = `n_effectifs_ok' + 1

    *--------------------------------------------------------------*
    * TEST DES COVARIABLES
    *
    * IMPORTANT :
    * EXACTEMENT le modele de la Section 7 :
    *
    * regress variable i.group3 i.bloc, vce(robust)
    *--------------------------------------------------------------*

    local min_pval = 1
    local worst_var ""

    local all_tests_ok = 1

    foreach v of global BALANCE_VARS {

        capture quietly regress `v' i.group3 i.bloc, vce(robust)

        if _rc {
            local all_tests_ok = 0
            continue
        }

        quietly testparm i.group3

        local p_this = r(p)

        if missing(`p_this') {
            local all_tests_ok = 0
            continue
        }

        if `p_this' < `min_pval' {

            local min_pval = `p_this'
            local worst_var "`v'"
        }
    }

    *--------------------------------------------------------------*
    * VARIABLES CATEGORIELLES
    *
    * Pour MILIEU, on utilise le meme principe de test d'association.
    *--------------------------------------------------------------*

    foreach v of global BALANCE_VARS_CAT {

        capture quietly tabulate `v'_num group3, chi2

        if _rc {
            local all_tests_ok = 0
            continue
        }

        local p_this = r(p)

        if missing(`p_this') {
            local all_tests_ok = 0
            continue
        }

        if `p_this' < `min_pval' {

            local min_pval = `p_this'
            local worst_var "`v'"
        }
    }

    *--------------------------------------------------------------*
    * TEST JOINT
    *
    * On teste si les covariables expliquent collectivement
    * l'assignation aux 3 bras.
    *--------------------------------------------------------------*

    local cat_num_list ""

    foreach v of global BALANCE_VARS_CAT {
        local cat_num_list "`cat_num_list' i.`v'_num"
    }

    capture quietly ///
        mlogit group3 $BALANCE_VARS `cat_num_list', base(1)

    if _rc {
        continue
    }

    capture quietly ///
        testparm $BALANCE_VARS `cat_num_list'

    if _rc {
        continue
    }

    local p_joint = r(p)

    if missing(`p_joint') {
        continue
    }

    *--------------------------------------------------------------*
    * ACCEPTABILITE MINIMALE
    *--------------------------------------------------------------*

    if !(`min_pval' > $BALANCE_PVAL_MIN ///
         & `p_joint' > $BALANCE_PVAL_MIN) {

        continue
    }

    local n_balance_ok = `n_balance_ok' + 1

    *--------------------------------------------------------------*
    * CRITERE D'OPTIMISATION
    *
    * Priorite 1 : maximiser la plus petite p-value
    * Priorite 2 : maximiser le test joint
    *--------------------------------------------------------------*

    local better = 0

    if `min_pval' > `best_min_pval' {
        local better = 1
    }
    else if `min_pval' == `best_min_pval' ///
        & `p_joint' > `best_joint_pval' {

        local better = 1
    }

    if `better' == 1 {

        local best_arms_seed = `s_arm'
        local best_min_pval = `min_pval'
        local best_joint_pval = `p_joint'
        local best_worst_var "`worst_var'"

        di as result "------------------------------------------------------------"
        di as result "NOUVEAU MEILLEUR SEED_ARMS"
        di as result "Seed       : `s_arm'"
        di as result "Min p      : " %6.4f `min_pval'
        di as result "Worst var  : `worst_var'"
        di as result "Joint p    : " %6.4f `p_joint'
        di as result "------------------------------------------------------------"

        * Sauvegarde de la meilleure allocation
        save "$outputdir/_BEST_ARMS.dta", replace
    }
}

*----------------------------------------------------------------------*
* RESULTAT SEED_ARMS
*----------------------------------------------------------------------*

di as result ""
di as result "============================================================"
di as result "MEILLEUR SEED_ARMS"
di as result "============================================================"

if missing(`best_arms_seed') {

    di as error "Aucun SEED_ARMS acceptable trouve."
    di as error "Candidats 52/52/52 : `n_effectifs_ok'"
    di as error "Candidats equilibres : `n_balance_ok'"

    exit 2001
}

di as result "SEED_ARMS       = `best_arms_seed'"
di as result "Min p-value     = " %6.4f `best_min_pval'
di as result "Variable worst  = `best_worst_var'"
di as result "Joint p-value   = " %6.4f `best_joint_pval'
di as result "Candidats 52/52/52 : `n_effectifs_ok'"
di as result "Candidats acceptables : `n_balance_ok'"

*----------------------------------------------------------------------*
* RECHERCHE SEED_PARENT
*----------------------------------------------------------------------*

use "$outputdir/_BEST_ARMS.dta", clear

gen byte treated = inlist(group3, 2, 3)

local winning_parent_seed .
local parent_found = 0

foreach s_par of local seed_list {

    if `parent_found' == 1 {
        continue, break
    }

    use "$outputdir/_BEST_ARMS.dta", clear

    gen byte treated = inlist(group3, 2, 3)

    sort id_infra

    set seed `s_par'

    *--------------------------------------------------------------*
    * Tirage parent
    *--------------------------------------------------------------*

    gen double rand_parent = runiform() if treated

    sort bloc group3 rand_parent

    by bloc group3: gen long rank_parent = _n if treated

    by bloc group3: gen long n_treated_cell = _N if treated

    gen byte parent_group = .

    replace parent_group = mod(rank_parent - 1, 2) + 1 ///
        if treated ///
        & rank_parent <= floor(n_treated_cell / 2) * 2

    *--------------------------------------------------------------*
    * Restes impairs
    *--------------------------------------------------------------*

    gen byte is_leftover = ///
        treated ///
        & rank_parent == n_treated_cell ///
        & mod(n_treated_cell, 2) == 1

    sort id_infra

    gen double rand_leftover = runiform() if is_leftover

    sort group3 rand_leftover

    by group3: gen long rank_leftover = _n if is_leftover

    bysort group3: egen long n_leftover_arm = total(is_leftover)

    replace parent_group = mod(rank_leftover - 1, 2) + 1 ///
        if is_leftover ///
        & rank_leftover <= floor(n_leftover_arm / 2) * 2

    gen double u_tiebreak = runiform() ///
        if is_leftover ///
        & rank_leftover == n_leftover_arm ///
        & mod(n_leftover_arm, 2) == 1

    replace parent_group = cond(u_tiebreak < 0.5, 1, 2) ///
        if is_leftover ///
        & rank_leftover == n_leftover_arm ///
        & mod(n_leftover_arm, 2) == 1

    *--------------------------------------------------------------*
    * PARITE MERE / PERE
    *--------------------------------------------------------------*

    quietly count if group3 == 2 & parent_group == 1
    local m2 = r(N)

    quietly count if group3 == 2 & parent_group == 2
    local f2 = r(N)

    quietly count if group3 == 3 & parent_group == 1
    local m3 = r(N)

    quietly count if group3 == 3 & parent_group == 2
    local f3 = r(N)

    if `m2' == `f2' & `m3' == `f3' {

        local winning_parent_seed = `s_par'
        local parent_found = 1

        save "$outputdir/_FINAL_RANDOMIZATION.dta", replace

        di as result ""
        di as result "============================================================"
        di as result "SOLUTION FINALE"
        di as result "============================================================"

        di as result "SEED_ARMS   = `best_arms_seed'"
        di as result "SEED_PARENT = `winning_parent_seed'"

        di as result ""
        di as result "Effectifs :"
        di as result "  Control                    = 52"
        di as result "  Salience                   = 52"
        di as result "  Salience + Implementation  = 52"

        di as result ""
        di as result "Parents :"
        di as result "  Salience                   : Mere = `m2'  Pere = `f2'"
        di as result "  Salience + Implementation : Mere = `m3'  Pere = `f3'"

        di as result ""
        di as result "Equilibre :"
        di as result "  Min p-value individuel = " %6.4f `best_min_pval'
        di as result "  Variable worst         = `best_worst_var'"
        di as result "  Test joint             = " %6.4f `best_joint_pval'

        di as result "============================================================"
    }
}

if `parent_found' == 0 {

    di as error "Aucun SEED_PARENT ne donne la parite exacte Mere/Pere."
    exit 2002
}

*----------------------------------------------------------------------*
* NETTOYAGE
*----------------------------------------------------------------------*

capture erase "$outputdir/_BEST_ARMS.dta"

di as result ""
di as result "Fichiers sauvegardes :"
di as result "  _FINAL_RANDOMIZATION.dta"
di as result ""
di as result "A reporter dans Section 0 :"
di as result "global SEED_ARMS   `best_arms_seed'"
di as result "global SEED_PARENT `winning_parent_seed'"
di as result "============================================================"

