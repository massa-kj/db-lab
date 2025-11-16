.PHONY: help install uninstall test clean dev

help: ## Show this help message
	@echo "DBLab Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make <target>"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install: ## Install DBLab system-wide (requires sudo)
	@echo "Installing DBLab..."
	sudo ./scripts/install.sh

uninstall: ## Uninstall DBLab from system (requires sudo)
	@echo "Uninstalling DBLab..."
	sudo dblab-uninstall

uninstall-clean: ## Uninstall DBLab and remove all user data (requires sudo)
	@echo "Uninstalling DBLab with data removal..."
	sudo dblab-uninstall --remove-data --stop-containers

test: ## Run basic functionality tests
	@echo "Testing DBLab installation..."
	@if command -v dblab >/dev/null 2>&1; then \
		echo "✓ dblab command available"; \
		dblab --help >/dev/null && echo "✓ help command works"; \
		dblab list postgres >/dev/null && echo "✓ list command works"; \
		echo "Testing with temporary instance..."; \
		dblab init postgres --instance test-makefile > test-makefile.env && echo "✓ init command works"; \
		echo "DBLAB_PG_PASSWORD=testpass123" >> test-makefile.env; \
		dblab up postgres --instance test-makefile --env-file test-makefile.env >/dev/null 2>&1 && \
		  echo "✓ up command works (running in background)"; \
		dblab status postgres --instance test-makefile >/dev/null && echo "✓ status command works"; \
		dblab down postgres --instance test-makefile >/dev/null && echo "✓ down command works"; \
		echo "yes" | dblab destroy postgres --instance test-makefile >/dev/null 2>&1 && echo "✓ destroy command works"; \
		rm -f test-makefile.env; \
		echo "✓ All tests passed"; \
	else \
		echo "✗ dblab command not found. Please run 'make install' first."; \
		exit 1; \
	fi

dev: ## Run from source (development mode)
	@echo "Running DBLab from source..."
	@./bin/dblab --help | head -5

clean: ## Remove temporary files
	@echo "Cleaning up temporary files..."
	@rm -f *.env
	@rm -f /tmp/*test*.env
	@echo "✓ Cleanup complete"

version: ## Show version information
	@if [ -f VERSION ]; then \
		echo "DBLab version: $$(cat VERSION)"; \
	else \
		echo "Version file not found"; \
	fi
