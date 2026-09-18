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

Cette note (i) définit tous les termes techniques utilisés, (ii) présente et démontre pas à pas la
formule mathématique du MDE — utilisable telle quelle dans le protocole de recherche et dans un
enseignement de méthodologie —, (iii) **inverse cette formule pour dimensionner l'échantillon** :
nombre d'écoles $J$, nombre de filles par école $n$, effectif total $N$, puis effectif à recruter
compte tenu de l'attrition, (iv) traduit les résultats du log en langage clair pour le PI/l'équipe
KCDev, et (v) explique comment réutiliser le fichier `.do`.

> **Réponse opérationnelle immédiate** (détaillée et démontrée en section 4) : avec **20 filles
> enquêtées par école**, un ICC de 0,10 et une cible de 0,20 SD, il faut **57 écoles par bras**,
> soit **171 écoles** et **3 420 filles analysées** — ce qui suppose d'en **recruter 4 275** pour
> absorber une attrition de 20 %.

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

### 2.4 Le tableau des quatre issues possibles d'un test d'hypothèse (erreurs de type I et II)

Les concepts d'alpha et de puissance (§2.2 et §2.3) se comprennent mieux ensemble, à partir du
tableau croisé ci-dessous, qui liste les **quatre situations possibles** lorsqu'on teste une
hypothèse nulle $H_0$ (ici, $H_0$ = « le traitement n'a aucun effet ») :

|                                                 | **Ne pas rejeter $H_0$**                                            | **Rejeter $H_0$**                                                   |
| ----------------------------------------------- | --------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| **$H_0$ est vraie** (pas d'effet réel) | Décision correcte                                                          | Décision incorrecte :**Erreur de type I** — probabilité $\alpha$ |
| **$H_0$ est fausse** (effet réel)      | Décision incorrecte :**Erreur de type II** — probabilité $\beta$ | Décision correcte                                                          |

**Définitions à retenir :**

- **Erreur de type I** : rejeter à tort une hypothèse nulle qui est en réalité vraie — c'est-à-dire
  conclure que le traitement a un effet alors qu'il n'en a pas. Sa probabilité est **alpha ($\alpha$)**,
  le seuil de signification défini en §2.2 (« alpha est la taille du test »).
- **Erreur de type II** : ne pas rejeter une hypothèse nulle qui est en réalité fausse — c'est-à-dire
  ne pas détecter un effet du traitement qui existe pourtant réellement. Sa probabilité est
  **bêta ($\beta$)** : c'est la probabilité de ne pas rejeter $H_0$ alors qu'elle est fausse.
- **La puissance statistique est le complément de $\beta$ : $\text{puissance} = 1-\beta$.** Une
  puissance de 80 % équivaut donc à accepter un risque d'erreur de type II ($\beta$) de 20 %.

Ce tableau est la base conceptuelle de tous les calculs qui suivent dans cette note : choisir
$\alpha=0{,}05$ et une puissance de $0{,}80$ revient à décider, *avant même de collecter les
données*, du niveau de risque que l'on accepte de courir sur chacune des deux colonnes du tableau.

### 2.5 Comment augmenter la puissance statistique — et pourquoi le cas CKDev est particulier

Dans un contexte standard (essai randomisé simple, individu par individu, deux bras seulement), la
littérature méthodologique retient généralement trois leviers pour augmenter la puissance
statistique d'un test :

1. **Augmenter la taille de l'échantillon.** Un échantillon plus grand apporte davantage
   d'information sur la population, ce qui facilite la détection d'un effet réel. À l'inverse, une
   puissance jugée insuffisante est souvent le signal qu'il faut agrandir l'échantillon.
2. **Viser (ou espérer) un effet plus grand.** Un effet de grande ampleur est mécaniquement plus
   facile à détecter statistiquement qu'un effet ténu — à échantillon égal, la puissance augmente
   avec la taille de l'effet réel.
3. **Relâcher le seuil de signification.** Un seuil de signification plus strict (par exemple 1 %
   plutôt que 5 %) réduit la puissance, car il devient plus difficile de rejeter $H_0$ même quand
   elle est fausse — ce qui revient à accepter davantage de risque d'erreur de type II. À l'inverse,
   un seuil moins strict augmente la puissance (mais au prix d'un risque accru d'erreur de type I).

En résumé, la recette générale pour obtenir une puissance élevée est : **un échantillon
suffisamment grand et un effet à détecter suffisamment large.**

#### Pourquoi le cas d'espèce (projet CKDev) s'écarte de cette recette standard

Cette recette générale suppose implicitement un design simple — randomisation individuelle et
deux bras. **Le projet CKDev s'en écarte sur trois points essentiels, qui obligent à nuancer
chacun des trois leviers ci-dessus :**

**a) « Augmenter l'échantillon » ne veut pas dire la même chose ici.** Parce que la randomisation
se fait au niveau de l'**école** et non de la fille (design en grappes, §2.1), le levier
« taille d'échantillon » se scinde en réalité en deux leviers distincts et **non équivalents** :
augmenter le nombre d'écoles ($J$), ou augmenter le nombre de filles par école ($n$). Comme
démontré dans la formule du MDE (§3.5), le premier levier est presque toujours plus efficace que
le second : à cause de l'ICC ($\rho$), ajouter des filles dans les écoles déjà incluses a des
rendements rapidement décroissants, alors qu'ajouter des écoles reste efficace. **« Augmenter
l'échantillon » dans ce projet signifie donc, en priorité, augmenter le nombre d'écoles — pas
le nombre de filles enquêtées.** C'est précisément ce qu'illustrent les Tables 0 et 0bis du §5.1 :
passer de 30 à 40 filles/école ne fait gagner que 3 écoles/bras, alors que l'ICC à lui seul fait
varier le besoin de 33 à 89 écoles/bras.

**b) Le design a trois bras, pas deux — avec un bras contrôle partagé.** La recette standard
(« deux bras ») suppose une seule comparaison. Ici, il y a **deux bras de traitement (T1 et T2) et
un seul bras de contrôle**, et l'analyse principale effectue **deux comparaisons distinctes**
(T1 vs Contrôle, et T2 vs Contrôle) qui **partagent le même groupe contrôle**. Deux conséquences
pratiques pour la puissance :

- Chaque comparaison individuelle (par exemple T1 vs Contrôle) garde la même logique de calcul
  que dans un design à deux bras — c'est ce que fait le script Stata bloc par bloc (§5.2, Table
  1) — mais le nombre d'écoles disponibles pour le bras contrôle doit être partagé entre les
     deux comparaisons, ce qui contraint l'allocation globale des 150 écoles (50/50/50) davantage
     que si l'étude ne comportait qu'un seul bras traité face au contrôle.
- Réaliser plusieurs comparaisons sur le même jeu de données (T1 vs C, T2 vs C, et éventuellement
  T1 vs T2) augmente le risque global de faux positifs (erreurs de type I cumulées sur
  l'ensemble des tests) — un point que le protocole doit mentionner explicitement, même si le
  script actuel calcule chaque comparaison isolément sans correction pour comparaisons
  multiples.

**c) La contrainte n'est pas symétrique entre $n$ et $J$ à budget donné.** Avec **20 filles
enquêtées par école** dans le design retenu, le nombre de filles par école est **fixé et modeste**
comparé aux 30 utilisées dans les tableaux d'origine du script (15 en 6ᵉ + 15 en 5ᵉ) : la marge de
manœuvre sur le levier « $n$ » est donc plus réduite, et le poids relatif du nombre d'écoles ($J$)
dans la puissance totale du design est encore plus déterminant que dans les Tables 0bis et 4.4 du
§4, qui exploraient des valeurs de $n$ allant jusqu'à 40. **Concrètement : avec seulement 20 filles
par école, le seul levier réellement efficace pour ramener le design à la puissance requise face
à un ICC plus élevé que prévu sera d'augmenter le nombre d'écoles par bras — pas le nombre de
filles enquêtées.**

