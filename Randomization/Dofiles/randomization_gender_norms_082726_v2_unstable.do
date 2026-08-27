*======================================================================*
* PROJECT     : Gender Norms RCT - Randomization of Schools
* PURPOSE     : Stratified block randomization
* VERSION     : v3 - revised per PI review (Mahounan)
*
* v3 CHANGELOG (par rapport a v2) :
*   - CORRECTIF Section 6 : l'ecole "excedentaire" d'une cellule
*     (bloc x bras) de taille impaire etait TOUJOURS attribuee a la
*     Mere (biais systematique : 36 Mere / 14 Pere observe dans le
*     bras Salience au lieu de 25/25). Elle est desormais attribuee
*     par un tirage aleatoire 50/50 independant par cellule, comme
*     deja fait pour le reste des bras de traitement en Section 5.
*   - Ajout d'un controle explicite du 50/50 GLOBAL par bras traite
*     (et pas seulement cellule par cellule) en Section 6.
*   - Commentaires enrichis, chaque section renvoyant explicitement
*     au point correspondant du retour du PI (Points 1, 2 et 3).
*
* DESIGN (updated per PI review):
*
*   1. Within each commune, schools are classified Small/Large using
*      the commune median of 6eme+5eme enrolment:
*         <= commune median -> Small
*          > commune median -> Large
*
*   2. Small and Large are TWO SEPARATE STRATA. Blocks are built
*      SEPARATELY within Small and, independently, within Large, for
*      each commune. A block NEVER mixes Small and Large schools.
*      (Previously blocks were mixed and only balanced in composition;
*      this did not guarantee separate arm balance within each size
*      category, which is what the design requires.)
*
*   3. Each commune is fully AUTONOMOUS. There is NO cross-commune
*      lending or fusion of any kind. The randomization stratum is
*      strictly (COMMUNE x Small/Large).
*      (Previously undersized communes borrowed schools from, or were
*      merged with, neighbouring communes via a multi-hop distance
*      algorithm. This is removed entirely per PI instruction.)
*
*   4. Within a (COMMUNE x Small/Large) stratum, schools are grouped
*      into blocks of 6 in randomized order. If the stratum size is
*      not an exact multiple of 6, the blocks of 6 are formed first,
*      and the LAST block of that stratum simply contains whichever
*      schools remain (this last block may therefore contain fewer
*      than 6 schools). No school is ever moved to or from another
*      commune to complete this last block.
*
*   5. Treatment (Control / Salience / Salience + Implementation) is
*      randomized within each final block.
*
*   6. Within EACH treated arm SEPARATELY (Salience, and Salience +
*      Implementation) - and within each block - the targeted parent
*      (Mother/Father) is randomized 50/50. This guarantees a 50/50
*      Mother/Father split inside every treatment arm, rather than
*      only at the block level pooling both treated arms together.
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
* just silently drops whichever variable matches. Turning abbreviation
* off makes every variable reference in this do-file resolve to its
* EXACT name only, eliminating this entire bug class.
set varabbrev off

*======================================================================*
* 0. SETTINGS
*======================================================================*

cd "C:\RONALDO\CKDEV\GENDER NORMS\Randomization"

global datadir   "Datasets"
global outputdir "Outputs"

