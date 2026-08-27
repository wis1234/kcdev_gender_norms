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
global SEED_FUSION 20260802   // seed for selecting WHICH specific schools
                               // a self-sufficient donor commune lends to
                               // an undersized neighbour (see Section 3B)

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


*======================================================================*
* 3B-3G. CONSTRUCTION DES POOLS / BLOCS DE RANDOMISATION
*======================================================================*
*
* LOGIQUE :
*
* 1. Toute commune avec >= 6 ecoles reste autonome par defaut.
*
* 2. Une commune avec < 6 ecoles est une commune RECEVEUSE.
*
* 3. Une commune donneuse ne peut preter que son SURPLUS au-dessus
*    du nombre entier de blocs de 6 qu'elle peut conserver.
*
*       N = 6   -> reserve 6  -> surplus 0
*       N = 7   -> reserve 6  -> surplus 1
*       N = 8   -> reserve 6  -> surplus 2
*       N = 11  -> reserve 6  -> surplus 5
*       N = 12  -> reserve 12 -> surplus 0
*       N = 13  -> reserve 12 -> surplus 1
*       N = 19  -> reserve 18 -> surplus 1
*
* 4. Le donneur est choisi selon la plus courte distance cumulative
*    entre communes, calculee a partir du fichier des communes
*    limitrophes.
*
* 5. La distance cumulative est calculee par Floyd-Warshall,
*    directement en Stata (PAS de Mata).
*
* 6. La frontiere Atlantique/Zou est stricte :
*    aucune arete n'est creee entre deux departements differents.
*    Aucun chemin multi-sauts ne peut donc traverser le departement.
*
* 7. Plusieurs donneurs peuvent contribuer a une meme commune
*    receveuse.
*
* 8. Si aucun surplus n'est disponible, une fusion COMPLETE est
*    effectuee avec le pool/commune le plus proche jusqu'a atteindre
*    au moins 6 ecoles.
*
* 9. Lors d'un pret, seules les ecoles effectivement pretees sont
*    deplacees vers le pool receveur. Les autres ecoles du donneur
*    restent dans le pool du donneur.
*
*======================================================================*


*----------------------------------------------------------------------*
* 3B. VERIFICATIONS INITIALES
*----------------------------------------------------------------------*

di as result "======================================================="
di as result "CONSTRUCTION DES POOLS DE RANDOMISATION"
di as result "======================================================="

describe COMMUNE size_label target_enrol med_enrol

isid id_infra


foreach v in COMMUNE size_label target_enrol {

    capture confirm variable `v'

    if _rc {

        di as error ///
            "Variable `v' absente de ecoles_size_classified.dta."

        exit 111
    }
}


quietly count if !inlist(size_label,"Small","Large")

if r(N) > 0 {

    di as error ///
        "`r(N)' ecoles ont un size_label invalide."

    tab size_label, missing

    exit 459
}


*----------------------------------------------------------------------*
* 3C. SI DES POOLS EXISTENT DEJA, ON LES CONSERVE
*----------------------------------------------------------------------*

capture confirm variable commune_bloc

