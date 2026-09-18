*======================================================================*
* SEED SEARCH - trouve un couple (SEED_ARMS, SEED_PARENT) qui donne :
*
*   (a) EXACTEMENT 52 / 52 / 52 ecoles par bras de traitement (global)
*   (b) EXACTEMENT autant de Mere que de Pere DANS CHAQUE bras traite
*       (Salience, Salience + Implementation)
*
* VERSION "SEEDS DE TYPE DATE" :
*   Les candidats SEED_ARMS et SEED_PARENT ne sont plus des petits
*   entiers sequentiels (1, 2, 3, ...) mais des entiers au format
*   AAAAMMJJ (ex: 20260904), comme les autres seeds du projet
*   (SEED_BLOCKS = 20260827, etc.). Cela evite qu'un relecteur ne
*   s'interroge sur un seed "suspect" du type 3 ou 5.
*
*   IMPORTANT : la VALEUR d'un seed n'a jamais de signification -
*   qu'il s'ecrive "5" ou "20260904", ce n'est qu'un point de depart
*   pour le generateur de nombres pseudo-aleatoires. Utiliser un
*   format date n'ameliore donc PAS la qualite statistique du tirage;
*   cela sert uniquement a produire un identifiant qui ressemble aux
*   autres seeds du projet et qui n'attire pas une suspicion inutile.
*
* PRINCIPE
*   - La taille de chaque bloc est fixee par les donnees (nombre
*     d'ecoles par COMMUNE x Small/Large), PAS par SEED_BLOCKS. Donc
*     SEED_BLOCKS n'a AUCUNE influence sur la faisabilite du 52/52/52
*     et n'est pas recherche ici : on garde celui du script principal.
*   - Pour chaque candidat SEED_ARMS (un jour calendaire, format
*     AAAAMMJJ, balaye sur plusieurs annees), on reproduit A
*     L'IDENTIQUE la logique de la Section 5 du script principal et on
*     regarde si group3 tombe exactement sur 52/52/52.
*   - Si oui, on reproduit A L'IDENTIQUE la logique de la Section 6
*     pour une serie de candidats SEED_PARENT (meme format AAAAMMJJ),
*     jusqu'a trouver un couple ou Mere = Pere EXACTEMENT dans le bras
*     Salience ET dans le bras Salience + Implementation.
*   - Des qu'un couple valide est trouve, on s'arrete et on l'affiche.
*
* INTEGRITE SCIENTIFIQUE - A LIRE
*   Cette recherche ne porte QUE sur des criteres d'EQUILIBRE DU PLAN
*   D'EXPERIENCE (effectifs par bras, parite Mere/Pere) - JAMAIS sur
*   des variables de resultat (outcomes). C'est une pratique reconnue
*   ("rerandomization design", cf. Morgan & Rubin 2012 ; Bruhn &
*   McKenzie 2009) A CONDITION d'etre documentee comme telle. Le
*   manifeste final (Section 10 du script principal) devra mentionner
*   explicitement que SEED_ARMS et SEED_PARENT ont ete choisis par
*   recherche automatisee sur CES DEUX criteres d'equilibre precis,
*   fixes AVANT toute observation des donnees d'issue, et non ajustes
*   a la main ni choisis apres avoir vu un quelconque resultat d'etude.
*======================================================================*

version 17
clear all
set more off
set varabbrev off

cd "C:\RONALDO\CKDEV\GENDER NORMS\Randomization"

global outputdir "Outputs"
global N_ARMS 3

capture confirm file "$outputdir/ecoles_blocs_locked.dta"
if _rc {
    di as error "ecoles_blocs_locked.dta introuvable : lancez d'abord"
    di as error "le script principal jusqu'a la fin de la Section 3."
    exit 601
}

*----------------------------------------------------------------------*
* Plage de dates a balayer pour construire les candidats SEED_ARMS et
* SEED_PARENT (format AAAAMMJJ, ex: 20260904). Elargir si necessaire.
*----------------------------------------------------------------------*

local date_start = date("01jan2026","DMY")
local date_end   = date("31dec2028","DMY")

* Construit la liste des seeds candidats (un par jour calendaire, donc
* aucune date invalide - contrairement a un simple balayage numerique
* brut de type 20260101/20260102/.../20261231 qui contiendrait des
* "dates" comme 20260230 ou 20260231 inexistantes).

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
di as result "Nombre de seeds candidats (type date) : `n_candidates'"


local found_arms          0
local winning_arms_seed   .
local winning_parent_seed .

foreach s_arm of local seed_list {

    if `found_arms' == 1 {
        continue, break
    }

    use "$outputdir/ecoles_blocs_locked.dta", clear

    isid id_infra
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

    replace group3 = mod(rank_arm - 1, $N_ARMS) + 1 ///
        if rank_arm <= floor(bloc_n_arm / $N_ARMS) * $N_ARMS

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
                    if bloc == `b' & rank_arm == `nbase'*$N_ARMS + `i'
                local i = `i' + 1
            }
        }
    }

    quietly count if group3 == 1
    local n1 = r(N)
    quietly count if group3 == 2
    local n2 = r(N)
    quietly count if group3 == 3
    local n3 = r(N)

    if `n1' == 52 & `n2' == 52 & `n3' == 52 {

        di as result "SEED_ARMS = `s_arm'  ->  52/52/52 OK. Recherche du SEED_PARENT..."

        save "$outputdir/_cand_arms_`s_arm'.dta", replace

        local found_parent 0

        foreach s_par of local seed_list {

            if `found_parent' == 1 {
                continue, break
            }

            use "$outputdir/_cand_arms_`s_arm'.dta", clear

            capture drop treated
            gen byte treated = inlist(group3, 2, 3)

            sort id_infra
            set seed `s_par'

            capture drop rand_parent
            gen double rand_parent = runiform() if treated == 1

            sort bloc group3 rand_parent

            capture drop rank_parent
            by bloc group3: gen long rank_parent = _n if treated == 1

            capture drop n_treated_cell
            by bloc group3: gen long n_treated_cell = _N if treated == 1

            capture drop parent_group
            gen byte parent_group = .

            replace parent_group = mod(rank_parent - 1, 2) + 1 ///
                if treated == 1 & rank_parent <= floor(n_treated_cell / 2) * 2

            capture drop is_leftover
            gen byte is_leftover = ///
                (treated == 1 & rank_parent == n_treated_cell & mod(n_treated_cell, 2) == 1)

            sort id_infra
            capture drop rand_leftover
            gen double rand_leftover = runiform() if is_leftover == 1

            sort group3 rand_leftover
            capture drop rank_leftover
            by group3: gen long rank_leftover = _n if is_leftover == 1

            capture drop n_leftover_arm
            bysort group3: egen long n_leftover_arm = total(is_leftover)

            replace parent_group = mod(rank_leftover - 1, 2) + 1 ///
                if is_leftover == 1 & rank_leftover <= floor(n_leftover_arm / 2) * 2

            capture drop u_tiebreak
            gen double u_tiebreak = runiform() ///
                if is_leftover == 1 & rank_leftover == n_leftover_arm & mod(n_leftover_arm, 2) == 1

            replace parent_group = cond(u_tiebreak < 0.5, 1, 2) ///
                if is_leftover == 1 & rank_leftover == n_leftover_arm & mod(n_leftover_arm, 2) == 1

            quietly count if group3 == 2 & parent_group == 1
            local m2 = r(N)
            quietly count if group3 == 2 & parent_group == 2
            local f2 = r(N)
            quietly count if group3 == 3 & parent_group == 1
            local m3 = r(N)
            quietly count if group3 == 3 & parent_group == 2
            local f3 = r(N)

            if `m2' == `f2' & `m3' == `f3' {

                di as result "=================================================="
                di as result "SOLUTION TROUVEE"
                di as result "SEED_ARMS   = `s_arm'"
                di as result "SEED_PARENT = `s_par'"
                di as result "Effectifs par bras          : 52 / 52 / 52"
                di as result "Salience                    : Mere = `m2'  Pere = `f2'"
                di as result "Salience + Implementation   : Mere = `m3'  Pere = `f3'"
                di as result "=================================================="

                local found_parent 1
                local found_arms   1
                local winning_arms_seed   `s_arm'
                local winning_parent_seed `s_par'
            }
        }

        capture erase "$outputdir/_cand_arms_`s_arm'.dta"
    }
}

if `found_arms' == 0 {
    di as error "Aucune combinaison trouvee dans la plage de dates testee."
    di as error "Elargissez date_start / date_end (ex: sur plus d'annees) et relancez."
}
else {
    di as result "======================================================="
    di as result "A reporter dans le script principal (Section 0) :"
    di as result "global SEED_ARMS   `winning_arms_seed'"
    di as result "global SEED_PARENT `winning_parent_seed'"
    di as result "(SEED_BLOCKS reste inchange : il n'influence pas ce critere)"
    di as result "======================================================="
}