global mergeoutdir "$outputdir/Data"
global infile "$mergeoutdir/master_x_gender_norm.xlsx"

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
di as result "GENDER NORMS RCT - RANDOMIZATION (v2)"
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
* ======================================================================
* >>> POINT 2 DU RETOUR PI (Mahounan) - premiere moitie <<<
*
*   "Small et Large doivent etre de vraies strates separees. [...]
*    on separe les ecoles, dans chaque commune, en deux strates :
*    Small (<= mediane d'effectif de la commune) et Large (> mediane)."
*
* Cette classification Small/Large est produite ICI (inchangee par
* rapport a la version precedente). La partie "blocs construits
* SEPAREMENT dans chaque strate" du Point 2 est mise en oeuvre plus
* loin, en Section 3.
* ======================================================================
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
      NBF6EME + ///
     NBF5EME

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
* 3. CONSTRUCTION DES BLOCS DE RANDOMISATION (SANS FUSION INTER-COMMUNE)
*======================================================================*
*
* ======================================================================
* >>> POINT 2 DU RETOUR PI (Mahounan) - deuxieme moitie <<<
*
*   "Les blocs doivent etre construits separement a l'interieur de
*    chaque strate. Autrement dit, on construit des blocs entre
*    ecoles Small d'une meme commune, et separement des blocs entre
*    ecoles Large de cette meme commune."
*
*   => Mis en oeuvre ci-dessous via la variable "stratum_id" =
*      group(COMMUNE, size_label) : les blocs (Section 3D-3E) sont
*      TOUJOURS construits a l'interieur d'une seule et meme strate
*      (COMMUNE x Small/Large). Un bloc ne peut donc jamais melanger
*      Small et Large (verifie explicitement en 3F).
*
* >>> POINT 3 DU RETOUR PI (Mahounan) <<<
*
*   "Il ne faut pas emprunter des ecoles a d'autres communes. [...]
*    Chaque commune doit rester independante. Si une strate commune x
*    Small/Large ne contient pas exactement un multiple de 6 ecoles,
*    il faut simplement gerer le dernier bloc avec le nombre d'ecoles
*    restantes dans cette meme strate. Il ne faut pas deplacer des
*    ecoles d'une commune vers une autre."
*
*   => Toute la logique anterieure de pret/fusion inter-communes
*      (distances Floyd-Warshall, fichier de voisinage, prets de
*      surplus, fusion de secours) a ete SUPPRIMEE. La strate est
*      strictement (COMMUNE x Small/Large) et rien d'autre : un bloc
*      ne peut donc jamais melanger deux communes (verifie en 3F).
*      Le dernier bloc d'une strate recoit simplement le reste des
*      ecoles de CETTE MEME strate (Section 3D), sans jamais aller
*      chercher d'ecoles ailleurs.
*
* RESUME DE LA LOGIQUE (comme demande par le PI) :
*
*   Commune -> Small/Large -> blocs -> randomisation des 3 bras
*   (Section 5) -> randomisation Mere/Pere separement dans chacun
*   des deux bras traites (Section 6).
* ======================================================================
*
* OBJECTIF :
*
* Pour chaque strate (COMMUNE x Small/Large), construire des blocs
* d'environ 6 ecoles, en gardant CHAQUE COMMUNE STRICTEMENT AUTONOME
* (aucun pret, aucune fusion avec une autre commune) et en gardant
* Small et Large STRICTEMENT SEPARES (jamais melanges dans un bloc).
*
* Si une strate n'est pas un multiple exact de $MIN_BLOCK_SIZE, les
* blocs de 6 sont formes en premier, et le DERNIER bloc de cette
* strate recoit simplement les ecoles restantes (qui peuvent donc
* etre moins de 6). Aucune ecole ne quitte jamais sa commune.
*
*======================================================================*

use "$outputdir/ecoles_size_classified.dta", clear

isid id_infra

quietly count if !inlist(size_label,"Small","Large")

if r(N) > 0 {

    di as error ///
        "`r(N)' ecoles ont un size_label invalide."

    tab size_label, missing

    exit 459
}


*----------------------------------------------------------------------*
* 3A. IDENTIFIANT DE STRATE (commune x taille) - AUCUNE FUSION
*----------------------------------------------------------------------*

capture drop stratum_label
gen str160 stratum_label = COMMUNE + " - " + size_label

label var stratum_label ///
    "Randomization stratum (COMMUNE x Small/Large, no cross-commune fusion)"

capture drop stratum_id
egen long stratum_id = group(stratum_label)

label var stratum_id ///
    "Numeric id of stratum (COMMUNE x Small/Large)"

capture drop stratum_N
bysort stratum_id: gen long stratum_N = _N

label var stratum_N ///
    "Number of schools in this COMMUNE x Small/Large stratum"


di as result "======================================================="
di as result "STRATES COMMUNE x TAILLE"
di as result "======================================================="

preserve
    contract stratum_id stratum_label stratum_N
    sort stratum_id
    list, noobs sep(0)
restore


*----------------------------------------------------------------------*
* 3B. ORDRE ALEATOIRE DES ECOLES A L'INTERIEUR DE CHAQUE STRATE
*----------------------------------------------------------------------*

sort id_infra

set seed $SEED_BLOCKS

capture drop rand_block
gen double rand_block = runiform()


*----------------------------------------------------------------------*
* 3C. RANG DE CHAQUE ECOLE DANS SA PROPRE STRATE
*----------------------------------------------------------------------*

sort stratum_id rand_block

capture drop rank_in_stratum
by stratum_id: gen long rank_in_stratum = _n

quietly count if missing(rank_in_stratum)

if r(N) > 0 {

    di as error ///
        "`r(N)' ecoles n'ont pas de rang dans leur strate."

    exit 459
}


*----------------------------------------------------------------------*
* 3D. NUMERO DE BLOC A L'INTERIEUR DE LA STRATE
*
* Blocs pleins de $MIN_BLOCK_SIZE ecoles ; le DERNIER bloc de la
* strate recoit simplement le reste. ceil(rang / 6) produit
* exactement ce comportement, par exemple pour une strate de 19 :
*
*   rangs 1-6   -> bloc local 1  (6 ecoles)
*   rangs 7-12  -> bloc local 2  (6 ecoles)
*   rangs 13-18 -> bloc local 3  (6 ecoles)
*   rang 19     -> bloc local 4  (1 ecole - dernier bloc, reste)
*
* Aucun emprunt a une autre commune n'intervient a aucun moment.
*----------------------------------------------------------------------*

capture drop block_number_local
gen long block_number_local = ceil(rank_in_stratum / $MIN_BLOCK_SIZE)

capture drop n_blocks_stratum
bysort stratum_id: egen long n_blocks_stratum = max(block_number_local)

label var n_blocks_stratum ///
    "Number of blocks within this stratum"


*----------------------------------------------------------------------*
* 3E. IDENTIFIANT FINAL DU BLOC (commune x taille x bloc local)
*----------------------------------------------------------------------*

capture drop bloc

egen long bloc = group(stratum_id block_number_local)

label var bloc ///
    "Final randomization block (COMMUNE x Small/Large x bloc local)"

bysort bloc: gen long bloc_n = _N

label var bloc_n ///
    "Number of schools in final randomization block"


*----------------------------------------------------------------------*
* 3F. VERIFICATIONS DE COHERENCE
*----------------------------------------------------------------------*

quietly count if missing(bloc)

if r(N) > 0 {

    di as error ///
        "`r(N)' ecoles n'ont pas recu de bloc."

    exit 459
}

isid id_infra


* Un bloc ne doit jamais melanger deux communes.
sort bloc COMMUNE
capture drop _check_comm
by bloc: gen byte _check_comm = (COMMUNE[1] != COMMUNE[_N])

quietly count if _check_comm == 1

if r(N) > 0 {

    di as error ///
        "ERREUR : un bloc contient plusieurs communes."

    exit 459
}

drop _check_comm


* Un bloc ne doit jamais melanger Small et Large.
sort bloc size_label
capture drop _check_size
by bloc: gen byte _check_size = (size_label[1] != size_label[_N])

quietly count if _check_size == 1

if r(N) > 0 {

    di as error ///
        "ERREUR : un bloc melange Small et Large."

    exit 459
}

drop _check_size


di as result ///
    "VERIFICATION OK : chaque bloc appartient a UNE SEULE commune et" ///
    " a UNE SEULE strate Small/Large."


*----------------------------------------------------------------------*
* 3G. REPRODUCTIBILITE DE LA CONSTRUCTION DES BLOCS
*----------------------------------------------------------------------*

preserve

    sort id_infra

    set seed $SEED_BLOCKS

    gen double rand_block_chk = runiform()

    sort stratum_id rand_block_chk

    by stratum_id: gen long rank_chk = _n

    gen long block_chk = ceil(rank_chk / $MIN_BLOCK_SIZE)

    egen long bloc_chk = group(stratum_id block_chk)

    assert bloc == bloc_chk

    di as result ///
        "REPRODUCIBILITY CONFIRMED with seed $SEED_BLOCKS (rng: `c(rngstate)')."

restore


*----------------------------------------------------------------------*
* 3H. COMPOSITION DES BLOCS
*----------------------------------------------------------------------*

di as result "======================================================="
di as result "COMPOSITION DES BLOCS"
di as result "======================================================="

preserve
    contract bloc stratum_label block_number_local bloc_n
    sort bloc
    list, noobs sep(0)
restore


quietly summarize bloc_n, meanonly

di as result "Taille minimale des blocs : `r(min)'"
di as result "Taille maximale des blocs : `r(max)'"

local bloc_mean_fmt : display %9.2f r(mean)
local bloc_mean_fmt = trim("`bloc_mean_fmt'")

di as result "Taille moyenne des blocs  : `bloc_mean_fmt'"


quietly count if bloc_n < $MIN_BLOCK_SIZE

if r(N) > 0 {

    di as text "-------------------------------------------------------"
    di as text "`r(N)' ecole(s) appartiennent a un DERNIER bloc de moins"
    di as text "de $MIN_BLOCK_SIZE ecoles. Ceci est ATTENDU par design"
    di as text "des lors qu'une strate (commune x taille) n'est pas un"
    di as text "multiple exact de $MIN_BLOCK_SIZE : le dernier bloc de"
    di as text "cette strate recoit simplement les ecoles restantes,"
    di as text "sans emprunt a une autre commune."
    di as text "-------------------------------------------------------"

    preserve
        keep if bloc_n < $MIN_BLOCK_SIZE
        keep bloc stratum_label block_number_local bloc_n
        duplicates drop
        sort bloc
        list, noobs sep(0)

        export excel using ///
            "$outputdir/blocks_below_minimum.xlsx", ///
            firstrow(variables) replace
    restore
}

else {

    di as result ///
        "Tous les blocs atteignent au moins $MIN_BLOCK_SIZE ecoles."
}


sort bloc id_infra

save "$outputdir/ecoles_blocs_locked.dta", replace

di as result "======================================================="
di as result "DATASET DES BLOCS SAUVEGARDE"
di as result "$outputdir/ecoles_blocs_locked.dta"
di as result "======================================================="


*======================================================================*
* FIN SECTION 3
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
* DIAGNOSTIC: how many schools per arm within each block.
*
* NOTE : depuis la v2, un bloc peut legitimement contenir moins de 6
* ecoles (dernier bloc d'une strate commune x taille non-multiple de
* 6 - voir Section 3). Dans ce cas, un ou plusieurs bras peuvent
* recevoir moins de 2 ecoles dans CE bloc precis. Ceci n'est plus une
* erreur bloquante : c'est une consequence attendue de l'absence
* d'emprunt inter-commune demandee par le PI. On se contente de le
* signaler pour information et tracabilite.
*----------------------------------------------------------------------*

preserve

    contract bloc group3, freq(narm)

    bysort bloc: egen narm_min_check = min(narm)

    quietly count if narm_min_check < 2

    if r(N) > 0 {

        di as text "-------------------------------------------------------"
        di as text "NOTE : dans certain(s) bloc(s), un bras recoit moins de"
        di as text "2 ecoles. Ceci ne peut survenir que dans le DERNIER"
        di as text "bloc d'une strate (commune x taille) dont la taille"
        di as text "est < $MIN_BLOCK_SIZE - situation attendue et acceptee"
        di as text "par design (voir Section 3)."
        di as text "-------------------------------------------------------"

        list bloc group3 narm if narm_min_check < 2, noobs

    }

    else {

        di as result ///
            "Chaque bras recoit au moins 2 ecoles dans chaque bloc."
    }

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
* 6. TARGETED PARENT RANDOMIZATION - SEPAREE PAR BRAS DE TRAITEMENT
*======================================================================*
*
* ======================================================================
* >>> POINT 1 DU RETOUR PI (Mahounan) <<<
*
*   "La randomisation Mere/Pere doit se faire separement dans chaque
*    bras de traitement. [...] dans le bras Salience, 50% Mere et 50%
*    Pere ; dans le bras Salience + Implementation, 50% Mere et 50%
*    Pere. Donc la randomisation Mere/Pere doit se faire au niveau
*    bloc x traitement, et non simplement au niveau du bloc."
*
* Mise en oeuvre : le tirage se fait au niveau (bloc x group3) - PAS
* seulement au niveau (bloc). Chaque bras traite (Salience, et
* Salience + Implementation) recoit donc SA PROPRE randomisation
* Mere/Pere, independamment de l'autre bras, meme quand les deux
* bras cohabitent dans le meme bloc.
*
* ------------------------------------------------------------------
* CORRECTIF IMPORTANT (v3) sur l'alternance Mere/Pere elle-meme :
*
*   Avec une simple alternance deterministe
*       parent_group = mod(rang-1, 2) + 1
*   le rang 1 tombe TOUJOURS sur "Mere". Quand une cellule (bloc x
*   bras) a un effectif IMPAIR (frequent car les blocs peuvent faire
*   moins de 6 ecoles - voir Point 3), l'ecole "excedentaire" est
*   alors TOUJOURS attribuee a la Mere, et ce de facon systematique
*   sur l'ensemble des cellules impaires. Le controle "ecart <= 1 par
*   cellule" reste satisfait (l'ecart RESTE petit dans chaque
*   cellule), mais le biais s'accumule dans le meme sens sur toutes
*   les cellules et casse le 50/50 GLOBAL par bras (ex. observe :
*   Salience = 36 Mere / 14 Pere au lieu de 25/25).
*
*   La correction applique EXACTEMENT le meme principe que celui deja
*   utilise en Section 5 pour repartir le reste des bras de
*   traitement : l'ecole excedentaire d'une cellule impaire est
*   attribuee par un TIRAGE ALEATOIRE INDEPENDANT (50/50), et non
*   plus systematiquement a la Mere.
* ======================================================================

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


