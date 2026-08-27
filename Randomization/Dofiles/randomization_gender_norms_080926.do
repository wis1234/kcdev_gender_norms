*======================================================================*
* PROJECT     : Gender Norms RCT - Randomization of Schools
* PURPOSE     : Implements, step by step, the randomization plan
*               "PLAN DE RANDOMISATION GENDER NORMS" :
*                 1. Validation of the (already cleaned) school database
*                 2. Size categorization of schools
*                 3. Construction of blocks (commune x size)
*                 4. Verification and fusion of blocks that are too small
*                 5. Random draw of the 3 treatment arms (by block)
*                 6. Random draw of the targeted parent (treated schools)
*                 7. Balance checks across the 3 arms
*                 8. Final randomization sheet
*
* INPUT       : master_x_gender_norm.xlsx
*               (162 schools - ALREADY CLEANED AND SCOPED upstream:
*               public schools only, Zou and Atlantique, no duplicate
*               id_infra, no missing key admin/enrolment fields. This
*               script does NOT re-clean the data - see Section 1,
*               which VALIDATES these assumptions and stops hard if
*               any of them is violated, rather than silently fixing
*               anything. Any cleaning issue must be fixed upstream,
*               in the merge/cleaning do-file, and the input re-saved.)
*               NOTE: MILIEU in this file is the DEGURBA-based
*               classification (PERIURBAN / RURAL / URBAN_SEMIDENSE /
*               URBAN_CORE), NOT the original administrative status.
*               The administrative status is preserved separately as
*               MILIEU_ADMIN (see Step 8).
*
* OUTPUTS     : log_fusion_strates.xlsx
*               randomization_final.xlsx        (locked randomization sheet)
*               randomization_final_locked_<timestamp>.dta
*               randomization_manifest_<timestamp>.txt   (audit trail)
*               randomization_log_<timestamp>.log
*
* AUTHOR      : [name]
* DATE WRITTEN: [date]
* STATA VERSION USED: [record version, e.g. 17.0 / 18.0]
*
* IMPORTANT - REPRODUCIBILITY
* This script must be version-controlled (git or equivalent). Any edit
* made AFTER the official draw (Section 5) invalidates the
* randomization and requires a new, re-approved seed and a new run.
*
* INTERNATIONAL-STANDARD PRACTICES FOLLOWED IN THIS SCRIPT
* (in line with J-PAL / IPA / AEA RCT Registry pre-analysis-plan norms):
*   - Seeds fixed and recorded BEFORE the draw (Section 0), never
*     chosen or changed post hoc.
*   - RNG engine explicitly declared (not just the numeric seed), so
*     the draw is reproducible even across Stata versions.
*   - Stratified/blocked assignment (commune x size), with an explicit
*     minimum block size so no stratum is under-powered.
*   - Immediate, in-script reproducibility check (re-draw with the
*     same seed, assert identical result) - Sections 5 and 6.
*   - Formal balance checks on stratification variables AND on
*     substantive covariates, with block fixed effects - Section 7.
*   - Locked, timestamped, checksummed output + written audit manifest
*     - Section 8 - so the final allocation cannot be silently altered.
*======================================================================*

version 17
clear all
set more off
set linesize 120

*======================================================================*
* 0. GLOBAL SETTINGS - EDIT PATHS AND SEEDS BEFORE RUNNING
*======================================================================*

* --Workingdirectory---------------------------------------------------

cd "C:\RONALDO\CKDEV\GENDER NORMS\Randomization"

* --- Paths -------------------------------------------------------------
global datadir   "Datasets"
global outputdir "Outputs"

* master_x_gender_norm.xlsx is produced by the merge do-file and is
* written to Outputs\Data, NOT Datasets - point directly at that
* location (this was the cause of the "file not found" / r(601) error).
* If you'd rather keep a single canonical "Datasets" folder, copy the
* file there instead and switch $infile back to "$datadir/...".
global mergeoutdir "$outputdir/Data"
global infile      "$mergeoutdir/master_x_gender_norm.xlsx"

capture confirm file "$infile"
if _rc {
    di as error "Input file not found: $infile"
    di as error "Run merge_master_gender_norm.do first (it writes to Outputs\Data), or update \$infile above to wherever you saved master_x_gender_norm.xlsx."
    exit 601
}

