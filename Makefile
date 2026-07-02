# Makefile — developer entrypoint for 5-DevOps-Toolkit (mirrors CI).
#
# Requires: bash, shellcheck, bats, python3 with ruff + pytest
#   (pip install -r requirements-dev.txt).
# Windows without `make`? Use ./tasks.ps1 with the same target names.

SHELL := bash
PY_TARGETS := 04-network-ssh/ssh_toolkit 05-docker-devops/ec2-deploy.py
SH_FILES := $(shell find . -name '*.sh' -not -path '*/.venv/*' -not -path '*/.git/*')

.DEFAULT_GOAL := help
.PHONY: help syntax shellcheck ruff lint bats pytest test all

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-11s\033[0m %s\n", $$1, $$2}'

syntax: ## bash -n over every shell script
	@for f in $(SH_FILES); do bash -n "$$f" || exit 1; done
	@echo "syntax ok ($(words $(SH_FILES)) scripts)"

shellcheck: ## shellcheck all shell scripts (ignores SC1091)
	@shellcheck -e SC1091 -S warning $(SH_FILES)

ruff: ## ruff real-error lint on the Python code
	@ruff check --select E9,F63,F7,F82 $(PY_TARGETS)

lint: syntax shellcheck ruff ## Run all linters

bats: ## Run the bats shell tests
	@bats tests/bats

pytest: ## Run the pytest suite
	@pytest 04-network-ssh/tests -q

test: bats pytest ## Run all tests

all: lint test ## Lint, then test