sort bloc group3 rand_parent

capture drop rank_parent
by bloc group3: gen long rank_parent = ///
    _n if treated == 1


*----------------------------------------------------------------------*
* Taille de chaque cellule (bloc x bras traite)
*----------------------------------------------------------------------*
* Comme group3 in {2,3} implique treated==1 pour TOUTES les ecoles
* d'une cellule (bloc,group3) traitee, _N compte exactement le nombre
* d'ecoles traitees de cette cellule.
*----------------------------------------------------------------------*

capture drop n_treated_cell
by bloc group3: gen long n_treated_cell = _N if treated == 1


*----------------------------------------------------------------------*
* 6A. PARTIE PAIRE DE LA CELLULE : alternance stricte 50/50
*----------------------------------------------------------------------*

capture drop parent_group
gen byte parent_group = .

replace parent_group = ///
    mod(rank_parent - 1, 2) + 1 ///
    if treated == 1 & ///
       rank_parent <= floor(n_treated_cell / 2) * 2


*----------------------------------------------------------------------*
* 6B. ECOLE EXCEDENTAIRE (cellule de taille impaire) : tirage aleatoire
*
* Un seul tirage uniforme independant par cellule (bloc x bras) dont
* la taille est impaire, dans le MEME flux de seed $SEED_PARENT (donc
* toujours reproductible), determine si l'ecole restante va a la
* Mere ou au Pere.
*----------------------------------------------------------------------*