capture mkdir "$outputdir"

local timestamp : di %tcCCYY-NN-DD_HH-MM-SS clock("$S_DATE $S_TIME", "DMYhms")
local timestamp = subinstr("`timestamp'", ":", "", .)
local timestamp = subinstr("`timestamp'", " ", "_", .)

capture log close
log using "$outputdir/randomization_log_`timestamp'.log", replace text

* --- RNG engine, declared explicitly ---------------------------------
* Stata's default RNG changed at v14 (KISS32 -> MT64/Mersenne Twister).
* Declaring it explicitly - rather than relying on whatever a given
* Stata installation defaults to - is what makes the draw reproducible
* on a DIFFERENT machine or Stata version, not just on this one.
set rng mt64

* --- Master seeds --------------------------------------------------
* Seeds are FIXED and RECORDED here BEFORE execution, as required by
* Step 5 of the plan. Do not change these values after the official
* draw. Two independent seeds are used so that a change to the parent
* sub-randomization (Step 6) can never alter the arm assignment
* (Step 5), and vice versa.
global SEED_ARMS   20260731     // seed for the 3-arm draw   (Step 5)
global SEED_PARENT 20260801     // seed for the parent draw  (Step 6)

* --- Design parameters --------------------------------------------
global MIN_BLOCK_SIZE 6         // minimum schools required per final block
global N_ARMS         3         // Control / Salience / Salience+Implementation

di as result "======================================================="
di as result "RNG engine  : `c(rngstate)'"
di as result "Seeds recorded for this run:"
di as result "  SEED_ARMS   = $SEED_ARMS"
di as result "  SEED_PARENT = $SEED_PARENT"
di as result "======================================================="

*======================================================================*
* 1. VALIDATION OF THE (ALREADY CLEANED) SCHOOL DATABASE
*======================================================================*
* This section does NOT clean the data. It only VALIDATES, with hard
* stops (assert / exit), the assumptions the rest of the script relies
* on. If any check fails, the script stops - fix the issue upstream
* (in the cleaning/merge do-file) and re-export master_x_gender_norm.xlsx.
* Silently dropping or fixing observations here, right before a
* pre-registered draw, is exactly the kind of researcher-discretion
* step a randomization script should never contain.

import excel using "$infile", firstrow clear case(upper)

* --- 1a. Required identifier: must already exist and be unique -------
* This is a SCHEMA mapping, not a data-cleaning step: master_x_gender_
* norm.xlsx carries the school identifier as SCHOOL_ID (built from
* name+commune in the merge do-file), not id_infra. id_infra is derived
* from it here so the rest of the script (which keys off id_infra
* throughout) works unchanged. If SCHOOL_ID itself is missing or not
* unique, that IS a genuine data problem, so it still stops the script.
capture confirm variable id_infra
if _rc {
    capture confirm variable SCHOOL_ID
    if _rc {
        di as error "Neither id_infra nor SCHOOL_ID found in $infile."
        di as error "The input is expected to carry one of these identifiers."
        exit 111
    }
    quietly count if missing(SCHOOL_ID)
    if r(N) > 0 {
        di as error "`r(N)' school(s) with missing SCHOOL_ID - input is not clean."
        exit 459
    }
    quietly duplicates report SCHOOL_ID
    if r(unique_value) < r(N) {
        di as error "SCHOOL_ID is not unique - input is not clean, fix upstream."
        exit 459
    }
    egen long id_infra = group(SCHOOL_ID)
    di as result "id_infra derived from SCHOOL_ID (1:1 mapping; SCHOOL_ID kept for traceability)."
}
isid id_infra

* --- 1b. Required fields: must have zero missing ---------------------
* If the file is genuinely clean and correctly scoped, none of this
* should fail - these are assertions, not filters.
foreach v of varlist DEPARTEMENT COMMUNE NOMETABLISSEMENT {
    quietly count if missing(`v')
    if r(N) > 0 {
        di as error "`r(N)' missing value(s) found in `v' - input is not clean."
        exit 459
    }
}
egen byte miss_grade = rmiss(NBM6EME NBF6EME NBM5EME NBF5EME)
quietly count if miss_grade > 0
if r(N) > 0 {
    di as error "`r(N)' school(s) missing 6eme/5eme enrolment counts - input is not clean."
    exit 459
}
drop miss_grade

