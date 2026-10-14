# Fibrik build and deploy entry points.
#
# CI workflows only call these targets (initial-stack.md §0 rule 5), so the
# same commands work on a laptop, the Mac mini and any CI provider.
# Run `make help` for the list.

SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# ---- Pinned tool versions -------------------------------------------------
HELM_VERSION    ?= v4.3.0
KIND_VERSION    ?= v0.33.0
KUBECTL_VERSION ?= v1.37.1

# ---- Deployment settings --------------------------------------------------
CHART        := deploy/helm/fibrik
RELEASE      ?= fibrik
NAMESPACE    ?= fibrik
# Values profile: ci | free | standard (deploy/helm/fibrik/values-<PROFILE>.yaml)
PROFILE      ?= ci
KIND_CLUSTER ?= fibrik
TIMEOUT      ?= 15m
PROFILES     := ci free standard

# ---- Tools, installed into ./.bin ----------------------------------------
BIN  := $(CURDIR)/.bin
OS   := $(shell uname -s | tr '[:upper:]' '[:lower:]')
ARCH := $(shell uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')

HELM    := $(BIN)/helm-$(HELM_VERSION)
KIND    := $(BIN)/kind-$(KIND_VERSION)
KUBECTL := $(BIN)/kubectl-$(KUBECTL_VERSION)

# Download $(1) to $(2) and check it against the SHA-256 published at $(3).
define fetch
	@mkdir -p $(BIN)
	@echo "downloading $(1)"
	@curl -fsSLo $(2).tmp $(1)
	@expected=$$(curl -fsSL $(3) | awk '{print $$1}'); \
	 actual=$$( (sha256sum $(2).tmp 2>/dev/null || shasum -a 256 $(2).tmp) | awk '{print $$1}'); \
	 if [ "$$expected" != "$$actual" ]; then echo "checksum mismatch for $(1)"; rm -f $(2).tmp; exit 1; fi
endef

$(HELM):
	$(call fetch,https://get.helm.sh/helm-$(HELM_VERSION)-$(OS)-$(ARCH).tar.gz,$@.tgz,https://get.helm.sh/helm-$(HELM_VERSION)-$(OS)-$(ARCH).tar.gz.sha256sum)
	@tar -xzf $@.tgz.tmp -C $(BIN) $(OS)-$(ARCH)/helm && mv $(BIN)/$(OS)-$(ARCH)/helm $@ && rmdir $(BIN)/$(OS)-$(ARCH) && rm -f $@.tgz.tmp

$(KIND):
	$(call fetch,https://kind.sigs.k8s.io/dl/$(KIND_VERSION)/kind-$(OS)-$(ARCH),$@,https://kind.sigs.k8s.io/dl/$(KIND_VERSION)/kind-$(OS)-$(ARCH).sha256sum)
	@mv $@.tmp $@ && chmod +x $@

$(KUBECTL):
	$(call fetch,https://dl.k8s.io/release/$(KUBECTL_VERSION)/bin/$(OS)/$(ARCH)/kubectl,$@,https://dl.k8s.io/release/$(KUBECTL_VERSION)/bin/$(OS)/$(ARCH)/kubectl.sha256)
	@mv $@.tmp $@ && chmod +x $@

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-14s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: tools
tools: $(HELM) $(KIND) $(KUBECTL) ## Install pinned helm, kind and kubectl into ./.bin
	@# Unversioned names for interactive use (the devcontainer puts .bin on PATH).
	@ln -sf $(notdir $(HELM)) $(BIN)/helm
	@ln -sf $(notdir $(KIND)) $(BIN)/kind
	@ln -sf $(notdir $(KUBECTL)) $(BIN)/kubectl

# ---- Chart checks (no cluster needed) -------------------------------------

.PHONY: lint
lint: $(HELM) ## Lint the chart and render every values profile
	$(HELM) lint --strict $(CHART)
	@for p in $(PROFILES); do \
	  echo "--- profile $$p"; \
	  $(HELM) lint --strict $(CHART) -f $(CHART)/values-$$p.yaml; \
	  $(HELM) template $(RELEASE) $(CHART) -n $(NAMESPACE) -f $(CHART)/values-$$p.yaml > /dev/null; \
	done

.PHONY: template
template: $(HELM) ## Render the chart for PROFILE to stdout
	@$(HELM) template $(RELEASE) $(CHART) -n $(NAMESPACE) -f $(CHART)/values-$(PROFILE).yaml

# ---- Local cluster (kind) -------------------------------------------------

.PHONY: kind-up
kind-up: $(KIND) $(KUBECTL) ## Create the kind cluster (idempotent)
	@if $(KIND) get clusters | grep -qx $(KIND_CLUSTER); then \
	  echo "kind cluster $(KIND_CLUSTER) already exists"; \
	else \
	  $(KIND) create cluster --name $(KIND_CLUSTER) --wait 120s; \
	fi
	$(KUBECTL) config use-context kind-$(KIND_CLUSTER)

.PHONY: kind-down
kind-down: $(KIND) ## Delete the kind cluster
	$(KIND) delete cluster --name $(KIND_CLUSTER)

# ---- Deploy and test (current kube context) -------------------------------

.PHONY: deploy
deploy: $(HELM) ## Install or upgrade the chart with PROFILE into the current context
	$(HELM) upgrade --install $(RELEASE) $(CHART) \
	  --namespace $(NAMESPACE) --create-namespace \
	  -f $(CHART)/values-$(PROFILE).yaml \
	  --wait --timeout $(TIMEOUT)

.PHONY: test
test: $(HELM) ## Run the chart's smoke tests (helm test)
	$(HELM) test $(RELEASE) --namespace $(NAMESPACE) --logs --timeout 5m

.PHONY: diag
diag: $(KUBECTL) ## Print pods, events and recent logs (for failed runs)
	-$(KUBECTL) get pods,pvc,svc -n $(NAMESPACE) -o wide
	-$(KUBECTL) get events -n $(NAMESPACE) --sort-by=.lastTimestamp
	-@for p in $$($(KUBECTL) get pods -n $(NAMESPACE) -o name); do \
	  echo "===== $$p"; \
	  $(KUBECTL) logs -n $(NAMESPACE) $$p --all-containers --tail=80 || true; \
	done

# ---- CI entry points -------------------------------------------------------

.PHONY: ci-lint
ci-lint: lint ## CI: chart checks

.PHONY: ci-kind
ci-kind: kind-up deploy test ## CI: deploy PROFILE=ci to a fresh kind cluster and run smoke tests

.PHONY: clean
clean: ## Remove downloaded tools
	rm -rf $(BIN)
