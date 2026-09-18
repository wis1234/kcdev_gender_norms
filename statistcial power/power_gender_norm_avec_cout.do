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
* Version ajustee : ajout d'un bloc dedie repondant a la question
*   "quelle taille d'echantillon pour detecter un effet de 20% (0.20 SD) ?"
*   (voir NOUVEAU BLOC 2 ci-dessous).
*
* Version ajustee (2) : ajout d'une SECTION COUT (parametres de cout par
*   ecole et par fille) et d'une OPTIMISATION de la combinaison (K,M) au
*   sens cout-efficacite, base sur la formule de "design optimal" de
*   Raudenbush (1997) / Snijders & Bosker (2012). Voir NOUVEAU BLOC 2bis.
*   Le reste du fichier original est inchange, seule la numerotation des
*   blocs a ete decalee.
*
* HOW TO USE THIS FILE
*   - Every parameter that should be replaced with your own value is flagged
*     with a "SPECIFY" comment, exactly as in the original J-PAL template.
*   - The file is organized in self-contained blocks (0 to 10). You can run
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

* --- Effet cible demande : 20% = 0.20 SD -----------------------------------
scalar target_mde_20 = 0.20        //SPECIFY - effet minimum a detecter (en SD), fixe par l'utilisateur

* --- SECTION COUT (parametres) ----------------------------------------------
* Ces deux couts sont les seuls inputs necessaires pour l'optimisation (K,M)
* du NOUVEAU BLOC 2bis ci-dessous. Voir ce bloc pour la logique complete.
*   - cout_fixe_ecole : cout qui ne depend PAS du nombre de filles enquetees
*     dans l'ecole (deplacement de l'equipe, autorisations administratives,
*     temps de mise en place/formation sur site, etc.)
*   - cout_par_fille   : cout marginal d'ENQUETER UNE FILLE DE PLUS dans une
*     ecole deja visitee (temps d'entretien, incitatif eventuel, saisie).
* Utiliser la MEME devise partout (ici FCFA a titre d'exemple).
scalar cout_par_fille  = 5000       //SPECIFY - cout variable par fille enquetee (FCFA)
scalar cout_fixe_ecole = 150000     //SPECIFY - cout fixe par ecole (FCFA)

di as text "Design summary: `=n_schools_total' schools (`=n_schools_per_arm' per arm), " ///
    "`=n_girls_per_school' girls/school, alpha=`=alpha_level', power target=`=power_target', " ///
    "central ICC assumption=`=rho_central'"
di as text "Cout : `=cout_fixe_ecole' FCFA fixe/ecole, `=cout_par_fille' FCFA/fille " ///
    "(ratio c1/c2 = `=cout_fixe_ecole'/`=cout_par_fille' = `=cout_fixe_ecole'/`=cout_par_fille'')"


********************************************************************************
*** NOUVEAU BLOC 2. TAILLE D'ECHANTILLON POUR DETECTER UN EFFET DE 20% (0.20 SD)
********************************************************************************

* Reponse directe a la question : "combien d'ecoles par bras faut-il pour
* detecter de maniere fiable (alpha=5%, puissance=80%) un effet de 20% d'un
* ecart-type, etant donne 30 filles enquetees par ecole ?"
*
* On fait varier l'ICC (rho) car aucune donnee de base n'existe encore pour
* l'estimer precisement (cf. note du Bloc 1). Le nombre d'ecoles necessaire
* est tres sensible a rho : c'est le parametre a signaler au PI comme
* "risque" principal sur la taille d'echantillon.

* IMPORTANT : on pre-calcule ce scalaire une seule fois, plutot que d'ecrire
* `=baseline_mean'+`=target_mde_20' directement dans la commande power.
* En Stata, `=expr' est deja une expansion de macro (donc du TEXTE) ; coller
* deux `=...' avec un "+" entre eux colle du texte ("0+0.2"), ce qui n'est
* PAS reevalue comme un calcul par "power twomeans" -> erreur "means must
* contain numbers". Il faut faire le calcul UNE fois via "scalar", puis
* reutiliser `=treat_mean_20' (un seul nombre deja calcule) partout ensuite.
scalar treat_mean_20 = baseline_mean + target_mde_20

matrix schools_for_20pct = J(4,3,.)
local row = 1
foreach rho of local rho_list {

    power twomeans `=baseline_mean' `=treat_mean_20', ///
        cluster ///
        m1(`=n_girls_per_school') mratio(`=mratio') ///
        kratio(`=nratio') ///
        sd(`=sd_outcome') rho(`rho') ///
        power(`=power_target') alpha(`=alpha_level') table

    matrix schools_for_20pct[`row',1] = `rho'
    matrix schools_for_20pct[`row',2] = r(K1)        // ecoles necessaires par bras
    matrix schools_for_20pct[`row',3] = r(N)          // effectif total (filles)

    local row = `row' + 1
}
matrix colnames schools_for_20pct = ICC Ecoles_par_bras N_total_filles
di as text _n "Table 0. Ecoles par bras necessaires pour detecter un effet de " ///
    "`=target_mde_20' SD (20%), 30 filles/ecole, alpha=`=alpha_level', puissance=`=power_target'"
matrix list schools_for_20pct

* Reponse "headline" avec l'hypothese d'ICC centrale (0.10)
power twomeans `=baseline_mean' `=treat_mean_20', ///
    cluster m1(`=n_girls_per_school') mratio(`=mratio') kratio(`=nratio') ///
    sd(`=sd_outcome') rho(`=rho_central') ///
    power(`=power_target') alpha(`=alpha_level') table
scalar k_needed_headline = ceil(r(K1))
di as error "REPONSE : pour detecter un effet de `=target_mde_20' SD (20%), avec " ///
    "`=n_girls_per_school' filles/ecole, alpha=`=alpha_level', puissance=`=power_target' " ///
    "et un ICC central de `=rho_central', il faut environ `=k_needed_headline' ecoles PAR BRAS " ///
    "(soit `=k_needed_headline'*3 ecoles au total pour 3 bras), contre 50/bras (150 au total) " ///
    "prevues dans le guide de projet. Si l'ICC reel est plus eleve (0.15-0.20), il faudrait " ///
    "70 a 90 ecoles/bras : c'est le principal risque a valider avec des donnees pilotes."

* --- Sensibilite complementaire : effet de 20% en faisant varier le nombre
*     de filles enquetees par ecole (m), a ICC central fixe -----------------
local m_list "20 25 30 35 40"   //SPECIFY - scenarios alternatifs de filles/ecole

matrix schools_by_m = J(5,2,.)
local row = 1
foreach m of local m_list {
    power twomeans `=baseline_mean' `=treat_mean_20', ///
        cluster m1(`m') mratio(`=mratio') kratio(`=nratio') ///
        sd(`=sd_outcome') rho(`=rho_central') ///
        power(`=power_target') alpha(`=alpha_level') table

    matrix schools_by_m[`row',1] = `m'
    matrix schools_by_m[`row',2] = r(K1)
    local row = `row' + 1
}
matrix colnames schools_by_m = Filles_par_ecole Ecoles_par_bras
di as text _n "Table 0bis. Ecoles/bras necessaires pour un effet de 20%, " ///
    "selon le nombre de filles enquetees par ecole (ICC central=`=rho_central')"
matrix list schools_by_m

* --- Scenario "compromis" utile pour le PI : le nombre de filles/ecole qui
*     permet de rester a 50 ecoles/bras (le budget prevu) tout en visant 20%.
*     On lit ce nombre directement dans schools_by_m (35 filles/ecole -> 50
*     ecoles/bras, cf. sortie ci-dessus) ; aucun nouveau calcul ici.
scalar m_compromis_50ecoles = 35   // lu dans Table 0bis : la valeur de m qui donne K1=50


********************************************************************************
****************** RESUME EXECUTIF (pour le PI / KCDev) ***********************
********************************************************************************
* Ce bloc ne fait AUCUN nouveau calcul : il se contente d'afficher, en une
* seule fois, les chiffres cles deja produits par le Bloc 2, pour eviter au
* PI de devoir chercher dans les ~500 lignes de sortie Stata.

di as result _n "{hline 78}"
di as result "RESUME EXECUTIF - Taille d'echantillon pour detecter un effet de 20% (0.20 SD)"
di as result "{hline 78}"
di as text   "  Hypothese d'ICC centrale retenue : `=rho_central'"
di as text   "  Avec 30 filles/ecole (design initial)  -> `=k_needed_headline' ecoles PAR BRAS " ///
    "(soit `=k_needed_headline'*3 au total), contre 50/bras prevues."
di as text   "  Avec `=m_compromis_50ecoles' filles/ecole (compromis)  -> 50 ecoles PAR BRAS " ///
    "suffisent (budget initial respecte)."
di as text   "  Risque principal : si l'ICC reel est plus proche de 0.15-0.20 (plausible pour " ///
    "des indicateurs de normes sociales/usage du temps), il faudrait 70 a 90 ecoles/bras " ///
    "meme avec des filles supplementaires par ecole - a valider avec des donnees pilotes."
di as result "{hline 78}" _n


********************************************************************************
*** NOUVEAU BLOC 2bis. SECTION COUT ET OPTIMISATION DE LA COMBINAISON (K,M) ****
********************************************************************************

* -----------------------------------------------------------------------------
* LOGIQUE DU CALCUL (a bien comprendre avant de lire le code) :
*
* Aux Blocs 2 a 9, K (ecoles/bras) et M (filles/ecole) sont traites comme des
* INPUTS FIXES : on donne M, "power twomeans" en deduit K (ou le MDE). Mais
* K et M ne sont pas independants d'un point de vue BUDGETAIRE : a budget
* total fixe, enqueter PLUS de filles par ecole (M eleve) laisse moins
* d'argent pour ouvrir de NOUVELLES ecoles (K plus bas), et inversement.
* Il existe donc UNE combinaison (K*, M*) qui, a budget donne, MINIMISE la
* variance de l'effet estime (= MAXIMISE la puissance / MINIMISE le MDE) -
* ou, de maniere equivalente, qui MINIMISE le cout total pour un MDE cible.
*
* 1) La variance de l'estimateur de l'effet (design cluster, 2 bras) est
*    proportionnelle a :
*         V(M,K)  is proportional to   [ rho + (1-rho)/M ] / K
*    (plus rho est eleve, moins ajouter des filles/ecole aide, car les
*    filles d'une meme ecole sont correlees entre elles ; plus rho est bas,
*    plus ajouter des filles/ecole rapporte gros en precision).
*
* 2) Le cout total POUR UN BRAS est :
*         C(M,K) = K * (c1 + c2*M)
*    avec c1 = cout_fixe_ecole (independant du nombre de filles) et
*         c2 = cout_par_fille  (proportionnel au nombre de filles).
*
* 3) En minimisant V(M,K) sous la contrainte C(M,K) = Budget fixe (ou, de
*    maniere equivalente, en minimisant C(M,K) pour V(M,K) donnee), la
*    solution a une forme fermee CELEBRE dans la litterature du "optimal
*    design" pour essais clusterises (Raudenbush 1997 ; Snijders & Bosker
*    2012, chap. 12 ; c'est aussi la formule utilisee par le logiciel
*    "Optimal Design" de Spybrook et al.) :
*
*         M* = sqrt( (c1/c2) * (1-rho)/rho )
*
*    Intuition : si ouvrir une ecole coute cher par rapport au cout marginal
*    d'une fille de plus (c1/c2 eleve), il vaut mieux enqueter BEAUCOUP de
*    filles par ecole (M* eleve) pour "amortir" le cout fixe. Si rho est
*    eleve (les filles d'une meme ecole se ressemblent beaucoup), ajouter
*    des filles supplementaires apporte peu d'information NOUVELLE, donc M*
*    diminue (mieux vaut ouvrir plus d'ecoles plutot que sur-enqueter les
*    memes).
*
* 4) Une fois M* calcule (et arrondi a un entier), on le reinjecte dans
*    "power twomeans" EXACTEMENT comme aux Blocs 2 a 9, pour trouver le K
*    necessaire pour atteindre la puissance cible sur l'effet demande
*    (ici 20% = 0.20 SD). On en deduit alors le cout total du design
*    optimal, a comparer au cout du design initial (30 filles/ecole).
*
* IMPORTANT - LIMITES : M* est optimal EN COUT UNIQUEMENT. Il faut toujours
* le confronter aux contraintes de terrain (nombre de filles eligibles
* disponibles par ecole - ici max ~30 sur la base de 15 en 6eme + 15 en
* 5eme -, duree de la collecte, lassitude des enquetrices, etc.). C'est
* pourquoi ce bloc fournit AUSSI une table de sensibilite (Table 7) qui
* recalcule le cout total pour PLUSIEURS valeurs de M autour de M*, afin de
* choisir une valeur ronde et realiste sans perdre beaucoup d'efficacite
* (la fonction de cout est generalement assez "plate" pres de l'optimum).
* -----------------------------------------------------------------------------

scalar cout_ratio = cout_fixe_ecole / cout_par_fille
di as text _n "Ratio de cout ecole/fille (c1/c2) = `=cout_ratio' " ///
    "(`=cout_fixe_ecole' FCFA fixe / `=cout_par_fille' FCFA par fille)"

* --- Table 6 : M* optimal et K associe, selon l'ICC (effet cible 20%) ------
matrix m_optimal = J(4,4,.)
local row = 1
foreach rho of local rho_list {

    scalar m_star         = sqrt(cout_ratio * (1-`rho')/`rho')
    scalar m_star_arrondi = round(m_star)

    power twomeans `=baseline_mean' `=treat_mean_20', ///
        cluster m1(`=m_star_arrondi') mratio(`=mratio') kratio(`=nratio') ///
        sd(`=sd_outcome') rho(`rho') ///
        power(`=power_target') alpha(`=alpha_level') table

    matrix m_optimal[`row',1] = `rho'
    matrix m_optimal[`row',2] = m_star
    matrix m_optimal[`row',3] = m_star_arrondi
    matrix m_optimal[`row',4] = r(K1)

    local row = `row' + 1
}
matrix colnames m_optimal = ICC M_etoile_exact M_etoile_arrondi K_par_bras_associe
di as text _n "Table 6. Combinaison (K*,M*) cout-optimale pour detecter 20% (0.20 SD), " ///
    "selon l'ICC, avec ratio de cout c1/c2 = `=cout_ratio'"
matrix list m_optimal

* --- Comparaison de cout : design INITIAL (30 filles/ecole) vs design
*     OPTIMAL (M*), a ICC central, pour le meme effet cible de 20% ---------
scalar m_star_central = m_optimal[2,3]     // ligne rho = 0.10 dans rho_list
scalar k_star_central = m_optimal[2,4]
scalar cout_design_optimal = n_arms * k_star_central * (cout_fixe_ecole + cout_par_fille*m_star_central)

scalar k_design_initial    = k_needed_headline   // deja calcule au Bloc 2 (52 ecoles/bras a ICC=0.10)
scalar cout_design_initial = n_arms * k_design_initial * (cout_fixe_ecole + cout_par_fille*n_girls_per_school)

scalar economie_fcfa = cout_design_initial - cout_design_optimal
scalar economie_pct  = round(100*economie_fcfa/cout_design_initial, 0.1)

di as result _n "{hline 78}"
di as result "COMPARAISON DE COUT (ICC central = `=rho_central', effet cible = 20% / 0.20 SD)"
di as result "{hline 78}"
di as text "  Design INITIAL : `=n_girls_per_school' filles/ecole, `=k_design_initial' ecoles/bras, " ///
    "`=n_arms' bras -> cout total = `=cout_design_initial' FCFA"
di as text "  Design OPTIMAL : `=m_star_central' filles/ecole, `=k_star_central' ecoles/bras, " ///
    "`=n_arms' bras -> cout total = `=cout_design_optimal' FCFA"
di as text "  Economie estimee : `=economie_fcfa' FCFA (`=economie_pct'% du budget du design initial), " ///
    "pour la MEME puissance (`=power_target') et le MEME effet cible (`=target_mde_20' SD)."
di as result "{hline 78}" _n

* --- Table 7 : sensibilite du cout total autour de M*, a ICC central -------
* Utile pour choisir une valeur ENTIERE et REALISTE de M (contrainte de
* terrain : au plus 15 filles en 6eme + 15 en 5eme = 30 filles/ecole
* disponibles dans le design actuel) sans trop s'eloigner de l'optimum.
local m_grid_list "10 15 20 25 30 35 40 45 50 60 70"   //SPECIFY - etendre/reduire selon le M* trouve

matrix cost_by_m = J(11,3,.)
local row = 1
foreach m of local m_grid_list {

    power twomeans `=baseline_mean' `=treat_mean_20', ///
        cluster m1(`m') mratio(`=mratio') kratio(`=nratio') ///
        sd(`=sd_outcome') rho(`=rho_central') ///
        power(`=power_target') alpha(`=alpha_level') table

    scalar k_needed_m  = ceil(r(K1))
    scalar cout_total_m = n_arms * k_needed_m * (cout_fixe_ecole + cout_par_fille*`m')

    matrix cost_by_m[`row',1] = `m'
    matrix cost_by_m[`row',2] = k_needed_m
    matrix cost_by_m[`row',3] = cout_total_m

    local row = `row' + 1
}
matrix colnames cost_by_m = Filles_par_ecole Ecoles_par_bras Cout_total_FCFA_3bras
di as text _n "Table 7. Cout total du design (3 bras, ICC central=`=rho_central') pour detecter " ///
    "20% (0.20 SD), selon M - le K necessaire est recalcule a chaque fois. Chercher la ligne " ///
    "avec le Cout_total_FCFA_3bras le plus bas : c'est la meilleure combinaison (K,M) PRATIQUE."
matrix list cost_by_m

* NOTE IMPORTANTE : si le M qui minimise le cout dans Table 7 depasse le
* nombre de filles reellement disponibles par ecole (ici ~30, cf. Bloc 1),
* la contrainte de terrain devient contraignante : il faut alors se caler
* sur le plus grand M realiste et laisser K s'ajuster - c'est exactement ce
* que montre la Table 0bis du Bloc 2 (35 filles/ecole -> 50 ecoles/bras).


********************************************************************************
**** 3. MDE FOR THE MAIN TREATMENT EFFECTS (T1 vs Control, T2 vs Control) *****
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
********* 4. REQUIRED NUMBER OF SCHOOLS FOR A GIVEN TARGET EFFECT SIZE ********
********************************************************************************

* Reverse question: "How many schools per arm would we need to reliably detect
* an effect of X standard deviations?" Useful to check whether the planned
* 150 schools are sufficient, or to justify the sample size to the PI/funders.
* NOTE: le cas de 0.20 (20%) - la question posee par l'utilisateur - est deja
* traite EN DETAIL au NOUVEAU BLOC 2 ci-dessus (avec en plus la sensibilite
* au nombre de filles/ecole), donc on ne le recalcule pas ici pour eviter un
* doublon ; ce bloc complete la vue d'ensemble avec d'AUTRES effets cibles.

local target_mde_list "0.15 0.25 0.30"   //SPECIFY - candidate target effect sizes (in SD); 0.20 -> voir Bloc 2

matrix schools_needed = J(12,3,.)
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
    "target effect size (30 girls/school, power=`=power_target', alpha=`=alpha_level'). " ///
    "NB: le cas 0.20 (20%) est dans la Table 0 du Bloc 2, pas repete ici."
matrix list schools_needed


********************************************************************************
********************* 5. MDE WITH A BASELINE COVARIATE (ANCOVA) ***************
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
*************** 6. ADJUSTING FOR ANTICIPATED ATTRITION AT ENDLINE *************
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
**** 7. POWER FOR THE NESTED MOTHER- VS FATHER-TARGETED RANDOMIZATION *********
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
******* 8. POWER FOR A BINARY OUTCOME (e.g., attendance, pass/fail) ***********
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
********* 9. SENSITIVITY GRAPH: MDE AS A FUNCTION OF ICC AND SAMPLE SIZE ******
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
    forvalues k = 20(10)90 {                 // etendu jusqu'a 90 pour couvrir le cas rho=0.20
                                              //SPECIFY - range of schools/arm to explore

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
    yline(0.20, lpattern(dash) lcolor(gs8)) ///
    ytitle("Minimum Detectable Effect (SD units)") ///
    xtitle("Number of schools per arm") ///
    title("MDE by number of schools per arm and ICC") ///
    subtitle("30 girls/school, power=0.80, alpha=0.05; dashed lines = planned design (50/arm) et cible 20%") ///
    legend(order(1 "ICC = 0.05" 2 "ICC = 0.10" 3 "ICC = 0.15" 4 "ICC = 0.20") pos(6) rows(1)) ///
    name(mde_sensitivity, replace)

graph export "MDE_sensitivity_CKDev_Benin.png", replace width(1600)   //SPECIFY - export path/name

restore


********************************************************************************
**************************** 10. EXPORT SUMMARY TABLES ************************
********************************************************************************

* Collect the key matrices built above into a single Excel workbook so they
* can be shared directly with the PI and KCDev (section 15 of the guide,
* "livrables attendus").

putexcel set "Power_MDE_CKDev_Benin_summary.xlsx", replace  //SPECIFY - output path/name

putexcel A1 = "Table 0. Ecoles par bras necessaires pour detecter un effet de 20% (0.20 SD)"
putexcel A2 = matrix(schools_for_20pct), names

putexcel A8 = "Table 0bis. Ecoles/bras pour un effet de 20%, selon filles/ecole"
putexcel A9 = matrix(schools_by_m), names

putexcel A16 = "Table 1. MDE for main pairwise comparisons (T1 vs C or T2 vs C)"
putexcel A17 = matrix(mde_main), names

putexcel A23 = "Table 2. Schools needed per arm for a target MDE"
putexcel A24 = matrix(schools_needed), names

putexcel A38 = "Table 3. MDE with ANCOVA-style baseline covariate adjustment"
putexcel A39 = matrix(mde_ancova), names

putexcel A46 = "Table 4. MDE under different attrition scenarios"
putexcel A47 = matrix(mde_attrition), names

putexcel A53 = "Table 5. Power for a binary outcome under assumed effects"
putexcel A54 = matrix(mde_binary), names

putexcel A59 = "Headline results"
putexcel A60 = "Ecoles/bras pour detecter 20% (ICC central 0.10)"
putexcel B60 = `=k_needed_headline'
putexcel A61 = "Main comparison MDE (T1 or T2 vs Control), 50 ecoles/bras"
putexcel B61 = `=mde_headline'
putexcel A62 = "Mother vs Father, within one treated arm"
putexcel B62 = `=mde_parent_within'
putexcel A63 = "Mother vs Father, pooled across treated arms"
putexcel B63 = `=mde_parent_pooled'

putexcel A66 = "Table 6. Combinaison (K*,M*) cout-optimale selon l'ICC (effet cible 20%)"
putexcel A67 = matrix(m_optimal), names

putexcel A73 = "Table 7. Cout total (3 bras) selon M, ICC central"
putexcel A74 = matrix(cost_by_m), names

putexcel A87 = "Comparaison de cout - design initial vs design optimal (ICC central)"
putexcel A88 = "Cout design initial (FCFA)"
putexcel B88 = `=cout_design_initial'
putexcel A89 = "Cout design optimal (FCFA)"
putexcel B89 = `=cout_design_optimal'
putexcel A90 = "Economie estimee (FCFA)"
putexcel B90 = `=economie_fcfa'
putexcel A91 = "Economie estimee (%)"
putexcel B91 = `=economie_pct'

di as text _n "All results exported to Power_MDE_CKDev_Benin_summary.xlsx " ///
    "and MDE_sensitivity_CKDev_Benin.png"

cap log close power_ckdev

********************************************************************************
* END OF FILE
*
* SUMMARY OF WHAT THIS SCRIPT DOES
*  0. Housekeeping (no baseline dataset needed at this design stage)
*  1. Sets the project's actual design parameters (150 schools, 50/arm,
*     30 girls/school, alpha, power) as SPECIFY-able scalars, plus the
*     target effect of 20% (0.20 SD) requested by the user AND the cost
*     parameters (cout_fixe_ecole, cout_par_fille) used in Block 2bis
*  2. [NOUVEAU] Repond directement : combien d'ecoles par bras pour detecter
*     un effet de 20% (0.20 SD), selon l'ICC (0.05 a 0.20) et selon le nombre
*     de filles enquetees par ecole
*  2bis. [NOUVEAU] Section cout : calcule la combinaison (K*,M*) qui minimise
*     le cout total pour un MDE cible donne (formule M* = sqrt(c1/c2 * (1-rho)/rho)),
*     compare le cout du design initial (30 filles/ecole) au design optimal,
*     et fournit une table de sensibilite du cout autour de M*
*  3. Computes the MDE for the two headline treatment contrasts
*     (T1 vs Control, T2 vs Control) across a range of plausible ICC values,
*     with the planned 50 schools/arm
*  4. Computes the number of schools per arm needed to detect a set of
*     target effect sizes (0.15 to 0.30 SD), to sanity-check the planned
*     150-school sample against several effect sizes at once
*  5. Shows how much an ANCOVA-style baseline covariate would improve
*     precision (lower MDE) for a range of plausible baseline R-squared
*  6. Shows how anticipated attrition erodes power/increases the MDE
*  7. Powers the SECONDARY, nested mother- vs father-targeted randomization,
*     both within a single treated arm and pooled across both treated arms
*  8. Repeats the exercise for a BINARY outcome (e.g., a protected study
*     slot, attendance threshold) using "power twoproportions, cluster"
*  9. Produces a sensitivity graph of MDE vs number of schools and ICC,
*     avec une ligne de reference a 20% (0.20 SD)
*  10. Exports all tables (y compris les Tables 6 et 7 sur le cout) to a
*     single Excel file for the PI/KCDev
********************************************************************************
