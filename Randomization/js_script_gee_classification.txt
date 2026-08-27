// ============================================================================
// CLASSIFICATION DEGURBA DES ECOLES URBAINES DU BENIN (Google Earth Engine)
// Version 2 - architecture scientifique separant classification officielle
// et indicateurs de contexte continus
// ============================================================================
//
// PRINCIPES METHODOLOGIQUES (important, lire avant de modifier) :
//   1. La classification OFFICIELLE (DEGURBA L1/L2) vient directement du
//      code SMOD du GHSL, SANS seuil arbitraire. Elle n'est jamais melangee
//      aux indicateurs continus.
//   2. Le DEGURBA "Level 1" officiel ne contient QUE 3 classes :
//      Urban Centre / Urban Cluster / Rural. Il n'existe PAS de classe
//      "periurbain" separee au niveau L1 officiel (le code 21 est noye
//      dans "Urban Cluster"). Un regroupement a 4 classes distinguant le
//      periurbain (comme dans beaucoup d'usages appliques) est donc un
//      choix d'AGREGATION PROPRE A CETTE ETUDE, explicitement etiquete
//      comme tel ci-dessous (degurba_etude_classe), et non presente comme
//      un standard officiel.
//   3. Les indicateurs continus (bati, densite, distance, temps de trajet)
//      DECRIVENT le contexte spatial ; ils ne redefinissent PAS la
//      classification officielle.
//   4. Une ecole-point peut tomber pres d'une frontiere entre deux cellules
//      SMOD (grille 1km) -> on ajoute des indicateurs de robustesse
//      spatiale (classe dominante et parts urbain/periurbain/rural dans
//      un voisinage) pour detecter ces cas limites.
//
// PRE-REQUIS :
//   1. Exporte tes ecoles urbaines en CSV avec un identifiant, "lon", "lat",
//      et idealement la colonne "MILIEU" (statut administratif).
//   2. GEE Code Editor -> Assets -> New -> Table Upload -> ton CSV
//   3. Copie le CHEMIN BRUT de l'asset (PAS l'URL du navigateur, juste
//      "projects/.../assets/..." ou "users/.../...") dans ECOLES_ASSET.
// ============================================================================

// ---------------------------------------------------------------------------
// 0. PARAMETRES A ADAPTER
// ---------------------------------------------------------------------------
var ECOLES_ASSET = 'projects/studio-2544773447-1b0d7/assets/ecoles_benin_urbain'; // <-- chemin brut
var ID_FIELD      = 'NOMETABLISSEMENT';   // <-- adapte si different
var CHAMP_LON     = 'lon';                // <-- adapte si different
var CHAMP_LAT     = 'lat';                // <-- adapte si different
var CHAMP_MILIEU  = 'MILIEU';             // <-- statut administratif ; laisse '' si absent
var BUFFERS       = [500, 1000, 3000];    // rayons en metres pour les indicateurs continus
var ANNEES_GHSL   = ['2020'];             // ajoute '2015','2025',... pour une analyse multi-annee

// ---------------------------------------------------------------------------
// 1. CHARGER LES ECOLES ET SECURISER LA GEOMETRIE
// ---------------------------------------------------------------------------
var ecolesBrut = ee.FeatureCollection(ECOLES_ASSET);
print('Nombre d ecoles chargees (brut) :', ecolesBrut.size());

// Reconstruire la geometrie a partir des colonnes lon/lat d'origine plutot
// que de faire confiance a la geometrie attachee par l'ingestion GEE
// (protege contre une inversion X/Y au moment de l'upload).
var ecolesGeomOk = ecolesBrut.map(function(f) {
  var lon = ee.Number(f.get(CHAMP_LON));
  var lat = ee.Number(f.get(CHAMP_LAT));
  return f.setGeometry(ee.Geometry.Point([lon, lat]));
});

// Filtre de securite : emprise approximative du Benin (avec marge)
var beninBbox = ee.Geometry.Rectangle([0.5, 6.0, 4.0, 12.5]);
var ecoles = ecolesGeomOk.filterBounds(beninBbox);
print('Nombre d ecoles avec geometrie valide (emprise Benin) :', ecoles.size());

var ecolesExclues = ecolesGeomOk.filter(ee.Filter.bounds(beninBbox).not());
print('ATTENTION - ecoles exclues (coordonnees suspectes) :', ecolesExclues);