if !_rc {

    di as result ///
        "commune_bloc existe deja : les pools existants sont conserves."

    capture confirm numeric variable commune_bloc

    if _rc {

        di as error ///
            "commune_bloc existe mais n'est pas numerique."

        exit 109
    }

    capture confirm variable commune_bloc_label

    if _rc {

        gen str120 commune_bloc_label = ""

        levelsof commune_bloc, local(existing_pools)

        foreach p of local existing_pools {

            quietly levelsof COMMUNE ///
                if commune_bloc == `p', ///
                local(clist) clean

            local clabel : subinstr local clist ///
                " " " + ", all

            replace commune_bloc_label = ///
                "`clabel'" ///
                if commune_bloc == `p'
        }
    }

}


else {


    *==================================================================*
    * 3C-1. INITIALISATION
    *==================================================================*

    gen str120 commune_bloc_label = COMMUNE

    bysort COMMUNE: gen long pool_N0 = _N


    *------------------------------------------------------------------*
    * Nombre de communes
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


    di as result ///
        "Nombre de communes presentes : `nC'"


    *==================================================================*
    * 3C-2. TAILLE INITIALE ET RESERVE DE CHAQUE COMMUNE
    *==================================================================*

    forvalues i = 1/`nC' {

        quietly count if COMMUNE == "`comm_`i''"

        local size_`i' = r(N)

        local current_`i' = `size_`i''

        *--------------------------------------------------------------*
        * Nombre d'ecoles que la commune doit conserver pour elle-meme
        *
        * Exemples :
        *   6  -> 6
        *   7  -> 6
        *   8  -> 6
        *   11 -> 6
        *   12 -> 12
        *   13 -> 12
        *   19 -> 18
        *
        * Une commune < 6 n'est pas donneuse.
        *--------------------------------------------------------------*

        if `size_`i'' >= $MIN_BLOCK_SIZE {

            local reserve_`i' = ///
                floor(`size_`i'' / $MIN_BLOCK_SIZE) * ///
                $MIN_BLOCK_SIZE

        }

        else {

            local reserve_`i' = 0

        }

        local surplus_`i' = ///
            `current_`i'' - `reserve_`i''

        local contrib_`i' ""
        local given_`i' ""

        di as text ///
            "  `comm_`i'' : N=`size_`i'' ; reserve=`reserve_`i'' ; surplus=`surplus_`i''"
    }


    *==================================================================*
    * 3C-3. DETECTION DES COMMUNES SOUS LE MINIMUM
    *==================================================================*

    local n_need = 0

    forvalues i = 1/`nC' {

        if `current_`i'' < $MIN_BLOCK_SIZE {

            local n_need = `n_need' + 1
        }
    }


    if `n_need' == 0 {

        di as result ///
            "Toutes les communes ont au moins $MIN_BLOCK_SIZE ecoles."

    }


    else {

        di as result ///
            "`n_need' commune(s) ont moins de $MIN_BLOCK_SIZE ecoles."



        *==============================================================*
        * 3C-4. LECTURE DU FICHIER DES DISTANCES
        *==============================================================*

        capture confirm file "$neighbor_csv"

        if _rc {

            di as error ///
                "Fichier de voisinage introuvable :"

            di as error ///
                "$neighbor_csv"

            exit 601
        }


        local nE = 0

        preserve

            import delimited using ///
                "$neighbor_csv", ///
                varnames(1) case(preserve) clear

            capture confirm variable Commune_Principale

            if _rc {

                di as error ///
                    "Variable Commune_Principale absente du fichier de voisinage."

                restore

                exit 111
            }


            capture confirm variable Commune_Limitrophe

            if _rc {

                di as error ///
                    "Variable Commune_Limitrophe absente du fichier de voisinage."

                restore

                exit 111
            }


            capture confirm variable Distance_Centroides_KM

            if _rc {

                di as error ///
                    "Variable Distance_Centroides_KM absente du fichier de voisinage."

                restore

                exit 111
            }


            rename Commune_Principale COMMUNE
            rename Commune_Limitrophe neighbor_COMMUNE
            rename Distance_Centroides_KM dist_km


            replace COMMUNE = ///
                strtrim(stritrim(upper(COMMUNE)))

            replace neighbor_COMMUNE = ///
                strtrim(stritrim(upper(neighbor_COMMUNE)))


            local nE = _N


            forvalues e = 1/`nE' {

                local efrom_`e' = COMMUNE[`e']
                local eto_`e'   = neighbor_COMMUNE[`e']
                local edist_`e' = dist_km[`e']
            }

        restore


        di as result ///
            "Nombre d'aretes de voisinage lues : `nE'"



        *==============================================================*
        * 3C-5. MATRICE DES DISTANCES DIRECTES
        *==============================================================*
        *
        * 1e9 = aucune connexion connue.
        *
        * Les connexions entre departements differents sont
        * volontairement interdites.
        *
        *==============================================================*

        tempname D

        matrix `D' = ///
            J(`nC', `nC', 1000000000)

        forvalues i = 1/`nC' {

            matrix `D'[`i',`i'] = 0
        }


        forvalues e = 1/`nE' {

            local fi = .
            local tj = .

            forvalues i = 1/`nC' {

                if "`comm_`i''" == "`efrom_`e''" {

                    local fi = `i'
                }

                if "`comm_`i''" == "`eto_`e''" {

                    local tj = `i'
                }
            }


            if `fi' < . & `tj' < . {

                *------------------------------------------------------*
                * CONTRAINTE DEPARTEMENTALE STRUCTURELLE
                *------------------------------------------------------*

                if "`dept_`fi''" == "`dept_`tj''" {

                    local dnew = `edist_`e''

                    if `dnew' < . {

                        local dold = ///
                            el(`D',`fi',`tj')

                        if `dnew' < `dold' {

                            matrix `D'[`fi',`tj'] = `dnew'
                            matrix `D'[`tj',`fi'] = `dnew'
                        }
                    }
                }
            }
        }



        *==============================================================*
        * 3C-6. FLOYD-WARSHALL
        *==============================================================*
        *
        * Transforme les distances directes en distances cumulatives
        * les plus courtes entre toutes les communes du MEME
        * departement.
        *
        * Aucun passage Atlantique -> Zou n'est possible.
        *
        *==============================================================*

        di as result ///
            "Calcul des distances cumulatives multi-sauts..."


        forvalues k = 1/`nC' {

            forvalues i = 1/`nC' {

                local dik = el(`D',`i',`k')

                if `dik' < 1000000000 {

                    forvalues j = 1/`nC' {

                        local dkj = el(`D',`k',`j')

                        if `dkj' < 1000000000 {

                            local dij = el(`D',`i',`j')

                            local alt = `dik' + `dkj'

                            if `alt' < `dij' {

                                matrix `D'[`i',`j'] = `alt'
                            }
                        }
                    }
                }
            }
        }


        di as result ///
            "Distances cumulatives calculees."



        *==============================================================*
        * 3C-7. PRETS DE SURPLUS
        *==============================================================*
        *
        * Chaque commune < 6 cherche successivement le donneur
        * disponible le plus proche.
        *
        * Plusieurs donneurs peuvent etre utilises.
        *
        *==============================================================*

        di as result "-------------------------------------------------------"
        di as result "PHASE 1 : PRETS DE SURPLUS"
        di as result "-------------------------------------------------------"


        forvalues i = 1/`nC' {

            while `current_`i'' < $MIN_BLOCK_SIZE {

                local best_j = 0
                local best_dist = 1000000000


                forvalues j = 1/`nC' {

                    if `j' != `i' {

                        local dij = el(`D',`i',`j')


                        *--------------------------------------------------*
                        * Le donneur doit :
                        *
                        * 1. etre accessible dans le meme departement
                        * 2. avoir un surplus reel
                        * 3. ne pas etre la commune receveuse
                        *--------------------------------------------------*

                        local available = ///
                            `current_`j'' - `reserve_`j''


                        if `dij' < 1000000000 & ///
                           `available' > 0 {

                            if `dij' < `best_dist' {

                                local best_dist = `dij'
                                local best_j = `j'
                            }
                        }
                    }
                }


                *----------------------------------------------------------*
                * Aucun donneur disponible
                *----------------------------------------------------------*

                if `best_j' == 0 {

                    continue, break
                }


                *----------------------------------------------------------*
                * Nombre d'ecoles necessaires
                *----------------------------------------------------------*

                local needed = ///
                    $MIN_BLOCK_SIZE - `current_`i''


                *----------------------------------------------------------*
                * Surplus reel du donneur
                *----------------------------------------------------------*

                local available = ///
                    `current_`best_j'' - ///
                    `reserve_`best_j''


                local amount = min(`needed',`available')


                if `amount' <= 0 {

                    continue, break
                }


                *----------------------------------------------------------*
                * Mise a jour des tailles
                *----------------------------------------------------------*

                local current_`i' = ///
                    `current_`i'' + `amount'

                local current_`best_j' = ///
                    `current_`best_j'' - `amount'


                *----------------------------------------------------------*
                * Enregistrer la contribution
                *
                * Format :
                *
                *   donneur_index:quantite
                *
                *----------------------------------------------------------*

                local contrib_`i' = ///
                    "`contrib_`i'' `best_j':`amount'"


                local given_`best_j' = ///
                    "`given_`best_j'' `i':`amount'"


                di as result ///
                    "  PRET : `comm_`best_j'' -> `comm_`i'' ; " ///
                    "`amount' ecole(s) ; distance cumulative = " ///
                    %9.2f `best_dist' " km"
            }

            *--------------------------------------------------------------*
            * FIX 4: commune `i' started below the minimum (reserve_`i'
            * was 0). If it just reached $MIN_BLOCK_SIZE via loans, its
            * reserve must be updated to match its new current size -
            * otherwise a LATER commune processed in this same forvalues
            * pass could wrongly treat `i' as a donor with phantom
            * surplus ( = current_`i' - reserve_`i' = current_`i' - 0 ),
            * re-lending schools `i' only just received/kept, without
            * `i' ever being re-checked against the minimum again.
            *--------------------------------------------------------------*
            if `size_`i'' < $MIN_BLOCK_SIZE {

                local reserve_`i' = `current_`i''
            }
        }



        *==============================================================*
        * 3C-8. VERIFICATION APRES PRETS
        *==============================================================*

        di as result "-------------------------------------------------------"
        di as result "TAILLES APRES PRETS"
        di as result "-------------------------------------------------------"


        local n_unresolved = 0

        forvalues i = 1/`nC' {

            di as text ///
                "  `comm_`i'' : `current_`i'' ecoles"

            if `current_`i'' < $MIN_BLOCK_SIZE {

                local n_unresolved = ///
                    `n_unresolved' + 1
            }
        }



        *==============================================================*
        * 3C-9. FUSION COMPLETE DE SECOURS
        *==============================================================*
        *
        * Si une commune reste < 6 apres epuisement des surplus,
        * on forme un pool complet avec la commune/pool le plus proche.
        *
        * La distance entre deux pools est la plus petite distance
        * cumulative entre deux communes appartenant aux pools.
        *
        *==============================================================*

        if `n_unresolved' > 0 {

            di as result "-------------------------------------------------------"
            di as result "PHASE 2 : FUSION COMPLETE DE SECOURS"
            di as result "-------------------------------------------------------"


            *----------------------------------------------------------*
            * Initialisation union-find
            *----------------------------------------------------------*

            forvalues i = 1/`nC' {

                local uf_parent_`i' = `i'
                local uf_total_`i'  = `current_`i''
            }


            *----------------------------------------------------------*
            * Fonction logique de recherche de racine
            *
            * On utilise des locals Stata plutot que Mata.
            *----------------------------------------------------------*

            local fusion_progress = 1


            while `fusion_progress' == 1 {

                local fusion_progress = 0


                *------------------------------------------------------*
                * Chercher UNE racine encore sous 6
                *------------------------------------------------------*

                local target_root = 0

                forvalues i = 1/`nC' {

                    local ri = `i'

                    while `uf_parent_`ri'' != `ri' {

                        local ri = `uf_parent_`ri''
                    }


                    if `uf_total_`ri'' < $MIN_BLOCK_SIZE {

                        local target_root = `ri'

                        continue, break
                    }
                }


                *------------------------------------------------------*
                * S'il n'y a plus de cluster insuffisant : FIN
                *------------------------------------------------------*

                if `target_root' == 0 {

                    continue, break
                }


                *------------------------------------------------------*
                * Chercher le cluster le plus proche
                *------------------------------------------------------*

                local best_root = 0
                local best_dist = 1000000000


                forvalues j = 1/`nC' {

                    local rj = `j'

                    while `uf_parent_`rj'' != `rj' {

                        local rj = `uf_parent_`rj''
                    }


                    if `rj' != `target_root' {

                        *--------------------------------------------------*
                        * Departement du cluster cible
                        *--------------------------------------------------*

                        local target_dept = ""

                        forvalues x = 1/`nC' {

                            local rx = `x'

                            while `uf_parent_`rx'' != `rx' {

                                local rx = `uf_parent_`rx''
                            }

                            if `rx' == `target_root' {

                                local target_dept ///
                                    "`dept_`x''"

                                continue, break
                            }
                        }


                        *--------------------------------------------------*
                        * Departement du cluster candidat
                        *--------------------------------------------------*

                        local candidate_dept = ""

                        forvalues x = 1/`nC' {

                            local rx = `x'

                            while `uf_parent_`rx'' != `rx' {

                                local rx = `uf_parent_`rx''
                            }

                            if `rx' == `rj' {

                                local candidate_dept ///
                                    "`dept_`x''"

                                continue, break
                            }
                        }


                        *--------------------------------------------------*
                        * STRICTEMENT MEME DEPARTEMENT
                        *--------------------------------------------------*

                        if "`target_dept'" == "`candidate_dept'" {

                            *------------------------------------------------*
                            * Distance minimale entre les deux clusters
                            *------------------------------------------------*

                            forvalues a = 1/`nC' {

                                local ra = `a'

                                while `uf_parent_`ra'' != `ra' {

                                    local ra = `uf_parent_`ra''
                                }

                                if `ra' == `target_root' {

                                    forvalues b = 1/`nC' {

                                        local rb = `b'

                                        while `uf_parent_`rb'' != `rb' {

                                            local rb = `uf_parent_`rb''
                                        }

                                        if `rb' == `rj' {

                                            local dab = ///
                                                el(`D',`a',`b')

                                            if `dab' < `best_dist' {

                                                local best_dist = `dab'
                                                local best_root = `rj'
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }


                *------------------------------------------------------*
                * Aucun cluster compatible
                *------------------------------------------------------*

                if `best_root' == 0 {

                    continue, break
                }


                *------------------------------------------------------*
                * Fusion
                *------------------------------------------------------*

                local new_total = ///
                    `uf_total_`target_root'' + ///
                    `uf_total_`best_root''


                local uf_parent_`best_root' = `target_root'

                local uf_total_`target_root' = ///
                    `new_total'


                local fusion_progress = 1


                di as result ///
                    "  FUSION COMPLETE : cluster `target_root' + " ///
                    "cluster `best_root' ; taille finale = " ///
                    "`new_total' ; distance = " ///
                    %9.2f `best_dist' " km"
            }



            *==========================================================*
            * 3C-10. RESOLUTION FINALE DES RACINES
            *==========================================================*

            forvalues i = 1/`nC' {

                local ri = `i'

                while `uf_parent_`ri'' != `ri' {

                    local ri = `uf_parent_`ri''
                }

                local final_root_`i' = `ri'
            }


            *==========================================================*
            * 3C-11. VERIFICATION DES CLUSTERS
            *==========================================================*

            local any_unresolved = 0

            forvalues i = 1/`nC' {

                if `final_root_`i'' == `i' {

                    if `uf_total_`i'' < $MIN_BLOCK_SIZE {

                        local any_unresolved = 1

                        di as error ///
                            "POOL INSUFFISANT : `comm_`i'' ; " ///
                            "`uf_total_`i'' ecoles"
                    }
                }
            }


            if `any_unresolved' == 1 {

                di as error "======================================================="
                di as error ///
                    "IMPOSSIBLE DE FORMER DES POOLS D'AU MOINS " ///
                    "$MIN_BLOCK_SIZE ECOLES."
                di as error "======================================================="


                preserve

                    keep if pool_N0 < $MIN_BLOCK_SIZE

                    keep COMMUNE DEPARTEMENT pool_N0

                    duplicates drop

                    export excel using ///
                        "$outputdir/communes_needing_cross_fusion.xlsx", ///
                        firstrow(variables) replace

                restore

                exit 198
            }



            *==========================================================*
            * 3C-12. LABEL DES FUSIONS COMPLETES
            *==========================================================*

            forvalues r = 1/`nC' {

                local root_members ""

                local root_exists = 0


                forvalues i = 1/`nC' {

                    if `final_root_`i'' == `r' {

                        local root_exists = 1

                        local root_members ///
                            "`root_members' `comm_`i''"
                    }
                }


                if `root_exists' == 1 {

                    local root_members : list sort root_members

                    local root_label : ///
                        subinstr local root_members ///
                        " " " + ", all


                    forvalues i = 1/`nC' {

                        if `final_root_`i'' == `r' {

                            quietly replace ///
                                commune_bloc_label = ///
                                "`root_label'" ///
                                if COMMUNE == "`comm_`i''"
                        }
                    }


                    if strpos("`root_label'"," + ") > 0 {

                        di as result ///
                            "  Pool fusionne : `root_label' " ///
                            "(`uf_total_`r'' ecoles)"
                    }
                }
            }
        }



        *==============================================================*
