# Règles de livraison MalviFactor

À chaque demande de mise à jour ou de nouvelle version de MalviFactor, suivre strictement cette procédure autonome (sans GitHub Actions) :

1. **Incrémenter la version** dans `frontend/pubspec.yaml` (`version: X.Y.Z+BUILD`).
2. **Vérifier le code** :
   - Backend : `python -m compileall -q backend/app`
   - Frontend : `cd frontend && flutter analyze`
3. **Compiler les livrables en local** :
   - Android APK signé : `cd frontend && flutter build apk --release`
   - Web PWA : `cd frontend && flutter build web --release`
4. **Commit, Tag & Push sur GitHub** :
   - Vérifier avec `git status` qu'aucun secret (`.env`, `*.jks`, `key.properties`) n'est suivi.
   - `git add -A`
   - `git commit -m "chore: release vX.Y.Z"`
   - `git push origin main`
   - `git tag vX.Y.Z`
   - `git push origin vX.Y.Z`
5. **Publier la GitHub Release avec l'APK en pièce jointe** (pour l'OTA Android) :
   - `gh release create vX.Y.Z frontend/build/app/outputs/flutter-apk/app-release.apk --title "MalviFactor vX.Y.Z" --notes "..."`
