import csv
from qgis.core import QgsProject, QgsDistanceArea

# 1. Analyse dynamique des couches présentes dans votre projet QGIS
toutes_les_couches = QgsProject.instance().mapLayers().values()

couche_origine = None
couche_jointe = None

# On cherche les couches par rapport au nombre de colonnes (champs)
for c in toutes_les_couches:
    champs = c.fields().names()
    # La couche jointe a obligatoirement la colonne dupliquée 'adm2_name_2' ou 'adm2_nam_1'
    if any('adm2_name_' in f or 'adm2_nam_' in f for f in champs):
        couche_jointe = c
    # La couche d'origine contient les entités de base
    elif 'adm2_name' in champs:
        couche_origine = c

# Si la détection automatique échoue, on prend la couche active comme couche jointe
if not couche_jointe:
    couche_jointe = iface.activeLayer()
if not couche_origine:
    print("Erreur : Impossible de détecter la couche d'origine des communes. Assurez-vous qu'elle est ouverte dans QGIS.")
else:
    print(f"-> Couche origine détectée : '{couche_origine.name()}'")
    print(f"-> Couche jointe détectée : '{couche_jointe.name()}'")

    # 2. Configuration du calculateur métrique
    calculateur = QgsDistanceArea()
    calculateur.setEllipsoid('WGS84')
    calculateur.setSourceCrs(couche_origine.crs(), QgsProject.instance().transformContext())

    # 3. Mapping des géométries d'origine
    dict_geom = {f['adm2_name']: f.geometry() for f in couche_origine.getFeatures()}

    chemin_sortie = r"C:\RONALDO\CKDEV\GENDER NORMS\Randomization\Classification\Commune\Outputs\communes_limitrophes_distance_centroides.csv"

    # 4. Identification dynamique des colonnes de jointure
    nom_champs = couche_jointe.fields().names()
    col_p = 'adm2_name'
    col_l = [f for f in nom_champs if 'adm2_name_' in f or 'adm2_nam_' in f][0] # Détecte 'adm2_name_2', 'adm2_nam_1', etc.

    # 5. Calcul et écriture
    with open(chemin_sortie, mode='w', newline='', encoding='utf-8') as fichier_csv:
        writer = csv.writer(fichier_csv)
        writer.writerow(['Commune_Principale', 'Commune_Limitrophe', 'Distance_Centroides_KM'])
        
        lignes_ecrites = 0
        for entite in couche_jointe.getFeatures():
            comp_p = entite[col_p]
            comp_l = entite[col_l]
            
            if comp_p != comp_l and comp_p in dict_geom and comp_l in dict_geom:
                pt_p = dict_geom[comp_p].centroid().asPoint()
                pt_l = dict_geom[comp_l].centroid().asPoint()
                
                # Calcul de la distance géodésique (sur ellipsoïde)
                distance_metres = calculateur.measureLine(pt_p, pt_l)
                distance_km = round(distance_metres / 1000, 2)
                
                # Si le projet est en degrés et non projeté, forcer une conversion robuste
                if distance_km < 0.1 and couche_origine.crs().isGeographic():
                    dist_degres = pt_p.distance(pt_l)
                    distance_km = round(dist_degres * 111.32, 2)
                
                writer.writerow([comp_p, comp_l, distance_km])
                lignes_ecrites += 1

    print(f"Extraction réussie ! {lignes_ecrites} lignes valides exportées vers : {chemin_sortie}")