* 3C-13. ATTRIBUTION DES ECOLES PRETEES
*==============================================================*
*
* Les tailles calculees en Phase 1 sont maintenant traduites
* en observations reelles.
*
* IMPORTANT :
*   Le receiver_label DOIT etre reconstruit pour chaque commune
*   receveuse dans la boucle d'attribution.
*
*   Sinon, Stata conserve le dernier receiver_label cree et peut
*   attribuer une ecole pretee au mauvais pool.
*
*==============================================================*

di as result "-------------------------------------------------------"
di as result "PHASE 3 : ATTRIBUTION DES ECOLES PRETEES"
di as result "-------------------------------------------------------"


*--------------------------------------------------------------*
* Initialisation
*--------------------------------------------------------------*

set seed $SEED_FUSION

capture drop _rand_fusion
gen double _rand_fusion = runiform()

capture drop _claimed_fusion
gen byte _claimed_fusion = 0


*--------------------------------------------------------------*
* ETAPE 1 :
* Construire les labels des pools receveurs
*
* Chaque commune receveuse conserve ses propres ecoles
* et recevra ensuite les ecoles pretees.
*--------------------------------------------------------------*

forvalues i = 1/`nC' {

    if "`contrib_`i''" != "" {

        *------------------------------------------------------*
        * Construire explicitement le label du RECEVEUR i
        *------------------------------------------------------*

        local members "`comm_`i''"

        foreach contribution of local contrib_`i' {

            local colon = strpos("`contribution'",":")

            local jidx = ///
                substr("`contribution'",1,`colon'-1)

            local members ///
                "`members' `comm_`jidx''"
        }

        local members : list sort members

        local receiver_label = ///
            subinstr("`members'"," "," + ",.)
        * FIX 2: subinstr() as a function needs a numeric replacement
        * count ("." = replace all), not the word "all" (that syntax
        * only applies to the ": subinstr local ..." macro-extended
        * function form). The bareword caused "all not found" / r(111).

        *------------------------------------------------------*
        * Appliquer le label aux ecoles ORIGINAIRES du receveur
        *------------------------------------------------------*

        quietly replace ///
            commune_bloc_label = ///
            "`receiver_label'" ///
            if COMMUNE == "`comm_`i''"

        di as result ///
            "  Pool par pret : `receiver_label' " ///
            "(`current_`i'' ecoles)"
    }
}


