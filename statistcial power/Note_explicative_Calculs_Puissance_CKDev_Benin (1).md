# Note explicative — Calculs de puissance et de taille d'effet minimale détectable (MDE)
### Projet « Normes de genre, corvées domestiques, éducation et aspirations des filles au Bénin »
CKDev / Dartmouth College — PI : M. Yedomiffi
Préparé à partir du script `power_gender_norm.do` et de son log d'exécution du 10/09/2026

---

## 1. Objectif de cette note

Le script Stata analysé calcule, pour un essai randomisé en grappes (cluster-randomized trial) à
3 bras (Contrôle / T1 « Salience » / T2 « Salience + Mise en œuvre »), trois familles de questions :

1. **Combien d'écoles par bras faut-il** pour détecter de façon fiable un effet donné (en particulier
   l'effet de 20 %, soit 0,20 écart-type, explicitement demandé) ?
2. **Quel est l'effet minimum détectable (MDE)** avec le design actuellement prévu (150 écoles,
   50 par bras, 30 filles par école) ?
3. **Comment ce MDE évolue-t-il** selon l'ICC (paramètre de corrélation intra-école), l'ajout de
   covariables de base (ANCOVA), l'attrition attendue, ou le type d'outcome (continu vs binaire) ?

Cette note (i) définit tous les termes techniques utilisés, (ii) traduit les résultats du log en
langage clair pour le PI/l'équipe KCDev, et (iii) explique comment réutiliser le fichier `.do`.

---

## 2. Concepts clés et vocabulaire technique

### 2.1 Randomisation en grappes (« cluster randomized design »)
Ici, l'unité randomisée n'est pas la fille (l'unité d'observation) mais **l'école** (l'unité de
randomisation). Toutes les filles d'une même école reçoivent le même traitement. Ce choix évite
la « contamination » entre parents d'une même école mais réduit la puissance statistique par
rapport à une randomisation individuelle, car les filles d'une même école ont tendance à se
ressembler sur l'outcome (cf. ICC ci-dessous).

### 2.2 Seuil de signification — `alpha`
Probabilité de conclure à tort qu'il y a un effet alors qu'il n'y en a pas (« faux positif »).
Convention : **alpha = 0,05** (5 %), test bilatéral.

### 2.3 Puissance statistique — `power`
Probabilité de détecter un effet réel s'il existe (probabilité de ne **pas** commettre de « faux
négatif »). Convention académique standard : **power = 0,80** (80 %). C'est la probabilité que
l'étude, si l'effet existe vraiment, produise un résultat statistiquement significatif.