// ---------------------------------------------------------------------------
// 2. TRAITEMENT POUR UN MILLESIME GHSL DONNE
// ---------------------------------------------------------------------------
// Toute la logique est encapsulee dans une fonction pour permettre, si
// besoin, une analyse multi-annee (voir section 5).
function traiterMillesime(annee) {

  // 2a. Couches sources (identifiants verifies dans le catalogue GEE)
  var built = ee.Image('JRC/GHSL/P2023A/GHS_BUILT_S/' + annee).select('built_surface');
  var pop   = ee.Image('JRC/GHSL/P2023A/GHS_POP/' + annee).select('population_count');
  var smod  = ee.Image('JRC/GHSL/P2023A/GHS_SMOD_V2-0/' + annee).select('smod_code');

  var smodProj    = smod.projection();
  var scaleMeters = ee.Number(smodProj.nominalScale());  // ~1000 m

  // Accessibilite (millesime fixe 2015, seul disponible pour ce produit) :
  // temps de trajet MOTORISE vers la zone densement peuplee la plus proche
  // (>=50 000 hab. OU densite >=1500 hab/km2), en minutes. Ce n'est PAS une
  // distance geographique : c'est un temps de trajet modelise (Weiss et al.
  // 2018, Malaria Atlas Project / Oxford / JRC / Google).
  var access = ee.Image(
    'projects/malariaatlasproject/assets/accessibility/accessibility_to_cities/2015_v1_0'
  ).select('accessibility');

  // 2b. Masques pour les distances
  // "Urban Centre" strict = code 30 uniquement (definition officielle DEGURBA
  // du coeur urbain : cellules contigues >=1500 hab/km2, population totale
  // >=50 000 habitants).
  var urbanCentreMask = smod.eq(30).selfMask();
  // "Coeur dense" = Urban Centre (30) + Dense Urban Cluster (23) - definition
  // plus permissive, utile pour de petites villes secondaires qui n'atteignent
  // pas le seuil de 50 000 habitants d'un "Urban Centre" au sens strict.
  var denseCoreMask = smod.gte(23).selfMask();

  // fastDistanceTransform : neighborhood en pixels de la grille SMOD (~1km).
  // 50 pixels ~= 50 km de rayon de recherche. Choix documente ici, pas une
  // definition universelle de "distance a la ville".
  var RAYON_RECHERCHE_PIXELS = 50;

  var distUrbanCentre = urbanCentreMask
    .fastDistanceTransform(RAYON_RECHERCHE_PIXELS, 'pixels')
    .sqrt().multiply(scaleMeters)
    .rename('dist_urban_centre_m').reproject(smodProj);

  var distDenseCore = denseCoreMask
    .fastDistanceTransform(RAYON_RECHERCHE_PIXELS, 'pixels')
    .sqrt().multiply(scaleMeters)
    .rename('dist_dense_core_m').reproject(smodProj);

  // 2c. Fonction : indicateurs continus (bati, population) pour un rayon donne
  function statsContinuesPourRayon(geom, rayon) {
    var aireBuffer = Math.PI * rayon * rayon;  // m2
    var buf = geom.buffer(rayon);

    var sommes = built.rename('built_sum')
      .addBands(pop.rename('pop_sum'))
      .reduceRegion({
        reducer: ee.Reducer.sum(),
        geometry: buf,
        scale: 100,
        maxPixels: 1e9
      });

    var builtPct = ee.Number(sommes.get('built_sum')).divide(aireBuffer).multiply(100);
    // Controle qualite : le % bati doit rester dans [0, 100]. Un depassement
    // signalerait un probleme de geometrie ou de resolution.
    var builtPctValide = builtPct.min(100).max(0);
    var builtPctFlag = builtPct.gt(100).or(builtPct.lt(0));

    var popDensite = ee.Number(sommes.get('pop_sum')).divide(aireBuffer).multiply(1e6); // hab/km2

    return {
      built_pct: builtPctValide,
      built_pct_flag_hors_bornes: builtPctFlag,
      pop_density: popDensite
    };
  }

  // 2d. Fonction : robustesse spatiale SMOD (classe dominante + parts par
  // grande categorie) dans un rayon donne. Utile car une ecole-point peut
  // tomber d'un cote ou de l'autre d'une frontiere de cellule 1km.
  function robustesseSmodPourRayon(geom, rayon) {
    var buf = geom.buffer(rayon);

    var mode = smod.reduceRegion({
      reducer: ee.Reducer.mode(),
      geometry: buf,
      scale: scaleMeters,
      maxPixels: 1e9
    }).get('smod_code');

    var hist = ee.Dictionary(smod.reduceRegion({
      reducer: ee.Reducer.frequencyHistogram(),
      geometry: buf,
      scale: scaleMeters,
      maxPixels: 1e9
    }).get('smod_code'));

    var getCount = function(code) {
      return ee.Number(hist.get(ee.Number(code).format('%d'), 0));
    };

    var total = ee.Number(hist.values().reduce(ee.Reducer.sum()));
    var totalSafe = total.max(1);  // evite une division par zero

    var coreCount       = getCount(30).add(getCount(23));
    var semidenseCount  = getCount(22);
    var periurbCount    = getCount(21);
    var ruralCount      = getCount(13).add(getCount(12)).add(getCount(11));

    return {
      smod_mode: mode,
      urban_core_share_pct:      coreCount.divide(totalSafe).multiply(100),
      urban_semidense_share_pct: semidenseCount.divide(totalSafe).multiply(100),
      periurban_share_pct:       periurbCount.divide(totalSafe).multiply(100),
      rural_share_pct:           ruralCount.divide(totalSafe).multiply(100),
      n_pixels_smod:             total
    };
  }

  // 2e. Fonction principale : indicateurs pour une ecole
  return function(f) {
    var geom = f.geometry();
    var suffixe = '_' + annee;

    // --- Classification officielle au point exact ---
    var pointVals = ee.Dictionary(smod.rename('smod_code')
      .addBands(distUrbanCentre)
      .addBands(distDenseCore)
      .addBands(access.rename('travel_time_min'))
      .reduceRegion({
        reducer: ee.Reducer.first(),
        geometry: geom,
        scale: 100,
        maxPixels: 1e9
      }));

    var smodCode = ee.Number(pointVals.get('smod_code', -999));

    // DEGURBA Level 2 : label lisible directement issu du code SMOD (8 classes)
    var degurbaL2 = ee.Algorithms.If(smodCode.eq(-999), 'NO_DATA',
      ee.Algorithms.If(smodCode.eq(30), 'Urban Centre',
      ee.Algorithms.If(smodCode.eq(23), 'Dense Urban Cluster',
      ee.Algorithms.If(smodCode.eq(22), 'Semi-dense Urban Cluster',
      ee.Algorithms.If(smodCode.eq(21), 'Suburban or peri-urban',
      ee.Algorithms.If(smodCode.eq(13), 'Rural Cluster',
      ee.Algorithms.If(smodCode.eq(12), 'Low Density Rural',
      ee.Algorithms.If(smodCode.eq(11), 'Very Low Density Rural',
      ee.Algorithms.If(smodCode.eq(10), 'Water', 'NO_DATA')))))))));

    // DEGURBA Level 1 OFFICIEL : SEULEMENT 3 classes (standard ONU/Eurostat
    // reel). 21+22+23 sont regroupes ensemble en "Urban Cluster" - il n'y a
    // PAS de classe "periurbain" distincte a ce niveau officiel.
    var degurbaL1Officiel = ee.Algorithms.If(smodCode.eq(-999), 'NO_DATA',
      ee.Algorithms.If(smodCode.eq(30), 'Urban Centre',
      ee.Algorithms.If(smodCode.gte(21), 'Urban Cluster',
      ee.Algorithms.If(smodCode.gte(11), 'Rural',
      ee.Algorithms.If(smodCode.eq(10), 'Water', 'NO_DATA')))));

    // Regroupement PROPRE A CETTE ETUDE (4 classes, PAS un standard officiel)
    // - distingue explicitement le periurbain (code 21), utile pour l'objectif
    //   de l'etude, mais a presenter comme un choix methodologique documente,
    //   pas comme "le standard ONU".
    var degurbaEtudeClasse = ee.Algorithms.If(smodCode.eq(-999), 'NO_DATA',
      ee.Algorithms.If(smodCode.gte(23), 'URBAN_CORE',
      ee.Algorithms.If(smodCode.eq(22), 'URBAN_SEMIDENSE',
      ee.Algorithms.If(smodCode.eq(21), 'PERIURBAN',
      ee.Algorithms.If(smodCode.gte(11), 'RURAL',
      ee.Algorithms.If(smodCode.eq(10), 'WATER', 'NO_DATA'))))));

    // --- Statut administratif et coherence ---
    var statutAdmin = CHAMP_MILIEU === '' ? null : f.get(CHAMP_MILIEU);
    var coherence = ee.Algorithms.If(
      ee.Algorithms.IsEqual(statutAdmin, null), 'STATUT_ADMIN_NON_RENSEIGNE',
      ee.Algorithms.If(
        smodCode.eq(-999), 'NON_EVALUABLE_NO_DATA',
        ee.Algorithms.If(
          smodCode.eq(10), 'NON_EVALUABLE_EAU',
          ee.Algorithms.If(
            smodCode.gte(11).and(smodCode.lte(13)),  // domaine rural strict (11-13)
            'INCOHERENT_ADMIN_URBAIN_MAIS_SMOD_RURAL',
            'COHERENT'
          )
        )
      )
    );

    // --- Indicateurs continus + robustesse spatiale par rayon ---
    var proprietes = {};
    proprietes['smod_code' + suffixe]              = smodCode;
    proprietes['degurba_l2' + suffixe]              = degurbaL2;
    proprietes['degurba_l1_officiel' + suffixe]     = degurbaL1Officiel;
    proprietes['degurba_etude_classe' + suffixe]    = degurbaEtudeClasse;
    proprietes['statut_administratif']              = statutAdmin;
    proprietes['classification_coherence' + suffixe] = coherence;
    proprietes['dist_urban_centre_m' + suffixe]     = pointVals.get('dist_urban_centre_m', -999);
    proprietes['dist_dense_core_m' + suffixe]       = pointVals.get('dist_dense_core_m', -999);
    proprietes['travel_time_min']                    = pointVals.get('travel_time_min', -999);

    BUFFERS.forEach(function(rayon) {
      var cont = statsContinuesPourRayon(geom, rayon);
      var rob  = robustesseSmodPourRayon(geom, rayon);
      var tagR = '_' + rayon + 'm' + suffixe;

      proprietes['built_pct' + tagR]              = cont.built_pct;
      proprietes['built_pct_flag_hors_bornes' + tagR] = cont.built_pct_flag_hors_bornes;
      proprietes['pop_density_km2' + tagR]        = cont.pop_density;
      proprietes['smod_mode' + tagR]              = rob.smod_mode;
      proprietes['urban_core_share_pct' + tagR]   = rob.urban_core_share_pct;
      proprietes['urban_semidense_share_pct' + tagR] = rob.urban_semidense_share_pct;
      proprietes['periurban_share_pct' + tagR]    = rob.periurban_share_pct;
      proprietes['rural_share_pct' + tagR]        = rob.rural_share_pct;
    });

    // Flag de robustesse : la classe au point differe-t-elle de la classe
    // dominante dans le voisinage immediat (500m) ? Signale un cas limite,
    // proche d'une frontiere entre deux cellules SMOD.
    var modeVoisinage500 = ee.Number(proprietes['smod_mode_500m' + suffixe]);
    proprietes['frontiere_classification_500m' + suffixe] =
      ee.Algorithms.If(smodCode.eq(-999), 'NON_EVALUABLE',
        ee.Number(smodCode).neq(modeVoisinage500));

    return f.set(proprietes);
  };
}

