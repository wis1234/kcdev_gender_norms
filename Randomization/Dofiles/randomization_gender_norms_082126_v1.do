*======================================================================*
* PROJECT     : Gender Norms RCT - Randomization of Schools
* PURPOSE     : Implements, step by step, the randomization plan
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

* Commune adjacency / centroid-distance crosswalk - place this file in
* $datadir. Expected columns: Commune_Principale, Commune_Limitrophe,
* Distance_Centroides_KM (one row per ordered adjacent pair).
global neighbor_csv "$datadir/communes_limitrophes_distance_centroides.csv"

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
global SEED_BLOCKS 20260730     // seed used only for block construction

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
* grouped together in COMMUNE etc. below (and matches the same
* normalization applied to the commune-adjacency crosswalk in 4b).
* Does not drop or alter any observation.
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
* 2. SIZE CATEGORIZATION OF SCHOOLS (Small / Large, vs commune MEDIAN)
*======================================================================*
* Basis: TOTAL ENROLMENT IN THE TARGETED GRADES (6eme and 5eme),
* compared to the MEDIAN of that same variable WITHIN EACH COMMUNE -
* not the school's overall enrolment, and not the commune MEAN.
*
* Why the median rather than the mean: school size is often skewed -
* a handful of very large schools can pull the mean far above what a
* "typical" school in the commune looks like, which would misclassify
* most schools as "small" relative to a few outliers. The median is
* robust to that and, by construction, splits each commune close to
* its actual centre.
*
* Rule (applied independently within each commune):
*   target_enrol <= commune median  -> "Small"
*   target_enrol >  commune median  -> "Large"
* A commune with only one school, or where every school has identical
* enrolment, will have no "Large" schools - this is expected and is
* handled by the block-fusion logic in Section 4.

gen long target_enrol = NBM6EME + NBF6EME + NBM5EME + NBF5EME
label var target_enrol "Total enrolment, targeted grades (6eme + 5eme)"

bysort COMMUNE: gen n_comm = _N
label var n_comm "Number of sampled schools in the commune"

* --- 2a. Commune-specific median of target_enrol ----------------------
bysort COMMUNE: egen double med_enrol = median(target_enrol)
label var med_enrol "Median target_enrol within the commune"

* --- 2b. Small / Large classification vs that median ------------------
gen str16 size_label = cond(target_enrol <= med_enrol, "Small", "Large")
label var size_label "Size category: below-or-equal (Small) vs above (Large) the commune median"

tab COMMUNE size_label, missing

* Communes left with a single size category (all "Small", no "Large")
* are exactly the ones that will need block fusion in Section 4 - flag
* them here for visibility before block construction.
bysort COMMUNE: egen byte has_small = max(size_label=="Small")
bysort COMMUNE: egen byte has_large = max(size_label=="Large")
gen byte n_size_cat = has_small + has_large
drop has_small has_large
quietly count if n_size_cat == 1
if r(N) > 0 {
    di as result "`r(N)' school(s) are in a commune with only ONE size " ///
        "category (all schools tied at/around the median) - these will " ///
        "be picked up by the block-fusion logic in Section 4."
}
drop n_size_cat

*======================================================================*
* 3-4. BLOCK CONSTRUCTION AND FUSION OF UNDERSIZED BLOCKS
*======================================================================*
* A block = one commune x size-category (Small/Large) combination.
* Each final block must contain AT LEAST $MIN_BLOCK_SIZE schools: not
* only to populate the 3 arms, but also - in treated blocks - to draw
* the targeted parent (mother / father) without leaving an empty cell
* (i.e. enough schools to cross 3 arms x 2 parental targets without
* gaps).

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

* --- 4b. Second fusion pass: merge with the NEAREST AVAILABLE
*         NEIGHBOURING COMMUNE (automated)
*======================================================================*
* Communes still below $MIN_BLOCK_SIZE after 4a are merged with an
* adjacent commune in the SAME department. Adjacency and centroid
* distance come from the crosswalk supplied in $neighbor_csv
* (communes_limitrophes_distance_centroides.csv: Commune_Principale,
* Commune_Limitrophe, Distance_Centroides_KM).
*
* Selection rule: for each undersized commune, walk its neighbours
* from NEAREST to FARTHEST (by centroid distance) and pick the FIRST
* one that is "available", meaning:
*   (i)  it has sampled schools in the current data (there is no point
*        merging into a commune with zero schools), AND
*   (ii) it is not ITSELF flagged as still-small (bloc_still_small==1),
*        so two undersized strata are never silently chained together
*        without review.
* If no neighbour satisfies both conditions, the commune is left
* unresolved and flagged for manual PI review, exactly as before.

