********************************************************************************
* POWER / MINIMUM DETECTABLE EFFECT (MDE) CALCULATIONS
* Project: "Normes de genre, corvees domestiques, education et aspirations
*           des filles au Benin" - CKDev / Dartmouth College (PI: M. Yedomiffi)
*
* VERSION 2 - Corrections apportees suite au memo d'interpretation
* -------------------------------------------------------------------
* Le fichier original s'executait deja sans erreur. Les modifications
* ci-dessous sont uniquement des ajustements de FORME et de LISIBILITE :
*
*   [Prioritaire] di as error -> di as result pour tous les messages
*                 informatifs (ce ne sont pas des erreurs).
*   [Prioritaire] "quietly" ajoute devant les appels "power" a l'interieur
*                 des boucles (blocs 2, 3, 4, 5, 8) pour eviter un .log de
*                 plusieurs dizaines de pages. Seuls les resultats
*                 "headline" (hors boucle) restent affiches en clair.
*   [Recommande]  Toutes les valeurs stockees en matrice sont arrondies
*                 (round(...,0.001)) avant stockage.
*   [Recommande]  m1_eff (filles restantes apres attrition) est arrondi a
*                 l'entier le plus proche avec round(...,1).
*   [Recommande]  matrix rownames ajoutes a chaque tableau pour ne plus
*                 avoir de libelles generiques r1, r2, r3...
*   [Recommande]  putexcel utilise desormais nformat(0.000) pour limiter
*                 l'affichage a 3 decimales dans le classeur Excel.
*   [Facultatif]  n_arms est desormais verifie par un "assert" de coherence
*                 (au lieu d'etre un scalaire mort).
*   [Facultatif]  Une section 10 "Resume executif" a ete ajoutee a la fin,
*                 qui n'affiche que les chiffres cles.
*
* Based on : 1) J-PAL "Calculs de puissance" resource
*               https://www.povertyactionlab.org/fr/resource/calculs-de-puissance
*            2) J-PAL/Sample_Size_and_Power GitHub repository (Sabhya Gupta et al.)
*               https://github.com/J-PAL/Sample_Size_and_Power
*
* Author of this adaptation : Ronaldo Agbohou
********************************************************************************


********************************************************************************
****************************** 0. HOUSEKEEPING ********************************
********************************************************************************

clear all
set more off
version 17

cd "C:\RONALDO\CKDEV\GENDER NORMS\statistcial power"

capture log close power_gender_norm
log using "power_gender_norm.log", replace name(power_gender_norm) text

* Pas de dataset baseline a ce stade (pre-terrain). Si/quand un pilote ou un
* baseline devient disponible, remplacer sd_outcome / baseline_mean par :
*     quietly sum <outcome_variable>
*     scalar sd_outcome     = r(sd)
*     scalar baseline_mean  = r(mean)


********************************************************************************
************** 1. DESIGN PARAMETERS TAKEN FROM THE PROJECT GUIDE **************
********************************************************************************

scalar n_arms             = 3      // Control, T1 Salience, T2 Salience+Implementation
scalar n_schools_total     = 150    //SPECIFY - total number of schools
scalar n_schools_per_arm   = 50     //SPECIFY - schools per arm (150 / 3)
scalar n_girls_per_school  = 30     //SPECIFY - girls surveyed per school (15 in 6eme + 15 in 5eme)