* --- 1c. Required scope: must already be public schools, Zou/Atlantique
quietly count if !inlist(upper(strtrim(STATUT)), "PUBLIC", "PUBLIQUE")
if r(N) > 0 {
    di as error "`r(N)' non-public school(s) found - input is not correctly scoped."
    exit 459
}
quietly count if !inlist(upper(strtrim(DEPARTEMENT)), "ZOU", "ATLANTIQUE")
if r(N) > 0 {
    di as error "`r(N)' school(s) outside Zou/Atlantique found - input is not correctly scoped."
    exit 459
}

* --- 1d. Light string normalization (NOT a cleaning step) -------------
* Purely technical: guarantees identical spelling/case/whitespace is
* grouped together in COMMUNE etc. below. Does not drop or alter any
* observation.
foreach v of varlist DEPARTEMENT COMMUNE ARRONDISSEMENT QUARTIERVILLAGE ///
                      NOMETABLISSEMENT STATUT MILIEU REGIME {
    capture confirm string variable `v'
    if !_rc {
        replace `v' = strtrim(stritrim(upper(`v')))
    }
}
capture confirm string variable MILIEU_ADMIN
if !_rc {
    replace MILIEU_ADMIN = strtrim(stritrim(upper(MILIEU_ADMIN)))
}

di as result "Input validated: `=_N' schools, all checks passed (unique id, " ///
    "no missing key fields, public, Zou + Atlantique)."

save "$outputdir/ecoles_valid_step1.dta", replace


*======================================================================*
* 2. SIZE CATEGORIZATION OF SCHOOLS
*======================================================================*
* Basis: percentile of TOTAL ENROLMENT IN THE TARGETED GRADES (6eme and
* 5eme), computed WITHIN EACH COMMUNE - not the school's overall
* enrolment - to stay centred on the population of interest.
* Default cut: 3 categories (small / medium / large). If a commune x
* size cell has fewer than $MIN_BLOCK_SIZE schools, that commune's
* categorization is simplified to 2 groups split at the median
* (below / above).


gen long target_enrol = NBM6EME + NBF6EME + NBM5EME + NBF5EME
label var target_enrol "Total enrolment, targeted grades (6eme + 5eme)"

* --- 2a. Default: commune-specific tertiles --------------------------
bysort COMMUNE: gen n_comm = _N

* xtile cannot be combined with by: (hard Stata restriction, r(190)), and
* egen's cut(..., group()) is NOT byable either (r(190): "cut() may not
* be combined with by") - unlike egen functions such as mean()/rank(),
* cut() has no by-prefix support at all. Instead, replicate the
* "as-equal-as-possible groups per commune" logic manually via within-
* commune rank: sort by target_enrol (id_infra as tiebreak, for a
* deterministic and reproducible split), rank 1..n_comm within commune,
* then cut that rank into 3 (or 2) equal-as-possible groups.
sort COMMUNE target_enrol id_infra
bysort COMMUNE (target_enrol id_infra): gen long rank_enrol = _n
gen byte size_cat3 = ceil(rank_enrol * 3 / n_comm)
replace size_cat3 = 3 if size_cat3 > 3
label define size_cat3_lbl 1 "Small" 2 "Medium" 3 "Large", replace
label values size_cat3 size_cat3_lbl

egen bloc3_id = group(COMMUNE size_cat3)
bysort bloc3_id: gen bloc3_n = _N
bysort COMMUNE: egen min_bloc3_n = min(bloc3_n)

* --- 2b. Fallback: commune-specific median split (2 categories) ------
* Applied only to communes where the 3-category scheme yields at least
* one commune x size cell below $MIN_BLOCK_SIZE. Reuses rank_enrol from
* 2a (same ordering/tiebreak), so no separate egen call is needed.
gen byte fallback_2cat = (min_bloc3_n < $MIN_BLOCK_SIZE)
gen byte size_cat2 = ceil(rank_enrol * 2 / n_comm)
replace size_cat2 = 2 if size_cat2 > 2
label define size_cat2_lbl 1 "Below median" 2 "Above median", replace
label values size_cat2 size_cat2_lbl

