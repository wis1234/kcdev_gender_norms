*======================================================================*
* PROJECT     : Gender Norms RCT - Randomization of Schools
* PURPOSE     : Stratified block randomization
*
* DESIGN:
*   1. Schools are classified Small/Large using the commune median.
*   2. Blocks are constructed within commune/pool.
*   3. Each block contains approximately 6 schools.
*   4. Small and Large schools are distributed separately across blocks,
*      so their numbers differ by at most 1 across blocks.
*   5. Only communes with < 6 schools are fused with other commune(s)
*      before block construction, using MULTI-HOP fusion:
*        - if no directly adjacent commune has spare capacity, the
*          search extends via neighbours-of-neighbours (shortest
*          CUMULATIVE centroid distance, Floyd-Warshall),
*        - if one partner commune is still not enough to reach the
*          minimum, MULTIPLE communes are cumulated into one pool,
*          always following nearest-cumulative-distance first,
*        - fusion NEVER crosses the Zou/Atlantique department
*          boundary: this is enforced structurally, by never creating
*          an edge between two communes of different departments, so
*          no multi-hop path can ever transit through the other
*          department either.
*   6. Treatment is randomized within final blocks.
*======================================================================*

version 17
clear all
set more off
set linesize 120

* Variable name abbreviation is disabled for the ENTIRE script. Without
* this, a command like "capture drop bloc" - issued defensively before
* (re)creating the variable "bloc" - can silently resolve to a totally
* different, longer variable if "bloc" happens to be a UNIQUE prefix
* match for it at that point in the dataset (e.g. "block_number", since
* neither "bloc" nor "bloc_n"/"bloc_n_arm" exist yet when that command
* runs). Stata does not warn when an abbreviation match is unique - it
* just silently drops whichever variable matches, which previously
* deleted block_number moments after it was confirmed complete. Turning
* abbreviation off makes every variable reference in this do-file
* resolve to its EXACT name only, eliminating this entire bug class.
set varabbrev off

*======================================================================*
* 0. SETTINGS
*======================================================================*

cd "C:\RONALDO\CKDEV\GENDER NORMS\Randomization"

global datadir   "Datasets"
global outputdir "Outputs"

global mergeoutdir "$outputdir/Data"
global infile "$mergeoutdir/master_x_gender_norm.xlsx"

global neighbor_csv "$datadir/communes_limitrophes_distance_centroides.csv"

global MIN_BLOCK_SIZE 6
global N_ARMS 3

global SEED_BLOCKS 20260730
global SEED_ARMS   20260731
global SEED_PARENT 20260801

capture mkdir "$outputdir"

capture confirm file "$infile"
if _rc {
    di as error "Input file not found:"
    di as error "$infile"
    exit 601
}

* Timestamp
local timestamp : di %tcCCYY-NN-DD_HH-MM-SS clock("$S_DATE $S_TIME", "DMYhms")
local timestamp = subinstr("`timestamp'", ":", "", .)
local timestamp = subinstr("`timestamp'", " ", "_", .)

capture log close
log using "$outputdir/randomization_log_`timestamp'.log", replace text

set rng mt64

di as result "======================================================="
di as result "GENDER NORMS RCT - RANDOMIZATION"
di as result "======================================================="
di as result "SEED_BLOCKS = $SEED_BLOCKS"
di as result "SEED_ARMS   = $SEED_ARMS"
di as result "SEED_PARENT = $SEED_PARENT"
di as result "======================================================="


*======================================================================*
* 1. IMPORT AND VALIDATION
*======================================================================*

import excel using "$infile", firstrow clear case(upper)

*----------------------------------------------------------------------*
* School identifier
*----------------------------------------------------------------------*

capture confirm variable id_infra

if _rc {

    capture confirm variable SCHOOL_ID

    if _rc {
        di as error "Neither id_infra nor SCHOOL_ID exists."
        exit 111
    }

    quietly count if missing(SCHOOL_ID)

    if r(N) > 0 {
        di as error "`r(N)' schools have missing SCHOOL_ID."
        exit 459
    }

    quietly duplicates report SCHOOL_ID

    if r(unique_value) < r(N) {
        di as error "SCHOOL_ID is not unique."
        exit 459
    }

    egen long id_infra = group(SCHOOL_ID)

}

isid id_infra


*----------------------------------------------------------------------*
* Required variables
*----------------------------------------------------------------------*

foreach v of varlist DEPARTEMENT COMMUNE NOMETABLISSEMENT {

    quietly count if missing(`v')

    if r(N) > 0 {
        di as error "`r(N)' observations have missing `v'."
        exit 459
    }

}


*----------------------------------------------------------------------*
* Grade enrolment variables
*----------------------------------------------------------------------*

egen byte miss_grade = rmiss( ///
    NBM6EME NBF6EME NBM5EME NBF5EME ///
)

quietly count if miss_grade > 0

if r(N) > 0 {

    di as error ///
        "`r(N)' schools have missing 6eme/5eme enrolment."

    exit 459

}

drop miss_grade


*----------------------------------------------------------------------*
* Public schools / departments
*----------------------------------------------------------------------*

quietly count if ///
    !inlist(upper(strtrim(STATUT)), "PUBLIC", "PUBLIQUE")

if r(N) > 0 {

    di as error ///
        "`r(N)' non-public schools detected."

    exit 459

}


quietly count if ///
    !inlist(upper(strtrim(DEPARTEMENT)), "ZOU", "ATLANTIQUE")

if r(N) > 0 {

    di as error ///
        "`r(N)' schools outside Zou/Atlantique detected."

    exit 459

}


*----------------------------------------------------------------------*
* Technical string normalization
*----------------------------------------------------------------------*

foreach v of varlist ///
    DEPARTEMENT COMMUNE ARRONDISSEMENT ///
    QUARTIERVILLAGE NOMETABLISSEMENT ///
    STATUT MILIEU REGIME {

    capture confirm string variable `v'

    if !_rc {
        replace `v' = strtrim(stritrim(upper(`v')))
    }

}

capture confirm string variable MILIEU_ADMIN

if !_rc {
    replace MILIEU_ADMIN = ///
        strtrim(stritrim(upper(MILIEU_ADMIN)))
}