sort bloc group3

capture drop u_leftover
by bloc group3: gen double u_leftover = ///
    runiform() ///
    if treated == 1 & _n == 1 & mod(n_treated_cell, 2) == 1

capture drop u_leftover_cell
bysort bloc group3: egen double u_leftover_cell = max(u_leftover)

replace parent_group = ///
    cond(u_leftover_cell < 0.5, 1, 2) ///
    if treated == 1 & ///
       rank_parent == n_treated_cell & ///
       mod(n_treated_cell, 2) == 1

drop u_leftover u_leftover_cell


quietly count if treated == 1 & missing(parent_group)

if r(N) > 0 {

    di as error ///
        "`r(N)' ecoles traitees n'ont pas recu de parent_group."

    exit 459
}


label define parent_lbl ///
    1 "Mother" ///
    2 "Father", replace

label values parent_group parent_lbl

label var parent_group ///
    "Targeted parent (randomized within bloc x treatment arm)"


di as result "Repartition Mere/Pere par bloc et par bras :"

tab bloc parent_group ///
    if treated == 1


di as result "Repartition Mere/Pere par bras (verification globale 50/50) :"

tab group3 parent_group ///
    if treated == 1


*----------------------------------------------------------------------*
* Equilibre Mere/Pere a l'interieur de chaque (bloc x bras)
*----------------------------------------------------------------------*