count if bloc_still_small==1
local n_need_cross = r(N)

if `n_need_cross' > 0 {
    di as error "`n_need_cross' school(s) remain in blocks below " ///
        "$MIN_BLOCK_SIZE after the within-commune fusion (4a). " ///
        "Attempting automated nearest-available cross-commune fusion."

    capture confirm file "$neighbor_csv"
    if _rc {
        di as error "Commune adjacency file not found: $neighbor_csv"
        di as error "Place communes_limitrophes_distance_centroides.csv in $datadir, then re-run from Section 4b."

        preserve
            keep if bloc_still_small==1
            duplicates drop COMMUNE DEPARTEMENT, force
            keep COMMUNE DEPARTEMENT
            export excel using "$outputdir/communes_needing_cross_fusion.xlsx", ///
                firstrow(variables) replace
        restore
        exit 198
    }

    * --- Set of communes actually available in the sample (i.e. have
    *     at least one sampled school) - possible fusion partners.
    levelsof COMMUNE, local(available_communes) clean

    * --- Set of communes still needing a partner (candidates are
    *     excluded from matching each other, see rule (ii) above).
    levelsof COMMUNE if bloc_still_small==1, local(small_communes) clean

    * --- Load the adjacency/distance crosswalk into its own frame,
    *     nearest-first within each Commune_Principale, normalized the
    *     same way as COMMUNE in the main data (upper/trim).
    capture frame drop nbr
    frame create nbr
    frame nbr: import delimited using "$neighbor_csv", clear varnames(1) case(preserve)
    frame nbr: rename Commune_Principale COMMUNE
    frame nbr: rename Commune_Limitrophe neighbor_COMMUNE
    frame nbr: rename Distance_Centroides_KM dist_km
    frame nbr: replace COMMUNE = strtrim(stritrim(upper(COMMUNE)))
    frame nbr: replace neighbor_COMMUNE = strtrim(stritrim(upper(neighbor_COMMUNE)))
    frame nbr: sort COMMUNE dist_km

    * --- Frame to record the chosen nearest-available partner (if any)
    *     for each undersized commune.
    capture frame drop nbr_assign
    frame create nbr_assign
    frame nbr_assign: set obs 0
    frame nbr_assign: gen str40  COMMUNE            = ""
    frame nbr_assign: gen str40  neighbor_COMMUNE   = ""
    frame nbr_assign: gen double neighbor_dist_km   = .

    foreach comm of local small_communes {
        local match     ""
        local match_dist .

        capture frame drop nbr_this
        frame copy nbr nbr_this
        frame nbr_this: keep if COMMUNE == "`comm'"
        frame nbr_this: quietly count
        local nrow = r(N)

        if `nrow' > 0 {
            forvalues r = 1/`nrow' {
                frame nbr_this: local cand      = neighbor_COMMUNE[`r']
                frame nbr_this: local cand_dist = dist_km[`r']

                local is_available : list cand in available_communes
                local is_small_too : list cand in small_communes

                if `is_available' & !`is_small_too' & "`match'" == "" {
                    local match      "`cand'"
                    local match_dist = `cand_dist'
                }
            }
        }
        frame drop nbr_this

        frame nbr_assign {
            local newobs = _N + 1
            quietly set obs `newobs'
            quietly replace COMMUNE          = "`comm'"  in `newobs'
            quietly replace neighbor_COMMUNE = "`match'" in `newobs'
            quietly replace neighbor_dist_km = `match_dist' in `newobs'
        }

        if "`match'" != "" {
            di as result "  `comm' -> nearest available neighbour: `match' (`=string(`match_dist',"%9.2f")' km)"
        }
        else {
            di as error "  `comm' -> NO available neighbour found (all neighbours missing from the " ///
                "sample or themselves undersized) - flagged for manual review."
        }
    }
    frame drop nbr

    * --- Bring the assignment back into the main dataset -------------
    frlink m:1 COMMUNE, frame(nbr_assign)
    frget neighbor_COMMUNE neighbor_dist_km, from(nbr_assign)
    drop nbr_assign

    gen str40 commune_bloc = COMMUNE
    replace commune_bloc = COMMUNE + " + " + neighbor_COMMUNE ///
        if bloc_still_small==1 & !missing(neighbor_COMMUNE)
		
		* --- Propagate the merged label to the MATCHED NEIGHBOUR's own