* --- 2c. Final size category actually used ---------------------------
gen str16 size_label = ""
replace size_label = "Small"        if fallback_2cat==0 & size_cat3==1
replace size_label = "Medium"       if fallback_2cat==0 & size_cat3==2
replace size_label = "Large"        if fallback_2cat==0 & size_cat3==3
replace size_label = "BelowMedian"  if fallback_2cat==1 & size_cat2==1
replace size_label = "AboveMedian"  if fallback_2cat==1 & size_cat2==2
label var size_label "Final size category used for blocking"

tab COMMUNE size_label, missing
tab fallback_2cat

drop bloc3_id bloc3_n min_bloc3_n

*======================================================================*
* 3-4. BLOCK CONSTRUCTION AND FUSION OF UNDERSIZED BLOCKS
*======================================================================*
* A block = one commune x size-category combination. Each final block
* must contain AT LEAST $MIN_BLOCK_SIZE schools: not only to populate
* the 3 arms, but also - in treated blocks - to draw the targeted
* parent (mother / father) without leaving an empty cell (i.e. enough
* schools to cross 3 arms x 2 parental targets without gaps).

egen bloc_id0 = group(COMMUNE size_label)
bysort bloc_id0: gen bloc0_n = _N
gen byte bloc_small = bloc0_n < $MIN_BLOCK_SIZE

* --- 4a. First fusion pass: merge size strata WITHIN THE SAME COMMUNE
* If any size cell within a commune is still too small, collapse ALL
* size categories of that commune into a single "All sizes" stratum.
gen str24 size_label_f1 = size_label
bysort COMMUNE: egen byte any_small_in_comm = max(bloc_small)
replace size_label_f1 = "All sizes" if any_small_in_comm==1

egen bloc_id1 = group(COMMUNE size_label_f1)
bysort bloc_id1: gen bloc1_n = _N
gen byte bloc_still_small = bloc1_n < $MIN_BLOCK_SIZE

* Log every commune that required a within-commune fusion
preserve
    keep if any_small_in_comm==1
    quietly count
    if r(N) > 0 {
        duplicates drop COMMUNE size_label bloc0_n, force
        keep COMMUNE size_label bloc0_n
        gen str30 fusion_type = "within-commune (all sizes merged)"
        gen str20 fusion_date = "$S_DATE"
        export excel using "$outputdir/log_fusion_strates.xlsx", ///
            firstrow(variables) replace sheet("within_commune")
        di as result "Within-commune fusion log written (log_fusion_strates.xlsx)."
    }
    else {
        di as result "No within-commune fusion needed - log_fusion_strates.xlsx (within_commune) not created."
    }
restore

* --- 4b. Second fusion pass: merge with a NEIGHBOURING COMMUNE -------
* Communes still below $MIN_BLOCK_SIZE after 4a are merged with an
* adjacent commune in the SAME department, as specified in the plan.
* Administrative adjacency is NOT contained in the school database and
* must be supplied from a verified source (official commune boundary
* map / INSAE administrative gazetteer) BEFORE this section is run.
* Build "neighbor_map.dta" with variables: COMMUNE, neighbor_COMMUNE,
* DEPARTEMENT (one row per adjacent pair).

count if bloc_still_small==1
local n_need_cross = r(N)