di as result ///
    "Input validated: `=_N' schools."

save "$outputdir/ecoles_valid_step1.dta", replace


*======================================================================*
* 2. SCHOOL SIZE CLASSIFICATION
*======================================================================*
*
* Target variable:
*
*     total enrolment in 6eme + 5eme
*
* Classification within each commune:
*
*     <= commune median  -> Small
*     >  commune median  -> Large
*
*======================================================================*

gen long target_enrol = ///
    NBM6EME + NBF6EME + ///
    NBM5EME + NBF5EME

label var target_enrol ///
    "Total enrolment in 6eme and 5eme"


bysort COMMUNE: gen long n_comm = _N

bysort COMMUNE: egen double med_enrol = ///
    median(target_enrol)

label var med_enrol ///
    "Median target enrolment within commune"


gen str8 size_label = ""

replace size_label = "Small" ///
    if target_enrol <= med_enrol

replace size_label = "Large" ///
    if target_enrol > med_enrol

label var size_label ///
    "Small/Large according to commune median"


tab COMMUNE size_label, missing


*----------------------------------------------------------------------*
* Save classification
*----------------------------------------------------------------------*

save "$outputdir/ecoles_size_classified.dta", replace

*======================================================================*
* 3-4. CONSTRUCTION DES BLOCS DE RANDOMISATION
*======================================================================*
*
* OBJECTIF :
*
* Dans chaque commune (ou pool de communes deja fusionne si necessaire),
* construire des blocs d'environ 6 ecoles.
*
* IMPORTANT :
*
*   commune_bloc = identifiant NUMERIQUE du pool final
*
*   commune_bloc_label = nom lisible du pool
*
*   size_label = Small / Large
*
* Small et Large NE constituent PAS deux strates separees.
*
* Ils servent uniquement a equilibrer la composition de chaque bloc.
*
* Exemple :
*
*   Commune avec 12 ecoles :
*
*       6 Small
*       6 Large
*
*   => 2 blocs de 6 :
*
*       Bloc 1 : 3 Small + 3 Large
*       Bloc 2 : 3 Small + 3 Large
*
* Exemple :
*
*   Commune avec 19 ecoles :
*
*       10 Small
*        9 Large
*
*   => 3 blocs :
*
*       Bloc 1 : 4 Small + 3 Large = 7
*       Bloc 2 : 3 Small + 3 Large = 6
*       Bloc 3 : 3 Small + 3 Large = 6
*
* L'objectif est que :
*
*   - la difference Small entre deux blocs <= 1
*   - la difference Large entre deux blocs <= 1
*   - aucun bloc < 6 ecoles
*
*======================================================================*


*----------------------------------------------------------------------*
* 3A. CHARGEMENT DU FICHIER
*----------------------------------------------------------------------*

clear

use "$outputdir/ecoles_size_classified.dta", clear


*----------------------------------------------------------------------*
* 3B. VERIFICATIONS INITIALES
*----------------------------------------------------------------------*

di as result "======================================================="
di as result "VERIFICATION DU FICHIER POUR LA CONSTRUCTION DES BLOCS"
di as result "======================================================="

* FIX: the original line here was
*     describe commune_bloc commune_bloc_label size_label target_enrol COMMUNE
* `describe` is NOT wrapped in `capture`, so it stopped the script with
* r(111) as soon as it hit `commune_bloc` - which does not exist yet at
* this point (ecoles_size_classified.dta only has size_label /
* target_enrol / med_enrol / COMMUNE / n_comm; commune_bloc is only
* created a few lines below, in the "commune_bloc doit normalement deja
* exister" block). Describing only the variables that are guaranteed to
* exist at this stage fixes the crash; commune_bloc / commune_bloc_label
* are described further below, AFTER they have actually been created.
describe COMMUNE size_label target_enrol med_enrol n_comm


* Identifiant ecole
isid id_infra


* Variables obligatoires
foreach v in COMMUNE size_label target_enrol {

    capture confirm variable `v'

    if _rc {

        di as error ///
            "Variable `v' absente de ecoles_size_classified.dta."

        exit 111
    }
}


* commune_bloc doit normalement deja exister
capture confirm variable commune_bloc