*     schools too, and force both sides into "All sizes", so they
*     are pooled into one final block instead of two.
levelsof COMMUNE if bloc_still_small==1 & !missing(neighbor_COMMUNE), local(fused_list) clean
foreach comm of local fused_list {
    quietly levelsof neighbor_COMMUNE if COMMUNE=="`comm'", local(nbr_match) clean
    local nbr_match : word 1 of `nbr_match'
    local merged_label = "`comm'" + " + " + "`nbr_match'"

    replace commune_bloc  = "`merged_label'" if COMMUNE=="`nbr_match'"
    replace size_label_f1 = "All sizes"      if COMMUNE=="`nbr_match'" | COMMUNE=="`comm'"
}
		
		

    * --- Log every automated cross-commune fusion ---------------------
    preserve
        keep if bloc_still_small==1 & !missing(neighbor_COMMUNE)
        quietly count
        if r(N) > 0 {
            duplicates drop COMMUNE neighbor_COMMUNE neighbor_dist_km, force
            keep COMMUNE neighbor_COMMUNE neighbor_dist_km
            rename neighbor_dist_km distance_km
            gen str40 fusion_type = "cross-commune (nearest available neighbour, automated)"
            gen str20 fusion_date = "$S_DATE"
            export excel using "$outputdir/log_fusion_strates.xlsx", ///
                firstrow(variables) sheetreplace sheet("cross_commune")
            di as result "Cross-commune fusion log written (log_fusion_strates.xlsx, sheet cross_commune)."
        }
    restore

    * --- Communes that still could not be resolved automatically -----
    preserve
        keep if bloc_still_small==1 & missing(neighbor_COMMUNE)
        quietly count
        if r(N) > 0 {
            di as error "`r(N)' school(s) remain in communes with NO available " ///
                "cross-commune partner. Manual PI review required before Section 5."
            duplicates drop COMMUNE DEPARTEMENT, force
            keep COMMUNE DEPARTEMENT
            export excel using "$outputdir/communes_needing_cross_fusion.xlsx", ///
                firstrow(variables) replace
            di as result "List written: communes_needing_cross_fusion.xlsx. " ///
                "Resolve manually (e.g. widen $MIN_BLOCK_SIZE review, or a " ///
                "second-nearest / cross-department exception approved by the " ///
                "PI) and re-run from Section 4b."
            exit 198
        }
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

label var bloc "Randomization block (commune[+nearest available neighbour] x size), FINAL"
tab bloc, missing
di as result "Blocks constituted: `=r(r)' blocks, all with >= $MIN_BLOCK_SIZE schools."

* Blocs figes -> stratified base locked, single input file
save "$outputdir/ecoles_blocs_locked.dta", replace

*======================================================================*
* 5. RANDOM DRAW OF THE 3 TREATMENT ARMS (BY BLOCK)
*======================================================================*
* Stratified draw by block. Two properties are enforced that were
* previously broken:
*   (a) REPRODUCIBILITY: the dataset is sorted by the fixed, content-
*       independent key id_infra IMMEDIATELY before every call to
*       runiform() under a recorded seed. runiform() assigns numbers
*       by physical row order in memory; if that order differs between
*       two runs (e.g. because a PRIOR sort by bloc/rand_arm is still
*       in effect), the same seed maps to different draws per school
*       and the "same seed -> same result" guarantee silently breaks.
*   (b) UNBIASED REMAINDER: when a block's size is not a multiple of
*       N_ARMS, the leftover school(s) are allocated to a RANDOMLY
*       CHOSEN subset of arms (drawn under the same seeded stream),
*       not always to arm 1/2 first. The previous version always gave
*       the remainder to the lowest-numbered arms, which - repeated
*       across 17 blocks - produced a systematic (non-random) skew
*       toward Control/Salience and away from Salience+Implementation.

isid id_infra

* --- Reproducibility anchor: fixed sort key before the seeded draw ---
sort id_infra

set seed $SEED_ARMS
gen double rand_arm = runiform()

sort bloc rand_arm
by bloc: gen long rank_arm    = _n
by bloc: gen long bloc_n_arm  = _N

gen byte group3 = .

* --- Base cyclic assignment for the "complete cycles" part of each block
replace group3 = mod(rank_arm - 1, $N_ARMS) + 1 ///
    if rank_arm <= floor(bloc_n_arm / $N_ARMS) * $N_ARMS

