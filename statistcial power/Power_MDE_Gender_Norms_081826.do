********************************************************************************
* POWER / MINIMUM DETECTABLE EFFECT (MDE) CALCULATIONS
* Project: "Normes de genre, corvees domestiques, education et aspirations
*           des filles au Benin" - CKDev / Dartmouth College (PI: M. Yedomiffi)
*
* Purpose : Determine sample size, MDE and power for a school-level cluster-
*           randomized trial with:
*             - 3 arms: Control / T1 "Salience" / T2 "Salience + Implementation"
*             - a nested (school-level) mother- vs father-targeted randomization
*               inside the two treatment arms
*
* Based on : 1) J-PAL "Calculs de puissance" resource
*               https://www.povertyactionlab.org/fr/resource/calculs-de-puissance
*            2) J-PAL/Sample_Size_and_Power GitHub repository (Sabhya Gupta et al.)
*               https://github.com/J-PAL/Sample_Size_and_Power
*               -> this file adapts "J-PAL_Power_built_in_commands.do"
*                  (clustered design section) to the design parameters
*                  described in the CKDev project guide.
*
* Author of this adaptation : Ronaldo Agbohou
*
* HOW TO USE THIS FILE
*   - Every parameter that should be replaced with your own value is flagged
*     with a "SPECIFY" comment, exactly as in the original J-PAL template.
*   - The file is organized in self-contained blocks (0 to 8). You can run
*     block 0 first (housekeeping) and then any other block independently.
*   - Because no baseline / pilot dataset exists yet for this study, the
*     calculations below are run on STANDARDIZED effect sizes (mean = 0,
*     sd = 1). This is standard practice at the design stage: an MDE of,
*     say, 0.20 means "0.20 of a standard deviation of the outcome
*     variable". Once baseline/pilot data are collected, replace the
*     mean/sd placeholders in block 1 with the real values (see the
*     commented-out "sum" lines) and re-run.
*   - All standard errors are clustered at the SCHOOL level throughout,
*     because randomization happens at the school level while outcomes
*     (girls' time use, school performance, etc.) are measured at the
*     student level. This mirrors "loneway" + "power ..., cluster" in the
*     original J-PAL template.
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

* This design has no continuous baseline outcome variable yet (pre-fieldwork
* stage), so we do NOT load a dataset here, unlike the original J-PAL file
* (which uses baroda_0102_1obs.dta). Instead, all design parameters are set
* as scalars/locals below. If/when a pilot or comparable secondary dataset
* becomes available (e.g. a similar time-use survey), replace the
* "sd_outcome" and "baseline_mean" scalars with:
*     quietly sum <outcome_variable>
*     scalar sd_outcome     = r(sd)
*     scalar baseline_mean  = r(mean)



********************************************************************************
************** 1. DESIGN PARAMETERS TAKEN FROM THE PROJECT GUIDE **************
********************************************************************************

* --- Unit of randomization and unit of observation -----------------------
* Randomization unit  : secondary school (to avoid contamination between
*                        parents of the same school and to simplify delivery)
* Observation unit     : focal girl (6eme and 5eme), nested within school

* --- Planned sample envisioned in the project guide -----------------------
scalar n_arms            = 3      // Control, T1 Salience, T2 Salience+Implementation
scalar n_schools_total    = 150    //SPECIFY - total number of schools
scalar n_schools_per_arm  = 50     //SPECIFY - schools per arm (150 / 3)
scalar n_girls_per_school = 30     //SPECIFY - girls surveyed per school (15 in 6eme + 15 in 5eme)

* --- Statistical parameters -----------------------------------------------
scalar alpha_level  = 0.05         //SPECIFY - significance level (two-sided)
scalar power_target = 0.80         //SPECIFY - desired statistical power
scalar nratio       = 1            //SPECIFY - ratio of treatment schools to control schools (1 = equal)
scalar mratio       = 1            //SPECIFY - ratio of girls surveyed per school, treatment vs control (1 = equal)

* --- Standardized outcome (until pilot/baseline data are available) -------
* We work in standard-deviation units: mean = 0, sd = 1.
scalar sd_outcome    = 1
scalar baseline_mean = 0

* --- Intra-cluster correlation (ICC / rho) ---------------------------------
* No baseline data exist yet to estimate rho with "loneway" (as in the
* original J-PAL file: loneway $outcome $cluster_var). Since school-level
* ICCs for time-use / schooling outcomes in similar RCTs typically range
* from about 0.02 to 0.20, we run the calculations across a plausible
* RANGE and flag a "central" assumption for the headline numbers.
*SPECIFY - once baseline data are collected, replace this block with:
*   loneway <outcome> <school_id_variable>
*   scalar rho_central = r(rho)
scalar rho_central = 0.10          //SPECIFY - central/plausible ICC assumption
local  rho_list     "0.05 0.10 0.15 0.20"   //SPECIFY - sensitivity range for ICC

di as text "Design summary: `=n_schools_total' schools (`=n_schools_per_arm' per arm), " ///
    "`=n_girls_per_school' girls/school, alpha=`=alpha_level', power target=`=power_target', " ///
    "central ICC assumption=`=rho_central'"


********************************************************************************
**** 2. MDE FOR THE MAIN TREATMENT EFFECTS (T1 vs Control, T2 vs Control) *****
********************************************************************************

* This corresponds to coefficients beta1 (Salience) and beta2 (Salience +
* Implementation) in the main specification of the project guide (section 11.2):
*   Y_is = alpha + beta1*Salience_s + beta2*Implementation_s + X_i0'theta + FE_block + e_is
*
* Each pairwise comparison (T1 vs C, or T2 vs C) uses 50 treated schools
* against 50 control schools, i.e. a standard two-arm clustered design.
* We loop over the ICC sensitivity range defined above.

matrix mde_main = J(4,3,.)
local row = 1
foreach rho of local rho_list {

    power twomeans `=baseline_mean', ///
        cluster ///
        k1(`=n_schools_per_arm') ///        // number of clusters (schools) in the reference arm
        kratio(`=nratio') ///               // ratio of treated to control clusters
        m1(`=n_girls_per_school') ///       // girls surveyed per school in the reference arm
        mratio(`=mratio') ///
        sd(`=sd_outcome') ///
        rho(`rho') ///
        power(`=power_target') ///
        alpha(`=alpha_level') ///
        table

    matrix mde_main[`row',1] = `rho'
    matrix mde_main[`row',2] = r(delta)     // MDE in raw outcome units (= SD units here)
    matrix mde_main[`row',3] = r(N)         // total number of respondents (girls)

    local row = `row' + 1
}
matrix colnames mde_main = ICC MDE_sd_units Total_N
di as text _n "Table 1. MDE for a single pairwise comparison (e.g. T1 vs Control), " ///
    "50 schools/arm, 30 girls/school, power=`=power_target', alpha=`=alpha_level'"
matrix list mde_main

* Headline number using the central ICC assumption
power twomeans `=baseline_mean', cluster k1(`=n_schools_per_arm') kratio(`=nratio') ///
    m1(`=n_girls_per_school') mratio(`=mratio') sd(`=sd_outcome') rho(`=rho_central') ///
    power(`=power_target') alpha(`=alpha_level') table
scalar mde_headline = round(r(delta),0.001)
di as error "Headline result: with `=n_schools_per_arm' schools per arm, " ///
    "`=n_girls_per_school' girls per school, power `=power_target', alpha `=alpha_level' " ///
    "and an assumed ICC of `=rho_central', this design can detect an effect of " ///
    "`=mde_headline' standard deviations for a single pairwise comparison " ///
    "(e.g. Salience vs Control)."


********************************************************************************
********* 3. REQUIRED NUMBER OF SCHOOLS FOR A GIVEN TARGET EFFECT SIZE ********
********************************************************************************

* Reverse question: "How many schools per arm would we need to reliably detect
* an effect of X standard deviations?" Useful to check whether the planned
* 150 schools are sufficient, or to justify the sample size to the PI/funders.

local target_mde_list "0.15 0.20 0.25 0.30"   //SPECIFY - candidate target effect sizes (in SD)

matrix schools_needed = J(16,3,.)
local row = 1
foreach rho of local rho_list {
    foreach mde of local target_mde_list {

        scalar treat_mean = `=baseline_mean' + `mde'*`=sd_outcome'

        power twomeans `=baseline_mean' `=treat_mean', ///
            cluster ///
            m1(`=n_girls_per_school') mratio(`=mratio') ///
            kratio(`=nratio') ///
            sd(`=sd_outcome') rho(`rho') ///
            power(`=power_target') alpha(`=alpha_level') table

        matrix schools_needed[`row',1] = `rho'
        matrix schools_needed[`row',2] = `mde'
        matrix schools_needed[`row',3] = r(K1)    // schools needed per arm (control side)

        local row = `row' + 1
    }
}
matrix colnames schools_needed = ICC Target_MDE_sd Schools_needed_per_arm
di as text _n "Table 2. Number of schools per arm required to detect a given " ///
    "target effect size (30 girls/school, power=`=power_target', alpha=`=alpha_level')"
matrix list schools_needed


********************************************************************************
********************* 4. MDE WITH A BASELINE COVARIATE (ANCOVA) ***************
********************************************************************************

* Adding a baseline (pre-intervention) measure of the same outcome - e.g. the
* girl's baseline chores/study/rest time, or a baseline test score - as a
* control variable reduces residual variance and improves power (this is the
* ANCOVA logic used in "2a/2b" of the original J-PAL file, but adapted to the
* clustered case: the residual SD is obtained from a regression of the
* endline outcome on baseline covariates using pilot/baseline data).
*
* Since no pilot data exist yet, we illustrate the gain from a plausible
* baseline R-squared (share of endline variance explained by baseline
* covariates), which is typical for this type of study (education/time-use
* baseline controls often explain 20% to 40% of endline variance).

local r2_list "0 0.10 0.20 0.30 0.40"   //SPECIFY - plausible baseline R-squared values
                                          // (0 = no covariate adjustment, same as Table 1)

matrix mde_ancova = J(5,3,.)
local row = 1
foreach r2 of local r2_list {

    scalar res_sd = `=sd_outcome' * sqrt(1 - `r2')    // residual SD after netting out covariates

    power twomeans `=baseline_mean', ///
        cluster k1(`=n_schools_per_arm') kratio(`=nratio') ///
        m1(`=n_girls_per_school') mratio(`=mratio') ///
        sd(`=res_sd') rho(`=rho_central') ///
        power(`=power_target') alpha(`=alpha_level') table

    matrix mde_ancova[`row',1] = `r2'
    matrix mde_ancova[`row',2] = r(delta)
    matrix mde_ancova[`row',3] = res_sd

    local row = `row' + 1
}
matrix colnames mde_ancova = Baseline_Rsq MDE_sd_units Residual_SD
di as text _n "Table 3. MDE with ANCOVA-style baseline covariate adjustment " ///
    "(central ICC=`=rho_central', 50 schools/arm, 30 girls/school)"
matrix list mde_ancova

di as error "NOTE: once baseline data are available, replace the R-squared " ///
    "placeholders above with the actual R-squared from " ///
    "'regress <endline_outcome> <baseline_outcome> <other_baseline_controls>', " ///
    "as in section 2 of the original J-PAL template."


********************************************************************************
*************** 5. ADJUSTING FOR ANTICIPATED ATTRITION AT ENDLINE *************
********************************************************************************

* Attrition (girls/households not found at endline, section 11.6 of the
* project guide) effectively shrinks the number of girls surveyed per
* school. We recompute the MDE assuming a plausible attrition rate.

local attrition_list "0.05 0.10 0.15 0.20"   //SPECIFY - plausible attrition rates

matrix mde_attrition = J(4,3,.)
local row = 1
foreach att of local attrition_list {

    scalar m1_eff = `=n_girls_per_school' * (1 - `att')   // effective girls/school retained

    power twomeans `=baseline_mean', ///
        cluster k1(`=n_schools_per_arm') kratio(`=nratio') ///
        m1(`=m1_eff') mratio(`=mratio') ///
        sd(`=sd_outcome') rho(`=rho_central') ///
        power(`=power_target') alpha(`=alpha_level') table

    matrix mde_attrition[`row',1] = `att'
    matrix mde_attrition[`row',2] = m1_eff
    matrix mde_attrition[`row',3] = r(delta)

    local row = `row' + 1
}
matrix colnames mde_attrition = Attrition_rate Effective_girls_per_school MDE_sd_units
di as text _n "Table 4. MDE under different attrition scenarios " ///
    "(central ICC=`=rho_central', 50 schools/arm)"
matrix list mde_attrition


********************************************************************************
**** 6. POWER FOR THE NESTED MOTHER- VS FATHER-TARGETED RANDOMIZATION *********
********************************************************************************

* Inside the treated arms (T1 and T2), schools are additionally randomized
* into "mother-targeted" vs "father-targeted" delivery (section 5.3 of the
* project guide). This comparison has a SMALLER number of clusters than the
* main T-vs-Control comparisons, because it only uses treated schools.
*
* Two useful versions of this comparison:
*   (a) Within a single treated arm (e.g. T1-mother vs T1-father):
*       50 T1 schools split roughly 25 vs 25
*   (b) Pooling both treated arms (T1+T2 mother vs T1+T2 father):
*       100 treated schools split roughly 50 vs 50
* Both assume the mother/father split itself is randomized in balanced blocks.

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
di as error "Mother vs Father WITHIN one treated arm (25 vs 25 schools): " ///
    "MDE = `=mde_parent_within' SD (central ICC=`=rho_central')."

* (b) Pooled across both treated arms (T1+T2: mother vs father)
power twomeans `=baseline_mean', ///
    cluster k1(`=n_schools_per_parent_pooled') kratio(1) ///
    m1(`=n_girls_per_school') mratio(1) ///
    sd(`=sd_outcome') rho(`=rho_central') ///
    power(`=power_target') alpha(`=alpha_level') table
scalar mde_parent_pooled = round(r(delta),0.001)
di as error "Mother vs Father POOLED across treated arms (50 vs 50 schools): " ///
    "MDE = `=mde_parent_pooled' SD (central ICC=`=rho_central')."

di as text _n "NOTE: because the mother/father contrast has fewer clusters than " ///
    "the main T-vs-Control contrasts, it is powered to detect LARGER effects. " ///
    "This should be flagged explicitly to the PI (see project guide, section 16, " ///
    "'points a valider'), since it directly affects how confidently the study " ///
    "can speak to Table in section 5.3 of the guide (mother vs father comparisons)."


********************************************************************************
******* 7. POWER FOR A BINARY OUTCOME (e.g., attendance, pass/fail) ***********
********************************************************************************

* Several indicators in the project's outcome dictionary (Annexe C) are
* binary or close to binary, e.g. "protected_slot" (existence of a protected
* study slot) or school attendance thresholds. For binary outcomes, the
* J-PAL template recommends "power twoproportions" instead of "power
* twomeans" (see preamble note in the original file): the baseline
* proportion IS the mean, and its own variance is a function of that
* proportion, so no separate "sd" input is required.

scalar p_control = 0.30      //SPECIFY - assumed proportion with the outcome in control
                              //          (e.g., 30% of girls have a protected study slot)
local  mde_pp_list "0.10 0.15 0.20"   //SPECIFY - candidate absolute percentage-point effects

matrix mde_binary = J(3,3,.)
local row = 1
foreach d of local mde_pp_list {

    scalar p_treat = p_control + `d'

    * NOTE: here the sample size (k1, m1) is already fixed by the design, so
    * we ask Stata to solve FOR the achieved power - we must NOT also supply
    * power() as an input, otherwise the command is over-determined (this
    * caused a "too many arguments specified with effect-size determination"
    * error). Compare this achieved power to the power_target scalar by eye.
    power twoproportions `=p_control' `=p_treat', ///
        cluster k1(`=n_schools_per_arm') kratio(`=nratio') ///
        m1(`=n_girls_per_school') mratio(`=mratio') ///
        rho(`=rho_central') ///
        alpha(`=alpha_level') table

    matrix mde_binary[`row',1] = `d'
    matrix mde_binary[`row',2] = r(N)
    matrix mde_binary[`row',3] = r(power)

    local row = `row' + 1
}
matrix colnames mde_binary = Assumed_effect_pp Total_N Achieved_power
di as text _n "Table 5. Power to detect assumed percentage-point effects on a " ///
    "binary outcome (baseline proportion=`=p_control', central ICC=`=rho_central')"
matrix list mde_binary


********************************************************************************
********* 8. SENSITIVITY GRAPH: MDE AS A FUNCTION OF ICC AND SAMPLE SIZE ******
********************************************************************************

* This block builds a small dataset from the "power" results across a grid
* of ICC values and number of schools per arm, then plots the MDE curve.
* This is useful to present to the PI/KCDev as a one-page visual summary of
* how robust the planned 150-school sample is to ICC uncertainty (section 16
* of the guide, "points a valider" - sample size is not yet finalized).

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

        power twomeans `=baseline_mean', ///
            cluster k1(`k') kratio(`=nratio') ///
            m1(`=n_girls_per_school') mratio(`=mratio') ///
            sd(`=sd_outcome') rho(`rho') ///
            power(`=power_target') alpha(`=alpha_level')

        clear
        set obs 1
        gen rho       = `rho'
        gen n_schools = `k'
        gen mde       = r(delta)
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

graph export "MDE_sensitivity_CKDev_Benin.png", replace width(1600)   //SPECIFY - export path/name

restore


********************************************************************************
**************************** 9. EXPORT SUMMARY TABLES *************************
********************************************************************************

* Collect the key matrices built above into a single Excel workbook so they
* can be shared directly with the PI and KCDev (section 15 of the guide,
* "livrables attendus").

putexcel set "Power_MDE_CKDev_Benin_summary.xlsx", replace  //SPECIFY - output path/name

putexcel A1 = "Table 1. MDE for main pairwise comparisons (T1 vs C or T2 vs C)"
putexcel A2 = matrix(mde_main), names

putexcel A8 = "Table 2. Schools needed per arm for a target MDE"
putexcel A9 = matrix(schools_needed), names

putexcel A26 = "Table 3. MDE with ANCOVA-style baseline covariate adjustment"
putexcel A27 = matrix(mde_ancova), names

putexcel A34 = "Table 4. MDE under different attrition scenarios"
putexcel A35 = matrix(mde_attrition), names

putexcel A41 = "Table 5. Power for a binary outcome under assumed effects"
putexcel A42 = matrix(mde_binary), names

putexcel A47 = "Headline MDE (central ICC assumption)"
putexcel A48 = "Main comparison (T1 or T2 vs Control)"
putexcel B48 = `=mde_headline'
putexcel A49 = "Mother vs Father, within one treated arm"
putexcel B49 = `=mde_parent_within'
putexcel A50 = "Mother vs Father, pooled across treated arms"
putexcel B50 = `=mde_parent_pooled'

di as text _n "All results exported to Power_MDE_CKDev_Benin_summary.xlsx " ///
    "and MDE_sensitivity_CKDev_Benin.png"

cap log close power_ckdev

********************************************************************************
* END OF FILE
*
* SUMMARY OF WHAT THIS SCRIPT DOES
*  0. Housekeeping (no baseline dataset needed at this design stage)
*  1. Sets the project's actual design parameters (150 schools, 50/arm,
*     30 girls/school, alpha, power) as SPECIFY-able scalars
*  2. Computes the MDE for the two headline treatment contrasts
*     (T1 vs Control, T2 vs Control) across a range of plausible ICC values
*  3. Computes the number of schools per arm needed to detect a set of
*     target effect sizes, to sanity-check the planned 150-school sample
*  4. Shows how much an ANCOVA-style baseline covariate would improve
*     precision (lower MDE) for a range of plausible baseline R-squared
*  5. Shows how anticipated attrition erodes power/increases the MDE
*  6. Powers the SECONDARY, nested mother- vs father-targeted randomization,
*     both within a single treated arm and pooled across both treated arms
*  7. Repeats the exercise for a BINARY outcome (e.g., a protected study
*     slot, attendance threshold) using "power twoproportions, cluster"
*  8. Produces a sensitivity graph of MDE vs number of schools and ICC
*  9. Exports all tables to a single Excel file for the PI/KCDev
********************************************************************************