// ---------------------------------------------------------------------------
// 3. APPLIQUER LE TRAITEMENT (pour chaque millesime demande)
// ---------------------------------------------------------------------------
var ecolesIndic = ecoles;
ANNEES_GHSL.forEach(function(annee) {
  ecolesIndic = ecolesIndic.map(traiterMillesime(annee));
});

// ---------------------------------------------------------------------------
// 4. RECAPITULATIF ET VALIDATION VISUELLE (sur le premier millesime demande)
// ---------------------------------------------------------------------------
var anneeRef = ANNEES_GHSL[0];
print('Apercu des indicateurs (5 premieres ecoles) :', ecolesIndic.limit(5));
print('Repartition DEGURBA L1 officiel (' + anneeRef + ') :',
      ecolesIndic.aggregate_histogram('degurba_l1_officiel_' + anneeRef));
print('Repartition DEGURBA classe etude (' + anneeRef + ') :',
      ecolesIndic.aggregate_histogram('degurba_etude_classe_' + anneeRef));
print('Coherence avec le statut administratif (' + anneeRef + ') :',
      ecolesIndic.aggregate_histogram('classification_coherence_' + anneeRef));

Map.setOptions('HYBRID');
Map.centerObject(ecolesIndic, 10);
var champEtude = 'degurba_etude_classe_' + anneeRef;
Map.addLayer(ecolesIndic.filter(ee.Filter.eq(champEtude, 'URBAN_CORE')),
             {color: 'FF0000'}, 'Urban core');
