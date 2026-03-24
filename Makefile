SHELL := /bin/bash

USERS ?= 10
DURATION ?= 120
THINK ?= 0.5
MODE ?= all
TOKENS ?= 64

.PHONY: help host mig up demo stress-on stress-off load load-stop down

help:
	@echo "Available targets:"
	@echo "  make host                - install host prerequisites"
	@echo "  make mig                 - enable MIG, create layout, export UUIDs, validate"
	@echo "  make up                  - start the stack"
	@echo "  make demo                - run smoke/demo queries"
	@echo "  make stress-on           - start OOM / memory pressure demo"
	@echo "  make stress-off          - stop OOM / memory pressure demo"
	@echo "  make load                - start configurable text load"
	@echo "       variables: USERS=$(USERS) DURATION=$(DURATION) THINK=$(THINK) MODE=$(MODE) TOKENS=$(TOKENS)"
	@echo "  make load-stop           - stop text load"
	@echo "  make down                - cleanup lab"

host:
	sudo bash scripts/00_host_prereqs.sh

mig:
	sudo bash scripts/01_enable_mig.sh
	sudo bash scripts/02_create_layout.sh
	sudo bash scripts/03_export_env.sh
	sudo bash scripts/04_validate_host.sh

up:
	bash scripts/05_start_stack.sh

demo:
	bash scripts/06_demo_queries.sh

stress-on:
	bash scripts/07_start_stress.sh

stress-off:
	bash scripts/08_stop_stress.sh

load:
	LOAD_USERS=$(USERS) \
	LOAD_DURATION_SEC=$(DURATION) \
	LOAD_THINK_TIME_SEC=$(THINK) \
	LOAD_MODEL_MODE=$(MODE) \
	LOAD_MAX_TOKENS=$(TOKENS) \
	bash scripts/09_start_text_load.sh

load-stop:
	bash scripts/10_stop_text_load.sh

down:
	bash scripts/99_cleanup.sh
