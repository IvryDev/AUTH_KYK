# Stack Keycloak + Traefik + Postgres — déploiement complet (prod & dev)

> Révision complète **selon la documentation officielle** (Keycloak, Docker, Traefik, Postgres) + ajouts manquants. Ce guide fournit une arborescence propre, des fichiers Compose pour **production** (TLS via Traefik & Let's Encrypt) et **développement** (local sans proxy), des secrets, et un README pas-à-pas avec scripts pratiques.

---

## 1) Arborescence projet
```
.
├── README.md
├── .env                          # à créer depuis .env.example
├── .env.example
├── docker-compose.yml            # prod (Traefik + TLS)
├── docker-compose.override.dev.yml  # dev local (sans Traefik)
├── traefik/
│   └── dynamic.yml               # (optionnel) middlewares/file-provider
├── secrets/
│   ├── db_user
│   ├── db_password
│   ├── keycloak_admin_user
│   └── keycloak_admin_password
├── letsencrypt/
│   └── acme.json                 # créé automatiquement, chmod 600
├── keycloak/
│   └── realm-exports/            # exports/imports de realms
├── backup/
│   └── db/                       # sauvegardes PostgreSQL (.sql.gz)
└── scripts/
    ├── makefile                  # cibles pratiques (make up, backup, etc.)
    └── kc-export-realm.sh        # helper export realm
```

---

## 2) Fichier `.env.example`
Copiez ce fichier en `.env` puis adaptez les valeurs.

```bash
# Domaine public
KC_HOSTNAME=auth.swilauto.com

# Email utilisé par Let's Encrypt (ACME)
LETSENCRYPT_EMAIL=contact@swilauto.com

# Versions images (gelées pour reproductibilité)
KEYCLOAK_IMAGE=quay.io/keycloak/keycloak:26.0
POSTGRES_IMAGE=postgres:16.4
TRAEFIK_IMAGE=traefik:v3.1

# (Optionnel) Configuration import realm au démarrage
# Placez vos JSONs de realm dans ./keycloak/realm-exports et laissez à true pour importer
KC_IMPORT_REALM=true
```

> ⚠️ Ne commitez pas `.env` si vous y mettez des valeurs sensibles.

---

## 3) `docker-compose.yml` (Production, avec Traefik & HTTPS)

```yaml
version: '3.9'

services:
  postgres:
    image: ${POSTGRES_IMAGE}
    environment:
      POSTGRES_DB: keycloak
      POSTGRES_USER_FILE: /run/secrets/db_user
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    volumes:
      - pg_data:/var/lib/postgresql/data
    secrets:
      - db_user
      - db_password
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $(cat /run/secrets/db_user)"]
      interval: 10s
      retries: 5
    restart: unless-stopped
    networks: [ backend ]

  traefik:
    image: ${TRAEFIK_IMAGE}
    command:
      - "--providers.docker=true"
      - "--providers.file.directory=/etc/traefik/dynamic"
      - "--providers.file.watch=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.le.acme.httpchallenge=true"
      - "--certificatesresolvers.le.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.le.acme.email=${LETSENCRYPT_EMAIL}"
      - "--certificatesresolvers.le.acme.storage=/letsencrypt/acme.json"
      - "--log.level=INFO"
      - "--api.dashboard=false"  # laissez false en prod
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./letsencrypt:/letsencrypt
      - ./traefik:/etc/traefik/dynamic:ro
    networks: [ edge ]
    restart: unless-stopped

  keycloak:
    image: ${KEYCLOAK_IMAGE}
    command:
      - start
      - --hostname=${KC_HOSTNAME}
      - --hostname-strict=false
      - --http-enabled=true
      - --http-port=8080
      - --proxy=edge
      - --optimized
      - ${KC_IMPORT_REALM:+--import-realm}
    environment:
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://postgres:5432/keycloak
      KC_DB_USERNAME_FILE: /run/secrets/db_user
      KC_DB_PASSWORD_FILE: /run/secrets/db_password
      KEYCLOAK_ADMIN_FILE: /run/secrets/keycloak_admin_user
      KEYCLOAK_ADMIN_PASSWORD_FILE: /run/secrets/keycloak_admin_password
    depends_on:
      postgres:
        condition: service_healthy
    labels:
      traefik.enable: "true"

      # Route HTTPS
      traefik.http.routers.keycloak.rule: "Host(`${KC_HOSTNAME}`)"
      traefik.http.routers.keycloak.entrypoints: "websecure"
      traefik.http.routers.keycloak.tls.certresolver: "le"
      traefik.http.services.keycloak.loadbalancer.server.port: "8080"

      # HTTP -> HTTPS
      traefik.http.routers.keycloak-web.rule: "Host(`${KC_HOSTNAME}`)"
      traefik.http.routers.keycloak-web.entrypoints: "web"
      traefik.http.routers.keycloak-web.middlewares: "https-redirect"

      # Middlewares sécurité (cf. traefik/dynamic.yml)
      traefik.http.routers.keycloak.middlewares: "kc-sec"
    secrets:
      - db_user
      - db_password
      - keycloak_admin_user
      - keycloak_admin_password
    volumes:
      - ./keycloak/realm-exports:/opt/keycloak/data/import:ro
    networks: [ backend, edge ]
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:8080/health/ready || exit 1"]
      interval: 15s
      retries: 10

volumes:
  pg_data:

secrets:
  db_user:
    file: ./secrets/db_user
  db_password:
    file: ./secrets/db_password
  keycloak_admin_user:
    file: ./secrets/keycloak_admin_user
  keycloak_admin_password:
    file: ./secrets/keycloak_admin_password

networks:
  backend:
    driver: bridge
  edge:
    driver: bridge
```

---

## 4) `docker-compose.override.dev.yml` (Développement local, sans Traefik)
> Fichier chargé automatiquement par Docker Compose en plus de `docker-compose.yml`. Ici on **désactive Traefik** et on fait tourner Keycloak en mode dev sur `http://localhost:8080`.

```yaml
version: '3.9'

services:
  traefik:
    profiles: ["disabled"]

  keycloak:
    command:
      - start-dev
      - --http-port=8080
      - --hostname-strict=false
    environment:
      # Pour le dev, on peut garder les fichiers de secrets
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://postgres:5432/keycloak
      KC_DB_USERNAME_FILE: /run/secrets/db_user
      KC_DB_PASSWORD_FILE: /run/secrets/db_password
      KEYCLOAK_ADMIN_FILE: /run/secrets/keycloak_admin_user
      KEYCLOAK_ADMIN_PASSWORD_FILE: /run/secrets/keycloak_admin_password
    ports:
      - "8080:8080"

  postgres:
    ports:
      - "5432:5432"
```

> Astuce: vous pouvez aussi lancer en dev sans charger `docker-compose.yml` (prod) en utilisant `--profile disabled` pour Traefik, ou un fichier *alt* minimal.

---

## 5) `traefik/dynamic.yml` (middlewares & headers de sécurité)

```yaml
http:
  middlewares:
    https-redirect:
      redirectScheme:
        scheme: https
    kc-sec:
      headers:
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        browserXssFilter: true
        contentTypeNosniff: true
        frameDeny: true
        referrerPolicy: no-referrer-when-downgrade
        customFrameOptionsValue: SAMEORIGIN
```

> Vous pouvez ajouter ici des middlewares d’auth pour le dashboard, si vous l’exposez.

---

## 6) Fichiers `secrets/` (contenu & permissions)
Créez les 4 fichiers (une seule ligne chacun) :
```
secrets/db_user                 # ex: keycloak
secrets/db_password             # ex: motdepasse_robuste
secrets/keycloak_admin_user     # ex: admin
secrets/keycloak_admin_password # ex: motdepasse_admin_robuste
```

Puis appliquez des permissions restrictives :
```bash
chmod 600 secrets/*
# Pour Traefik ACME
touch letsencrypt/acme.json && chmod 600 letsencrypt/acme.json
```

---

## 7) Scripts pratiques

### 7.1 `scripts/makefile`
```makefile
SHELL := /bin/bash

PROJECT ?= keycloak-stack
COMPOSE := docker compose

.PHONY: up down restart logs ps exec-kc exec-db backup-db restore-db export-realm import-realm

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down -v

restart:
	$(COMPOSE) restart

logs:
	$(COMPOSE) logs -f --tail=200

ps:
	$(COMPOSE) ps

exec-kc:
	$(COMPOSE) exec keycloak /bin/bash

exec-db:
	$(COMPOSE) exec postgres bash -lc "psql -U $$(cat /run/secrets/db_user) -d keycloak"

backup-db:
	mkdir -p backup/db && \
	$(COMPOSE) exec -T postgres bash -lc "pg_dump -U $$(cat /run/secrets/db_user) keycloak | gzip" > backup/db/keycloak_$$(date +%F_%H%M%S).sql.gz && \
	echo "Backup créé dans backup/db/"

restore-db:
	@if [ -z "$(FILE)" ]; then echo "Usage: make restore-db FILE=backup/db/nom.sql.gz"; exit 1; fi
	zcat $(FILE) | $(COMPOSE) exec -T postgres bash -lc "psql -U $$(cat /run/secrets/db_user) -d keycloak"

export-realm:
	@if [ -z "$(REALM)" ]; then echo "Usage: make export-realm REALM=myrealm"; exit 1; fi
	$(COMPOSE) exec keycloak bash -lc \
	  "/opt/keycloak/bin/kc.sh export --realm=$(REALM) --dir=/opt/keycloak/data/export --users same_file" && \
	$(COMPOSE) cp keycloak:/opt/keycloak/data/export ./keycloak/realm-exports && \
	echo "Export disponible dans ./keycloak/realm-exports"

import-realm:
	@if [ -z "$(REALM_FILE)" ]; then echo "Usage: make import-realm REALM_FILE=keycloak/realm-exports/myrealm-realm.json"; exit 1; fi
	$(COMPOSE) cp $(REALM_FILE) keycloak:/opt/keycloak/data/import/
	$(COMPOSE) restart keycloak
```

### 7.2 `scripts/kc-export-realm.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
REALM_NAME=${1:-master}
DIR=/opt/keycloak/data/export

mkdir -p "$DIR"
/opt/keycloak/bin/kc.sh export \
  --realm="$REALM_NAME" \
  --dir="$DIR" \
  --users same_file

echo "Export du realm '$REALM_NAME' terminé dans $DIR"
```
> Rendre exécutable : `chmod +x scripts/kc-export-realm.sh`

---

## 8) README.md (guide pas-à-pas)

```markdown
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

```

---

## 9) Notes et bonnes pratiques
- **Sécurité** : utilisez des mots de passe forts (secrets), restreignez l’accès SSH, mettez un firewall. N’exposez pas le dashboard Traefik en prod ou protégez-le (basic auth).
- **Sauvegardes** : programmez `make backup-db` via cron sur l’hôte ou utilisez un conteneur dédié de backup si besoin.
- **Observabilité** : ajoutez Prometheus/Grafana et metrics Keycloak si nécessaire.
- **Montées de version** : lisez les *release notes* Keycloak avant de changer de tag.

---

## 10) Différences clés vs configuration initiale
- Ajout d’un **`.env`** et **tags figés** des images.
- Séparation **réseaux** `backend`/`edge`.
- **Traefik** avec file provider pour middlewares + ACME persistant.
- **Healthchecks** robustes (DB + Keycloak).
- **Import de realm** au démarrage (optionnel) + scripts d’export/import.
- **Secrets Docker** partout (pas de mots de passe en clair dans l’env).
- **Guide complet** + scripts Makefile pour l’exploitation quotidienne.

---

### Fin ✨
Si tu veux, je peux aussi ajouter :
- un profil **staging** Let’s Encrypt (pour tests sans rate-limit),
- des **middlewares** d’auth sur un routeur dashboard sécurisé,
- une **politique de rotation** des backups.