*--------------------------------------------------------------*
* ETAPE 2 :
* Tirer les ecoles pretees chez chaque donneur
*
* IMPORTANT :
* receiver_label est reconstruit A L'INTERIEUR de cette boucle.
* Il ne peut donc plus rester celui du dernier receveur.
*--------------------------------------------------------------*

forvalues i = 1/`nC' {

    if "`contrib_`i''" != "" {

        *------------------------------------------------------*
        * RECONSTRUIRE LE LABEL DU RECEVEUR i
        *------------------------------------------------------*

        local members "`comm_`i''"

        foreach contribution of local contrib_`i' {

            local colon = strpos("`contribution'",":")

            local jidx = ///
                substr("`contribution'",1,`colon'-1)

            local members ///
                "`members' `comm_`jidx''"
        }

        local members : list sort members

        local receiver_label = ///
            subinstr("`members'"," "," + ",.)
        * FIX 2 (same issue as above, second occurrence)


        *------------------------------------------------------*
        * Parcourir les donneurs de CE receveur
        *------------------------------------------------------*

        foreach contribution of local contrib_`i' {

            local colon = strpos("`contribution'",":")

            local jidx = ///
                substr("`contribution'",1,`colon'-1)

            local amount = ///
                substr("`contribution'",`colon'+1,.)


            local donor_name = ///
                "`comm_`jidx''"


            *--------------------------------------------------*
            * Selection aleatoire des ecoles du donneur
            * encore disponibles
            *--------------------------------------------------*

            preserve

                quietly keep if ///
                    COMMUNE == "`donor_name'" & ///
                    _claimed_fusion == 0

                quietly sort _rand_fusion

                quietly count

                local n_available = r(N)


                *--------------------------------------------------*
                * Verification de securite
                *--------------------------------------------------*

                if `n_available' < `amount' {

                    restore

                    di as error ///
                        "======================================================="

                    di as error ///
                        "ERREUR : pas assez d'ecoles disponibles chez " ///
                        "`donor_name'."

                    di as error ///
                        "Demandes : `amount'"

                    di as error ///
                        "Disponibles : `n_available'"

                    di as error ///
                        "Receveur : `receiver_label'"

                    di as error ///
                        "======================================================="

                    exit 459
                }


                *--------------------------------------------------*
                * Garder exactement le nombre d'ecoles necessaire
                *--------------------------------------------------*

                quietly keep in 1/`amount'

                quietly keep id_infra

                tempfile selected_ids

                quietly save ///
                    `selected_ids', replace

            restore


            *--------------------------------------------------*
            * Identifier les ecoles selectionnees
            *--------------------------------------------------*

            quietly merge 1:1 id_infra using ///
                `selected_ids', ///
                gen(_fusion_match)


            *--------------------------------------------------*
            * ATTRIBUTION AU BON RECEVEUR
            *
            * Ici receiver_label correspond obligatoirement
            * a commune i actuellement traitee.
            *--------------------------------------------------*

            quietly replace ///
                commune_bloc_label = ///
                "`receiver_label'" ///
                if _fusion_match == 3


            *--------------------------------------------------*
            * Marquer les ecoles deja pretees
            *--------------------------------------------------*

            quietly replace ///
                _claimed_fusion = 1 ///
                if _fusion_match == 3


            quietly drop _fusion_match


            di as result ///
                "  ATTRIBUTION : `donor_name' -> `receiver_label' ; " ///
                "`amount' ecole(s)"

        }
    }
}


