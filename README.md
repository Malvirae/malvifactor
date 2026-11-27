# MalviFactor

Application personnelle de suivi nutritionnel et de calcul adaptatif de dépense énergétique (TDEE) inspirée de MacroFactor, conçue pour un foyer de deux utilisateurs avec synchronisation Android (Health Connect) et accès Web PWA.

## Architecture du monorepo

- `backend/` : API FastAPI + SQLAlchemy 2.0 async (`asyncpg`) + PostgreSQL 16 (`pg_trgm`)
- `frontend/` : Application Flutter multiplateforme (Android + Web PWA) avec Riverpod, GoRouter, Dio, `fl_chart`, `mobile_scanner`, ML Kit OCR et Google Health Connect
- `nginx/` : Reverse proxy Nginx (`/api/` -> `backend:8000`)
- `compose.yaml` : Stack Docker prête pour Dockge

## Fonctionnalités clés

- **Journal alimentaire en timeline horaire** : recherche floue `pg_trgm` sur la table officielle **ANSES Ciqual 2025** et **Open Food Facts**, scan de code-barres EAN avec vérification/correction aux 100 g, **OCR d'étiquette nutritionnelle** si produit inconnu, recettes partagées, sélection multiple (copie, déplacement par flèche horaire, copie multi-dates, suppression optimiste) et mode compact.
- **Suivi du poids & TDEE adaptatif** : lissage exponentiel EWMA ($\alpha = 0.1$), synchronisation automatique avec **Google Health Connect** sur Android, bilan hebdomadaire (*Check-in*) avec historique non rétroactif des cibles macros.
- **Onboarding guidé en 6 étapes** : Katch-McArdle (avec `%` masse grasse) ou Mifflin-St Jeor + NEAT et volume d'entraînement.
- **Mises à jour OTA Android** : vérification automatique via les Releases GitHub et installation directe de l'APK signé.

## Déploiement Backend (Docker Compose / Dockge)

1. Copier `.env.example` vers `.env` et renseigner `POSTGRES_PASSWORD` et `SECRET_KEY`.
2. Lancer la stack :
   ```bash
   docker compose up -d --build
   ```
3. Créer les comptes utilisateurs via CLI :
   ```bash
   docker compose exec backend python -m app.cli create-user \
     --email user@example.com --username user --display-name "Prénom" --password "MotDePasse!"
   ```
4. Importer la table Ciqual 2025 :
   ```bash
   docker compose exec backend python -m app.cli import-ciqual
   ```
