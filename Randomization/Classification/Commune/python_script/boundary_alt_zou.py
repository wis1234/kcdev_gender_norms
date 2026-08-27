import csv

# 1. Récupérer automatiquement la couche sélectionnée (cliquée) dans votre panneau à gauche
couche_jointe = iface.activeLayer()

if couche_jointe is None:
    print("Erreur : Veuillez cliquer sur la couche issue de la jointure dans le panneau de gauche avant de lancer le script.")
else:
    # 2. Définir le chemin de sortie
    chemin_sortie = r"C:\RONALDO\CKDEV\GENDER NORMS\Randomization\Classification\Commune\communes_limitrophes_propre.csv"

    # 3. Extraire et écrire uniquement les deux colonnes essentielles
    with open(chemin_sortie, mode='w', newline='', encoding='utf-8') as fichier_csv:
        writer = csv.writer(fichier_csv)
        
        # Écrire l'entête
        writer.writerow(['Commune_Principale', 'Commune_Limitrophe'])
        
        # Parcourir chaque ligne du tableau QGIS
        for entite in couche_jointe.getFeatures():
            # Nous utilisons une sécurité au cas où les noms de colonnes diffèrent légèrement
            commune_p = entite['adm2_name'] if 'adm2_name' in entite.fields().names() else entite[0]
            commune_l = entite['adm2_name_2'] if 'adm2_name_2' in entite.fields().names() else entite[1]
            
            # Enregistrer dans le CSV
            writer.writerow([commune_p, commune_l])

    print("Extraction terminée avec succès ! Le fichier propre est créé.")