*==============================================================*
* FIN 3C-13
*==============================================================*
        *==============================================================*
        * 3C-14. ATTRIBUTION DES FUSIONS COMPLETES
        *==============================================================*
        *
        * Les observations encore non reclamees appartenant a un
        * cluster fallback recoivent le label du cluster.
        *
        *==============================================================*

        forvalues r = 1/`nC' {

            local root_exists = 0
            local root_members ""


            forvalues i = 1/`nC' {

                if "`final_root_`i''" != "" {

                    if `final_root_`i'' == `r' {

                        local root_exists = 1

                        local root_members ///
                            "`root_members' `comm_`i''"
                    }
                }
            }


            if `root_exists' == 1 {

                local root_members : list sort root_members

                local root_label : ///
                    subinstr local root_members ///
                    " " " + ", all


                *------------------------------------------------------*
                * Une fusion complete est appliquee seulement si elle
                * concerne plusieurs communes.
                *------------------------------------------------------*

                if strpos("`root_label'"," + ") > 0 {

                    foreach cc of local root_members {

                        quietly replace ///
                            commune_bloc_label = ///
                            "`root_label'" ///
                            if COMMUNE == "`cc'" & ///
                               _claimed_fusion == 0
                    }
                }
            }
        }



        *--------------------------------------------------------------*
        * Nettoyage
        *--------------------------------------------------------------*

        drop _rand_fusion _claimed_fusion


        capture drop pool_N0



        *==============================================================*
        * 3C-15. LOG DES FUSIONS
        *==============================================================*

        preserve

            keep if strpos(commune_bloc_label," + ") > 0

            quietly count

            if r(N) > 0 {

                duplicates drop commune_bloc_label, force

                keep commune_bloc_label

                gen str40 fusion_type = ///
                    "cross-commune automated"

                gen str20 fusion_date = "$S_DATE"

                export excel using ///
                    "$outputdir/log_fusion_strates.xlsx", ///
                    firstrow(variables) replace ///
                    sheet("cross_commune")

                di as result ///
                    "Log des fusions exporte : log_fusion_strates.xlsx"
            }

        restore
    }


    *==================================================================*
    * 3C-16. IDENTIFIANT NUMERIQUE FINAL DES POOLS
    *==================================================================*

    capture drop commune_bloc

    egen long commune_bloc = ///
        group(commune_bloc_label)


    label var commune_bloc ///
        "Final commune/pool identifier"

}
* <-- FIX 1: this closing brace was missing, so everything from 3D
*     onward was previously nested (unterminated) inside the
*     "else" branch opened at "capture confirm variable commune_bloc".