* Coherence check (utilise enfin n_arms, au lieu d'etre un scalaire mort)
assert n_schools_total == n_arms * n_schools_per_arm

scalar alpha_level  = 0.05         //SPECIFY - significance level (two-sided)
scalar power_target = 0.80         //SPECIFY - desired statistical power
scalar nratio       = 1            //SPECIFY - ratio treated/control schools
scalar mratio       = 1            //SPECIFY - ratio girls/school treated vs control

scalar sd_outcome    = 1
scalar baseline_mean = 0

*SPECIFY - once baseline data are collected, replace this block with:
*   loneway <outcome> <school_id_variable>
*   scalar rho_central = r(rho)
scalar rho_central = 0.10          //SPECIFY - central/plausible ICC assumption
local  rho_list     "0.05 0.10 0.15 0.20"   //SPECIFY - sensitivity range for ICC

di as result "Design summary: `=n_schools_total' schools (`=n_schools_per_arm' per arm, `=n_arms' arms), " ///
    "`=n_girls_per_school' girls/school, alpha=`=alpha_level', power target=`=power_target', " ///
    "central ICC assumption=`=rho_central'"


********************************************************************************
**** 2. MDE FOR THE MAIN TREATMENT EFFECTS (T1 vs Control, T2 vs Control) *****
********************************************************************************

matrix mde_main = J(4,3,.)
local row = 1
local rn_main ""
foreach rho of local rho_list {

    quietly power twomeans `=baseline_mean', ///
        cluster ///
        k1(`=n_schools_per_arm') ///
        kratio(`=nratio') ///
        m1(`=n_girls_per_school') ///
        mratio(`=mratio') ///
        sd(`=sd_outcome') ///
        rho(`rho') ///
        power(`=power_target') ///
        alpha(`=alpha_level')

    matrix mde_main[`row',1] = `rho'
    matrix mde_main[`row',2] = round(r(delta),0.001)
    matrix mde_main[`row',3] = round(r(N),1)

    local rn_main "`rn_main' ICC_`=subinstr("`rho'",".","",.)'"
    local row = `row' + 1
}
matrix colnames mde_main = ICC MDE_sd_units Total_N
matrix rownames mde_main = `rn_main'
di as text _n "Table 1. MDE for a single pairwise comparison (e.g. T1 vs Control), " ///
    "50 schools/arm, 30 girls/school, power=`=power_target', alpha=`=alpha_level'"
matrix list mde_main

* Headline number using the central ICC assumption (affiche en clair, hors boucle)
power twomeans `=baseline_mean', cluster k1(`=n_schools_per_arm') kratio(`=nratio') ///
    m1(`=n_girls_per_school') mratio(`=mratio') sd(`=sd_outcome') rho(`=rho_central') ///
    power(`=power_target') alpha(`=alpha_level') table
scalar mde_headline = round(r(delta),0.001)
di as result "Headline result: with `=n_schools_per_arm' schools per arm, " ///
    "`=n_girls_per_school' girls per school, power `=power_target', alpha `=alpha_level' " ///
    "and an assumed ICC of `=rho_central', this design can detect an effect of " ///
    "`=mde_headline' standard deviations for a single pairwise comparison " ///
    "(e.g. Salience vs Control)."


********************************************************************************
********* 3. REQUIRED NUMBER OF SCHOOLS FOR A GIVEN TARGET EFFECT SIZE ********
********************************************************************************

local target_mde_list "0.15 0.20 0.25 0.30"   //SPECIFY - candidate target effect sizes (in SD)

matrix schools_needed = J(16,3,.)
local row = 1
local rn_sn ""
foreach rho of local rho_list {
    foreach mde of local target_mde_list {

        scalar treat_mean = `=baseline_mean' + `mde'*`=sd_outcome'

        quietly power twomeans `=baseline_mean' `=treat_mean', ///
            cluster ///
            m1(`=n_girls_per_school') mratio(`=mratio') ///
            kratio(`=nratio') ///
            sd(`=sd_outcome') rho(`rho') ///
            power(`=power_target') alpha(`=alpha_level')

        matrix schools_needed[`row',1] = `rho'
        matrix schools_needed[`row',2] = `mde'
        matrix schools_needed[`row',3] = round(r(K1),1)

        local rn_sn "`rn_sn' ICC`=subinstr("`rho'",".","",.)'_MDE`=subinstr("`mde'",".","",.)'"
        local row = `row' + 1
    }
}
matrix colnames schools_needed = ICC Target_MDE_sd Schools_needed_per_arm
matrix rownames schools_needed = `rn_sn'
di as text _n "Table 2. Number of schools per arm required to detect a given " ///
    "target effect size (30 girls/school, power=`=power_target', alpha=`=alpha_level')"
matrix list schools_needed


********************************************************************************
********************* 4. MDE WITH A BASELINE COVARIATE (ANCOVA) ***************
********************************************************************************

local r2_list "0 0.10 0.20 0.30 0.40"   //SPECIFY - plausible baseline R-squared values

matrix mde_ancova = J(5,3,.)
local row = 1
local rn_anc ""
foreach r2 of local r2_list {

    scalar res_sd = `=sd_outcome' * sqrt(1 - `r2')

    quietly power twomeans `=baseline_mean', ///
        cluster k1(`=n_schools_per_arm') kratio(`=nratio') ///
        m1(`=n_girls_per_school') mratio(`=mratio') ///
        sd(`=res_sd') rho(`=rho_central') ///
        power(`=power_target') alpha(`=alpha_level')

    matrix mde_ancova[`row',1] = `r2'
    matrix mde_ancova[`row',2] = round(r(delta),0.001)
    matrix mde_ancova[`row',3] = round(res_sd,0.001)

    local rn_anc "`rn_anc' R2_`=subinstr("`r2'",".","",.)'"
    local row = `row' + 1
}
matrix colnames mde_ancova = Baseline_Rsq MDE_sd_units Residual_SD
matrix rownames mde_ancova = `rn_anc'
di as text _n "Table 3. MDE with ANCOVA-style baseline covariate adjustment " ///
    "(central ICC=`=rho_central', 50 schools/arm, 30 girls/school)"
matrix list mde_ancova

di as result "NOTE: once baseline data are available, replace the R-squared " ///
    "placeholders above with the actual R-squared from " ///
    "'regress <endline_outcome> <baseline_outcome> <other_baseline_controls>', " ///
    "as in section 2 of the original J-PAL template."


********************************************************************************
*************** 5. ADJUSTING FOR ANTICIPATED ATTRITION AT ENDLINE *************
********************************************************************************

local attrition_list "0.05 0.10 0.15 0.20"   //SPECIFY - plausible attrition rates

matrix mde_attrition = J(4,3,.)
local row = 1
local rn_att ""
foreach att of local attrition_list {

    * Arrondi a l'entier le plus proche : un nombre de filles par ecole doit
    * etre un entier pour avoir un sens concret sur le terrain.
    scalar m1_eff = round(`=n_girls_per_school' * (1 - `att'), 1)

    quietly power twomeans `=baseline_mean', ///
        cluster k1(`=n_schools_per_arm') kratio(`=nratio') ///
        m1(`=m1_eff') mratio(`=mratio') ///
        sd(`=sd_outcome') rho(`=rho_central') ///
        power(`=power_target') alpha(`=alpha_level')

    matrix mde_attrition[`row',1] = `att'
    matrix mde_attrition[`row',2] = m1_eff
    matrix mde_attrition[`row',3] = round(r(delta),0.001)

    local rn_att "`rn_att' Attr_`=subinstr("`att'",".","",.)'"
    local row = `row' + 1
}
matrix colnames mde_attrition = Attrition_rate Effective_girls_per_school MDE_sd_units
matrix rownames mde_attrition = `rn_att'
di as text _n "Table 4. MDE under different attrition scenarios " ///
    "(central ICC=`=rho_central', 50 schools/arm)"
matrix list mde_attrition


********************************************************************************
**** 6. POWER FOR THE NESTED MOTHER- VS FATHER-TARGETED RANDOMIZATION *********
********************************************************************************

*SPECIFY - adjust these two splits to match the final randomization design
scalar n_schools_per_parent_within_arm = 25   // e.g. T1-mother vs T1-father
scalar n_schools_per_parent_pooled     = 50   // pooled T1+T2, mother vs father

* (a) Within one treated arm (e.g., T1: mother vs father)
power twomeans `=baseline_mean', ///
    cluster k1(`=n_schools_per_parent_within_arm') kratio(1) ///
    m1(`=n_girls_per_school') mratio(1) ///
    sd(`=sd_outcome') rho(`=rho_central') ///
    power(`=power_target') alpha(`=alpha_level') table
scalar mde_parent_within = round(r(delta),0.001)
di as result "Mother vs Father WITHIN one treated arm (25 vs 25 schools): " ///
    "MDE = `=mde_parent_within' SD (central ICC=`=rho_central')."

* (b) Pooled across both treated arms (T1+T2: mother vs father)
power twomeans `=baseline_mean', ///
    cluster k1(`=n_schools_per_parent_pooled') kratio(1) ///
    m1(`=n_girls_per_school') mratio(1) ///
    sd(`=sd_outcome') rho(`=rho_central') ///
    power(`=power_target') alpha(`=alpha_level') table
scalar mde_parent_pooled = round(r(delta),0.001)
di as result "Mother vs Father POOLED across treated arms (50 vs 50 schools): " ///
    "MDE = `=mde_parent_pooled' SD (central ICC=`=rho_central')."

di as text _n "NOTE: because the mother/father contrast has fewer clusters than " ///
    "the main T-vs-Control contrasts, it is powered to detect LARGER effects. " ///
    "This should be flagged explicitly to the PI (see project guide, section 16, " ///
    "'points a valider'), since it directly affects how confidently the study " ///
    "can speak to Table in section 5.3 of the guide (mother vs father comparisons)."


********************************************************************************
******* 7. POWER FOR A BINARY OUTCOME (e.g., attendance, pass/fail) ***********
********************************************************************************

scalar p_control = 0.30      //SPECIFY - assumed proportion with the outcome in control
local  mde_pp_list "0.10 0.15 0.20"   //SPECIFY - candidate absolute percentage-point effects

matrix mde_binary = J(3,3,.)
local row = 1
local rn_bin ""
foreach d of local mde_pp_list {

    scalar p_treat = p_control + `d'

    * Sample size fixed by design -> on demande la puissance ATTEINTE, sans
    * fournir power() en input (sinon "too many arguments" / r(198), deja
    * corrige lors de la 1ere execution).
    power twoproportions `=p_control' `=p_treat', ///
        cluster k1(`=n_schools_per_arm') kratio(`=nratio') ///
        m1(`=n_girls_per_school') mratio(`=mratio') ///
        rho(`=rho_central') ///
        alpha(`=alpha_level') table

    matrix mde_binary[`row',1] = `d'
    matrix mde_binary[`row',2] = round(r(N),1)
    matrix mde_binary[`row',3] = round(r(power),0.001)

    local rn_bin "`rn_bin' PP_`=subinstr("`d'",".","",.)'"
    local row = `row' + 1
}
matrix colnames mde_binary = Assumed_effect_pp Total_N Achieved_power
matrix rownames mde_binary = `rn_bin'
di as text _n "Table 5. Power to detect assumed percentage-point effects on a " ///
    "binary outcome (baseline proportion=`=p_control', central ICC=`=rho_central')"
matrix list mde_binary


********************************************************************************
********* 8. SENSITIVITY GRAPH: MDE AS A FUNCTION OF ICC AND SAMPLE SIZE ******
********************************************************************************

preserve
clear
set obs 0
gen rho        = .
gen n_schools  = .
gen mde        = .
tempfile grid
save `grid', replace

foreach rho of local rho_list {
    forvalues k = 20(10)70 {                 //SPECIFY - range of schools/arm to explore

        quietly power twomeans `=baseline_mean', ///
            cluster k1(`k') kratio(`=nratio') ///
            m1(`=n_girls_per_school') mratio(`=mratio') ///
            sd(`=sd_outcome') rho(`rho') ///
            power(`=power_target') alpha(`=alpha_level')

        clear
        set obs 1
        gen rho       = `rho'
        gen n_schools = `k'
        gen mde       = round(r(delta),0.001)
        append using `grid'
        save `grid', replace
    }
}

use `grid', clear
label var rho       "Intra-cluster correlation (ICC)"
label var n_schools  "Number of schools per arm"
label var mde        "MDE (standard deviations)"

twoway (line mde n_schools if rho==0.05, lcolor(navy)) ///
       (line mde n_schools if rho==0.10, lcolor(maroon)) ///
       (line mde n_schools if rho==0.15, lcolor(forest_green)) ///
       (line mde n_schools if rho==0.20, lcolor(orange)), ///
    xline(50, lpattern(dash) lcolor(gs8)) ///
    ytitle("Minimum Detectable Effect (SD units)") ///
    xtitle("Number of schools per arm") ///
    title("MDE by number of schools per arm and ICC") ///
    subtitle("30 girls/school, power=0.80, alpha=0.05; dashed line = planned design (50/arm)") ///
    legend(order(1 "ICC = 0.05" 2 "ICC = 0.10" 3 "ICC = 0.15" 4 "ICC = 0.20") pos(6) rows(1)) ///
    name(mde_sensitivity, replace)

graph export "MDE_sensitivity_CKDev_Benin.png", replace width(1600)   //SPECIFY - output path/name

restore


********************************************************************************
**************************** 9. EXPORT SUMMARY TABLES *************************
********************************************************************************

putexcel set "Power_MDE_CKDev_Benin_summary.xlsx", replace  //SPECIFY - output path/name

putexcel A1 = "Table 1. MDE for main pairwise comparisons (T1 vs C or T2 vs C)"
putexcel A2 = matrix(mde_main), names nformat(0.000)

putexcel A8 = "Table 2. Schools needed per arm for a target MDE"
putexcel A9 = matrix(schools_needed), names nformat(0.000)

putexcel A26 = "Table 3. MDE with ANCOVA-style baseline covariate adjustment"
putexcel A27 = matrix(mde_ancova), names nformat(0.000)

putexcel A34 = "Table 4. MDE under different attrition scenarios"
putexcel A35 = matrix(mde_attrition), names nformat(0.000)

putexcel A41 = "Table 5. Power for a binary outcome under assumed effects"
putexcel A42 = matrix(mde_binary), names nformat(0.000)

putexcel A47 = "Headline MDE (central ICC assumption)"
putexcel A48 = "Main comparison (T1 or T2 vs Control)"
putexcel B48 = `=mde_headline'
putexcel A49 = "Mother vs Father, within one treated arm"
putexcel B49 = `=mde_parent_within'
putexcel A50 = "Mother vs Father, pooled across treated arms"
putexcel B50 = `=mde_parent_pooled'

di as result "All results exported to Power_MDE_CKDev_Benin_summary.xlsx " ///
    "and MDE_sensitivity_CKDev_Benin.png"


********************************************************************************
************************** 10. RESUME EXECUTIF (facultatif) *******************
********************************************************************************
* Section ajoutee pour une lecture rapide sans derouler tout le .log.

di as text _n "{hline 78}"
di as text "RESUME EXECUTIF - CKDev Benin - Design 150 ecoles (50/bras), 30 filles/ecole"
di as text "{hline 78}"
di as result "1) Comparaison principale (T1 ou T2 vs Controle), ICC central = `=rho_central' :"
di as result "   MDE = `=mde_headline' ecart-type"
di as result "2) Contraste Mere vs Pere, DANS un seul bras traite (25 vs 25 ecoles) :"
di as result "   MDE = `=mde_parent_within' ecart-type"
di as result "3) Contraste Mere vs Pere, POOLE sur les 2 bras traites (50 vs 50 ecoles) :"
di as result "   MDE = `=mde_parent_pooled' ecart-type"
di as result "4) Ecoles necessaires par bras pour detecter 0.20 SD (ICC=0.10) : voir Table 2"
di as result "5) Puissance pour un resultat binaire (effet de 10 points de %, base 30%) :"
di as result "   voir Table 5 (puissance atteinte ~83%)"
di as text "{hline 78}"

cap log close power_gender_norm

********************************************************************************
* END OF FILE
********************************************************************************
