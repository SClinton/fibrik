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
COSIGN_VERSION  ?= v3.1.3
K3D_VERSION     ?= v5.9.0
FLUX_VERSION    ?= v2.9.6
TOFU_VERSION    ?= v1.13.1
BINFMT_IMAGE    ?= tonistiigi/binfmt:qemu-v10.2.3

# ---- Deployment settings --------------------------------------------------
CHART        := deploy/helm/fibrik
RELEASE      ?= fibrik
NAMESPACE    ?= fibrik
# Values profile: ci | poc | free | standard (deploy/helm/fibrik/values-<PROFILE>.yaml)
PROFILE      ?= ci
KIND_CLUSTER ?= fibrik
TIMEOUT      ?= 15m
PROFILES     := ci poc free standard
# Extra helm arguments, e.g. EXTRA_ARGS="--set storage.endpoint=https://..."
EXTRA_ARGS   ?=

# ---- Images ----------------------------------------------------------------
IMAGE_REGISTRY ?= ghcr.io/sclinton
# `dev` for local and CI builds; CI publishes the commit SHA on main.
IMAGE_TAG      ?= dev
PLATFORMS      ?= linux/amd64,linux/arm64
IMAGES         := fibrik-api fibrik-otelcol
CONTEXT_fibrik-api     := .
DOCKERFILE_fibrik-api  := build/fibrik-api.Dockerfile
CONTEXT_fibrik-otelcol    := cmd/fibrik-otelcol
DOCKERFILE_fibrik-otelcol := cmd/fibrik-otelcol/Dockerfile

# ---- Python ----------------------------------------------------------------
PYTHON ?= python3
VENV   := $(CURDIR)/.venv