**En synthèse :** la recette générale (plus d'échantillon, effet plus grand, seuil plus souple)
reste valable en théorie, mais dans un design en grappes à bras multiples comme celui-ci, le
premier levier (« plus d'échantillon ») doit être compris spécifiquement comme « plus d'écoles »,
et non « plus de filles » — et le partage d'un même groupe contrôle entre deux comparaisons ajoute
une contrainte d'allocation et un risque de comparaisons multiples que le protocole doit traiter
explicitement.

### 2.6 Effet minimum détectable — `MDE` (delta dans les tableaux Stata)

C'est la plus petite différence entre le groupe traité et le groupe contrôle que le design est
capable de détecter avec la puissance et le seuil choisis. Il est exprimé ici **en écarts-types
(SD) de l'outcome**, car aucune donnée de base (pilote) n'existe encore : on travaille donc en
variables « standardisées » (moyenne = 0, écart-type = 1). Un MDE de 0,20 signifie « le design
peut détecter un effet égal à 20 % d'un écart-type de l'outcome, pas moins ». Plus le MDE est
petit, plus le design est puissant (mais plus il faut d'échantillon).

> Remarque pratique : « effet de 20 % » est un raccourci de langage pour « effet de 0,20 écart-type »,
> une unité standard en économie du développement (dite *taille d'effet standardisée* ou *Cohen's d*).
> Ce n'est **pas** 20 % du niveau moyen de l'outcome.

### 2.7 Coefficient de corrélation intra-classe — `ICC` / `rho`

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

### 2.8 Nombre de grappes et ratio de grappes — `k1`, `k2`, `kratio`

- `k1` = nombre d'écoles dans le groupe de référence (souvent le contrôle).
- `k2` = nombre d'écoles dans le groupe comparé (souvent le traitement).
- `kratio` = k2 / k1 (ici toujours 1, car on prévoit un nombre égal d'écoles par bras).

### 2.9 Taille par grappe et ratio — `m1`, `m2`, `mratio`

- `m1` / `m2` = nombre de filles enquêtées par école dans chaque groupe (ici 30 : 15 en 6ᵉ et 15 en 5ᵉ).
- `mratio` = m2 / m1 (ici 1, même nombre de filles par école dans les deux groupes).

### 2.10 Écart-type de l'outcome — `sd`

Dispersion de l'outcome dans la population. Fixé à 1 ici car l'outcome est standardisé (pas encore
de données réelles). À remplacer plus tard par l'écart-type réel de l'indicateur mesuré (temps
consacré aux corvées, score de test, etc.).

### 2.11 `power twomeans` vs `power twoproportions`

- **`power twomeans`** : utilisé pour un outcome **continu** (ex. nombre d'heures de corvées,
  score d'aspiration). Le paramètre clé est `sd` (écart-type).
- **`power twoproportions`** : utilisé pour un outcome **binaire** (oui/non), par exemple « la
  fille dispose-t-elle d'un créneau d'étude protégé ? ». Ici, pas besoin de `sd` séparé : la
  variance est automatiquement déduite de la proportion de référence (`p1`) et de la proportion
  attendue dans le groupe traité (`p2`).

### 2.12 Ajustement ANCOVA (covariable de base) — `R²`

Si l'on dispose d'une mesure de l'outcome **avant** l'intervention (baseline) et qu'on l'utilise
comme variable de contrôle dans la régression finale, on réduit la variance résiduelle non
expliquée, donc on **améliore la puissance** (MDE plus petit) sans changer la taille d'échantillon.
Le `R²` de baseline indique la part de la variance de l'outcome final expliquée par les covariables
de base (ex. 20-40 % typiquement observé dans les études d'éducation/usage du temps).

### 2.13 Attrition

Proportion de filles/ménages perdus entre l'enquête de référence (baseline) et l'enquête finale
(endline) — refus, déménagement, absence, etc. L'attrition réduit le nombre effectif de filles
suivies par école (`m1_eff`), donc dégrade légèrement la puissance / augmente le MDE.

### 2.14 Randomisation emboîtée (« nested ») mère vs père

À l'intérieur des bras traités (T1 et T2), les écoles sont en plus randomisées entre un ciblage
« mère » et un ciblage « père » du message. Cette comparaison secondaire dispose de **moins
d'écoles** que la comparaison principale (traitement vs contrôle), car elle n'utilise que les
écoles déjà traitées : elle est donc **mécaniquement moins puissante** (MDE plus grand).

---

## 3. La formule du MDE : construction terme par terme

Cette section explicite **la formule mathématique que Stata utilise en arrière-plan** lorsqu'on
tape `power twomeans, cluster`. L'objectif est double : (i) permettre de comprendre — et non
seulement d'exécuter — le calcul, et (ii) fournir une formule citable telle quelle dans le
protocole de recherche, avec sa justification scientifique.

### 3.1 Pourquoi une formule « spéciale » pour les essais en grappes ?

Dans un essai randomisé classique (randomisation au niveau individuel), chaque fille enquêtée
apporte une information statistiquement indépendante des autres. Ici, ce n'est pas le cas : la
randomisation se fait au niveau de **l'école**, alors que l'outcome est mesuré au niveau de **la
fille**. Deux filles de la même école partagent le même environnement scolaire, le même
facilitateur, la même exposition à l'intervention — elles ont donc tendance à se ressembler sur
l'outcome, indépendamment du fait qu'elles soient traitées ou non. On dit que leurs résultats sont
**corrélés au sein d'une grappe (l'école)**.

**Pourquoi c'est important :** si l'on ignore cette corrélation et qu'on traite les 30 filles
d'une école comme 30 observations indépendantes, on **sous-estime l'erreur standard** de l'effet
mesuré, ce qui **surestime artificiellement la puissance réelle du design** (on croit pouvoir
détecter des effets plus petits qu'on ne le peut réellement). La formule de puissance en grappes
corrige ce biais en ajoutant un terme spécifique, le **coefficient de corrélation intra-classe
($\rho$)**, qui pénalise la formule lorsque les filles d'une même école se ressemblent trop.

### 3.2 La formule complète

$$
MDE = M(\kappa,\alpha)\times\sqrt{\dfrac{1}{P(1-P)}}\times\sqrt{\dfrac{\rho}{J}+\dfrac{1-\rho}{J\cdot n}}\times\sigma\times\sqrt{1-R^2}
$$

Cette formule est la version « en grappes » de la formule de puissance classique pour la
comparaison de deux moyennes. Elle est composée de **quatre blocs multiplicatifs**, chacun ayant
un rôle et une justification propres. Nous les détaillons un par un ci-dessous, dans l'ordre où
ils apparaissent.

---

### 3.3 Bloc 1 — $M(\kappa,\alpha)$ : le « prix à payer » pour la puissance et le seuil de signification

$$
M(\kappa,\alpha) = t_{1-\kappa} + t_{\alpha/2}
$$

**Nouveaux termes à définir :**

- $t_{1-\kappa}$ : la valeur critique de la loi de Student (ou, en approximation, de la loi
  normale) correspondant à la puissance visée $\kappa$. Pour $\kappa = 0{,}80$ (80 %), cette
  valeur vaut environ **0,84**.
- $t_{\alpha/2}$ : la valeur critique correspondant au seuil de signification bilatéral $\alpha$.
  Pour $\alpha = 0{,}05$ (test bilatéral, donc $\alpha/2 = 0{,}025$ de chaque côté), cette valeur
  vaut environ **1,96**.
- $M(\kappa,\alpha)$ : la somme des deux, soit $0{,}84 + 1{,}96 \approx \mathbf{2{,}80}$ pour la
  convention standard (puissance 80 %, seuil bilatéral 5 %).

**Pourquoi ce terme existe :** c'est lui qui traduit numériquement les deux risques d'erreur que
l'on accepte de courir dans un test statistique :

- le **risque de première espèce ($\alpha$)** : conclure à tort qu'il y a un effet (faux positif) ;
- le **risque de deuxième espèce ($1-\kappa$)** : ne pas détecter un effet qui existe réellement
  (faux négatif).

Plus on exige une puissance élevée (ex. 90 % au lieu de 80 %) ou un seuil de signification plus
strict (ex. 1 % au lieu de 5 %), plus $M(\kappa,\alpha)$ augmente, et donc plus le MDE augmente
(le design devient plus exigeant, il faut un effet plus grand — ou un échantillon plus important —
pour conclure).

> **Point de vigilance pédagogique :** Stata utilise la loi de Student (qui dépend des degrés de
> liberté, eux-mêmes liés au nombre d'écoles) plutôt que la loi normale pour ce calcul, ce qui
> explique de très légers écarts entre la valeur « à la main » (2,80, avec la loi normale) et la
> valeur exacte produite par `power twomeans` (voir vérification numérique en §3.7).

### 3.4 Bloc 2 — $\sqrt{\dfrac{1}{P(1-P)}}$ : le facteur d'allocation entre bras

**Nouveau terme à définir :**

- $P$ : la **proportion de l'échantillon (d'écoles) allouée au bras traité**. Dans le design
  CKDev, chaque comparaison oppose un bras traité à un bras contrôle en nombre égal d'écoles, donc
  $P = 0{,}5$.

**Pourquoi ce terme existe :** l'information statistique disponible pour comparer deux groupes est
maximale lorsque les deux groupes ont la même taille ($P=0{,}5$). Si l'allocation est déséquilibrée
(par exemple 70 % des écoles traitées contre 30 % au contrôle), le terme $\dfrac{1}{P(1-P)}$
augmente, ce qui dégrade la précision de la comparaison — **à nombre total d'écoles égal**, un
design déséquilibré est toujours moins puissant qu'un design équilibré.

**Calcul avec $P=0{,}5$ :** $P(1-P) = 0{,}5\times0{,}5 = 0{,}25$, donc $\dfrac{1}{P(1-P)} = 4$, et
$\sqrt{4} = 2$. C'est pourquoi, dans le cas équilibré (le cas du projet CKDev), ce bloc se réduit
simplement à un facteur multiplicatif de **2** — c'est la simplification utilisée dans la note
précédente.

### 3.5 Bloc 3 — $\sqrt{\dfrac{\rho}{J}+\dfrac{1-\rho}{J\cdot n}}$ : le cœur « grappes » de la formule

C'est le bloc le plus important à comprendre, car c'est lui qui distingue un essai en grappes d'un
essai randomisé individuellement.

**Termes déjà définis en section 2, rappelés ici dans leur rôle exact :**

- $\rho$ (ICC) : la corrélation intra-école (section 2.7).
- $J$ : **le nombre total d'écoles dans les deux bras comparés** (contrôle + traitement).
  ⚠️ **Point de vigilance essentiel** : $J$ n'est **pas** le nombre d'écoles par bras. Pour une
  comparaison T1 vs Contrôle avec 50 écoles de chaque côté, $J = 100$. Cette confusion est la
  source d'erreur la plus fréquente lorsqu'on transpose cette formule à la main : si l'on utilise
  par erreur $J=50$ (le nombre d'écoles *par bras*) tout en gardant le facteur $1/(P(1-P))$ du
  bloc 2, on obtient un MDE trop grand d'un facteur $\sqrt{2}$ (voir vérification numérique en
  §3.7, qui montre explicitement les deux cas).
- $n$ : le nombre de filles enquêtées par école (section 2.9).

**Pourquoi ce bloc a exactement cette forme — intuition mathématique :**
Ce terme est la variance de l'estimateur de l'effet moyen, décomposée en deux sources
d'incertitude :

1. $\dfrac{\rho}{J}$ : la part de variance liée à la **variabilité entre écoles**. Ce terme ne
   dépend **pas** de $n$ : quel que soit le nombre de filles enquêtées dans une école, cette école
   reste une seule et unique observation du point de vue de la variabilité inter-écoles. **C'est
   ce terme qui explique pourquoi ajouter des écoles est toujours efficace, alors qu'ajouter des
   filles dans les mêmes écoles a des rendements décroissants.**
2. $\dfrac{1-\rho}{J\cdot n}$ : la part de variance liée à la **variabilité entre filles à
   l'intérieur d'une même école**. Ce terme diminue à la fois avec $J$ (plus d'écoles) et avec $n$
   (plus de filles par école), mais il est **pondéré par $(1-\rho)$** : plus $\rho$ est élevé,
   moins ce deuxième terme compte, et moins ajouter des filles par école est utile.

**Cas limites pédagogiques utiles à illustrer en cours :**

- Si $\rho = 0$ (aucune ressemblance intra-école, cas théorique) : la formule se réduit à
  $\dfrac{1}{J\cdot n}$, exactement la formule d'un essai randomisé au niveau individuel avec
  $J\cdot n$ observations indépendantes.
- Si $\rho = 1$ (toutes les filles d'une école sont identiques sur l'outcome, cas théorique
  extrême) : la formule se réduit à $\dfrac{1}{J}$ — enquêter plus de filles par école n'apporte
  alors **strictement aucune information supplémentaire** ; seul le nombre d'écoles compte.

Le design CKDev, avec $\rho \approx 0{,}10$, se situe entre ces deux extrêmes, mais nettement plus
proche du cas « $\rho$ élevé » que du cas individuel — d'où l'importance disproportionnée du
nombre d'écoles par rapport au nombre de filles par école dans tous les résultats du §5.

### 3.6 Bloc 4 — $\sigma\times\sqrt{1-R^2}$ : l'échelle de mesure et l'ajustement ANCOVA

- $\sigma$ : l'écart-type de la variable de résultat (section 2.10). Il convertit le MDE, qui est
  une quantité sans dimension issue des trois blocs précédents, dans **l'unité de mesure réelle de
  l'outcome** (écarts-types de l'indicateur étudié).
- $R^2$ (nouveau dans cette section, déjà introduit en 2.12) : la part de variance de l'outcome
  final expliquée par des covariables mesurées **avant** l'intervention (baseline). Le terme
  $\sqrt{1-R^2}$ réduit le MDE parce qu'il retire de $\sigma$ la portion de variance qui est déjà
  « expliquée » — donc prévisible — par la situation initiale des filles, ne laissant que la
  variance réellement résiduelle, celle sur laquelle l'intervention doit encore faire ses preuves
  statistiquement.

**Pourquoi ce terme est ajouté à la formule « de base » :** la formule de puissance la plus simple
(sans ANCOVA) suppose qu'on compare seulement les moyennes brutes à l'endline. Mais si le protocole
prévoit — comme c'est le cas ici — de contrôler pour des variables de baseline dans la régression
finale (section 11.2 du guide de projet), il faut en tenir compte dès l'étape de calcul de
puissance, sous peine de sous-estimer la précision réellement atteignable. C'est l'objet du
**Bloc 5 (ANCOVA)** de la section 5.4 de cette note.

### 3.7 Vérification numérique complète, terme par terme

Reprenons la comparaison principale **T1 vs Contrôle**, avec les paramètres du design CKDev :
$\kappa=0{,}80$, $\alpha=0{,}05$, $P=0{,}5$, $\rho=0{,}10$, $J=100$ (50+50), $n=30$, $\sigma=1$,
$R^2=0$.

| Étape                         | Calcul                                           | Résultat          |
| ------------------------------ | ------------------------------------------------ | ------------------ |
| 1.$M(\kappa,\alpha)$         | $0{,}84+1{,}96$                                | $2{,}80$         |
| 2.$\sqrt{1/(P(1-P))}$        | $\sqrt{1/0{,}25}$                              | $2{,}00$         |
| 3.$\rho/J$                   | $0{,}10/100$                                   | $0{,}0010$       |
| 4.$(1-\rho)/(J\cdot n)$      | $0{,}90/(100\times30)$                         | $0{,}0003$       |
| 5. Somme (3+4) puis racine     | $\sqrt{0{,}0013}$                              | $0{,}0361$       |
| 6.$\sigma\times\sqrt{1-R^2}$ | $1\times\sqrt{1}$                              | $1{,}00$         |
| **MDE final**            | $2{,}80\times2{,}00\times0{,}0361\times1{,}00$ | **≈ 0,202** |

→ Résultat **identique** au 0,202 SD obtenu par `power twomeans, cluster` dans la Table 1 du log
(l'écart au 3ᵉ chiffre s'explique uniquement par l'usage de la loi de Student par Stata, plus
précise que l'approximation normale utilisée ici pour la pédagogie).

**Vérification de l'erreur classique à éviter (mauvaise définition de $J$) :** si l'on utilisait
par erreur $J=50$ (nombre d'écoles *par bras*, et non total) sans ajuster le bloc 2, on obtiendrait :

$$
2{,}80\times2{,}00\times\sqrt{\dfrac{0{,}10}{50}+\dfrac{0{,}90}{50\times30}} = 2{,}80\times2{,}00\times0{,}0510 \approx 0{,}286
$$

— un chiffre **différent et trompeur** (il correspond en réalité, par coïncidence, au MDE de la
comparaison secondaire mère/père *à l'intérieur d'un seul bras*, qui utilise effectivement
25+25=50 écoles au total — voir §5.6). Cette vérification illustre concrètement pourquoi la
définition de $J$ doit être rappelée explicitement dans le protocole.

**Vérification avec ajustement ANCOVA ($R^2=0{,}30$) :** en reprenant le résultat ci-dessus et en
multipliant par $\sqrt{1-0{,}30}=\sqrt{0{,}70}\approx0{,}837$ :

$$
0{,}202\times0{,}837 \approx 0{,}169
$$

→ Résultat **identique** à la Table 3 du log (0,169 pour $R^2=30\,\%$), confirmant que la formule
complète (avec le terme $\sqrt{1-R^2}$) reproduit exactement tous les scénarios testés dans le
script Stata, ANCOVA compris.

### 3.8 Les formules inverses : vers le dimensionnement de l'échantillon

La formule du §3.2 répond à la question « quel est le plus petit effet détectable, **étant donné**
un design ? ». Mais au stade du protocole, la question opérationnelle est l'inverse : « **quel
design faut-il** pour atteindre un MDE cible ? ». Trois inversions successives sont nécessaires :

1. isoler $J$ (le nombre d'écoles) — **§4.3**
2. isoler $n$ (le nombre de filles par école) — **§4.4**
3. en déduire $N$ (l'échantillon total), puis l'échantillon **à recruter** compte tenu de
   l'attrition — **§4.5 et §4.6**

Ces trois inversions, ainsi que la démonstration algébrique complète qui y conduit, font l'objet
de la **section 4** ci-dessous.

### 3.9 Glossaire complémentaire des nouveaux termes introduits dans cette section

| Symbole              | Nom                                | Définition                                                                                          | Valeur dans le design CKDev (comparaison principale) |
| -------------------- | ---------------------------------- | ---------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| $M(\kappa,\alpha)$ | Facteur de puissance-signification | Somme des valeurs critiques associées à la puissance visée et au seuil de signification           | ≈ 2,80                                              |
| $t_{1-\kappa}$     | Valeur critique de puissance       | Quantile de la loi de Student (ou normale) correspondant à la puissance$\kappa$                   | ≈ 0,84 (pour$\kappa=0{,}80$)                      |
| $t_{\alpha/2}$     | Valeur critique de signification   | Quantile de la loi de Student (ou normale) correspondant au seuil bilatéral$\alpha$               | ≈ 1,96 (pour$\alpha=0{,}05$)                      |
| $P$                | Ratio d'allocation                 | Proportion des écoles allouées au bras traité                                                     | 0,5 (allocation équilibrée)                        |
| $J$                | Nombre total de grappes            | Nombre**total** d'écoles dans les **deux bras comparés** (et non par bras)             | 100 (50+50)                                          |
| $R^2$              | Pouvoir explicatif de la baseline  | Part de la variance de l'outcome final expliquée par des covariables mesurées avant l'intervention | 0 à 0,40 selon scénario                            |

---

## 4. De la formule au dimensionnement de l'échantillon : démonstration complète

Cette section est le cœur opérationnel de la note. Elle montre, **sans sauter une seule étape
algébrique**, comment on part de la formule de puissance classique (randomisation individuelle)
pour aboutir successivement :

- à la formule du MDE en grappes (§4.1 et §4.2),
- au nombre d'écoles requis $J$ (§4.3),
- au nombre de filles par école requis $n$ (§4.4),
- à l'échantillon total $N$ (§4.5),
- et enfin à l'échantillon **à recruter sur le terrain** compte tenu de l'attrition (§4.6).

Chaque substitution est explicitée : aucun terme n'apparaît sans qu'on ait dit d'où il vient.

---

### 4.1 Le point de départ : l'équation de puissance classique

La formule de référence, pour une randomisation **individuelle** (chaque observation est
indépendante des autres), s'écrit :

$$
MDE = \left(t_{1-\kappa}+t_{\alpha/2}\right)\sqrt{\dfrac{1}{P(1-P)}\times\dfrac{\sigma^2}{N}}
$$

Cette équation n'est pas un postulat : elle se démontre en deux temps, l'un portant sur la
**précision** de l'estimateur, l'autre sur les **risques d'erreur** acceptés.

#### 4.1.a — D'où vient le contenu de la racine carrée (la précision)

L'effet du traitement est estimé par la différence des moyennes observées :

$$
\hat\beta = \bar{Y}_{\text{traité}} - \bar{Y}_{\text{contrôle}}
$$

Pour une moyenne calculée sur des observations indépendantes de variance $\sigma^2$ :

$$
\text{Var}(\bar{Y}_{\text{traité}}) = \dfrac{\sigma^2}{N_T}
\qquad\qquad
\text{Var}(\bar{Y}_{\text{contrôle}}) = \dfrac{\sigma^2}{N_C}
$$

Les deux groupes étant disjoints et indépendants, **les variances s'additionnent** :

$$
\text{Var}(\hat\beta) = \dfrac{\sigma^2}{N_T}+\dfrac{\sigma^2}{N_C}
$$

On introduit alors $N$ (effectif **total**) et $P$ (part allouée au traitement), de sorte que
$N_T = PN$ et $N_C = (1-P)N$ :

$$
\text{Var}(\hat\beta)=\dfrac{\sigma^2}{PN}+\dfrac{\sigma^2}{(1-P)N}
=\dfrac{\sigma^2}{N}\left[\dfrac{1}{P}+\dfrac{1}{1-P}\right]
$$

Le crochet se simplifie en mettant au même dénominateur :

$$
\dfrac{1}{P}+\dfrac{1}{1-P}=\dfrac{(1-P)+P}{P(1-P)}=\dfrac{1}{P(1-P)}
\qquad\text{car } (1-P)+P=1
$$

D'où le résultat :

$$
\boxed{\;\text{Var}(\hat\beta)=\dfrac{1}{P(1-P)}\times\dfrac{\sigma^2}{N}\;}
$$

**C'est exactement l'intérieur de la racine.** L'erreur standard $SE(\hat\beta)$ en est la racine
carrée.

> **Lecture du terme $\frac{1}{P(1-P)}$ :** il est minimal pour $P=0{,}5$ (il vaut alors 4) et
> augmente dès qu'on s'éloigne de l'équilibre entre bras. À effectif total identique, un design
> déséquilibré est donc toujours moins précis. C'est le « prix de l'asymétrie ».

#### 4.1.b — D'où vient le facteur $(t_{1-\kappa}+t_{\alpha/2})$ (les risques d'erreur)

Ce facteur ne dépend pas de l'échantillon : il traduit les deux risques définis au §2.4.

- **$t_{\alpha/2}$ — le seuil de rejet.** On rejette $H_0$ si l'effet estimé dépasse
  $t_{\alpha/2}\times SE(\hat\beta)$. Pour $\alpha=0{,}05$ bilatéral (soit 0,025 de chaque côté) :
  $t_{\alpha/2}\approx 1{,}96$.
- **$t_{1-\kappa}$ — la marge de puissance.** Franchir le seuil une fois ne suffit pas : on veut le
  franchir dans $\kappa$ % des échantillons possibles. Cela impose une distance supplémentaire
  $t_{1-\kappa}\times SE(\hat\beta)$. Pour $\kappa=0{,}80$ (donc $\beta=0{,}20$) :
  $t_{1-\kappa}\approx 0{,}84$.

L'effet doit couvrir **les deux distances cumulées**, d'où leur somme :

$$
M(\kappa,\alpha)=t_{1-\kappa}+t_{\alpha/2}\approx 0{,}84+1{,}96=\mathbf{2{,}80}
$$

$$
MDE = M(\kappa,\alpha)\times SE(\hat\beta)
$$

En remplaçant $SE(\hat\beta)$ par la racine obtenue en §4.1.a, **on retrouve l'équation de départ**.
La démonstration du cas classique est bouclée.

---

### 4.2 Le passage aux grappes : on ne remplace qu'un seul morceau

#### 4.2.a — Pourquoi $\sigma^2/N$ devient invalide ici

Le terme $\sigma^2/N$ suppose $N$ observations **indépendantes**. Or, dans ce projet, les filles
d'une même école partagent le même établissement, le même facilitateur et la même exposition. On
décompose donc l'outcome de la fille $i$ dans l'école $j$ :

$$
Y_{ij}=\mu+\underbrace{u_j}_{\text{effet école}}+\underbrace{e_{ij}}_{\text{écart individuel}}
$$

| Composante | Signification                            | Variance                                          |
| ---------- | ---------------------------------------- | ------------------------------------------------- |
| $u_j$    | ce qui est commun à toute l'école$j$ | $\tau^2$ — variance **inter**-écoles    |
| $e_{ij}$ | ce qui est propre à la fille$i$       | $\sigma_w^2$ — variance **intra**-école |

La variance totale se décompose ainsi : $\sigma^2=\tau^2+\sigma_w^2$.

**Définition formelle de l'ICC** (le $\rho$ introduit au §2.7) :

$$
\rho=\dfrac{\tau^2}{\tau^2+\sigma_w^2}=\dfrac{\tau^2}{\sigma^2}
$$

C'est la **part de la variance totale attribuable au niveau école**. On en tire les deux identités
qui serviront de substitution :

$$
\tau^2=\rho\,\sigma^2
\qquad\text{et}\qquad
\sigma_w^2=(1-\rho)\,\sigma^2
$$

#### 4.2.b — Variance de la moyenne d'UNE école ($n$ filles enquêtées)

$$
\text{Var}(\bar{Y}_j)=\underbrace{\tau^2}_{\text{ne diminue jamais}}+\underbrace{\dfrac{\sigma_w^2}{n}}_{\text{diminue avec }n}
$$

> **C'est le point décisif de toute la démonstration.** Enquêter davantage de filles dans une
> école ne réduit que le **second** terme. Le premier, $\tau^2$, reste identique : une école reste
> une école, quel que soit le nombre de filles interrogées à l'intérieur. C'est la traduction
> mathématique exacte de tout ce qui a été affirmé aux §2.5 et §2.7.

#### 4.2.c — Variance de la moyenne d'UN BRAS ($k$ écoles)

Les écoles étant indépendantes les unes des autres, la moyenne d'un bras de $k$ écoles a pour
variance :

$$
\text{Var}(\bar{Y}_{\text{bras}})=\dfrac{\tau^2+\dfrac{\sigma_w^2}{n}}{k}
$$

Pour alléger l'écriture des étapes suivantes, posons une fois pour toutes :

$$
\boxed{\;V_{\text{école}}=\tau^2+\dfrac{\sigma_w^2}{n}\;}
$$

$V_{\text{école}}$ se lit : « la variance qu'apporte **une école**, compte tenu du fait qu'on y
enquête $n$ filles ». La variance d'un bras s'écrit alors simplement $V_{\text{école}}/k$.

#### 4.2.d — Variance de l'effet estimé : développement intégral

**Point de départ.** L'effet estimé reste la différence des moyennes :

$$
\hat\beta=\bar{Y}_{\text{traité}}-\bar{Y}_{\text{contrôle}}
$$

Avec $k_T$ écoles traitées et $k_C$ écoles contrôle :

$$
\text{Var}(\bar{Y}_{\text{traité}})=\dfrac{V_{\text{école}}}{k_T}
\qquad\qquad
\text{Var}(\bar{Y}_{\text{contrôle}})=\dfrac{V_{\text{école}}}{k_C}
$$

Une école est soit traitée, soit contrôle, jamais les deux : les deux groupes sont indépendants,
**les variances s'additionnent** :

$$
\text{Var}(\hat\beta)=\dfrac{V_{\text{école}}}{k_T}+\dfrac{V_{\text{école}}}{k_C}
$$

**Substitution 1 — introduire $J$ et $P$.** On pose $J=k_T+k_C$ (nombre **total** d'écoles dans les
deux bras comparés) et $P$ = part des écoles allouée au traitement. Donc $k_T=P\,J$ et
$k_C=(1-P)\,J$ :

$$
\text{Var}(\hat\beta)=\dfrac{V_{\text{école}}}{P\,J}+\dfrac{V_{\text{école}}}{(1-P)\,J}
$$

On factorise $\dfrac{V_{\text{école}}}{J}$, présent dans les deux termes :

$$
\text{Var}(\hat\beta)=\dfrac{V_{\text{école}}}{J}\left[\dfrac{1}{P}+\dfrac{1}{1-P}\right]
$$

**Substitution 2 — simplifier le crochet.** Exactement comme au §4.1.a :

$$
\dfrac{1}{P}+\dfrac{1}{1-P}
=\dfrac{1\times(1-P)}{P(1-P)}+\dfrac{1\times P}{P(1-P)}
=\dfrac{(1-P)+P}{P(1-P)}
=\dfrac{1}{P(1-P)}
$$

$$
\text{Var}(\hat\beta)=\dfrac{1}{P(1-P)}\times\dfrac{V_{\text{école}}}{J}
$$

> **À ce stade, comparez avec le §4.1.a :** la structure est rigoureusement identique. Seul
> $\dfrac{\sigma^2}{N}$ a été remplacé par $\dfrac{V_{\text{école}}}{J}$. Rien d'autre n'a bougé.

**Substitution 3 — remplacer $\tau^2$ et $\sigma_w^2$ par $\rho$.** On réinjecte la définition de
$V_{\text{école}}$, puis les deux identités du §4.2.a :

$$
\dfrac{V_{\text{école}}}{J}
=\dfrac{\tau^2+\dfrac{\sigma_w^2}{n}}{J}
=\dfrac{\rho\,\sigma^2+\dfrac{(1-\rho)\,\sigma^2}{n}}{J}
$$

On factorise $\sigma^2$ au numérateur :

$$
=\dfrac{\sigma^2\left(\rho+\dfrac{1-\rho}{n}\right)}{J}
$$

Puis on distribue le $\dfrac{1}{J}$ sur les deux termes de la parenthèse :

$$
\boxed{\;\dfrac{V_{\text{école}}}{J}=\sigma^2\left(\dfrac{\rho}{J}+\dfrac{1-\rho}{J\cdot n}\right)\;}
$$

**Assemblage final.** En remontant :

$$
\text{Var}(\hat\beta)=\dfrac{1}{P(1-P)}\times\sigma^2\left(\dfrac{\rho}{J}+\dfrac{1-\rho}{J\cdot n}\right)
$$

$$
SE(\hat\beta)=\sqrt{\dfrac{1}{P(1-P)}}\times\sigma\sqrt{\dfrac{\rho}{J}+\dfrac{1-\rho}{J\cdot n}}
$$

Et puisque $MDE=M(\kappa,\alpha)\times SE(\hat\beta)$, en ajoutant l'ajustement ANCOVA
($\sigma\rightarrow\sigma\sqrt{1-R^2}$, cf. §3.6) :

$$
\boxed{\;MDE=M(\kappa,\alpha)\sqrt{\dfrac{1}{P(1-P)}}\;\sqrt{\dfrac{\rho}{J}+\dfrac{1-\rho}{J\cdot n}}\;\;\sigma\sqrt{1-R^2}\;}
$$

**La chaîne est complète.** Chaque substitution a été explicitée : $k_T,k_C\rightarrow J,P$ ; puis
crochet $\rightarrow\frac{1}{P(1-P)}$ ; puis $\tau^2,\sigma_w^2\rightarrow\rho,\sigma^2$.

#### 4.2.e — Contrôle de cohérence : l'effet de plan (design effect)

Cette étape n'ajoute rien de neuf mais prouve que la formule en grappes **contient** la formule
classique. Posons $N=J\cdot n$ et factorisons :

$$
\sigma^2\left(\dfrac{\rho}{J}+\dfrac{1-\rho}{Jn}\right)
=\dfrac{\sigma^2}{Jn}\Big(n\rho+1-\rho\Big)
=\dfrac{\sigma^2}{N}\underbrace{\Big(1+(n-1)\rho\Big)}_{DEFF}
$$

**$DEFF=1+(n-1)\rho$** est l'**effet de plan** : le facteur par lequel la variance est multipliée du
seul fait de la randomisation en grappes. Deux vérifications :

- Si $\rho=0$ → $DEFF=1$ → **on retombe exactement sur l'équation du §4.1**. La formule en grappes
  est bien une généralisation, pas une formule concurrente.
- Avec $n=30$ et $\rho=0{,}10$ → $DEFF=1+29\times0{,}10=\mathbf{3{,}9}$. La variance est presque
  quadruplée : les 3 000 filles enquêtées n'apportent autant d'information que
  $3\,000/3{,}9\approx770$ observations indépendantes. **C'est ce chiffre qui explique à lui seul
  pourquoi l'échantillon doit être si important.**

---

### 4.3 Première inversion : extraire $J$ (combien d'écoles ?)

#### 4.3.a — Une constante pour alléger tous les calculs

Regroupons tous les termes qui ne dépendent ni de $J$ ni de $n$ :

$$
\boxed{\;A=\dfrac{M(\kappa,\alpha)^2\times\sigma^2(1-R^2)}{P(1-P)}\;}
$$

Avec les paramètres du projet ($M=2{,}80$ ; $\sigma=1$ ; $R^2=0$ ; $P=0{,}5$ donc $P(1-P)=0{,}25$) :

$$
A=\dfrac{2{,}80^2\times1\times1}{0{,}25}=\dfrac{7{,}84}{0{,}25}=\mathbf{31{,}36}
$$

En élevant la formule du MDE au carré, elle devient très maniable :

$$
MDE^2=A\left(\dfrac{\rho}{J}+\dfrac{1-\rho}{J\cdot n}\right)=\dfrac{A}{J}\left(\rho+\dfrac{1-\rho}{n}\right)
$$

#### 4.3.b — Isoler $J$

$$
\boxed{\;J=\dfrac{A}{MDE^2}\left(\rho+\dfrac{1-\rho}{n}\right)\;}
$$

**Rappel impératif :** $J$ est le nombre **total** d'écoles dans les **deux bras comparés**. Il faut
le diviser par 2 (cas équilibré) pour obtenir le nombre d'écoles **par bras**.

#### 4.3.c — Application : $n = 20$ filles par école, $\rho=0{,}10$, $MDE=0{,}20$

| Étape                          | Calcul                     | Résultat                          |
| ------------------------------- | -------------------------- | ---------------------------------- |
| Terme inter-écoles             | $\rho$                   | 0,100                              |
| Terme intra-école              | $(1-\rho)/n = 0{,}90/20$ | 0,045                              |
| Somme des deux termes           | $0{,}100+0{,}045$        | 0,145                              |
| Facteur$A/MDE^2$              | $31{,}36/0{,}04$         | 784                                |
| **$J$ (total, 2 bras)** | $784\times0{,}145$       | $113{,}7\rightarrow\mathbf{114}$ |
| **Écoles par bras**      | $114/2$                  | **57**                       |

#### 4.3.d — Tableau complet selon $n$ (ρ = 0,10 ; MDE = 0,20 SD)

| Filles/école$n$ | $\rho+\frac{1-\rho}{n}$ | $J$ total | **Écoles/bras**    |
| ------------------ | ------------------------- | ----------- | ------------------------- |
| 20                 | 0,1450                    | 114         | **57**              |
| 25                 | 0,1360                    | 107         | **54**              |
| 30                 | 0,1300                    | 102         | **51** (Stata : 52) |
| 35                 | 0,1257                    | 99          | **50**              |
| 40                 | 0,1225                    | 96          | **48** (Stata : 49) |

Les légers écarts avec Stata (±1 école) tiennent uniquement à l'approximation normale de
$M(\kappa,\alpha)$, Stata utilisant la loi de Student exacte. Les ordres de grandeur sont
identiques.

---

### 4.4 Deuxième inversion : extraire $n$ (combien de filles par école ?)

#### 4.4.a — Isoler $n$

On repart de $MDE^2=\dfrac{A}{J}\left(\rho+\dfrac{1-\rho}{n}\right)$ et on isole pas à pas :

$$
\dfrac{J\cdot MDE^2}{A}=\rho+\dfrac{1-\rho}{n}
\qquad\Longrightarrow\qquad
\dfrac{1-\rho}{n}=\dfrac{J\cdot MDE^2}{A}-\rho
$$

$$
\boxed{\;n=\dfrac{1-\rho}{\dfrac{J\cdot MDE^2}{A}-\rho}\;}
$$

#### 4.4.b — Application : $J=100$ (50 écoles/bras, le budget prévu), $\rho=0{,}10$, $MDE=0{,}20$

| Étape                        | Calcul               | Résultat                        |
| ----------------------------- | -------------------- | -------------------------------- |
| $J\times MDE^2$             | $100\times0{,}04$  | 4,00                             |
| Divisé par$A$              | $4{,}00/31{,}36$   | 0,1276                           |
| Moins$\rho$ (dénominateur) | $0{,}1276-0{,}100$ | 0,0276                           |
| **$n$ requis**        | $0{,}90/0{,}0276$  | $32{,}7\rightarrow\mathbf{33}$ |

Stata, avec la loi de Student exacte, donne **35**. C'est ce chiffre de 35 qui doit être retenu
comme valeur opérationnelle (cf. Table 0bis du §5.1).

#### 4.4.c — Le « mur » mathématique : un seuil d'écoles infranchissable

La formule de $n$ révèle une limite absolue : **le dénominateur doit rester strictement positif**,
sans quoi $n$ serait négatif ou infini. La condition s'écrit :

$$
\dfrac{J\cdot MDE^2}{A}>\rho
\qquad\Longleftrightarrow\qquad
J>\dfrac{A\,\rho}{MDE^2}=784\times0{,}10=\mathbf{78{,}4}
$$

> **Traduction opérationnelle :** en dessous de **79 écoles au total** (soit 40 par bras), **aucun
> nombre de filles par école — pas même 1 000 — ne permettra jamais d'atteindre un MDE de 0,20 SD.**
> C'est la conséquence directe du fait que le terme $\rho/J$ ne dépend pas de $n$ (§4.2.b).
> Cet argument est décisif à présenter au PI : il démontre que le nombre d'écoles n'est pas
> négociable en dessous d'un certain plancher, quel que soit l'effort d'enquête consenti.

---

### 4.5 Troisième étape : de $J$ et $n$ vers l'échantillon total $N$

#### 4.5.a — La relation de base et le piège des 3 bras

Pour une comparaison à deux bras :

$$
N_{\text{comparaison}}=J\times n
$$

⚠️ **Attention** : $J$ ne couvre que les **deux bras d'une comparaison**. Le projet comptant
**trois bras** (Contrôle, T1, T2) avec un contrôle partagé, l'échantillon réellement à collecter
sur le terrain est :

$$
\boxed{\;N_{\text{étude, 3 bras}}=3\times\dfrac{J}{2}\times n\;}
$$

où $\dfrac{J}{2}$ est le nombre d'écoles **par bras**.

#### 4.5.b — Tableau de dimensionnement (ρ = 0,10 ; MDE = 0,20 SD ; α = 5 % ; puissance = 80 %)

| Filles/école$n$ | Écoles/bras | Écoles totales (3 bras) | Filles/bras | **$N$ total (3 bras)** |              |               |                 |                 |
| ----------------------------------------------------------------------------------------------------------- | ------------ | ------------- | --------------- | --------------- |
| **20**                                                                                                | **57** | **171** | **1 140** | **3 420** |
| 25                                                                                                          | 54           | 162           | 1 350           | 4 050           |
| 30                                                                                                          | 52           | 156           | 1 560           | 4 680           |
| 35                                                                                                          | 50           | 150           | 1 750           | 5 250           |

**Lecture essentielle — l'arbitrage budgétaire central du projet :** en passant de 20 à 35 filles
par école, on n'économise que **7 écoles par bras**, mais on augmente l'effectif total à enquêter
de **1 830 filles**. Économiser des écoles coûte donc très cher en volume d'enquêtes. Le choix
entre ces lignes doit se faire sur la base de la structure de coûts réelle du terrain (coût d'une
école mobilisée vs coût d'un questionnaire supplémentaire).

#### 4.5.c — Le scénario retenu : 20 filles par école

$$
\boxed{\;n=20\;\Rightarrow\;57\text{ écoles/bras}\;\Rightarrow\;171\text{ écoles}\;\Rightarrow\;N=3\,420\text{ filles}\;}
$$

À comparer aux **150 écoles / 3 000 filles** prévues dans le guide de projet : il manquerait
**21 écoles et 420 filles** pour atteindre la puissance visée.

---

### 4.6 Quatrième étape : intégrer l'attrition dans l'échantillon à recruter

#### 4.6.a — Le principe : le $n$ de la formule est le $n$ **analysé**

Point souvent mal compris, et source d'erreur fréquente dans les protocoles : le $n$ qui apparaît
dans la formule du MDE est le nombre de filles **effectivement retrouvées et analysées à
l'endline**, et non le nombre recruté au départ. Si un taux d'attrition $a$ est anticipé :

$$
n_{\text{analysé}}=n_{\text{recruté}}\times(1-a)
\qquad\Longrightarrow\qquad
\boxed{\;n_{\text{recruté}}=\dfrac{n_{\text{analysé}}}{1-a}\;}
$$

Le facteur $\dfrac{1}{1-a}$ est appelé **facteur d'inflation d'attrition**. Pour un taux
d'attrition de 20 % :

$$
\dfrac{1}{1-0{,}20}=\dfrac{1}{0{,}80}=\mathbf{1{,}25}
$$

Il faut donc recruter **25 % de filles en plus** que le nombre requis à l'analyse — et non 20 % de
plus, erreur de calcul courante.

#### 4.6.b — Stratégie A : compenser par le recrutement (recommandée)

On conserve les 57 écoles par bras et on recrute davantage de filles dans chaque école.

| Élément                                    | Calcul                 | Résultat       |
| -------------------------------------------- | ---------------------- | --------------- |
| Filles**analysées** requises / école | résultat du §4.3.c   | 20              |
| Filles à**recruter** / école         | $20/0{,}80$          | **25**    |
| Écoles par bras                             | inchangé              | 57              |
| Écoles totales (3 bras)                     | $57\times3$          | 171             |
| Filles recrutées / bras                     | $57\times25$         | 1 425           |
| **$N$ total à recruter**            | $171\times25$        | **4 275** |
| $N$ attendu à l'analyse (contrôle)       | $4\,275\times0{,}80$ | 3 420 ✓        |

$$
\boxed{\;\textbf{Recruter 4 275 filles (25/école, 171 écoles) pour en analyser 3 420}\;}
$$

#### 4.6.c — Stratégie B : si l'école ne peut fournir que 20 filles

Si une contrainte de terrain impose un plafond de 20 filles **recrutées** par école, alors
$n_{\text{analysé}}=20\times0{,}80=16$, et il faut compenser par **davantage d'écoles**. On
réapplique la formule du §4.3.b avec $n=16$ :

| Étape                            | Calcul                 | Résultat                          |
| --------------------------------- | ---------------------- | ---------------------------------- |
| Terme intra-école                | $0{,}90/16$          | 0,05625                            |
| Somme avec$\rho$                | $0{,}100+0{,}05625$  | 0,15625                            |
| $J$ total                       | $784\times0{,}15625$ | $122{,}5\rightarrow\mathbf{123}$ |
| **Écoles par bras**        | $123/2$              | **62**                       |
| Écoles totales (3 bras)          | $62\times3$          | 186                                |
| **$N$ total à recruter** | $186\times20$        | **3 720**                    |

#### 4.6.d — Comparaison des deux stratégies

|                             | **Stratégie A** (plus de filles) | **Stratégie B** (plus d'écoles)  |
| --------------------------- | --------------------------------------- | ---------------------------------------- |
| Écoles à mobiliser        | 171                                     | **186** (+15)                      |
| Filles à recruter          | **4 275** (+555)                  | 3 720                                    |
| Filles analysées attendues | 3 420                                   | 2 976 (16 × 186)                        |
| Poste de coût dominant     | questionnaires individuels              | logistique, déplacements, autorisations |

**Recommandation :** la stratégie A est généralement préférable, car mobiliser 15 écoles
supplémentaires (négociation, autorisations administratives, trajets, formation d'enquêteurs
supplémentaires) coûte habituellement plus cher que 555 questionnaires additionnels dans des
écoles **déjà visitées**. L'arbitrage final dépend toutefois de la structure de coûts réelle du
terrain béninois : c'est une décision à documenter explicitement dans le protocole.

---

### 4.7 Récapitulatif de la chaîne complète

| # | Opération                                    | Formule obtenue                                                                          | Résultat (projet,$n=20$) |
| - | --------------------------------------------- | ---------------------------------------------------------------------------------------- | --------------------------- |
| 1 | Variance de$\hat\beta$, obs. indépendantes | $\frac{1}{P(1-P)}\cdot\frac{\sigma^2}{N}$                                              | —                          |
| 2 | Ajout des deux risques d'erreur               | $MDE=M(\kappa,\alpha)\cdot SE$                                                         | $M=2{,}80$                |
| 3 | Décomposition$Y_{ij}=\mu+u_j+e_{ij}$       | $\frac{\sigma^2}{N}\rightarrow\sigma^2\!\left(\frac{\rho}{J}+\frac{1-\rho}{Jn}\right)$ | $DEFF=2{,}9$              |
| 4 | Ajout ANCOVA                                  | $\sigma\rightarrow\sigma\sqrt{1-R^2}$                                                  | $R^2=0$ retenu            |
| 5 | Inversion pour$J$                           | $J=\frac{A}{MDE^2}\!\left(\rho+\frac{1-\rho}{n}\right)$                                | **57 écoles/bras**   |
| 6 | Inversion pour$n$                           | $n=\frac{1-\rho}{J\cdot MDE^2/A-\rho}$                                                 | 35 si$J=100$              |
| 7 | Passage à l'échantillon (3 bras)            | $N=3\cdot\frac{J}{2}\cdot n$                                                           | **3 420 filles**      |
| 8 | Inflation d'attrition (20 %)                  | $N_{\text{recruté}}=\frac{N}{1-a}$                                                    | **4 275 filles**      |

> **Les trois chiffres à retenir pour le protocole (scénario 20 filles/école, ρ = 0,10,
> MDE = 0,20 SD, attrition 20 %) : 171 écoles · 4 275 filles à recruter · 3 420 filles analysées.**

---

## 5. Interprétation des résultats du log

### 5.1 Question centrale : combien d'écoles par bras pour détecter un effet de 20 % (0,20 SD) ?

*(Bloc « Nouveau Bloc 2 », Table 0 et Table 0bis du log)*

Avec 30 filles enquêtées par école (design initial), le nombre d'écoles nécessaires **par bras**
varie fortement selon l'hypothèse d'ICC :

| ICC (rho)                            | Écoles nécessaires / bras | Effectif total de filles |
| ------------------------------------ | --------------------------- | ------------------------ |
| 0,05                                 | 33                          | 1 980                    |
| **0,10 (hypothèse centrale)** | **52**                | **3 120**          |
| 0,15                                 | 70                          | 4 200                    |
| 0,20                                 | 89                          | 5 340                    |

**Lecture : avec l'hypothèse centrale (ICC = 0,10), il faudrait environ 52 écoles par bras (156 au
total) pour détecter de façon fiable un effet de 0,20 SD — soit légèrement plus que les 50 écoles
par bras (150 au total) actuellement prévues dans le guide de projet.** Le design prévu est donc
« à la limite » : suffisant si l'ICC réel est ≤ 0,10, insuffisant si l'ICC réel est plus élevé
(0,15-0,20, plage plausible pour des indicateurs de normes sociales).

**Solution de compromis identifiée (Table 0bis) :** en gardant 50 écoles/bras (budget déjà prévu)
mais en enquêtant **35 filles par école au lieu de 30**, on atteint la puissance requise pour
détecter 0,20 SD à ICC central = 0,10. Augmenter davantage le nombre de filles par école (au-delà
de 35-40) rapporte de moins en moins, précisément à cause de l'ICC (voir §2.7) : ajouter des filles
dans une même école a des rendements décroissants sur la puissance.

### 5.2 MDE effectivement atteignable avec le design prévu (50 écoles/bras, 30 filles/école)

*(Table 1)*

| ICC            | MDE (en SD)     |
| -------------- | --------------- |
| 0,05           | 0,160           |
| **0,10** | **0,202** |
| 0,15           | 0,237           |
| 0,20           | 0,267           |

**Lecture : avec le design tel que prévu aujourd'hui, la comparaison principale (T1 vs Contrôle,
ou T2 vs Contrôle) peut détecter un effet d'environ 0,20 SD si l'ICC réel est proche de 0,10** —
cohérent avec le §3.1. Si l'ICC réel est plus élevé, le plus petit effet détectable augmente
(jusqu'à ~0,27 SD si ICC = 0,20), c'est-à-dire que l'étude perd la capacité de détecter des effets
plus modestes.

> Ces quatre valeurs de MDE sont obtenues en appliquant directement la formule du §3.2 avec
> $J=100$ (50+50), $n=30$, en ne faisant varier que $\rho$ — voir la vérification numérique
> complète au §3.7 pour le cas $\rho=0{,}10$.

### 5.3 Combien d'écoles pour d'autres cibles d'effet (0,15 / 0,25 / 0,30 SD) ?

*(Table 2)* — Utile pour situer le design prévu par rapport à d'autres hypothèses d'effet :

- Viser un effet plus **petit** (0,15 SD, plus ambitieux) exige beaucoup plus d'écoles :
  57 à 159 selon l'ICC.
- Viser un effet plus **grand** (0,25 ou 0,30 SD, plus modeste comme ambition) demande beaucoup
  moins d'écoles : 15 à 57 selon l'ICC.

Ceci illustre la sensibilité classique : diviser par deux le MDE visé multiplie approximativement
par quatre le nombre d'écoles nécessaires.

### 5.4 Gain de puissance avec une covariable de base (ANCOVA)

*(Table 3, à ICC central = 0,10, 50 écoles/bras)*

| R² de base             | MDE (SD) |
| ----------------------- | -------- |
| 0 % (pas de covariable) | 0,202    |
| 10 %                    | 0,192    |
| 20 %                    | 0,181    |
| 30 %                    | 0,169    |
| 40 %                    | 0,156    |

**Lecture : si l'on dispose d'une mesure de l'outcome avant l'intervention (baseline) qui explique
par exemple 30 % de la variance de l'outcome final, le MDE passe de 0,202 à 0,169 SD — un gain de
précision non négligeable, à taille d'échantillon inchangée.** Ceci plaide pour la collecte d'une
enquête de référence (baseline) sur les mêmes indicateurs que ceux mesurés à l'endline.

### 5.5 Effet de l'attrition attendue

*(Table 4, à ICC central = 0,10, 50 écoles/bras)*

| Taux d'attrition | Filles suivies / école (effectif) | MDE (SD) |
| ---------------- | ---------------------------------- | -------- |
| 5 %              | 28,5                               | 0,203    |
| 10 %             | 27                                 | 0,205    |
| 15 %             | 25,5                               | 0,206    |
| 20 %             | 24                                 | 0,208    |

**Lecture : même avec une attrition élevée (20 %), la dégradation du MDE reste modeste (0,202 →
0,208 SD) parce que le nombre d'écoles — le facteur le plus puissant sur la précision dans un
design en grappes — ne change pas.** L'attrition affecte surtout le nombre de filles par école,
qui a un impact plus faible sur la puissance que le nombre d'écoles.

### 5.6 Comparaison secondaire mère vs père (randomisation emboîtée)

*(Bloc 7)*

- **À l'intérieur d'un seul bras traité** (25 écoles « mère » vs 25 écoles « père ») : MDE = **0,286 SD**.
- **En regroupant les deux bras traités** (50 écoles « mère » vs 50 écoles « père ») : MDE = **0,202 SD**.

**Lecture : la comparaison mère vs père est nettement moins puissante que la comparaison
principale traitement vs contrôle si elle est faite à l'intérieur d'un seul bras (0,286 SD contre
0,202 SD).** Elle rejoint la précision de la comparaison principale seulement si l'on regroupe les
deux bras traités. **Point à signaler explicitement au PI** : les conclusions sur la comparaison
mère/père (section 5.3 du guide projet) devront être interprétées avec cette limite de puissance
à l'esprit, en particulier si l'analyse est faite bras par bras plutôt qu'en poolant.

### 5.7 Cas d'un outcome binaire (ex. « créneau d'étude protégé »)

*(Table 5, hypothèse : 30 % des filles du groupe contrôle ont l'outcome)*

| Effet visé (points de %) | Puissance atteinte |
| ------------------------- | ------------------ |
| +10 points (30 % → 40 %) | 83,0 %             |
| +15 points (30 % → 45 %) | 99,1 %             |
| +20 points (30 % → 50 %) | 99,99 %            |

**Lecture : avec le design prévu, l'étude a largement la puissance nécessaire (>80 %) pour détecter
un effet de 10 points de pourcentage ou plus sur un outcome binaire dont la prévalence de référence
est de 30 %.** Ce type d'outcome est donc moins « à risque » sur le plan de la puissance que les
outcomes continus visés à 0,20 SD.

### 5.8 Graphique de sensibilité (MDE selon le nombre d'écoles et l'ICC)

Le fichier `MDE_sensitivity_CKDev_Benin.png` produit par le script trace, pour chaque hypothèse
d'ICC (0,05 à 0,20), la courbe du MDE en fonction du nombre d'écoles par bras (de 20 à 90), avec
deux lignes de repère : 50 écoles/bras (design prévu) et 0,20 SD (effet cible). Ce graphique
permet de visualiser en un coup d'œil que la ligne « 50 écoles » croise la ligne « 0,20 SD »
approximativement au niveau de la courbe ICC = 0,10, confirmant numériquement les résultats du §3.2.

---

## 6. Synthèse pour le PI / l'équipe KCDev

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
  §2.7) et refaire tourner ce script pour remplacer l'hypothèse centrale de 0,10 par la valeur
  observée.

### Dimensionnement chiffré recommandé (scénario 20 filles/école — voir section 4)

| Paramètre                                    | Valeur          | Source               |
| --------------------------------------------- | --------------- | -------------------- |
| Filles**analysées** par école ($n$) | 20              | hypothèse de design |
| Écoles par bras                              | **57**    | §4.3.c              |
| Écoles totales (3 bras)                      | **171**   | §4.5.c              |
| Filles**analysées** attendues ($N$)  | **3 420** | §4.5.c              |
| Taux d'attrition anticipé                    | 20 %            | §2.13               |
| Facteur d'inflation                           | × 1,25         | §4.6.a              |
| Filles à**recruter** par école        | **25**    | §4.6.b              |
| **Filles à recruter au total**         | **4 275** | §4.6.b              |

- **Écart avec le guide de projet :** le design initial (150 écoles / 3 000 filles) est inférieur
  de **21 écoles** et **420 filles analysées** à ce que requiert la cible de 0,20 SD sous
  l'hypothèse centrale d'ICC.
- **Plancher absolu à connaître (§4.4.c) :** en dessous de **79 écoles au total** (40 par bras),
  aucun effort d'enquête supplémentaire — quel que soit le nombre de filles par école — ne
  permettra d'atteindre un MDE de 0,20 SD. Le nombre d'écoles n'est donc pas un paramètre
  d'ajustement libre.

---

## 7. Mode d’emploi : comment réutiliser le fichier `.do`

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