*----------------------------------------------------------------------*
* 3D. VERIFICATION DES POOLS
*----------------------------------------------------------------------*

di as result "======================================================="
di as result "COMPOSITION DES POOLS"
di as result "======================================================="


bysort commune_bloc: gen long pool_N = _N


preserve

    contract commune_bloc commune_bloc_label ///
        size_label, freq(n)


    reshape wide n, ///
        i(commune_bloc commune_bloc_label) ///
        j(size_label) string


    capture confirm variable nSmall

    if _rc {

        gen nSmall = 0
    }


    capture confirm variable nLarge

    if _rc {

        gen nLarge = 0
    }


    replace nSmall = 0 if missing(nSmall)
    replace nLarge = 0 if missing(nLarge)


    gen pool_total = ///
        nSmall + nLarge


    order ///
        commune_bloc ///
        commune_bloc_label ///
        nLarge ///
        nSmall ///
        pool_total


    sort commune_bloc


    list, noobs sep(0)

restore



*----------------------------------------------------------------------*
* 3E. VERIFICATION ABSOLUE DE LA TAILLE DES POOLS
*----------------------------------------------------------------------*

quietly count if pool_N < $MIN_BLOCK_SIZE


if r(N) > 0 {

    di as error "======================================================="
    di as error ///
        "`r(N)' ecoles appartiennent encore a un pool de moins de " ///
        "$MIN_BLOCK_SIZE ecoles."
    di as error "======================================================="


    preserve

        keep if pool_N < $MIN_BLOCK_SIZE

        keep ///
            commune_bloc ///
            commune_bloc_label ///
            COMMUNE ///
            DEPARTEMENT ///
            pool_N


        duplicates drop

        list, noobs sep(0)


        export excel using ///
            "$outputdir/pools_below_minimum.xlsx", ///
            firstrow(variables) replace

    restore


    di as error ///
        "La construction des pools ne peut pas continuer."

    exit 459
}