if `n_need_cross' > 0 {
    di as error "`n_need_cross' school(s) remain in blocks below " ///
        "$MIN_BLOCK_SIZE after the within-commune fusion (4a)."

    capture confirm file "$datadir/neighbor_map.dta"
    if _rc {
        di as error "neighbor_map.dta not found. Build the verified " ///
            "commune-adjacency crosswalk before proceeding, then re-run " ///
            "from Section 4b. Stopping here to avoid an unverified " ///
            "geographic assumption."

        preserve
            keep if bloc_still_small==1
            duplicates drop COMMUNE DEPARTEMENT, force
            keep COMMUNE DEPARTEMENT
            export excel using "$outputdir/communes_needing_cross_fusion.xlsx", ///
                firstrow(variables) replace
        restore
        exit 198
    }

    * --- Apply the verified adjacency crosswalk ----------------------
    preserve
        keep if bloc_still_small==1
        keep id_infra COMMUNE DEPARTEMENT
        merge m:1 COMMUNE using "$datadir/neighbor_map.dta", ///
            keep(match master) keepusing(neighbor_COMMUNE) nogen
        * Choose, for each undersized commune, the single neighbour
        * that yields a block >= $MIN_BLOCK_SIZE once merged. This
        * pairing decision must be reviewed by the PI/statistician
        * and hard-coded below (illustrative placeholder pairs):
        * replace neighbor_COMMUNE = "ADJACENT_COMMUNE_NAME" if COMMUNE=="SMALL_COMMUNE_NAME"
        save "$outputdir/cross_fusion_assignment.dta", replace
    restore

    merge m:1 COMMUNE using "$outputdir/cross_fusion_assignment.dta", ///
        keepusing(neighbor_COMMUNE) nogen
    gen str40 commune_bloc = COMMUNE
    replace commune_bloc = COMMUNE + " + " + neighbor_COMMUNE ///
        if bloc_still_small==1 & !missing(neighbor_COMMUNE)

    preserve
        keep if bloc_still_small==1
        duplicates drop COMMUNE neighbor_COMMUNE, force
        keep COMMUNE neighbor_COMMUNE
        gen str30 fusion_type = "cross-commune (same department)"
        gen str20 fusion_date = "$S_DATE"
        export excel using "$outputdir/log_fusion_strates.xlsx", ///
            firstrow(variables) sheetreplace sheet("cross_commune")
    restore
}
else {
    gen str40 commune_bloc = COMMUNE
    di as result "No cross-commune fusion required: all blocks reach " ///
        "$MIN_BLOCK_SIZE after the within-commune pass."
}

* --- 4c. Final, LOCKED block variable --------------------------------
egen bloc = group(commune_bloc size_label_f1), label
bysort bloc: gen bloc_n = _N
assert bloc_n >= $MIN_BLOCK_SIZE

label var bloc "Randomization block (commune[+neighbour] x size), FINAL"
tab bloc, missing
di as result "Blocks constituted: `=r(r)' blocks, all with >= $MIN_BLOCK_SIZE schools."

* Blocs figes -> stratified base locked, single input file
save "$outputdir/ecoles_blocs_locked.dta", replace

*======================================================================*
* 5. RANDOM DRAW OF THE 3 TREATMENT ARMS (BY BLOCK)
*======================================================================*
* Stratified draw by block (commune x size, possibly fused): each
* school is assigned to Control, Salience, or Salience + Implementation,
* targeting a balance close to 1/3-1/3-1/3 per block.
* Seed AND rng engine fixed and recorded BEFORE execution (Section 0);
* script version-controlled; draw re-executed below with the same seed
* to confirm reproducibility.

isid id_infra

set seed $SEED_ARMS
gen double rand_arm = runiform()

sort bloc rand_arm
by bloc: gen long rank_arm = _n
by bloc: gen byte group3 = mod(rank_arm - 1, $N_ARMS) + 1

label define arm_lbl 1 "Control" 2 "Salience" 3 "Salience + Implementation", replace
label values group3 arm_lbl
label var group3 "Randomized treatment arm"

di as result "Arm allocation by block:"
tab bloc group3

* Overall allocation should be close to 1/3-1/3-1/3
tab group3

* --- 5a. Reproducibility check ----------------------------------------
* Re-draws with the SAME recorded seed and confirms an identical
* allocation. Run this block again in a fresh session / on another
* machine before considering the draw final.
preserve
    set seed $SEED_ARMS
    gen double rand_arm_chk = runiform()
    sort bloc rand_arm_chk
    by bloc: gen long rank_chk = _n
    by bloc: gen byte group3_chk = mod(rank_chk - 1, $N_ARMS) + 1
    assert group3 == group3_chk
    di as result "REPRODUCIBILITY CONFIRMED with seed $SEED_ARMS (rng: `c(rngstate)')."
restore