if _rc {

    di as error "-------------------------------------------------------"
    di as error "ATTENTION : commune_bloc n'existe pas dans le fichier."
    di as error "-------------------------------------------------------"

    * Si le label existe, on peut reconstruire le pool
    * a partir de commune_bloc_label.
    capture confirm variable commune_bloc_label

    if !_rc {

        di as result ///
            "commune_bloc_label trouve : reconstruction de commune_bloc."

        egen long commune_bloc = group(commune_bloc_label)

    }
    else {

        di as result ///
            "Aucun pool pre-construit trouve."

        di as result ///
            "Construction de commune_bloc a partir de COMMUNE, avec fusion" ///
            " automatique des communes sous le seuil."

        *----------------------------------------------------------------*
        * AUTOMATED CROSS-COMMUNE FUSION - MULTI-HOP, DEPARTMENT-STRICT,
        * MULTI-COMMUNE CUMULATION
        *----------------------------------------------------------------*
        * Rules (as specified by the PI):
        *   (1) If no DIRECTLY adjacent commune has spare capacity, the
        *       search extends via neighbours-of-neighbours (multi-hop),
        *       using the SHORTEST CUMULATIVE centroid distance -
        *       implemented via Floyd-Warshall over the full commune
        *       adjacency graph.
        *   (2) If a single partner commune's surplus is not enough to
        *       reach $MIN_BLOCK_SIZE, MULTIPLE different communes are
        *       cumulated into one pool, always respecting nearest-
        *       cumulative-distance-first (implemented as a Kruskal-style
        *       greedy merge over all pairwise shortest distances, sorted
        *       ascending).
        *   (3) Department boundary (Zou vs Atlantique) is NEVER crossed.
        *       This is enforced STRUCTURALLY: an edge is only ever
        *       created between two communes in $neighbor_csv when they
        *       belong to the SAME department. Since Floyd-Warshall can
        *       only route through edges that exist, no multi-hop path
        *       can ever transit through the other department either -
        *       the constraint holds by construction, not by a filter
        *       applied after the fact.
        * If, even after multi-hop and multi-commune cumulation, a
        * cluster still cannot reach $MIN_BLOCK_SIZE within its own
        * department, it is flagged for manual PI review and the script
        * stops (exit 198), exactly as in the previous version.

        gen str120 commune_bloc_label = COMMUNE

        bysort COMMUNE: gen long pool_N0 = _N
        gen byte pool0_small = pool_N0 < $MIN_BLOCK_SIZE

        quietly count if pool0_small == 1
        local n_need_cross = r(N)

        if `n_need_cross' > 0 {

            di as error "`n_need_cross' ecole(s) sont dans une commune de moins de" ///
                " $MIN_BLOCK_SIZE ecoles. Fusion multi-sauts (distance cumulee)," ///
                " meme departement strict, cumul de plusieurs communes si necessaire."

            capture confirm file "$neighbor_csv"
            if _rc {
                di as error "Fichier de communes limitrophes introuvable :"
                di as error "$neighbor_csv"
                di as error "Placez communes_limitrophes_distance_centroides.csv" ///
                    " dans $datadir, puis relancez a partir de cette section."

                preserve
                    keep if pool0_small==1
                    duplicates drop COMMUNE DEPARTEMENT, force
                    keep COMMUNE DEPARTEMENT
                    export excel using "$outputdir/communes_needing_cross_fusion.xlsx", ///
                        firstrow(variables) replace
                restore
                exit 198
            }

            *------------------------------------------------------------------*
            * A. Liste des communes presentes, indexees 1..nC, avec departement
            *------------------------------------------------------------------*
            local nC = 0
            preserve
                keep COMMUNE DEPARTEMENT
                duplicates drop COMMUNE DEPARTEMENT, force
                sort COMMUNE
                local nC = _N
                forvalues i = 1/`nC' {
                    local comm_`i' = COMMUNE[`i']
                    local dept_`i' = DEPARTEMENT[`i']
                }
            restore

            * Taille (nb ecoles) de chaque commune, dans le meme index
            forvalues i = 1/`nC' {
                quietly count if COMMUNE == "`comm_`i''"
                local size_`i'  = r(N)
                local clu_`i'   = `i'          // union-find : chacun son propre cluster
                local total_`i' = `size_`i''   // taille cumulee du cluster
            }

            *------------------------------------------------------------------*
            * B. Aretes du crosswalk (voisins directs), extraites en locals
            *------------------------------------------------------------------*
            local nE = 0
            preserve
                import delimited using "$neighbor_csv", clear varnames(1) case(preserve)
                rename Commune_Principale COMMUNE
                rename Commune_Limitrophe neighbor_COMMUNE
                rename Distance_Centroides_KM dist_km
                replace COMMUNE          = strtrim(stritrim(upper(COMMUNE)))
                replace neighbor_COMMUNE = strtrim(stritrim(upper(neighbor_COMMUNE)))
                local nE = _N
                forvalues e = 1/`nE' {
                    local efrom_`e' = COMMUNE[`e']
                    local eto_`e'   = neighbor_COMMUNE[`e']
                    local edist_`e' = dist_km[`e']
                }
            restore

            *------------------------------------------------------------------*
            * C. Matrice de distances directes : Inf par defaut, 0 diagonale,
            *    UNIQUEMENT si meme departement (contrainte stricte, structurelle)
            *------------------------------------------------------------------*
            tempname D
            matrix `D' = J(`nC', `nC', 1e9)
            forvalues i = 1/`nC' {
                matrix `D'[`i',`i'] = 0
            }

            forvalues e = 1/`nE' {
                local fi = .
                local tj = .
                forvalues i = 1/`nC' {
                    if "`comm_`i''" == "`efrom_`e''" local fi = `i'
                    if "`comm_`i''" == "`eto_`e''"   local tj = `i'
                }
                if `fi' < . & `tj' < . {
                    if "`dept_`fi''" == "`dept_`tj''" {
                        local cur = `D'[`fi',`tj']
                        if `edist_`e'' < `cur' {
                            matrix `D'[`fi',`tj'] = `edist_`e''
                            matrix `D'[`tj',`fi'] = `edist_`e''
                        }
                    }
                }
            }

            *------------------------------------------------------------------*
            * D. Floyd-Warshall (Mata, matrice pure - aucun chemin ne peut
            *    traverser un autre departement puisque ces aretes n'existent
            *    simplement pas dans D)
            *------------------------------------------------------------------*
            mata:
                Dm = st_matrix("`D'")
                nCm = rows(Dm)
                for (k=1; k<=nCm; k++) {
                    for (i=1; i<=nCm; i++) {
                        if (Dm[i,k] < 1e9) {
                            for (j=1; j<=nCm; j++) {
                                if (Dm[i,k] + Dm[k,j] < Dm[i,j]) Dm[i,j] = Dm[i,k] + Dm[k,j]
                            }
                        }
                    }
                }
                st_matrix("`D'", Dm)
            end

            *------------------------------------------------------------------*
            * E. Liste de toutes les paires (i<j) avec distance cumulee finie,
            *    triee ensuite par distance croissante
            *------------------------------------------------------------------*
            tempfile pairs_ds
            capture postutil clear
            postfile ph int i1 int i2 double dist using `pairs_ds', replace
            forvalues i = 1/`nC' {
                local jstart = `i' + 1
                forvalues j = `jstart'/`nC' {
                    local dij = `D'[`i',`j']
                    if `dij' < 1e9 {
                        post ph (`i') (`j') (`dij')
                    }
                }
            }
            postclose ph

            *------------------------------------------------------------------*
            * F. Fusion gloutonne (type Kruskal) : parcours par distance
            *    croissante, fusion tant qu'au moins un des deux clusters est
            *    encore sous le seuil. Les locals clu_*/total_* (union-find)
            *    survivent au preserve/restore ci-dessous (seules les donnees
            *    en memoire sont affectees par preserve, pas les macros).
            *------------------------------------------------------------------*
            preserve
                use `pairs_ds', clear
                sort dist
                local nP = _N

                forvalues r = 1/`nP' {
                    local a = i1[`r']
                    local b = i2[`r']

                    local ra = `a'
                    while `clu_`ra'' != `ra' {
                        local ra = `clu_`ra''
                    }
                    local rb = `b'
                    while `clu_`rb'' != `rb' {
                        local rb = `clu_`rb''
                    }

                    if `ra' != `rb' {
                        if `total_`ra'' < $MIN_BLOCK_SIZE | `total_`rb'' < $MIN_BLOCK_SIZE {
                            local new_total = `total_`ra'' + `total_`rb''
                            local clu_`rb'   = `ra'
                            local total_`ra' = `new_total'
                        }
                    }
                }
            restore

            *------------------------------------------------------------------*
            * G. Resoudre la racine finale de chaque commune, construire les
            *    labels de pool (concatenation triee des noms de communes), et
            *    detecter les clusters encore insuffisants apres fusion multi-
            *    sauts (plus aucun voisin disponible dans le meme departement).
            *------------------------------------------------------------------*
            forvalues i = 1/`nC' {
                local cur = `i'
                while `clu_`cur'' != `cur' {
                    local cur = `clu_`cur''
                }
                local root_`i' = `cur'
            }

            local roots_seen ""
            local any_unresolved = 0

            forvalues i = 1/`nC' {
                local r = `root_`i''
                local in_seen : list r in roots_seen
                if !`in_seen' {
                    local roots_seen "`roots_seen' `r'"

                    local members ""
                    forvalues j = 1/`nC' {
                        if `root_`j'' == `r' {
                            local members "`members' `comm_`j''"
                        }
                    }
                    local members : list sort members
                    local lbl : subinstr local members " " " + ", all
                    local clu_total = `total_`r''

                    if `clu_total' < $MIN_BLOCK_SIZE {
                        di as error "  Pool INSUFFISANT meme apres fusion multi-sauts : " ///
                            "`lbl' (`clu_total' ecoles, departement `dept_`i'') - revue PI requise."
                        local any_unresolved = 1
                    }
                    else {
                        di as result "  Pool fusionne (multi-sauts, meme departement) : " ///
                            "`lbl' (`clu_total' ecoles)"
                    }

                    foreach cc of local members {
                        quietly replace commune_bloc_label = "`lbl'" if COMMUNE == "`cc'"
                    }
                }
            }

            * --- Log de toutes les fusions effectuees (pools avec >1 commune) --
            preserve
                keep if strpos(commune_bloc_label, " + ") > 0
                quietly count
                if r(N) > 0 {
                    duplicates drop commune_bloc_label, force
                    keep commune_bloc_label
                    gen str30 fusion_type = "cross-commune (multi-sauts, meme departement, automated)"
                    gen str20 fusion_date = "$S_DATE"
                    export excel using "$outputdir/log_fusion_strates.xlsx", ///
                        firstrow(variables) replace sheet("cross_commune")
                    di as result "Log de fusion cross-commune ecrit (log_fusion_strates.xlsx, feuille cross_commune)."
                }
            restore

            * --- Arret si un cluster reste insuffisant meme apres multi-sauts --
            if `any_unresolved' == 1 {
                preserve
                    bysort commune_bloc_label: gen long clu_check_n = _N
                    keep if clu_check_n < $MIN_BLOCK_SIZE
                    keep COMMUNE DEPARTEMENT commune_bloc_label clu_check_n
                    duplicates drop
                    export excel using "$outputdir/communes_needing_cross_fusion.xlsx", ///
                        firstrow(variables) replace
                restore
                di as result "Liste ecrite : communes_needing_cross_fusion.xlsx." ///
                    " Aucun partenaire (direct ou multi-sauts) disponible dans le" ///
                    " meme departement. Resolvez manuellement, puis relancez."
                exit 198
            }

            drop pool_N0 pool0_small

        }
        else {
            di as result "Aucune fusion cross-commune necessaire : toutes les" ///
                " communes atteignent $MIN_BLOCK_SIZE ecoles."
        }

        egen long commune_bloc = group(commune_bloc_label)

    }
}


* Verifier que commune_bloc est numerique
capture confirm numeric variable commune_bloc

if _rc {

    di as error ///
        "commune_bloc existe mais n'est pas numerique."

    exit 109
}


* Verifier size_label
quietly count if !inlist(size_label,"Small","Large")

if r(N) > 0 {

    di as error ///
        "`r(N)' observations ont un size_label invalide."

    tab size_label, missing

    exit 459
}