### 2.4 Effet minimum détectable — `MDE` (delta dans les tableaux Stata)
C'est la plus petite différence entre le groupe traité et le groupe contrôle que le design est
capable de détecter avec la puissance et le seuil choisis. Il est exprimé ici **en écarts-types
(SD) de l'outcome**, car aucune donnée de base (pilote) n'existe encore : on travaille donc en
variables « standardisées » (moyenne = 0, écart-type = 1). Un MDE de 0,20 signifie « le design
peut détecter un effet égal à 20 % d'un écart-type de l'outcome, pas moins ». Plus le MDE est
petit, plus le design est puissant (mais plus il faut d'échantillon).

> Remarque pratique : « effet de 20 % » est un raccourci de langage pour « effet de 0,20 écart-type »,
> une unité standard en économie du développement (dite *taille d'effet standardisée* ou *Cohen's d*).
> Ce n'est **pas** 20 % du niveau moyen de l'outcome.

### 2.5 Coefficient de corrélation intra-classe — `ICC` / `rho`
C'est **le paramètre le plus déterminant et le plus incertain** de tout le calcul. Il mesure à quel
point les filles d'une même école se ressemblent entre elles sur l'outcome, comparé à des filles
d'écoles différentes (valeurs entre 0 et 1) :
- rho = 0 → les filles d'une même école ne se ressemblent pas plus que des filles d'écoles
  différentes (comme si l'échantillon était randomisé au niveau individuel — cas le plus favorable).
- rho élevé (proche de 1) → les filles d'une même école sont presque identiques entre elles sur
  l'outcome ; ajouter des filles dans une même école n'apporte alors presque plus d'information
  nouvelle (cas le plus défavorable).

**Conséquence pratique : plus l'ICC est élevé, plus il faut d'écoles (et non simplement plus de
filles) pour conserver la même puissance.** Comme aucune donnée pilote n'existe, le script teste
une plage plausible : rho = 0,05 / 0,10 / 0,15 / 0,20, avec 0,10 comme hypothèse centrale. Une fois
des données de terrain disponibles, l'ICC réel s'estime avec la commande Stata `loneway` sur les
données pilotes.

### 2.6 Nombre de grappes et ratio de grappes — `k1`, `k2`, `kratio`
- `k1` = nombre d'écoles dans le groupe de référence (souvent le contrôle).
- `k2` = nombre d'écoles dans le groupe comparé (souvent le traitement).
- `kratio` = k2 / k1 (ici toujours 1, car on prévoit un nombre égal d'écoles par bras).

### 2.7 Taille par grappe et ratio — `m1`, `m2`, `mratio`
- `m1` / `m2` = nombre de filles enquêtées par école dans chaque groupe (ici 30 : 15 en 6ᵉ et 15 en 5ᵉ).
- `mratio` = m2 / m1 (ici 1, même nombre de filles par école dans les deux groupes).

### 2.8 Écart-type de l'outcome — `sd`
Dispersion de l'outcome dans la population. Fixé à 1 ici car l'outcome est standardisé (pas encore
de données réelles). À remplacer plus tard par l'écart-type réel de l'indicateur mesuré (temps
consacré aux corvées, score de test, etc.).

### 2.9 `power twomeans` vs `power twoproportions`
- **`power twomeans`** : utilisé pour un outcome **continu** (ex. nombre d'heures de corvées,
  score d'aspiration). Le paramètre clé est `sd` (écart-type).
- **`power twoproportions`** : utilisé pour un outcome **binaire** (oui/non), par exemple « la
  fille dispose-t-elle d'un créneau d'étude protégé ? ». Ici, pas besoin de `sd` séparé : la
  variance est automatiquement déduite de la proportion de référence (`p1`) et de la proportion
  attendue dans le groupe traité (`p2`).

### 2.10 Ajustement ANCOVA (covariable de base) — `R²`
Si l'on dispose d'une mesure de l'outcome **avant** l'intervention (baseline) et qu'on l'utilise
comme variable de contrôle dans la régression finale, on réduit la variance résiduelle non
expliquée, donc on **améliore la puissance** (MDE plus petit) sans changer la taille d'échantillon.
Le `R²` de baseline indique la part de la variance de l'outcome final expliquée par les covariables
de base (ex. 20-40 % typiquement observé dans les études d'éducation/usage du temps).

### 2.11 Attrition
Proportion de filles/ménages perdus entre l'enquête de référence (baseline) et l'enquête finale
(endline) — refus, déménagement, absence, etc. L'attrition réduit le nombre effectif de filles
suivies par école (`m1_eff`), donc dégrade légèrement la puissance / augmente le MDE.

### 2.12 Randomisation emboîtée (« nested ») mère vs père
À l'intérieur des bras traités (T1 et T2), les écoles sont en plus randomisées entre un ciblage
« mère » et un ciblage « père » du message. Cette comparaison secondaire dispose de **moins
d'écoles** que la comparaison principale (traitement vs contrôle), car elle n'utilise que les
écoles déjà traitées : elle est donc **mécaniquement moins puissante** (MDE plus grand).

---

## 3. Interprétation des résultats du log

### 3.1 Question centrale : combien d'écoles par bras pour détecter un effet de 20 % (0,20 SD) ?
*(Bloc « Nouveau Bloc 2 », Table 0 et Table 0bis du log)*

Avec 30 filles enquêtées par école (design initial), le nombre d'écoles nécessaires **par bras**
varie fortement selon l'hypothèse d'ICC :

| ICC (rho) | Écoles nécessaires / bras | Effectif total de filles |
|---|---|---|
| 0,05 | 33 | 1 980 |
| **0,10 (hypothèse centrale)** | **52** | **3 120** |
| 0,15 | 70 | 4 200 |
| 0,20 | 89 | 5 340 |

**Lecture : avec l'hypothèse centrale (ICC = 0,10), il faudrait environ 52 écoles par bras (156 au
total) pour détecter de façon fiable un effet de 0,20 SD — soit légèrement plus que les 50 écoles
par bras (150 au total) actuellement prévues dans le guide de projet.** Le design prévu est donc
« à la limite » : suffisant si l'ICC réel est ≤ 0,10, insuffisant si l'ICC réel est plus élevé
(0,15-0,20, plage plausible pour des indicateurs de normes sociales).

**Solution de compromis identifiée (Table 0bis) :** en gardant 50 écoles/bras (budget déjà prévu)
mais en enquêtant **35 filles par école au lieu de 30**, on atteint la puissance requise pour
détecter 0,20 SD à ICC central = 0,10. Augmenter davantage le nombre de filles par école (au-delà
de 35-40) rapporte de moins en moins, précisément à cause de l'ICC (voir §2.5) : ajouter des filles
dans une même école a des rendements décroissants sur la puissance.

### 3.2 MDE effectivement atteignable avec le design prévu (50 écoles/bras, 30 filles/école)
*(Table 1)*

| ICC | MDE (en SD) |
|---|---|
| 0,05 | 0,160 |
| **0,10** | **0,202** |
| 0,15 | 0,237 |
| 0,20 | 0,267 |

**Lecture : avec le design tel que prévu aujourd'hui, la comparaison principale (T1 vs Contrôle,
ou T2 vs Contrôle) peut détecter un effet d'environ 0,20 SD si l'ICC réel est proche de 0,10** —
cohérent avec le §3.1. Si l'ICC réel est plus élevé, le plus petit effet détectable augmente
(jusqu'à ~0,27 SD si ICC = 0,20), c'est-à-dire que l'étude perd la capacité de détecter des effets
plus modestes.

### 3.3 Combien d'écoles pour d'autres cibles d'effet (0,15 / 0,25 / 0,30 SD) ?
*(Table 2)* — Utile pour situer le design prévu par rapport à d'autres hypothèses d'effet :
- Viser un effet plus **petit** (0,15 SD, plus ambitieux) exige beaucoup plus d'écoles :
  57 à 159 selon l'ICC.
- Viser un effet plus **grand** (0,25 ou 0,30 SD, plus modeste comme ambition) demande beaucoup
  moins d'écoles : 15 à 57 selon l'ICC.

Ceci illustre la sensibilité classique : diviser par deux le MDE visé multiplie approximativement
par quatre le nombre d'écoles nécessaires.

### 3.4 Gain de puissance avec une covariable de base (ANCOVA)
*(Table 3, à ICC central = 0,10, 50 écoles/bras)*

| R² de base | MDE (SD) |
|---|---|
| 0 % (pas de covariable) | 0,202 |
| 10 % | 0,192 |
| 20 % | 0,181 |
| 30 % | 0,169 |
| 40 % | 0,156 |

**Lecture : si l'on dispose d'une mesure de l'outcome avant l'intervention (baseline) qui explique
par exemple 30 % de la variance de l'outcome final, le MDE passe de 0,202 à 0,169 SD — un gain de
précision non négligeable, à taille d'échantillon inchangée.** Ceci plaide pour la collecte d'une
enquête de référence (baseline) sur les mêmes indicateurs que ceux mesurés à l'endline.

### 3.5 Effet de l'attrition attendue
*(Table 4, à ICC central = 0,10, 50 écoles/bras)*

| Taux d'attrition | Filles suivies / école (effectif) | MDE (SD) |
|---|---|---|
| 5 % | 28,5 | 0,203 |
| 10 % | 27 | 0,205 |
| 15 % | 25,5 | 0,206 |
| 20 % | 24 | 0,208 |

**Lecture : même avec une attrition élevée (20 %), la dégradation du MDE reste modeste (0,202 →
0,208 SD) parce que le nombre d'écoles — le facteur le plus puissant sur la précision dans un
design en grappes — ne change pas.** L'attrition affecte surtout le nombre de filles par école,
qui a un impact plus faible sur la puissance que le nombre d'écoles.

### 3.6 Comparaison secondaire mère vs père (randomisation emboîtée)
*(Bloc 7)*

- **À l'intérieur d'un seul bras traité** (25 écoles « mère » vs 25 écoles « père ») : MDE = **0,286 SD**.
- **En regroupant les deux bras traités** (50 écoles « mère » vs 50 écoles « père ») : MDE = **0,202 SD**.

**Lecture : la comparaison mère vs père est nettement moins puissante que la comparaison
principale traitement vs contrôle si elle est faite à l'intérieur d'un seul bras (0,286 SD contre
0,202 SD).** Elle rejoint la précision de la comparaison principale seulement si l'on regroupe les
deux bras traités. **Point à signaler explicitement au PI** : les conclusions sur la comparaison
mère/père (section 5.3 du guide projet) devront être interprétées avec cette limite de puissance
à l'esprit, en particulier si l'analyse est faite bras par bras plutôt qu'en poolant.

### 3.7 Cas d'un outcome binaire (ex. « créneau d'étude protégé »)
*(Table 5, hypothèse : 30 % des filles du groupe contrôle ont l'outcome)*

| Effet visé (points de %) | Puissance atteinte |
|---|---|
| +10 points (30 % → 40 %) | 83,0 % |
| +15 points (30 % → 45 %) | 99,1 % |
| +20 points (30 % → 50 %) | 99,99 % |

**Lecture : avec le design prévu, l'étude a largement la puissance nécessaire (>80 %) pour détecter
un effet de 10 points de pourcentage ou plus sur un outcome binaire dont la prévalence de référence
est de 30 %.** Ce type d'outcome est donc moins « à risque » sur le plan de la puissance que les
outcomes continus visés à 0,20 SD.

### 3.8 Graphique de sensibilité (MDE selon le nombre d'écoles et l'ICC)
Le fichier `MDE_sensitivity_CKDev_Benin.png` produit par le script trace, pour chaque hypothèse
d'ICC (0,05 à 0,20), la courbe du MDE en fonction du nombre d'écoles par bras (de 20 à 90), avec
deux lignes de repère : 50 écoles/bras (design prévu) et 0,20 SD (effet cible). Ce graphique
permet de visualiser en un coup d'œil que la ligne « 50 écoles » croise la ligne « 0,20 SD »
approximativement au niveau de la courbe ICC = 0,10, confirmant numériquement les résultats du §3.2.

---

## 4. Synthèse pour le PI / l'équipe KCDev

- **Le design actuellement prévu (150 écoles, 50/bras, 30 filles/école) est globalement adapté
  pour détecter un effet de 0,20 SD, mais seulement si l'ICC réel est proche de 0,10.**
- **Le principal risque identifié est l'incertitude sur l'ICC.** Si l'ICC réel se situe entre
  0,15 et 0,20 (plausible pour des indicateurs de normes sociales/usage du temps), il faudrait
  70 à 90 écoles par bras pour conserver la même capacité de détection — soit 20 à 40 écoles de
  plus par bras que prévu.
- **Deux leviers d'atténuation, sans changer le nombre d'écoles :**
  1. Augmenter légèrement le nombre de filles enquêtées par école (35 au lieu de 30) suffit à
     couvrir le scénario central (ICC = 0,10).
  2. Collecter une enquête de référence (baseline) sur les mêmes outcomes pour bénéficier d'un
     ajustement ANCOVA, qui réduit le MDE à budget d'échantillon inchangé.
- **La comparaison secondaire mère vs père est structurellement moins puissante** que la
  comparaison principale et devra être analysée en poolant les deux bras traités pour espérer
  une précision comparable.
- **Action recommandée avant la finalisation du design :** dès que des données pilotes ou une
  enquête de référence comparable sont disponibles, réestimer l'ICC réel avec `loneway` (voir
  §2.5) et refaire tourner ce script pour remplacer l'hypothèse centrale de 0,10 par la valeur
  observée.

---

## 5. Mode d'emploi : comment réutiliser le fichier `.do`

1. **Pré-requis :** Stata 17 ou plus (commande `power` disponible depuis Stata 14).
2. **Adapter le chemin de travail** en modifiant la ligne `cd "C:\RONALDO\CKDEV\..."` en haut du
   fichier vers votre propre dossier de travail.
3. **Paramètres à ajuster en priorité** (repérés par le commentaire `//SPECIFY` dans le fichier) :
   - `n_schools_per_arm`, `n_girls_per_school` : le design envisagé.
   - `alpha_level`, `power_target` : les conventions statistiques (généralement à laisser à
     0,05 / 0,80 sauf exigence particulière du bailleur).
   - `rho_central` et `rho_list` : l'hypothèse (ou la plage d'hypothèses) sur l'ICC — **à mettre
     à jour dès que des données réelles sont disponibles**, via `loneway <outcome> <ecole_id>`.
   - `target_mde_20` (bloc 2) et `target_mde_list` (bloc 4) : les tailles d'effet à tester.
   - `p_control` et `mde_pp_list` (bloc 8) : pour les outcomes binaires.
4. **Exécuter le script en entier** (`do power_gender_norm.do`) ou bloc par bloc — chaque bloc est
   autonome après exécution du Bloc 0 (housekeeping) et du Bloc 1 (paramètres).
5. **Résultats produits automatiquement :**
   - `Power_MDE_CKDev_Benin_summary.xlsx` : toutes les tables numériques, prêtes à partager avec
     le PI ou le bailleur.
   - `MDE_sensitivity_CKDev_Benin.png` : le graphique de sensibilité MDE / ICC / nombre d'écoles.
   - `power_gender_norm.log` : le journal complet de l'exécution (utile pour audit/réplication).
6. **Dès que des données pilotes existent :** remplacer les scalaires `sd_outcome`,
   `baseline_mean` et `rho_central` par les valeurs réelles calculées via :
   ```stata
   quietly sum <variable_outcome>
   scalar sd_outcome    = r(sd)
   scalar baseline_mean = r(mean)
   loneway <variable_outcome> <identifiant_ecole>
   scalar rho_central   = r(rho)
   ```
   puis relancer le script pour obtenir des estimations de puissance fondées sur des données
   réelles plutôt que sur des hypothèses.

---

*Note préparée à partir de l'adaptation du template J-PAL « Sample_Size_and_Power » (J-PAL,
[ressource « Calculs de puissance »](https://www.povertyactionlab.org/fr/resource/calculs-de-puissance) ;
[dépôt GitHub J-PAL/Sample_Size_and_Power](https://github.com/J-PAL/Sample_Size_and_Power)),
adaptation réalisée par Ronaldo Agbohou.*
