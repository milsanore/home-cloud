#!make
SHELL:=/bin/bash

NOW:=$(shell date -u +%Y-%m-%dT%H%M%SZ)
PROJECT:=home-cloud
# named volumes used by running services (compose prefixes them with "$(PROJECT)_")
VOLUMES:=mariadb nextcloud wordpress \
	proxy-certs proxy-conf proxy-dhparam proxy-html proxy-vhost acme-acme
# GNU tar, multi-arch (works on the raspberry pi)
TAR_IMAGE:=debian:bookworm-slim

# pp - pretty print function
yellow := $(shell tput setaf 3)
normal := $(shell tput sgr0)
define pp
	@printf '$(yellow)$(1)$(normal)\n'
endef

.PHONY: help
help: Makefile
	@echo " Choose a command to run:"
	@sed -n 's/^##//p' $< | column -t -s ':' | sed -e 's/^/ /'

## start: 🟢
.PHONY: start
start:
	$(call pp,starting infrastructure...)
	docker compose -p $(PROJECT) up -d \
		socket-proxy \
		proxy \
		acme \
		db \
		nextcloud \
		wordpress

## stop: 🟠
.PHONY: stop
stop:
	$(call pp,stopping infrastructure...)
	docker compose -p $(PROJECT) stop

## down: 🔴 DELETE infrastructure
.PHONY: down
down:
	@echo -n "Are you sure? [y/N] " && read ans && [ $${ans:-N} = y ]
	$(call pp,DELETING infrastructure...)
	docker compose -p $(PROJECT) down

## backup: 💾 stop, backup volumes + config, restart
.PHONY: backup
backup: BACKUP_DIR:=$(abspath ./backups/$(NOW))
backup:
	$(call pp,stopping infrastructure for a consistent backup...)
	docker compose -p $(PROJECT) stop
	$(call pp,backing up to $(BACKUP_DIR)...)
	mkdir -p -m 700 $(BACKUP_DIR)
	cp -a docker-compose.yml .env secrets $(BACKUP_DIR)/
	@failed=0; \
	for v in $(VOLUMES); do \
		if ! docker volume inspect $(PROJECT)_$$v >/dev/null 2>&1; then \
			echo "  $(PROJECT)_$$v: not found, skipping"; continue; \
		fi; \
		echo "  $(PROJECT)_$$v"; \
		docker run --rm \
			-v $(PROJECT)_$$v:/data:ro \
			-v $(BACKUP_DIR):/backup \
			$(TAR_IMAGE) tar --numeric-owner -C /data -czf /backup/$$v.tar.gz . \
			|| { echo "  $(PROJECT)_$$v: FAILED"; failed=1; }; \
	done; \
	printf '$(yellow)restarting infrastructure...$(normal)\n'; \
	docker compose -p $(PROJECT) start; \
	exit $$failed

## restore: 🔌 create volumes from a backup, e.g. make restore BACKUP=./backups/<timestamp>
.PHONY: restore
restore:
	@[ -n "$(BACKUP)" ] || { echo "usage: make restore BACKUP=./backups/<timestamp>"; exit 1; }
	@for v in $(VOLUMES); do \
		[ -f $(BACKUP)/$$v.tar.gz ] || continue; \
		if docker volume inspect $(PROJECT)_$$v >/dev/null 2>&1; then \
			echo "volume $(PROJECT)_$$v already exists, aborting"; exit 1; \
		fi; \
	done
	$(call pp,restoring from $(BACKUP)...)
	@for v in $(VOLUMES); do \
		if [ ! -f $(BACKUP)/$$v.tar.gz ]; then \
			echo "  $(PROJECT)_$$v: no backup, skipping"; continue; \
		fi; \
		echo "  $(PROJECT)_$$v"; \
		docker volume create \
			--label com.docker.compose.project=$(PROJECT) \
			--label com.docker.compose.volume=$$v \
			$(PROJECT)_$$v >/dev/null || exit 1; \
		docker run --rm \
			-v $(PROJECT)_$$v:/data \
			-v $(abspath $(BACKUP)):/backup:ro \
			$(TAR_IMAGE) tar --numeric-owner -C /data -xzf /backup/$$v.tar.gz || exit 1; \
	done

## update: ⬆️  backup, pull newer images, recreate changed containers, update nextcloud apps (weekly via cron)
.PHONY: update
update:
	$(MAKE) backup BACKUP_DIR=$(abspath ./backups/auto-$(NOW))
	$(call pp,pulling images...)
	docker compose -p $(PROJECT) pull
	$(call pp,recreating changed containers...)
	docker compose -p $(PROJECT) up -d --wait
	$(call pp,waiting for nextcloud to finish any upgrade...)
	@for i in $$(seq 1 60); do \
		docker exec -u www-data nextcloud php occ status --output=json 2>/dev/null \
			| grep -q '"maintenance":false.*"needsDbUpgrade":false' && exit 0; \
		sleep 10; \
	done; echo "nextcloud not ready after 10 minutes"; exit 1
	$(call pp,updating nextcloud apps...)
	docker exec -u www-data nextcloud php occ app:update --all
	docker image prune -f
	$(MAKE) prune-backups

## prune-backups: 🧹 keep only the newest automatic backups (backups/auto-*)
KEEP_BACKUPS?=2
.PHONY: prune-backups
prune-backups:
	@ls -1d backups/auto-* 2>/dev/null | sort | head -n -$(KEEP_BACKUPS) | while read -r d; do \
		echo "  removing $$d"; rm -rf "$$d"; \
	done
