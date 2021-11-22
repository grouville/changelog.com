# curl will fail while dagger is a private repository
# DAGGER_BIN := dagger-$(DAGGER_VERSION)-$(platform)-amd64
# DAGGER_URL := $(DAGGER_RELEASES)/download/v$(DAGGER_VERSION)/dagger-$(platform)-amd64
# DAGGER := $(LOCAL_BIN)/$(DAGGER_BIN)

DAGGER_RELEASES := https://github.com/dagger/dagger/releases
DAGGER_VERSION := 0.1.0-alpha.30
DAGGER_DIR := $(LOCAL_BIN)/dagger_v$(DAGGER_VERSION)_$(platform)_amd64
DAGGER_URL := $(DAGGER_RELEASES)/download/v$(DAGGER_VERSION)/$(notdir $(DAGGER_DIR)).tar.gz
DAGGER := $(DAGGER_DIR)/dagger
$(DAGGER): | $(GH) $(CURL) $(LOCAL_BIN)
	@printf "$(RED)$(BOLD)curl$(RESET)$(RED) will fail while $(BOLD)$(DAGGER_RELEASES)$(RESET)$(RED) is a private repository$(RESET)\n"
	@printf "$(GREY)$(CURL) --progress-bar --fail --location --output $(DAGGER_DIR).tar.gz $(DAGGER_URL)$(RESET)\n"
	@printf "$(GREEN)Using $(BOLD)gh$(RESET)$(GREEN) instead$(RESET)\n"
	rm -fr $(DAGGER_DIR)*
	$(GH) release download v$(DAGGER_VERSION) --repo dagger/dagger --pattern '*darwin_amd64.tar.gz' --dir $(LOCAL_BIN)
	mkdir -p $(DAGGER_DIR) && tar zxf $(DAGGER_DIR).tar.gz -C $(DAGGER_DIR)
	touch $(DAGGER)
	chmod +x $(DAGGER)
	$(DAGGER) version | grep $(DAGGER_VERSION)
	ln -sf $(DAGGER) $(LOCAL_BIN)/dagger
.PHONY: dagger
dagger: $(DAGGER)
.PHONY: releases-dagger
releases-dagger:
	$(OPEN) $(DAGGER_RELEASES)

DAGGER_GIT_DIR := $(CURDIR)/tmp/dagger-$(DAGGER_VERSION)
$(DAGGER_GIT_DIR):
	git clone \
	  --branch v$(DAGGER_VERSION) --single-branch --depth 1 \
	  git@github.com:dagger/dagger $(DAGGER_GIT_DIR)
.PHONY: tmp/dagger
tmp/dagger: $(DAGGER_GIT_DIR)

DAGGER_CTX = cd $(BASE_DIR) && time $(DAGGER)
# Log in plain format if DEBUG variable is set
ifneq (,$(DEBUG))
  DAGGER_CTX += --log-format plain
endif
DAGGER_HOME := $(BASE_DIR)/.dagger
DAGGER_ENV := $(DAGGER_HOME)/env
OTEL_EXPORTER_JAEGER_ENDPOINT := http://$(shell awk -F'[/:]' '{ print $$4 }' <<< $(DOCKER_HOST)):14268/api/traces
export OTEL_EXPORTER_JAEGER_ENDPOINT

$(DAGGER_HOME): | $(DAGGER)
	@printf "$(BOLD)TODO$(RESET) $(CYAN)Make $(BOLD)dagger init$(RESET)$(CYAN) command idempotent$(RESET)\n"
	$(DAGGER_CTX) init
.PHONY: dagger-init
dagger-init: | $(DAGGER_HOME)

$(DAGGER_ENV)/ci: | dagger-init
	$(DAGGER_CTX) new ci --package $(CURDIR)/dagger/ci
	printf "$(INFO)Run this only once per environment$(NORMAL)\n"
	read -p "Enter your DockerHub username: " dockerhub_username \
	; $(DAGGER_CTX) input text dockerhub_username $$dockerhub_username --environment ci
	read -p "Enter your DockerHub password: " dockerhub_password \
	; $(DAGGER_CTX) input secret dockerhub_password $$dockerhub_password --environment ci

define _convert_dockerignore_to_excludes
awk '{ print "--exclude " $$1 }' < $(BASE_DIR)/.dockerignore
endef
.PHONY: dagger-ci
dagger-ci: $(DAGGER_ENV)/ci $(LPASS)
	@printf "$(BOLD)TODO$(RESET) $(CYAN)Document multiple $(BOLD)--exclude$(RESET)$(CYAN) statements$(RESET)\n"
	$(DAGGER_CTX) input dir app . $(shell $(_convert_dockerignore_to_excludes)) --exclude deps --environment ci
	$(DAGGER_CTX) input text prod_dockerfile --file docker/Dockerfile.production --environment ci
	$(DAGGER_CTX) input text docker_host $(DOCKER_HOST) --environment ci
	@printf "$(BOLD)TODO$(RESET) $(CYAN)Remove $(BOLD)JAEGER_TRACE$(RESET)$(CYAN) from docs, it no longer works multiple$(RESET)\n"
	$(DAGGER_CTX) up --log-level debug --environment ci

.PHONY: dagger-clean
dagger-clean:
	rm -fr $(DAGGER_HOME)
