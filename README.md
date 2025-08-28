# Keycloak + Traefik + Postgres (prod & dev)

## Prérequis
- Docker & Docker Compose v2
- Nom de domaine pointant vers votre hôte (A/AAAA), ex: `auth.swilauto.com`
- Ports 80/443 ouverts (firewall / cloud)

## 1. Préparer l’arborescence
```bash
mkdir -p secrets letsencrypt traefik keycloak/realm-exports backup/db scripts
cp .env.example .env
```

## 2. Renseigner `.env`
Éditez les valeurs (`KC_HOSTNAME`, `LETSENCRYPT_EMAIL`, versions d’images…).

## 3. Créer les secrets
```bash
echo "keycloak" > secrets/db_user
echo "un_motdepasse_TRES_robuste" > secrets/db_password
echo "admin" > secrets/keycloak_admin_user
echo "un_autre_motdepasse_TRES_robuste" > secrets/keycloak_admin_password
chmod 600 secrets/*
```

## 4. Initialiser Traefik ACME
```bash
touch letsencrypt/acme.json && chmod 600 letsencrypt/acme.json
```

## 5. Lancer en production (TLS automatique)
```bash
docker compose up -d
```
Attendez l’obtention des certificats (quelques dizaines de secondes). Visitez :
```
https://$KC_HOSTNAME
```

## 6. Lancer en développement local (sans Traefik)
```bash
docker compose -f docker-compose.yml -f docker-compose.override.dev.yml up -d
open http://localhost:8080
```

## 7. Export / Import de realm
- Export : `make export-realm REALM=monrealm`
- Import au démarrage : placez vos JSON dans `./keycloak/realm-exports/` et laissez `KC_IMPORT_REALM=true`
- Import à chaud : `make import-realm REALM_FILE=keycloak/realm-exports/monrealm-realm.json`

## 8. Sauvegardes PostgreSQL
- Sauvegarde : `make backup-db`
- Restauration : `make restore-db FILE=backup/db/keycloak_YYYY-MM-DD_HHMMSS.sql.gz`

## 9. Mise à jour des images
1. Modifiez les tags dans `.env` (KEYCLOAK_IMAGE, POSTGRES_IMAGE, TRAEFIK_IMAGE)
2. `docker compose pull && docker compose up -d`

## 10. Dépannage
- **Boucle de redirection / 400** : vérifiez `--proxy=edge` et `KC_HOSTNAME`
- **Certificats non émis** : testez l’accès HTTP (port 80) depuis l’extérieur, logs Traefik `docker compose logs traefik`
- **DB connexion** : validez secrets et `KC_DB_URL`