*----------------------------------------------------------------------*
* 3C. CREATION D'UN LABEL LISIBLE SI NECESSAIRE
*----------------------------------------------------------------------*

capture confirm variable commune_bloc_label

if _rc {

    gen str120 commune_bloc_label = ""

    levelsof commune_bloc, local(pool_ids)

    foreach p of local pool_ids {

        quietly levelsof COMMUNE ///
            if commune_bloc==`p', local(clist) clean

        local clabel : subinstr local clist " " " + ", all

        replace commune_bloc_label = ///
            "`clabel'" ///
            if commune_bloc==`p'
    }
}

* Now that commune_bloc / commune_bloc_label are guaranteed to exist,
* it's safe to describe them for the diagnostic log.
describe commune_bloc commune_bloc_label


*----------------------------------------------------------------------*
* 3D. DIAGNOSTIC DES POOLS
*----------------------------------------------------------------------*

di as result "======================================================="
di as result "COMPOSITION DES POOLS"
di as result "======================================================="

preserve

    contract commune_bloc commune_bloc_label size_label, freq(n)

    reshape wide n, ///
        i(commune_bloc commune_bloc_label) ///
        j(size_label) string

    capture confirm variable nSmall
    if _rc gen nSmall = 0

    capture confirm variable nLarge
    if _rc gen nLarge = 0

    replace nSmall = 0 if missing(nSmall)
    replace nLarge = 0 if missing(nLarge)

    gen pool_total = nSmall + nLarge

    order commune_bloc commune_bloc_label ///
        nLarge nSmall pool_total

    sort commune_bloc

    list, noobs sep(0)

restore


*----------------------------------------------------------------------*
* 3E. VERIFICATION DE LA TAILLE DES POOLS
*----------------------------------------------------------------------*

bysort commune_bloc: gen long pool_N = _N

quietly count if pool_N < $MIN_BLOCK_SIZE

if r(N) > 0 {

    di as error "-------------------------------------------------------"
    di as error ///
        "`r(N)' ecoles appartiennent encore a un pool de moins de " ///
        "$MIN_BLOCK_SIZE ecoles."
    di as error "-------------------------------------------------------"

    preserve

        keep if pool_N < $MIN_BLOCK_SIZE

        keep commune_bloc commune_bloc_label COMMUNE pool_N

        duplicates drop

        list, noobs sep(0)

        export excel using ///
            "$outputdir/pools_below_minimum.xlsx", ///
            firstrow(variables) replace

    restore

    di as error ///
        "La construction des blocs ne peut pas continuer."

    exit 459
}


*======================================================================*
* 4. DETERMINATION DU NOMBRE DE BLOCS
*======================================================================*
*
* Regle :
*
*       nombre de blocs = floor(N / 6)
*
* avec la contrainte que chaque bloc doit contenir au moins 6 ecoles.
*
* Exemples :
*
*       N=6   -> 1 bloc
*       N=7   -> 1 bloc
*       N=8   -> 1 bloc
*       N=10  -> 1 bloc
*       N=11  -> 1 bloc
*       N=12  -> 2 blocs
*       N=13  -> 2 blocs
*       N=14  -> 2 blocs
*       N=17  -> 2 blocs
*       N=18  -> 3 blocs
*       N=19  -> 3 blocs
*       N=23  -> 3 blocs
*       N=24  -> 4 blocs
*
*======================================================================*


capture drop n_blocks_pool

gen long n_blocks_pool = floor(pool_N / $MIN_BLOCK_SIZE)

replace n_blocks_pool = 1 ///
    if n_blocks_pool < 1


* Verification mathematique
assert pool_N / n_blocks_pool >= $MIN_BLOCK_SIZE


di as result "======================================================="
di as result "NOMBRE DE BLOCS PAR POOL"
di as result "======================================================="

preserve

    keep commune_bloc commune_bloc_label pool_N n_blocks_pool

    duplicates drop

    sort commune_bloc

    list, noobs sep(0)

restore


*======================================================================*
* 4A. RANDOMISATION DE L'ORDRE DES ECOLES
*======================================================================*
*
* Cette etape ne determine PAS le traitement.
*
* Elle determine uniquement l'ordre aleatoire utilise pour repartir
* les Small et Large entre les blocs.
*
* Seed independant :
*
*       SEED_BLOCKS
*
*======================================================================*

sort id_infra

set seed $SEED_BLOCKS

capture drop rand_block

gen double rand_block = runiform()


*======================================================================*
* 4B. CONSTRUCTION DES RANGS SMALL ET LARGE
*======================================================================*
*
* IMPORTANT :
*
* On cree un rang independant pour :
*
*       Small
*
*       Large
*
* dans chaque pool.
*
* Puis on distribue chaque categorie de maniere cyclique :
*
*       1 -> Bloc 1
*       2 -> Bloc 2
*       ...
*       B -> Bloc B
*       B+1 -> Bloc 1
*
* Cela garantit mathematiquement que les nombres de Small et Large
* different d'au maximum 1 entre les blocs.
*
*======================================================================*


capture drop rank_small
capture drop rank_large
capture drop block_number


gen long rank_small = .
gen long rank_large = .


*----------------------------------------------------------------------*
* Rang Small
*----------------------------------------------------------------------*

sort commune_bloc size_label rand_block

by commune_bloc: gen long _rank_tmp = ///
    sum(size_label=="Small")

replace rank_small = _rank_tmp ///
    if size_label=="Small"

drop _rank_tmp


*----------------------------------------------------------------------*
* Rang Large
*----------------------------------------------------------------------*

sort commune_bloc size_label rand_block

by commune_bloc: gen long _rank_tmp = ///
    sum(size_label=="Large")

replace rank_large = _rank_tmp ///
    if size_label=="Large"

drop _rank_tmp


*----------------------------------------------------------------------*
* Verification des rangs
*----------------------------------------------------------------------*

quietly count if size_label=="Small" & missing(rank_small)

if r(N) > 0 {

    di as error ///
        "`r(N)' Small schools have no rank."

    exit 459
}


quietly count if size_label=="Large" & missing(rank_large)

if r(N) > 0 {

    di as error ///
        "`r(N)' Large schools have no rank."

    exit 459
}


*======================================================================*
* 4C. DISTRIBUTION SMALL / LARGE DANS LES BLOCS
*======================================================================*
*
* C'est ici que se trouve le coeur du design.
*
* ATTENTION :
*
* commune_bloc est NUMERIQUE.
*
* On utilise donc :
*
*       commune_bloc == `p'
*
* et NON :
*
*       commune_bloc == "`p'"
*
*======================================================================*


gen long block_number = .


levelsof commune_bloc, local(pool_list)


foreach p of local pool_list {


    *--------------------------------------------------------------*
    * Nombre de blocs du pool
    *--------------------------------------------------------------*

    quietly summarize n_blocks_pool ///
        if commune_bloc==`p', meanonly

    local nb = r(max)


    *--------------------------------------------------------------*
    * SMALL
    *--------------------------------------------------------------*

    replace block_number = ///
        mod(rank_small - 1, `nb') + 1 ///
        if commune_bloc==`p' ///
        & size_label=="Small"


    *--------------------------------------------------------------*
    * LARGE
    *--------------------------------------------------------------*

    replace block_number = ///
        mod(rank_large - 1, `nb') + 1 ///
        if commune_bloc==`p' ///
        & size_label=="Large"

}


*======================================================================*
* 4D. VERIFICATION CRITIQUE : TOUTES LES ECOLES DOIVENT AVOIR UN BLOC
*======================================================================*

quietly count if missing(block_number)

if r(N) > 0 {

    di as error "======================================================="
    di as error ///
        "`r(N)' ecoles n'ont pas recu de block_number."
    di as error "======================================================="

    preserve

        keep if missing(block_number)

        keep id_infra SCHOOL_ID COMMUNE ///
            commune_bloc commune_bloc_label ///
            size_label rank_small rank_large ///
            n_blocks_pool

        list, noobs sep(0)

        export excel using ///
            "$outputdir/debug_missing_blocks.xlsx", ///
            firstrow(variables) replace

    restore

    exit 459
}


di as result ///
    "Toutes les `=_N' ecoles ont recu un block_number."


*======================================================================*
* 4E. CREATION DE L'IDENTIFIANT FINAL DU BLOC
*======================================================================*
*
* Le bloc final est :
*
*       commune_bloc + block_number
*
* et NON :
*
*       commune + size
*
* Donc Small et Large sont bien melanges dans le meme bloc.
*
*======================================================================*


capture drop bloc

* Garde-fou explicite : si block_number n'existe pas ici, ce n'est PAS un
* bug du code (il est cree et rempli en Section 4C, juste au-dessus) -
* cela signifie presque toujours que le do-file a ete execute par
* fragments (ex. selection partielle relancee, ou un `clear`/`use` d'un
* fichier anterieur a la creation de block_number) plutot qu'en une
* seule execution continue depuis le debut. Ce message le dit
* explicitement, au lieu de laisser Stata renvoyer un cryptique
* "variable block_number not found".
capture confirm variable block_number
if _rc {
    di as error "======================================================="
    di as error "ERREUR : block_number n'existe pas dans les donnees en"
    di as error "memoire a ce stade."
    di as error "======================================================="
    di as error "Cette variable est creee et remplie en Section 4C, juste"
    di as error "au-dessus de cette ligne. Si elle est absente ici, c'est"
    di as error "presque toujours le signe que le do-file a ete execute"
    di as error "PAR FRAGMENTS (ex. selection partielle relancee apres la"
    di as error "Section 4D, ou un clear/use d'un fichier anterieur a sa"
    di as error "creation), et non en une seule execution continue."
    di as error "Solution : relancez l'integralite du do-file, du tout"
    di as error "debut (version 17 / clear all) jusqu'a la fin, sans"
    di as error "executer de selection partielle entre les sections."
    exit 111
}

egen long bloc = ///
    group(commune_bloc block_number)


label var bloc ///
    "Final mixed Small/Large randomization block"


bysort bloc: gen long bloc_n = _N

label var bloc_n ///
    "Number of schools in final randomization block"


*======================================================================*
* 4F. CONTROLE DE LA TAILLE DES BLOCS
*======================================================================*

quietly summarize bloc_n, meanonly

di as result "======================================================="
di as result "TAILLE DES BLOCS"
di as result "======================================================="

di as result ///
    "Minimum : `r(min)'"

di as result ///
    "Maximum : `r(max)'"

di as result ///
    "Moyenne : `=string(r(mean),"%9.2f")'"


assert bloc_n >= $MIN_BLOCK_SIZE


*======================================================================*
* 4G. COMPOSITION SMALL / LARGE DE CHAQUE BLOC
*======================================================================*

di as result "======================================================="
di as result "COMPOSITION DES BLOCS"
di as result "======================================================="


preserve

    contract commune_bloc commune_bloc_label ///
        block_number size_label, freq(n)


    reshape wide n, ///
        i(commune_bloc commune_bloc_label block_number) ///
        j(size_label) string


    capture confirm variable nSmall
    if _rc gen nSmall = 0


    capture confirm variable nLarge
    if _rc gen nLarge = 0


    replace nSmall = 0 if missing(nSmall)
    replace nLarge = 0 if missing(nLarge)


    gen block_total = nSmall + nLarge


    order commune_bloc commune_bloc_label ///
        block_number nLarge nSmall block_total


    sort commune_bloc block_number


    list, noobs sepby(commune_bloc)

restore


*======================================================================*
* 4H. TEST FORMEL DE L'EQUILIBRE SMALL / LARGE
*======================================================================*
*
* Pour chaque pool :
*
*       max(Small) - min(Small) <= 1
*
*       max(Large) - min(Large) <= 1
*
*======================================================================*


preserve


    contract commune_bloc block_number size_label, freq(n)


    reshape wide n, ///
        i(commune_bloc block_number) ///
        j(size_label) string


    capture confirm variable nSmall
    if _rc gen nSmall = 0


    capture confirm variable nLarge
    if _rc gen nLarge = 0


    replace nSmall = 0 if missing(nSmall)
    replace nLarge = 0 if missing(nLarge)


    bysort commune_bloc: egen min_small = min(nSmall)
    bysort commune_bloc: egen max_small = max(nSmall)


    bysort commune_bloc: egen min_large = min(nLarge)
    bysort commune_bloc: egen max_large = max(nLarge)


    gen diff_small = max_small - min_small
    gen diff_large = max_large - min_large


    *--------------------------------------------------------------*
    * Small
    *--------------------------------------------------------------*

    quietly count if diff_small > 1

    if r(N) > 0 {

        di as error ///
            "ERREUR : distribution Small desequilibree."

        list commune_bloc ///
            min_small max_small diff_small ///
            if diff_small > 1, noobs

        restore

        exit 459
    }


    *--------------------------------------------------------------*
    * Large
    *--------------------------------------------------------------*

    quietly count if diff_large > 1

    if r(N) > 0 {

        di as error ///
            "ERREUR : distribution Large desequilibree."

        list commune_bloc ///
            min_large max_large diff_large ///
            if diff_large > 1, noobs

        restore

        exit 459
    }


    di as result ///
        "Small et Large sont equilibres mathematiquement dans chaque pool."


restore


*======================================================================*
* 4I. VERIFICATION DE LA COMPOSITION MIXTE
*======================================================================*
*
* Si un pool possede a la fois Small ET Large, on veut verifier autant
* que possible que les deux categories sont presentes dans les memes
* blocs.
*
* Lorsque cela est mathematiquement possible, chaque bloc recoit au
* moins une ecole Small et une ecole Large.
*
*======================================================================*


preserve


    contract bloc size_label, freq(n)


    reshape wide n, ///
        i(bloc) ///
        j(size_label) string


    capture confirm variable nSmall
    if _rc gen nSmall = 0


    capture confirm variable nLarge
    if _rc gen nLarge = 0


    replace nSmall = 0 if missing(nSmall)
    replace nLarge = 0 if missing(nLarge)


    gen mixed_block = ///
        (nSmall > 0 & nLarge > 0)


    quietly count if mixed_block==0


    local nonmixed = r(N)


    if `nonmixed' > 0 {

        di as text ///
            "`nonmixed' bloc(s) ne contiennent qu'une categorie."

        di as text ///
            "Cela peut etre mathematiquement inevitable lorsque " ///
            "une categorie est trop peu nombreuse."
    }
    else {

        di as result ///
            "Tous les blocs contiennent Small ET Large."
    }