di as result ///
    "VERIFICATION OK : tous les pools ont au moins " ///
    "$MIN_BLOCK_SIZE ecoles."



*----------------------------------------------------------------------*
* 3F. CONTROLE DE L'INTEGRITE DES ECOLES
*----------------------------------------------------------------------*

quietly count

local n_total_schools = r(N)


quietly count if missing(commune_bloc)

if r(N) > 0 {

    di as error ///
        "`r(N)' ecoles n'ont pas de commune_bloc."

    exit 459
}


quietly count if missing(commune_bloc_label)

if r(N) > 0 {

    di as error ///
        "`r(N)' ecoles n'ont pas de commune_bloc_label."

    exit 459
}


isid id_infra


di as result ///
    "VERIFICATION OK : `n_total_schools' ecoles sont affectees a un pool."



*----------------------------------------------------------------------*
* 3G. RESUME FINAL DES POOLS
*----------------------------------------------------------------------*

di as result "======================================================="
di as result "RESUME FINAL DES POOLS"
di as result "======================================================="


preserve

    contract ///
        commune_bloc ///
        commune_bloc_label, ///
        freq(pool_size)


    sort commune_bloc


    list ///
        commune_bloc ///
        commune_bloc_label ///
        pool_size, ///
        noobs sep(0)

restore


quietly summarize pool_N, meanonly


local pool_min = r(min)
local pool_max = r(max)
local pool_mean = r(mean)


local pool_mean_fmt : ///
    display %9.2f `pool_mean'

local pool_mean_fmt = ///
    trim("`pool_mean_fmt'")


di as result ///
    "Nombre de pools : " ///
    `: word count `=string(1)''


quietly levelsof commune_bloc, local(final_pool_list)

local n_final_pools : word count `final_pool_list'


di as result ///
    "Nombre de pools : `n_final_pools'"


di as result ///
    "Taille minimale : `pool_min'"


di as result ///
    "Taille maximale : `pool_max'"


di as result ///
    "Taille moyenne  : `pool_mean_fmt'"


di as result "======================================================="
di as result "CONSTRUCTION DES POOLS TERMINEE"
di as result "======================================================="

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