preserve

    contract bloc group3 parent_group if treated == 1, freq(npar)

    bysort bloc group3: egen npar_max = max(npar)
    bysort bloc group3: egen npar_min = min(npar)

    assert npar_max - npar_min <= 1

    di as result ///
        "Mere/Pere equilibres (diff <= 1) dans chaque bloc x bras traite."

restore


*----------------------------------------------------------------------*
* Equilibre Mere/Pere GLOBAL, PAR BRAS (verification explicite du
* 50/50 demande par le PI, pas seulement cellule par cellule)
*----------------------------------------------------------------------*

preserve

    contract group3 parent_group if treated == 1, freq(narm_parent)

    bysort group3: egen narm_parent_max = max(narm_parent)
    bysort group3: egen narm_parent_min = min(narm_parent)

    quietly summarize narm_parent_max, meanonly
    local check_max = r(max)

    gen diff_arm_parent = narm_parent_max - narm_parent_min

    quietly count if diff_arm_parent > 1

    if r(N) > 0 {

        di as error "======================================================="
        di as error ///
            "ERREUR : au moins un bras de traitement n'est pas equilibre"
        di as error ///
            "50/50 (Mere/Pere) globalement (ecart > 1)."
        di as error "======================================================="

        list group3 parent_group narm_parent, noobs

        exit 459
    }

    di as result ///
        "Mere/Pere equilibres 50/50 (ecart <= 1) GLOBALEMENT dans" ///
        " CHAQUE bras traite (Salience, Salience + Implementation)."