restore


*======================================================================*
* 4J. RESUME FINAL DES BLOCS
*======================================================================*

quietly summarize bloc, meanonly

local n_blocks_final = r(max)


quietly summarize bloc_n, meanonly

local min_block = r(min)
local max_block = r(max)
local mean_block = r(mean)


di as result "======================================================="
di as result "CONSTRUCTION DES BLOCS TERMINEE"
di as result "======================================================="

di as result ///
    "Nombre de blocs : `n_blocks_final'"

di as result ///
    "Taille minimale : `min_block'"

di as result ///
    "Taille maximale : `max_block'"

di as result ///
    "Taille moyenne  : `=string(`mean_block',"%9.2f")'"


*======================================================================*
* 4K. EXPORT DU LOG DES BLOCS
*======================================================================*

preserve


    contract bloc commune_bloc commune_bloc_label ///
        block_number size_label, freq(n)


    reshape wide n, ///
        i(bloc commune_bloc commune_bloc_label block_number) ///
        j(size_label) string


    capture confirm variable nSmall
    if _rc gen nSmall = 0


    capture confirm variable nLarge
    if _rc gen nLarge = 0


    replace nSmall = 0 if missing(nSmall)
    replace nLarge = 0 if missing(nLarge)


    gen block_total = nSmall + nLarge


    order bloc commune_bloc commune_bloc_label ///
        block_number nLarge nSmall block_total


    sort commune_bloc block_number


    export excel using ///
        "$outputdir/log_blocks.xlsx", ///
        firstrow(variables) replace ///
        sheet("final_blocks")


