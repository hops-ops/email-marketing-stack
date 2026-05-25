SHELL := /bin/bash

PACKAGE ?= email-marketing-stack
XRD_DIR := apis/emailmarketingstacks
COMPOSITION := $(XRD_DIR)/composition.yaml
DEFINITION := $(XRD_DIR)/definition.yaml
CONFIGURATION := $(XRD_DIR)/configuration.yaml
EXAMPLE_DEFAULT := examples/emailmarketingstacks/standard.yaml
RENDER_TESTS := $(wildcard tests/test-*)
E2E_TESTS := $(wildcard tests/e2etest-*)

clean:
	rm -rf _output
	rm -rf .up
	rm -f $(CONFIGURATION)

build:
	up project build

generate-configuration:
	@set -euo pipefail; \
	hops validate generate-configuration --path . --api-path "$(XRD_DIR)"

# Examples list — mirrors GitHub Actions workflow.
# Format: example_path::observed_resources_path (observed_resources_path optional).
EXAMPLES := \
    examples/emailmarketingstacks/minimal.yaml:: \
    examples/emailmarketingstacks/standard.yaml:: \
    examples/emailmarketingstacks/local-colima.yaml::

render\:all:
	@tmpdir=$$(mktemp -d); \
	pids=""; \
	for entry in $(EXAMPLES); do \
		example=$${entry%%::*}; \
		observed=$${entry#*::}; \
		api_dir=$$(echo "$$example" | awk -F/ '{print "apis/" $$2}'); \
		composition="$$api_dir/composition.yaml"; \
		definition="$$api_dir/definition.yaml"; \
		outfile="$$tmpdir/$$(echo $$entry | tr '/:' '__')"; \
		( \
			if [ -n "$$observed" ]; then \
				echo "=== Rendering $$example with observed-resources $$observed ==="; \
				up composition render --xrd=$$definition $$composition $$example --observed-resources=$$observed; \
			else \
				echo "=== Rendering $$example (api=$$api_dir) ==="; \
				up composition render --xrd=$$definition $$composition $$example; \
			fi; \
			echo "" \
		) > "$$outfile" 2>&1 & \
		pids="$$pids $$!:$$outfile"; \
	done; \
	failed=0; \
	for pair in $$pids; do \
		pid=$${pair%%:*}; \
		outfile=$${pair#*:}; \
		if ! wait $$pid; then failed=1; fi; \
		cat "$$outfile"; \
	done; \
	rm -rf "$$tmpdir"; \
	exit $$failed

validate\:all:
	@tmpdir=$$(mktemp -d); \
	pids=""; \
	for entry in $(EXAMPLES); do \
		example=$${entry%%::*}; \
		observed=$${entry#*::}; \
		api_dir=$$(echo "$$example" | awk -F/ '{print "apis/" $$2}'); \
		composition="$$api_dir/composition.yaml"; \
		definition="$$api_dir/definition.yaml"; \
		outfile="$$tmpdir/$$(echo $$entry | tr '/:' '__')"; \
		( \
			if [ -n "$$observed" ]; then \
				echo "=== Validating $$example with observed-resources $$observed ==="; \
				up composition render --xrd=$$definition $$composition $$example \
					--observed-resources=$$observed --include-full-xr --quiet | \
					crossplane beta validate $$api_dir --error-on-missing-schemas -; \
			else \
				echo "=== Validating $$example (api=$$api_dir) ==="; \
				up composition render --xrd=$$definition $$composition $$example \
					--include-full-xr --quiet | \
					crossplane beta validate $$api_dir --error-on-missing-schemas -; \
			fi; \
			echo "" \
		) > "$$outfile" 2>&1 & \
		pids="$$pids $$!:$$outfile"; \
	done; \
	failed=0; \
	for pair in $$pids; do \
		pid=$${pair%%:*}; \
		outfile=$${pair#*:}; \
		if ! wait $$pid; then failed=1; fi; \
		cat "$$outfile"; \
	done; \
	rm -rf "$$tmpdir"; \
	exit $$failed

.PHONY: render validate
render: ; @$(MAKE) 'render:all'
validate: ; @$(MAKE) 'validate:all'

render\:%:
	@example="examples/emailmarketingstacks/$*.yaml"; \
	up composition render --xrd=$(DEFINITION) $(COMPOSITION) $$example

validate\:%:
	@example="examples/emailmarketingstacks/$*.yaml"; \
	up composition render --xrd=$(DEFINITION) $(COMPOSITION) $$example \
		--include-full-xr --quiet | \
		crossplane beta validate $(XRD_DIR) --error-on-missing-schemas -

test:
	@if [ -n "$(RENDER_TESTS)" ]; then \
		up test run $(RENDER_TESTS); \
	else \
		echo "No render tests"; \
	fi

e2e:
	up test run $(E2E_TESTS) --e2e

publish:
	@if [ -z "$(tag)" ]; then echo "Error: tag is not set. Usage: make publish tag=<version>"; exit 1; fi
	up project build --push --tag $(tag)
