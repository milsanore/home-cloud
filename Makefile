#!make
SHELL:=/bin/bash

NOW:=$(shell date -u +%Y-%m-%dT%H:%M:%S%Z)

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

## up: 🟢
.PHONY: up
up:
	$(call pp,starting infrastructure...)
	docker compose -p home-cloud up -d \
		proxy \
		acme \
		pihole \
		db \
		nextcloud \
		wordpress \
		samba \
		wireguard \
		wireguard-ui \
		qbittorrent

## stop: 🟠
.PHONY: stop
stop:
	$(call pp,stopping infrastructure...)
	docker compose -p home-cloud stop

## down: 🔴 DELETE infrastructure
.PHONY: down
down:
	@echo -n "Are you sure? [y/N] " && read ans && [ $${ans:-N} = y ]
	$(call pp,DELETING infrastructure...)
	docker compose -p home-cloud down

## backup: 🟢 backup volumes and associated compose
.PHONY: backup
backup:
	$(call pp,backing up data...)
	mkdir -p ./backups/${NOW}/db
	cp docker-compose.yml ./backups/${NOW}/
	docker cp --archive db:/config ./backups/${NOW}/db/
