/********************************************************************
 Project      : Gender norm
 Author       : Lucien Allosse
 Date         : [date]
 Purpose      : Suite au retour du PI (30/08/2026) : tester plusieurs
                graines pour la randomisation des bras, comparer leur
                equilibre (ecart max entre bras + tests de balance),
                et choisir la meilleure - en gardant la version
                actuelle comme reference. AUCUNE selection sur les
                resultats du projet, uniquement sur l'equilibre des
                covariables de depart (rerandomisation methodologique
                standard, cf. Morgan & Rubin 2012).
 Software     : Stata 16
 Input        : Outputs/ecoles_blocs_v2_locked.dta (blocs deja
                construits et valides - INCHANGES ici)
********************************************************************/

*======================================================================*
* 0. INITIALISATION
*======================================================================*

version 16.0
clear all
set more off
capture log close
capture frame drop arm_draw
capture frame drop results

*global working   "C:\1_CKDEV_File\1_CKDev_File\3_Projet_   Gender_ Norms_  May_2026\5_File_About_ Randomisation_ 08032026\12_Randomisation_Commune_ Independante_ 082926\Outputs"   // TODO: adapter le chemin

global working "C:\1_CKDEV_File\1_CKDev_File\3_Projet_   Gender_ Norms_  May_2026\5_File_About_ Randomisation_ 08032026\12_Randomisation_Commune_ Independante_ 082926"

global outputdir "$working\Outputs"
cd "$working"

global N_ARMS 3

* Graines candidates a tester : la graine actuelle (reference) + 4
* nouvelles graines. Modifier/ajouter des valeurs si besoin.
local candidate_seeds 20260828 20260901 20260902 20260903 20260904

local balance_vars target_enrol NBM6EME NBM5EME SALLESCLASSESTOT ///
    EXISTENCEEAU EXISTENCEELECT EXISTENCELATRINES EXISTENCEINFRASTSPORT

*======================================================================*
* 1. PREPARER LE CADRE DE RESULTATS
*======================================================================*

frame create results
frame results {
    gen long   seed        = .
    gen long   n_control   = .
    gen long   n_salience  = .
    gen long   n_salienceMO= .
    gen long   arm_gap     = .
    gen int    n_sig_5pct  = .
    gen double min_pvalue  = .
}

*======================================================================*
* 2. BOUCLE SUR LES GRAINES CANDIDATES
*======================================================================*

foreach s of local candidate_seeds {

    di as result "======================================================="
    di as result "TEST DE LA GRAINE : `s'"
    di as result "======================================================="

    use "$outputdir/ecoles_blocs_v2_locked.dta", clear

    *--- Randomisation des bras avec la graine `s' (logique inchangee) ---
    sort id_infra
    set seed `s'
    capture drop rand_arm
    gen double rand_arm = runiform()

    sort bloc rand_arm
    capture drop rank_arm
    capture drop bloc_n_arm
    by bloc: gen long rank_arm   = _n
    by bloc: gen long bloc_n_arm = _N

    capture drop group3
    gen byte group3 = .
    replace group3 = mod(rank_arm - 1, $N_ARMS) + 1 ///
        if rank_arm <= floor(bloc_n_arm / $N_ARMS) * $N_ARMS

    quietly levelsof bloc, local(blist_s)
    foreach b of local blist_s {
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
                    if bloc == `b' & rank_arm == `nbase' * $N_ARMS + `i'
                local i = `i' + 1
            }
        }
    }

    quietly count if missing(group3)
    assert r(N) == 0

    *--- Comptes par bras et ecart max ---
    quietly count if group3 == 1
    local nc = r(N)
    quietly count if group3 == 2
    local ns = r(N)
    quietly count if group3 == 3
    local nm = r(N)

    local gmax = max(`nc', `ns', `nm')
    local gmin = min(`nc', `ns', `nm')
    local gap  = `gmax' - `gmin'

    *--- Tests de balance : combien de variables significatives a 5% ---
    local n_sig = 0
    local min_p = 1

    foreach v of local balance_vars {
        capture confirm numeric variable `v'
        if !_rc {
            quietly regress `v' i.group3 i.bloc, vce(robust)
            quietly testparm i.group3
            local p = r(p)
            if `p' < 0.05 {
                local n_sig = `n_sig' + 1
            }
            if `p' < `min_p' {
                local min_p = `p'
            }
        }
    }

    di as result "Bras : Control=`nc' Salience=`ns' Salience+MO=`nm' (ecart max=`gap')"
    di as result "Variables significatives (p<0.05) : `n_sig' / 8. p minimale = `min_p'"

    *--- Stocker dans le cadre results ---
    frame post results (`s') (`nc') (`ns') (`nm') (`gap') (`n_sig') (`min_p')
}

*======================================================================*
* 3. TABLEAU COMPARATIF DES GRAINES
*======================================================================*

di as result "======================================================="
di as result "COMPARAISON DES GRAINES TESTEES"
di as result "======================================================="

frame results {
    gsort n_sig arm_gap
    list seed n_control n_salience n_salienceMO arm_gap n_sig_5pct min_pvalue, ///
        noobs sep(0)

    export excel using "$outputdir/comparaison_graines_bras.xlsx", ///
        firstrow(variables) replace
}

di as result "======================================================="
di as result "Choisissez la graine avec le plus petit ecart entre bras"
di as result "ET le moins de variables significatives (idealement 0-1)."
di as result "Notez cette graine : elle deviendra SEED_ARMS dans le"
di as result "script final. Reexecutez ensuite le do-file complet"
di as result "(5_Randomisation_v2...) avec cette valeur pour regenerer"
di as result "les bras, le parent, les exports et le manifeste."
di as result "======================================================="
