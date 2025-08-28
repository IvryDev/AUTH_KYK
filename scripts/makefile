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