restore


*======================================================================*
* 4L. SAUVEGARDE DU DATASET AVEC LES BLOCS
*======================================================================*

sort bloc id_infra

save ///
    "$outputdir/ecoles_blocs_locked.dta", ///
    replace


di as result "======================================================="
di as result "DATASET DES BLOCS SAUVEGARDE"
di as result "$outputdir/ecoles_blocs_locked.dta"
di as result "======================================================="


*======================================================================*
* FIN SECTIONS 3-4
*======================================================================*

*======================================================================*
* 5. RANDOMIZATION OF THE THREE TREATMENT ARMS
*======================================================================*
*
* Treatment is randomized INSIDE each final block.
*
* Arms:
*
*   1 = Control
*   2 = Salience
*   3 = Salience + Implementation
*
* Each block receives approximately equal numbers of schools.
*
* REPRODUCIBILITY NOTE: the dataset is sorted by the fixed,
* content-independent key id_infra IMMEDIATELY before the seeded
* runiform() call, since runiform() assigns numbers by physical row
* order in memory. This guarantees that re-running this section (or
* the whole do-file) on any machine, at any time, with the same seed,
* reproduces an IDENTICAL allocation.
*
*======================================================================*

isid id_infra

sort id_infra

set seed $SEED_ARMS

capture drop rand_arm