* --- 5b. Within-block balance check -----------------------------------
* By construction, the rank+modulo method should give each arm a count
* that differs by at most 1 school within any given block. This is
* asserted explicitly rather than assumed.
preserve
    contract bloc group3, freq(narm)
    bysort bloc: egen byte narm_max = max(narm)
    bysort bloc: egen byte narm_min = min(narm)
    assert narm_max - narm_min <= 1
    di as result "Arm counts balanced to within +/-1 school in every block."
restore

*======================================================================*
* 6. RANDOM DRAW OF THE TARGETED PARENT (TREATED SCHOOLS ONLY)
*======================================================================*
* In schools assigned to Salience or Salience + Implementation only,
* a binary mother / father draw is made within the same blocks,
* targeting a balance close to 50/50 per block.

gen byte treated = inlist(group3, 2, 3)
label var treated "1 = school in a treated arm (Salience or Salience+Impl.)"

set seed $SEED_PARENT
gen double rand_parent = runiform() if treated==1

sort bloc rand_parent
by bloc: gen long rank_parent = _n if treated==1
by bloc: gen byte parent_group = mod(rank_parent - 1, 2) + 1 if treated==1

label define parent_lbl 1 "Mother" 2 "Father", replace
label values parent_group parent_lbl
label var parent_group "Targeted parent (treated schools only)"

di as result "Targeted-parent allocation by block (treated schools only):"
tab bloc parent_group if treated==1
tab parent_group if treated==1

* --- 6a. Reproducibility check ----------------------------------------
preserve
    set seed $SEED_PARENT
    gen double rand_parent_chk = runiform() if treated==1
    sort bloc rand_parent_chk
    by bloc: gen long rank_parent_chk = _n if treated==1
    by bloc: gen byte parent_group_chk = mod(rank_parent_chk - 1, 2) + 1 if treated==1
    assert parent_group == parent_group_chk if treated==1
    di as result "REPRODUCIBILITY CONFIRMED with seed $SEED_PARENT (rng: `c(rngstate)')."
restore

*======================================================================*
* 7. BALANCE CHECKS ACROSS THE 3 ARMS
*======================================================================*
* By construction, blocks are commune x size strata, so the arms are
* exactly balanced on these two stratification variables within each
* block. The checks below (a) confirm this formally and (b) test
* balance on available pre-treatment covariates, controlling for block
* fixed effects. Any imbalance on a STRATIFICATION variable signals an
* implementation error and the draw (Section 5) must be corrected and
* re-run before proceeding to Step 8.

* --- 7a. Stratification variables: must show NO imbalance -----------
tab COMMUNE group3, chi2
tab size_label_f1 group3, chi2

* --- 7b. Substantive pre-treatment covariates, with block FE --------
local balance_vars target_enrol NBM6EME NBF6EME NBM5EME NBF5EME ///
    SALLESCLASSESTOT EXISTENCEEAU EXISTENCEELECT EXISTENCELATRINES ///
    EXISTENCEINFRASTSPORT

