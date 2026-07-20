FLUTTER := fvm flutter
DART := fvm dart

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: setup
setup: ## Configure the Flutter SDK and fetch dependencies (package + example)
	fvm use
	fvm flutter pub get
	cd example && fvm flutter pub get

.PHONY: get
get: ## Install dependencies
	$(FLUTTER) pub get

.PHONY: upgrade
upgrade: ## Upgrade dependencies to latest allowed versions
	$(FLUTTER) pub upgrade

.PHONY: analyze
analyze: ## Run static analysis
	$(FLUTTER) analyze

.PHONY: format
format: ## Format all Dart code
	$(DART) format .

.PHONY: format-check
format-check: ## Verify formatting without applying changes
	$(DART) format --set-exit-if-changed .

.PHONY: test
test: ## Run tests
	$(FLUTTER) test

.PHONY: check
check: format-check analyze test ## Run format check, analysis, and tests

.PHONY: clean
clean: ## Remove build artifacts
	$(FLUTTER) clean

.PHONY: run-example
run-example: ## Run the example app
	cd example && $(FLUTTER) run