gen double rand_arm = runiform()

sort bloc rand_arm

by bloc: gen long rank_arm = _n

by bloc: gen long bloc_n_arm = _N


capture drop group3

gen byte group3 = .


* Base balanced assignment
replace group3 = ///
    mod(rank_arm - 1, $N_ARMS) + 1 ///
    if rank_arm <= ///
    floor(bloc_n_arm / $N_ARMS) * $N_ARMS


* Randomized remainder - which arm(s) receive the leftover school(s)
* is drawn randomly PER BLOCK (same seeded stream), instead of always
* defaulting to the lowest-numbered arms. This avoids a systematic,
* non-random skew accumulating across many blocks.
levelsof bloc, local(blist_arm) clean


foreach b of local blist_arm {

    quietly summarize bloc_n_arm ///
        if bloc == `b', meanonly

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

            gen double u = runiform()

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


label define arm_lbl ///
    1 "Control" ///
    2 "Salience" ///
    3 "Salience + Implementation", replace

label values group3 arm_lbl

label var group3 ///
    "Randomized treatment arm"


di as result "Treatment allocation by block:"

tab bloc group3


di as result "Overall treatment allocation:"

tab group3


*----------------------------------------------------------------------*
* Treatment balance within blocks
*----------------------------------------------------------------------*

preserve

    contract bloc group3, freq(narm)

    bysort bloc: egen narm_max = max(narm)
    bysort bloc: egen narm_min = min(narm)

    assert narm_max - narm_min <= 1

    di as result ///
        "Treatment arms balanced within every block."

restore


*----------------------------------------------------------------------*
* Reproducibility check: re-draw with the SAME seed, sorting by the
* SAME fixed key (id_infra) beforehand, and confirm an identical
* allocation.
*----------------------------------------------------------------------*

preserve

    sort id_infra

    set seed $SEED_ARMS

    gen double rand_arm_chk = runiform()

    sort bloc rand_arm_chk

    by bloc: gen long rank_chk = _n
    by bloc: gen long bloc_n_chk = _N

    gen byte group3_chk = .

    replace group3_chk = ///
        mod(rank_chk - 1, $N_ARMS) + 1 ///
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


*======================================================================*
* 6. TARGETED PARENT RANDOMIZATION
*======================================================================*
*
* Only treated schools:
*
*   group3 = 2 or 3
*
* Mother / Father randomized within block.
*
* Same reproducibility anchor (sort id_infra before the seeded draw)
* applied here as in Section 5.
*
*======================================================================*

capture drop treated

gen byte treated = ///
    inlist(group3, 2, 3)

label var treated ///
    "1 = treated school"


sort id_infra

set seed $SEED_PARENT

capture drop rand_parent

gen double rand_parent = ///
    runiform() if treated == 1


sort bloc rand_parent

by bloc: gen long rank_parent = ///
    _n if treated == 1


capture drop parent_group

gen byte parent_group = ///
    mod(rank_parent - 1, 2) + 1 ///
    if treated == 1


label define parent_lbl ///
    1 "Mother" ///
    2 "Father", replace

label values parent_group parent_lbl

label var parent_group ///
    "Targeted parent"


tab bloc parent_group ///
    if treated == 1


*----------------------------------------------------------------------*
* Reproducibility check for the parent draw
*----------------------------------------------------------------------*

preserve

    sort id_infra

    set seed $SEED_PARENT

    gen double rand_parent_chk = runiform() if treated == 1

    sort bloc rand_parent_chk

    by bloc: gen long rank_parent_chk = _n if treated == 1

    gen byte parent_group_chk = ///
        mod(rank_parent_chk - 1, 2) + 1 if treated == 1

    assert parent_group == parent_group_chk if treated == 1

    di as result "REPRODUCIBILITY CONFIRMED with seed $SEED_PARENT (rng: `c(rngstate)')."

restore


*======================================================================*
* 7. BALANCE CHECKS
*======================================================================*

di as result "======================================================="
di as result "BALANCE CHECKS"
di as result "======================================================="


* Treatment distribution by commune
tab COMMUNE group3, chi2


* Treatment distribution by size
tab size_label group3, chi2


* Covariates
local balance_vars ///
    target_enrol ///
    NBM6EME NBF6EME ///
    NBM5EME NBF5EME ///
    SALLESCLASSESTOT ///
    EXISTENCEEAU ///
    EXISTENCEELECT ///
    EXISTENCELATRINES ///
    EXISTENCEINFRASTSPORT


foreach v of local balance_vars {

    capture confirm numeric variable `v'

    if !_rc {

        di as text ///
            _newline "--- Balance: `v' ---"

        quietly regress ///
            `v' i.group3 i.bloc, ///
            vce(robust)

        testparm i.group3

    }

}


*======================================================================*
* 8. FINAL RANDOMIZATION FILE
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


*----------------------------------------------------------------------*
* Export final Excel
*----------------------------------------------------------------------*

preserve

    local milieu_admin_var ""

    capture confirm variable MILIEU_ADMIN

    if !_rc {
        local milieu_admin_var "MILIEU_ADMIN"
    }


    keep id_infra ///
         DEPARTEMENT ///
         COMMUNE ///
         ARRONDISSEMENT ///
         NOMETABLISSEMENT ///
         MILIEU ///
         `milieu_admin_var' ///
         size_label ///
         bloc ///
         group3_lbl ///
         parent_lbl2 ///
         target_enrol ///
         med_enrol


    rename size_label  size_category
    rename group3_lbl  assigned_group
    rename parent_lbl2 targeted_parent


    order ///
        id_infra ///
        DEPARTEMENT ///
        COMMUNE ///
        ARRONDISSEMENT ///
        NOMETABLISSEMENT ///
        MILIEU ///
        `milieu_admin_var' ///
        size_category ///
        bloc ///
        assigned_group ///
        targeted_parent ///
        target_enrol ///
        med_enrol


    sort bloc id_infra


    export excel using ///
        "$outputdir/randomization_final.xlsx", ///
        firstrow(variables) replace ///
        sheet("randomization")


restore


*======================================================================*
* 9. ARCHIVE FULL DATASET
*======================================================================*

save ///
    "$outputdir/randomization_final_locked_`timestamp'.dta", ///
    replace


*======================================================================*
* 10. DATA SIGNATURE / AUDIT MANIFEST
*======================================================================*

datasignature

local sig = r(datasignature)


quietly count
local n_schools = r(N)

quietly summarize bloc, meanonly
local n_blocks = r(max)


file open manifest using ///
    "$outputdir/randomization_manifest_`timestamp'.txt", ///
    write replace


file write manifest ///
    "RANDOMIZATION MANIFEST - Gender Norms RCT" _n

file write manifest ///
    "=========================================" _n

file write manifest ///
    "Date/time       : $S_DATE $S_TIME" _n

file write manifest ///
    "Stata version   : `c(stata_version)'" _n

file write manifest ///
    "RNG engine      : mt64" _n

file write manifest ///
    "SEED_BLOCKS     : $SEED_BLOCKS" _n

file write manifest ///
    "SEED_ARMS       : $SEED_ARMS" _n

file write manifest ///
    "SEED_PARENT     : $SEED_PARENT" _n

file write manifest ///
    "N schools       : `n_schools'" _n

file write manifest ///
    "N blocks        : `n_blocks'" _n

file write manifest ///
    "Minimum block   : $MIN_BLOCK_SIZE" _n

file write manifest ///
    "Size rule       : commune median" _n

file write manifest ///
    "Small rule      : <= median" _n

file write manifest ///
    "Large rule      : > median" _n

file write manifest ///
    "Cross-commune fusion : multi-hop, department-strict, multi-commune cumulation" _n

file write manifest ///
    "Checksum        : `sig'" _n

file write manifest ///
    "Final Excel     : randomization_final.xlsx" _n

file close manifest


*======================================================================*
* 11. FINAL OUTPUT
*======================================================================*

di as result "======================================================="
di as result "RANDOMIZATION COMPLETE"
di as result "======================================================="

di as result ///
    "Final randomization:"
di as result ///
    "$outputdir/randomization_final.xlsx"

di as result ///
    "Locked dataset:"
di as result ///
    "$outputdir/randomization_final_locked_`timestamp'.dta"

di as result ///
    "Block dataset:"
di as result ///
    "$outputdir/ecoles_blocs_locked.dta"

di as result ///
    "Fusion log:"
di as result ///
    "$outputdir/log_fusion_strates.xlsx"

di as result ///
    "Manifest:"
di as result ///
    "$outputdir/randomization_manifest_`timestamp'.txt"

di as result "======================================================="

log close