restore


*----------------------------------------------------------------------*
* Reproducibility check for the parent draw (meme logique exacte,
* y compris le tirage aleatoire de l'ecole excedentaire)
*----------------------------------------------------------------------*

preserve

    sort id_infra

    set seed $SEED_PARENT

    gen double rand_parent_chk = runiform() if treated == 1

    sort bloc group3 rand_parent_chk

    by bloc group3: gen long rank_parent_chk = _n if treated == 1

    by bloc group3: gen long n_treated_cell_chk = _N if treated == 1

    gen byte parent_group_chk = .

    replace parent_group_chk = ///
        mod(rank_parent_chk - 1, 2) + 1 ///
        if treated == 1 & ///
           rank_parent_chk <= floor(n_treated_cell_chk / 2) * 2

    sort bloc group3

    gen double u_leftover_chk = ///
        runiform() ///
        if treated == 1 & _n == 1 & mod(n_treated_cell_chk, 2) == 1

    bysort bloc group3: egen double u_leftover_cell_chk = max(u_leftover_chk)

    replace parent_group_chk = ///
        cond(u_leftover_cell_chk < 0.5, 1, 2) ///
        if treated == 1 & ///
           rank_parent_chk == n_treated_cell_chk & ///
           mod(n_treated_cell_chk, 2) == 1

    assert parent_group == parent_group_chk if treated == 1

    di as result "REPRODUCIBILITY CONFIRMED with seed $SEED_PARENT (rng: `c(rngstate)')."

restore


*======================================================================*
* 7. BALANCE CHECKS
*======================================================================*

di as result "======================================================="
di as result "BALANCE CHECKS"
di as result "======================================================="


* NOTE : une commune peut contenir PLUSIEURS blocs (Small et Large
* etant randomises separement, et une strate pouvant elle-meme
* comporter plusieurs blocs de 6). Ce tableau au niveau COMMUNE est
* INFORMATIONNEL uniquement ; la garantie experimentale d'equilibre
* est assuree AU NIVEAU DU BLOC (bloc = COMMUNE x Small/Large x bloc
* local), verifiee dans la Section 5 ci-dessus.
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
         stratum_label ///
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
        stratum_label ///
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
    "RANDOMIZATION MANIFEST - Gender Norms RCT (v2)" _n

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
    "Target block size    : $MIN_BLOCK_SIZE" _n

file write manifest ///
    "Size rule            : commune median (<=  Small, > Large)" _n

file write manifest ///
    "Stratification        : COMMUNE x Small/Large, blocks built" _n

file write manifest ///
    "                        separately within each stratum" _n

file write manifest ///
    "Cross-commune fusion  : NONE (removed per PI review) - each" _n

file write manifest ///
    "                        commune is fully autonomous; the last" _n

file write manifest ///
    "                        block of an incomplete stratum simply" _n

file write manifest ///
    "                        contains the remaining schools" _n

file write manifest ///
    "Parent randomization  : Mother/Father 50/50, drawn separately" _n

file write manifest ///
    "                        within EACH treated arm x block" _n

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
    "Manifest:"
di as result ///
    "$outputdir/randomization_manifest_`timestamp'.txt"

di as result "======================================================="

log close