* --- Randomized remainder, block by block -----------------------------
levelsof bloc, local(blist_arm) clean
foreach b of local blist_arm {
    quietly summarize bloc_n_arm if bloc==`b', meanonly
    local n     = r(max)
    local nbase = floor(`n' / $N_ARMS)
    local rem   = `n' - `nbase' * $N_ARMS

    if `rem' > 0 {
        * Draw one uniform number per arm (same seeded stream, no
        * re-seeding), rank the arms by that draw, and give the extra
        * school(s) to the `rem' arms with the smallest draw. Which
        * arm(s) get the remainder therefore varies randomly from
        * block to block instead of always being arm 1, then arm 2...
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
                if bloc==`b' & rank_arm == `nbase'*$N_ARMS + `i'
            local i = `i' + 1
        }
    }
}

label define arm_lbl 1 "Control" 2 "Salience" 3 "Salience + Implementation", replace
label values group3 arm_lbl
label var group3 "Randomized treatment arm"

di as result "Arm allocation by block:"
tab bloc group3

* Overall allocation: should now be close to n/N_ARMS in EVERY arm,
* not just on average - the systematic remainder bias is removed.
tab group3
quietly tab group3
di as result "Total per arm (target: `=round(_N/$N_ARMS)' each, minimum required: 50):"
forvalues a = 1/$N_ARMS {
    quietly count if group3==`a'
    di as result "  Arm `a': `r(N)' schools"
    if r(N) < 50 {
        di as error "  WARNING: arm `a' has fewer than 50 schools. This can still " ///
            "happen by genuine chance with only 17 blocks; it is NOT evidence " ///
            "of a bug once the checks below pass. Do NOT re-seed to force a " ///
            "different draw - that would violate pre-registration. If 50 is a " ///
            "hard design requirement, this must be resolved via $MIN_BLOCK_SIZE " ///
            "or sample size BEFORE the draw, not after seeing this result."
    }
}

* --- 5a. Reproducibility check ----------------------------------------
* Re-draws with the SAME recorded seed, sorting by the SAME fixed key
* (id_infra) beforehand, and confirms an identical allocation.
preserve
    sort id_infra
    set seed $SEED_ARMS
    gen double rand_arm_chk = runiform()
    sort bloc rand_arm_chk
    by bloc: gen long rank_chk   = _n
    by bloc: gen long bloc_n_chk = _N

    gen byte group3_chk = .
    replace group3_chk = mod(rank_chk - 1, $N_ARMS) + 1 ///
        if rank_chk <= floor(bloc_n_chk / $N_ARMS) * $N_ARMS

    levelsof bloc, local(blist_chk) clean
    foreach b of local blist_chk {
        quietly summarize bloc_n_chk if bloc==`b', meanonly
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
                    if bloc==`b' & rank_chk == `nbase'*$N_ARMS + `i'
                local i = `i' + 1
            }
        }
    }

    assert group3 == group3_chk
    di as result "REPRODUCIBILITY CONFIRMED with seed $SEED_ARMS (rng: `c(rngstate)')."
restore

* --- 5b. Within-block balance check -----------------------------------
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
* IMPORTANT:
* The verification must reproduce the EXACT same observation order
* that was used for the original parent draw.
*
* The original parent draw was performed immediately after Section 5,
* where observations were left sorted by:
*       sort bloc rand_arm
*
* Therefore, the verification must recreate that same ordering using
* the already stored rand_arm variable before resetting the seed.

preserve

    * Recreate EXACTLY the ordering used in the original parent draw
    sort bloc rand_arm

    * Reset the parent seed
    set seed $SEED_PARENT

    * Reproduce the random numbers
    gen double rand_parent_chk = runiform() if treated==1

    * Reproduce the ranking within block
    sort bloc rand_parent_chk
    by bloc: gen long rank_parent_chk = _n if treated==1

    * Reproduce the Mother/Father assignment
    gen byte parent_group_chk = .
    replace parent_group_chk = mod(rank_parent_chk - 1, 2) + 1 ///
        if treated==1

    * Exact equality check
    assert parent_group == parent_group_chk if treated==1

    di as result "======================================================="
    di as result "PARENT DRAW REPRODUCIBILITY CONFIRMED"
    di as result "Seed       : $SEED_PARENT"
    di as result "RNG engine : `c(rngstate)'"
    di as result "======================================================="

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
         MILIEU `milieu_admin_var' size_label_f1 bloc group3_lbl parent_lbl2 target_enrol med_enrol

    rename size_label_f1 size_category
    rename group3_lbl     assigned_group
    rename parent_lbl2    targeted_parent

    order id_infra DEPARTEMENT COMMUNE ARRONDISSEMENT NOMETABLISSEMENT ///
          MILIEU `milieu_admin_var' size_category bloc assigned_group ///
          targeted_parent target_enrol med_enrol

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
file write manifest "Size categorization      : Small/Large vs within-commune MEDIAN of target_enrol" _n
file write manifest "Cross-commune fusion     : automated, nearest AVAILABLE neighbour (see $neighbor_csv)" _n
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