Map.addLayer(ecolesIndic.filter(ee.Filter.eq(champEtude, 'URBAN_SEMIDENSE')),
             {color: 'FFD700'}, 'Urban semi-dense');
Map.addLayer(ecolesIndic.filter(ee.Filter.eq(champEtude, 'PERIURBAN')),
             {color: 'FFA500'}, 'Periurban');
Map.addLayer(ecolesIndic.filter(ee.Filter.eq(champEtude, 'RURAL')),
             {color: '808080'}, 'Rural (incoherent avec le label administratif)');
Map.addLayer(ecolesIndic.filter(ee.Filter.eq(champEtude, 'NO_DATA')),
             {color: '000000'}, 'PAS DE DONNEE - verifier les coordonnees');

// ---------------------------------------------------------------------------
// 5. EXPORT CSV VERS GOOGLE DRIVE
// ---------------------------------------------------------------------------
Export.table.toDrive({
  collection: ecolesIndic,
  description: 'ecoles_urbaines_indicateurs_degurba_v2',
  folder: 'GEE_exports',
  fileNamePrefix: 'ecoles_urbaines_indicateurs_v2',
  fileFormat: 'CSV'
});

// ============================================================================
// NOTES METHODOLOGIQUES POUR LA REDACTION (memoire/article)
// ============================================================================
// - degurba_l1_officiel_ANNEE : classification officielle DEGURBA Level 1
//   (Schiavina, Melchiorri, Pesaresi 2023 ; methodologie recommandee par la
//   Commission statistique des Nations Unies). 3 classes seulement :
//   Urban Centre / Urban Cluster / Rural. C'est CETTE variable qu'il faut
//   citer comme "standard ONU" dans un texte scientifique.
// - degurba_l2_ANNEE : niveau de detail complet du GHS-SMOD (8 classes),
//   egalement officiel, publie tel quel par le GHSL.
// - degurba_etude_classe_ANNEE : regroupement en 4 classes CONSTRUIT POUR
//   CETTE ETUDE afin d'isoler le periurbain (absent du L1 officiel). A
//   presenter explicitement comme un choix methodologique de l'etude,
//   avec reference au code SMOD source (transparence/reproductibilite).
// - classification_coherence_ANNEE : compare le statut administratif
//   ("MILIEU" = Urbain, tel que fourni par le Ministere) a la realite
//   physique mesuree par le GHSL. Un statut "INCOHERENT" ne signifie pas
//   une erreur mais souligne une divergence entre definition administrative
//   et definition physique/statistique de l'urbain - a documenter comme
//   limite ou resultat interessant selon le contexte de l'etude.
// - frontiere_classification_500m_ANNEE : TRUE si la classe SMOD au point
//   exact de l'ecole differe de la classe dominante dans son voisinage de
//   500m. Signale les cas ou le resultat depend fortement de la precision
//   des coordonnees GPS -> a examiner en priorite lors de la validation
//   visuelle (image satellite deja affichee dans la carte GEE).
// - Les parts urban_core_share_pct / periurban_share_pct / rural_share_pct
//   (par rayon) permettent de nuancer une classification ponctuelle stricte :
//   ex. "ecole classee PERIURBAN au point, mais 84% de son voisinage de 1km
//   est en fait URBAN_CORE" est une info bien plus riche qu'une etiquette
//   binaire.
// - dist_urban_centre_m = distance au sens STRICT (code 30 seul, >= 50 000
//   habitants). dist_dense_core_m = distance a un coeur urbain plus large
//   (codes 23+30), pertinent pour de petites villes secondaires du Benin
//   qui n'atteignent pas le seuil de 50 000 habitants.
// - travel_time_min = temps de trajet MOTORISE modelise vers la zone
//   densement peuplee la plus proche (Weiss et al. 2018, Malaria Atlas
//   Project). Ce n'est pas une distance geographique.
// - Pour une analyse multi-annee, ajoute des millesimes a ANNEES_GHSL
//   (ex: ['2015','2020','2025']) ; chaque variable sera dupliquee avec le
//   suffixe correspondant (ex: degurba_etude_classe_2015, _2020, _2025).
// ============================================================================