# ---- Tools, installed into ./.bin ----------------------------------------
BIN  := $(CURDIR)/.bin
OS   := $(shell uname -s | tr '[:upper:]' '[:lower:]')
ARCH := $(shell uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')

HELM    := $(BIN)/helm-$(HELM_VERSION)
KIND    := $(BIN)/kind-$(KIND_VERSION)
KUBECTL := $(BIN)/kubectl-$(KUBECTL_VERSION)
COSIGN  := $(BIN)/cosign-$(COSIGN_VERSION)
K3D     := $(BIN)/k3d-$(K3D_VERSION)
FLUX    := $(BIN)/flux-$(FLUX_VERSION)
TOFU    := $(BIN)/tofu-$(TOFU_VERSION)

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

# k3d publishes one checksums file for all assets.
$(K3D):
	@mkdir -p $(BIN)
	@echo "downloading k3d $(K3D_VERSION)"
	@curl -fsSLo $@.tmp https://github.com/k3d-io/k3d/releases/download/$(K3D_VERSION)/k3d-$(OS)-$(ARCH)
	@expected=$$(curl -fsSL https://github.com/k3d-io/k3d/releases/download/$(K3D_VERSION)/checksums.txt | awk '$$2 ~ /(^|\/)k3d-$(OS)-$(ARCH)$$/ {print $$1}'); \
	 actual=$$( (sha256sum $@.tmp 2>/dev/null || shasum -a 256 $@.tmp) | awk '{print $$1}'); \
	 if [ -z "$$expected" ] || [ "$$expected" != "$$actual" ]; then echo "checksum mismatch for k3d"; rm -f $@.tmp; exit 1; fi
	@mv $@.tmp $@ && chmod +x $@

$(FLUX):
	@mkdir -p $(BIN)
	@echo "downloading flux $(FLUX_VERSION)"
	@v=$(FLUX_VERSION:v%=%); \
	 curl -fsSLo $@.tgz https://github.com/fluxcd/flux2/releases/download/$(FLUX_VERSION)/flux_$${v}_$(OS)_$(ARCH).tar.gz; \
	 expected=$$(curl -fsSL https://github.com/fluxcd/flux2/releases/download/$(FLUX_VERSION)/flux_$${v}_checksums.txt | awk '$$2 == "flux_'$${v}'_$(OS)_$(ARCH).tar.gz" {print $$1}'); \
	 actual=$$( (sha256sum $@.tgz 2>/dev/null || shasum -a 256 $@.tgz) | awk '{print $$1}'); \
	 if [ -z "$$expected" ] || [ "$$expected" != "$$actual" ]; then echo "checksum mismatch for flux"; rm -f $@.tgz; exit 1; fi
	@tar -xzf $@.tgz -C $(BIN) flux && mv $(BIN)/flux $@ && rm -f $@.tgz

$(TOFU):
	@mkdir -p $(BIN)
	@echo "downloading opentofu $(TOFU_VERSION)"
	@v=$(TOFU_VERSION:v%=%); \
	 curl -fsSLo $@.zip https://github.com/opentofu/opentofu/releases/download/$(TOFU_VERSION)/tofu_$${v}_$(OS)_$(ARCH).zip; \
	 expected=$$(curl -fsSL https://github.com/opentofu/opentofu/releases/download/$(TOFU_VERSION)/tofu_$${v}_SHA256SUMS | awk '$$2 == "tofu_'$${v}'_$(OS)_$(ARCH).zip" {print $$1}'); \
	 actual=$$( (sha256sum $@.zip 2>/dev/null || shasum -a 256 $@.zip) | awk '{print $$1}'); \
	 if [ -z "$$expected" ] || [ "$$expected" != "$$actual" ]; then echo "checksum mismatch for tofu"; rm -f $@.zip; exit 1; fi
	@python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extract('tofu', sys.argv[2])" $@.zip $(BIN) && mv $(BIN)/tofu $@ && chmod +x $@ && rm -f $@.zip

# cosign publishes one checksums file for all assets.
$(COSIGN):
	@mkdir -p $(BIN)
	@echo "downloading cosign $(COSIGN_VERSION)"
	@curl -fsSLo $@.tmp https://github.com/sigstore/cosign/releases/download/$(COSIGN_VERSION)/cosign-$(OS)-$(ARCH)
	@expected=$$(curl -fsSL https://github.com/sigstore/cosign/releases/download/$(COSIGN_VERSION)/cosign_checksums.txt | awk '$$2 == "cosign-$(OS)-$(ARCH)" {print $$1}'); \
	 actual=$$( (sha256sum $@.tmp 2>/dev/null || shasum -a 256 $@.tmp) | awk '{print $$1}'); \
	 if [ -z "$$expected" ] || [ "$$expected" != "$$actual" ]; then echo "checksum mismatch for cosign"; rm -f $@.tmp; exit 1; fi
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

.PHONY: py-dev
py-dev: $(VENV)/.installed ## Create .venv with the fibrik package and dev tools

$(VENV)/.installed: pyproject.toml
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install --quiet --upgrade pip
	$(VENV)/bin/pip install --quiet -e ".[dev]"
	@touch $@

.PHONY: py-lint
py-lint: py-dev ## Lint and format-check the Python code (ruff)
	$(VENV)/bin/ruff check fibrik tests
	$(VENV)/bin/ruff format --check fibrik tests

.PHONY: py-test
py-test: py-dev ## Run the Python unit tests
	$(VENV)/bin/pytest -q

.PHONY: tofu-validate
tofu-validate: $(TOFU) ## Format-check and validate the OpenTofu modules (no cloud credentials needed)
	$(TOFU) fmt -check -recursive deploy/tofu
	@for m in deploy/tofu/*/; do \
	  echo "--- $$m"; \
	  $(TOFU) -chdir=$$m init -backend=false -input=false >/dev/null; \
	  $(TOFU) -chdir=$$m validate; \
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

.PHONY: kind-load
kind-load: $(KIND) ## Load the locally built images into the kind cluster
	@for i in $(IMAGES); do $(KIND) load docker-image --name $(KIND_CLUSTER) $(IMAGE_REGISTRY)/$$i:$(IMAGE_TAG); done

.PHONY: k3d-up
k3d-up: $(K3D) $(KUBECTL) ## Create a k3d cluster (k3s in Docker; Mac mini, Codespaces). UI on localhost:8080
	@if $(K3D) cluster list $(KIND_CLUSTER) >/dev/null 2>&1; then \
	  echo "k3d cluster $(KIND_CLUSTER) already exists"; \
	else \
	  $(K3D) cluster create $(KIND_CLUSTER) --wait --timeout 180s \
	    --k3s-arg "--disable=traefik@server:0" -p "8080:80@loadbalancer"; \
	fi
	$(KUBECTL) config use-context k3d-$(KIND_CLUSTER)

.PHONY: k3d-load
k3d-load: $(K3D) ## Load the locally built images into the k3d cluster
	$(K3D) image import --cluster $(KIND_CLUSTER) $(foreach i,$(IMAGES),$(IMAGE_REGISTRY)/$(i):$(IMAGE_TAG))

.PHONY: k3d-down
k3d-down: $(K3D) ## Delete the k3d cluster
	$(K3D) cluster delete $(KIND_CLUSTER)

.PHONY: kind-down
kind-down: $(KIND) ## Delete the kind cluster
	$(KIND) delete cluster --name $(KIND_CLUSTER)

# ---- Deploy and test (current kube context) -------------------------------

.PHONY: deploy
deploy: $(HELM) ## Install or upgrade the chart with PROFILE into the current context
	$(HELM) upgrade --install $(RELEASE) $(CHART) \
	  --namespace $(NAMESPACE) --create-namespace \
	  -f $(CHART)/values-$(PROFILE).yaml \
	  --set images.registry=$(IMAGE_REGISTRY) --set images.tag=$(IMAGE_TAG) \
	  --wait --timeout $(TIMEOUT) $(EXTRA_ARGS)

.PHONY: test
test: $(HELM) ## Run the chart's smoke tests (helm test)
	$(HELM) test $(RELEASE) --namespace $(NAMESPACE) --logs --timeout 5m

.PHONY: e2e
e2e: $(KUBECTL) ## Send syslog lines and wait until they reach ClickHouse and Iceberg
	KUBECTL=$(KUBECTL) NAMESPACE=$(NAMESPACE) RELEASE=$(RELEASE) hack/e2e.sh

.PHONY: diag
diag: $(KUBECTL) ## Print pods, events and recent logs (for failed runs)
	-$(KUBECTL) get pods,pvc,svc -n $(NAMESPACE) -o wide
	-$(KUBECTL) get events -n $(NAMESPACE) --sort-by=.lastTimestamp
	-@for p in $$($(KUBECTL) get pods -n $(NAMESPACE) -o name); do \
	  echo "===== $$p"; \
	  $(KUBECTL) logs -n $(NAMESPACE) $$p --all-containers --tail=80 || true; \
	done

# ---- Images ------------------------------------------------------------------

define build_image
docker build -t $(IMAGE_REGISTRY)/$(1):$(IMAGE_TAG) -f $(DOCKERFILE_$(1)) $(CONTEXT_$(1))
endef

define push_image
docker buildx build --builder fibrik --platform $(PLATFORMS) -f $(DOCKERFILE_$(1)) \
  -t $(IMAGE_REGISTRY)/$(1):$(IMAGE_TAG) -t $(IMAGE_REGISTRY)/$(1):latest \
  --metadata-file $(BIN)/$(1).json --push $(CONTEXT_$(1))
$(COSIGN) sign --yes $(IMAGE_REGISTRY)/$(1)@$$(python3 -c "import json; print(json.load(open('$(BIN)/$(1).json'))['containerimage.digest'])")
endef

.PHONY: images
images: ## Build Fibrik images for this machine's platform (tag IMAGE_TAG)
	$(call build_image,fibrik-api)
	$(call build_image,fibrik-otelcol)

.PHONY: registry-login
registry-login: ## Log in to IMAGE_REGISTRY with REGISTRY_USER / REGISTRY_PASSWORD from the environment
	@echo "$$REGISTRY_PASSWORD" | docker login $(firstword $(subst /, ,$(IMAGE_REGISTRY))) -u "$$REGISTRY_USER" --password-stdin

.PHONY: images-push
images-push: $(COSIGN) ## Build multi-arch images, push them to IMAGE_REGISTRY and sign them (keyless)
	@mkdir -p $(BIN)
	docker run --privileged --rm $(BINFMT_IMAGE) --install arm64,amd64
	docker buildx inspect fibrik >/dev/null 2>&1 || docker buildx create --name fibrik
	$(call push_image,fibrik-api)
	$(call push_image,fibrik-otelcol)

# ---- CI entry points -------------------------------------------------------

.PHONY: ci-lint
ci-lint: lint ## CI: chart checks

.PHONY: gitops
gitops: $(FLUX) $(KUBECTL) ## Install Flux and point it at this repo (CLUSTER=local|free)
	$(FLUX) install
	$(KUBECTL) apply -k deploy/flux/clusters/$(CLUSTER)

CLUSTER ?= local

.PHONY: ci-k3d
ci-k3d: images k3d-up k3d-load deploy test e2e ## CI: same as ci-kind, on k3d (k3s)

.PHONY: ci-kind
ci-kind: images kind-up kind-load deploy test e2e ## CI: build images, deploy PROFILE=ci to kind, run smoke and e2e tests

.PHONY: clean
clean: ## Remove downloaded tools
	rm -rf $(BIN)