foreach v of local balance_vars {
    capture confirm numeric variable `v'
    if !_rc {
        di as text _newline "--- Balance check: `v' (arms, block FE) ---"
        quietly regress `v' i.group3 i.bloc, vce(robust)
        testparm i.group3
    }
}

* --- 7c. Flag: if any test above rejects balance on a stratification
* variable, STOP and re-run Step 5 with a corrected script (NOT a new
* seed chosen post hoc to "fix" the result - that would defeat the
* purpose of pre-registration).
di as result "Review the tests above. Proceed to Step 8 ONLY if no " ///
    "imbalance is found on COMMUNE or size_label_f1, and covariate " ///
    "tests are consistent with chance-level differences."

*======================================================================*
* 8. FINAL RANDOMIZATION SHEET
*======================================================================*
* One row per school: identifier, commune, size category, block,
* assigned group (Control / Salience / Salience + Implementation), and
* targeted parent (mother / father, if treated school). Locked and
* archived file, with a checksum and audit manifest so the output
* cannot be silently altered after the fact.
*
* MILIEU here is the DEGURBA-based classification (from the merge
* step); MILIEU_ADMIN is the original administrative status. Both are
* kept in the final sheet so the distinction stays visible downstream.

gen str30 group3_lbl  = ""
replace group3_lbl = "Control"                    if group3==1
replace group3_lbl = "Salience"                    if group3==2
replace group3_lbl = "Salience + Implementation"   if group3==3

gen str10 parent_lbl2 = ""
replace parent_lbl2 = "Mother" if parent_group==1
replace parent_lbl2 = "Father" if parent_group==2
replace parent_lbl2 = "N/A"    if treated==0

quietly count
local n_schools = r(N)
quietly tab bloc
local n_blocks = r(r)

preserve
    capture confirm variable MILIEU_ADMIN
    local milieu_admin_var = cond(_rc==0, "MILIEU_ADMIN", "")

    keep id_infra DEPARTEMENT COMMUNE ARRONDISSEMENT NOMETABLISSEMENT ///
         MILIEU `milieu_admin_var' size_label_f1 bloc group3_lbl parent_lbl2 target_enrol

    rename size_label_f1 size_category
    rename group3_lbl     assigned_group
    rename parent_lbl2    targeted_parent

    order id_infra DEPARTEMENT COMMUNE ARRONDISSEMENT NOMETABLISSEMENT ///
          MILIEU `milieu_admin_var' size_category bloc assigned_group ///
          targeted_parent target_enrol

    sort bloc id_infra

    export excel using "$outputdir/randomization_final.xlsx", ///
        firstrow(variables) replace sheet("randomization")

    di as result "Final randomization sheet written: randomization_final.xlsx"
restore

* Archival, timestamped, locked copy (full working dataset)
save "$outputdir/randomization_final_locked_`timestamp'.dta", replace

* --- 8a. Checksum + audit manifest ------------------------------------
* datasignature computes a checksum of the dataset currently in memory;
* stored alongside the seeds/timestamp, it lets anyone later verify the
* locked .dta was never modified after this run.
datasignature
local sig = r(datasignature)

file open manifest using "$outputdir/randomization_manifest_`timestamp'.txt", write replace
file write manifest "RANDOMIZATION MANIFEST - Gender Norms RCT" _n
file write manifest "===========================================" _n
file write manifest "Date / time of draw    : $S_DATE  $S_TIME" _n
file write manifest "Stata version          : `c(stata_version)'" _n
file write manifest "RNG engine             : `c(rngstate)'" _n
file write manifest "SEED_ARMS               : $SEED_ARMS" _n
file write manifest "SEED_PARENT              : $SEED_PARENT" _n
file write manifest "N schools randomized    : `n_schools'" _n
file write manifest "N blocks                : `n_blocks'" _n
file write manifest "Minimum block size       : $MIN_BLOCK_SIZE" _n
file write manifest "Locked dataset checksum : `sig'" _n
file write manifest "Locked dataset file     : randomization_final_locked_`timestamp'.dta" _n
file write manifest "Final sheet             : randomization_final.xlsx" _n
file write manifest "Do-file (this script)   : commit this exact version to git alongside these outputs." _n
file close manifest

di as result "Audit manifest written: randomization_manifest_`timestamp'.txt"
di as result "Dataset checksum: `sig'"

*======================================================================*
* MANAGING SCHOOL REPLACEMENTS BETWEEN DRAW AND FIELD LAUNCH
*======================================================================*
* If a sampled school becomes unavailable before fieldwork starts:
*   1. Do NOT re-randomize. Draw a replacement from the SAME block
*      (same commune x size stratum, same arm) among reserve schools
*      not already in the study sample, if any exist in the original
*      sampling frame.
*   2. If no reserve school exists in that block, escalate to the PI:
*      (a) accept and document the resulting block imbalance, or
*      (b) apply the same block-fusion logic as Step 4 to that case.
*   3. Log every replacement (id_infra removed, id_infra replacing it,
*      reason, date, decision-maker) in "log_remplacements.xlsx"
*      (template columns: id_infra_out, id_infra_in, bloc, group3,
*      reason, decision_date, decided_by).

di as result "======================================================="
di as result "Randomization complete. Review all logs before field launch:"
di as result "  - log_fusion_strates.xlsx"
di as result "  - randomization_final.xlsx"
di as result "  - randomization_manifest_`timestamp'.txt"
di as result "======================================================="

log close