* FIX 3: this whole 3D/3E block duplicates the pool-verification logic
* run just above. Since pool_N was already created there, regenerating
* it here without dropping it first used to fail with "pool_N already
* defined" (r(110)). Guarding with "capture drop" makes the (redundant)
* second pass harmless.
capture drop pool_N
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

sort id_infra

set seed $SEED_BLOCKS

capture drop rand_block

gen double rand_block = runiform()


*======================================================================*
* 4B. CONSTRUCTION DES RANGS SMALL ET LARGE
*======================================================================*

capture drop rank_small
capture drop rank_large
capture drop block_number


gen long rank_small = .
gen long rank_large = .


sort commune_bloc size_label rand_block

by commune_bloc: gen long _rank_tmp = ///
    sum(size_label=="Small")

replace rank_small = _rank_tmp ///
    if size_label=="Small"

drop _rank_tmp


sort commune_bloc size_label rand_block

by commune_bloc: gen long _rank_tmp = ///
    sum(size_label=="Large")

replace rank_large = _rank_tmp ///
    if size_label=="Large"

drop _rank_tmp


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

gen long block_number = .


levelsof commune_bloc, local(pool_list)


foreach p of local pool_list {

    quietly summarize n_blocks_pool ///
        if commune_bloc==`p', meanonly

    local nb = r(max)


    *--------------------------------------------------------------*
    * SMALL - forward cycle: 1 -> 2 -> ... -> nb -> 1 -> ...
    *--------------------------------------------------------------*

    replace block_number = ///
        mod(rank_small - 1, `nb') + 1 ///
        if commune_bloc==`p' ///
        & size_label=="Small"


    *--------------------------------------------------------------*
    * LARGE - REVERSE cycle: nb -> nb-1 -> ... -> 1 -> nb -> ...
    *
    * Reversing Large's cycle direction (relative to Small's forward
    * cycle) makes its remainder land on the HIGH-numbered blocks
    * while Small's remainder lands on the LOW-numbered blocks, so the
    * two surpluses/deficits COMPLEMENT instead of compound - this
    * guarantees every final block reaches at least $MIN_BLOCK_SIZE.
    *--------------------------------------------------------------*

    replace block_number = ///
        `nb' - mod(rank_large - 1, `nb') ///
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

capture drop bloc

* Garde-fou explicite : si block_number n'existe pas ici, ce n'est PAS un
* bug du code - cela signifie presque toujours que le do-file a ete
* execute par fragments plutot qu'en une seule execution continue.
capture confirm variable block_number
if _rc {
    di as error "======================================================="
    di as error "ERREUR : block_number n'existe pas dans les donnees en"
    di as error "memoire a ce stade."
    di as error "======================================================="
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

local bloc_n_mean_fmt : display %9.2f r(mean)
local bloc_n_mean_fmt = trim("`bloc_n_mean_fmt'")

di as result ///
    "Moyenne : `bloc_n_mean_fmt'"


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

local mean_block_fmt : display %9.2f `mean_block'
local mean_block_fmt = trim("`mean_block_fmt'")

di as result ///
    "Taille moyenne  : `mean_block_fmt'"


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
* defaulting to the lowest-numbered arms.
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
* EXPLICIT GUARANTEE: every block (stratum) allocates AT LEAST 2 schools
* per treatment arm.
*----------------------------------------------------------------------*

preserve

    contract bloc group3, freq(narm)

    bysort bloc: egen narm_min_check = min(narm)

    quietly count if narm_min_check < 2

    if r(N) > 0 {

        di as error "======================================================="
        di as error "ERREUR : au moins un bras recoit moins de 2 ecoles dans"
        di as error "au moins un bloc (stratum)."
        di as error "======================================================="

        list bloc group3 narm if narm_min_check < 2, noobs

        di as error "Ceci ne devrait jamais arriver tant que MIN_BLOCK_SIZE"
        di as error ">= 6 et N_ARMS = 3. Verifiez que ces parametres n'ont"
        di as error "pas ete modifies, et que le tirage n'a pas ete altere."

        exit 459
    }

    di as result ///
        "Garantie confirmee : chaque bras recoit au moins 2 ecoles dans" ///
        " chaque bloc (stratum)."

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


* NOTE : ce tableau est INFORMATIONNEL uniquement. COMMUNE n'est PAS
* l'unite de randomisation des lors qu'une fusion cross-commune a eu
* lieu - une commune fusionnee peut legitimement montrer une
* repartition inegale par bras alors que son BLOC parent est
* parfaitement equilibre.
tab COMMUNE group3, chi2


tab size_label group3, chi2


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
    "SEED_FUSION     : $SEED_FUSION" _n

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
    "Cross-commune fusion : surplus-lending (Mata), department-strict, fallback full-merge" _n

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