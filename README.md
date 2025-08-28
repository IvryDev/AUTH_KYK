Option A — Docker Compose (Traefik + TLS auto + PostgreSQL)
1) Arbo & fichiers
infra/
├─ docker-compose.yml
├─ .env
├─ secrets/
│  ├─ keycloak_admin_user
│  ├─ keycloak_admin_password
│  ├─ db_user
│  ├─ db_password
└─ backup/
   └─ pgbackrest.conf   (optionnel)

2) Créer les secrets (hors Git)
```sh
mkdir -p infra/secrets
openssl rand -hex 8  > infra/secrets/keycloak_admin_user        # ex: admin-3f9a
openssl rand -base64 32 > infra/secrets/keycloak_admin_password # fort
echo "keycloak" > infra/secrets/db_user
openssl rand -base64 32 > infra/secrets/db_password
chmod 600 infra/secrets/*
```
1) .env (adapte le domaine / email)
# Domaine public pour Keycloak
```md
KC_HOSTNAME=auth.mondomaine.com

# Email pour Let's Encrypt
LETSENCRYPT_EMAIL=ops@mondomaine.com

# Versions images (gèle les tags pour la reproductibilité)
KEYCLOAK_IMAGE=quay.io/keycloak/keycloak:26.0
POSTGRES_IMAGE=postgres:16.4
TRAEFIK_IMAGE=traefik:v3.1
```
4) docker-compose.yml
Pourquoi c’est “prod” ✅

TLS auto & renouvellement via Traefik/Let’s Encrypt (HTTP→HTTPS forcé, HSTS).

Secrets Docker (pas d’identifiants en clair).

Healthchecks PostgreSQL & Keycloak (readiness).

Ressources limitées (évite l’OOM du JVM et protège la machine).

Logs (stdout/stderr → branche dans ta stack ELK/Loki si besoin).

Sécurité: no-new-privileges, proxy en frontal, pas d’exposition de port 8080 en public.

5) Lancer
cd infra
docker compose up -d
# Attends ~1 min le premier build optimisé


Va sur https://auth.mondomaine.com (utilise l’admin généré dans secrets/).

6) Sauvegardes PostgreSQL (simple & efficace)

Ajoute un job pg_dump quotidien (cron sur l’hôte ou conteneur dédié) :
```sh

docker run --rm --network infra_edge \
  -v "$PWD/backups:/backups" \
  -v "$PWD/secrets:/run/secrets:ro" \
  ${POSTGRES_IMAGE} \
  sh -c 'PGPASSWORD=$(cat /run/secrets/db_password) pg_dump -h postgres -U $(cat /run/secrets/db_user) keycloak \
        | gzip > /backups/keycloak-$(date +%F-%H%M).sql.gz'

```

Conserve au moins 7–14 jours de rétention + test de restauration.

7) Observabilité (Prometheus/Grafana)

Keycloak expose /metrics (activé par --metrics-enabled=true).

Scrape via Prometheus (job HTTP sur le service interne keycloak:8080).

Dashboard Grafana recommandé : Keycloak Metrics (plusieurs dispos sur la marketplace Grafana).