DAGGER_BIN := dagger-$(DAGGER_VERSION)-$(platform)-amd64
DAGGER_URL := $(DAGGER_RELEASES)/download/v$(DAGGER_VERSION)/dagger-$(platform)-amd64
DAGGER := $(LOCAL_BIN)/$(DAGGER_BIN)

DAGGER_RELEASES := https://github.com/dagger/dagger/releases
DAGGER_VERSION := 0.1.0-alpha.30
DAGGER_DIR := $(LOCAL_BIN)/dagger_v$(DAGGER_VERSION)_$(platform)_amd64
DAGGER_URL := $(DAGGER_RELEASES)/download/v$(DAGGER_VERSION)/$(notdir $(DAGGER_DIR)).tar.gz
DAGGER := $(DAGGER_DIR)/dagger
$(DAGGER): | $(GH) $(CURL) $(LOCAL_BIN)
	@printf "🤔 $(RED)$(BOLD)curl$(RESET)$(RED) will fail while $(BOLD)$(DAGGER_RELEASES)$(RESET)$(RED) is a private repository$(RESET)\n"
	@printf "$(GREY)$(CURL) --progress-bar --fail --location --output $(DAGGER_DIR).tar.gz $(DAGGER_URL)$(RESET)\n"
	@printf "💡 $(GREEN)Using $(BOLD)gh$(RESET)$(GREEN) instead$(RESET)\n"
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

DAGGER_DIR := $(CURDIR)/tmp/dagger-$(DAGGER_VERSION)
$(DAGGER_DIR):
	git clone \
	  --branch v$(DAGGER_VERSION) --single-branch --depth 1 \
	  git@github.com:dagger/dagger $(DAGGER_DIR)
.PHONY: tmp/dagger
tmp/dagger: $(DAGGER_DIR)

DAGGER_CTX = cd $(BASE_DIR) && $(DAGGER)
# Log in plain format if DEBUG variable is set
ifneq (,$(DEBUG))
  DAGGER_CTX += --log-format plain
endif
DAGGER_HOME := $(BASE_DIR)/.dagger
DAGGER_ENV := $(DAGGER_HOME)/env
# 🤔 JAEGER_TRACE no longer works
# TODO: remove from docs
OTEL_EXPORTER_JAEGER_ENDPOINT := http://$(shell awk -F'[/:]' '{ print $$4 }' <<< $(DOCKER_HOST)):14268/api/traces
export OTEL_EXPORTER_JAEGER_ENDPOINT

export JAEGER_TRACE

$(DAGGER_HOME): | $(DAGGER)
	@printf "\n🤔 $(YELLOW)Does the existence of the $(RESET)$(BOLD).dagger$(RESET)$(YELLOW) dir imply $(GREEN)$(BOLD)dagger init$(RESET)?\n"
	@printf "💡 $(GREEN)Make this command idempotent$(RESET)\n\n"
	$(DAGGER_CTX) init
.PHONY: dagger-init
dagger-init: | $(DAGGER_HOME)

$(DAGGER_ENV)/ci-%: | dagger-init
	$(DAGGER_CTX) new ci-$(*) --package $(CURDIR)/dagger/ci/$(*)
	$(DAGGER_CTX) input dir app . $(shell $(_convert_dockerignore_to_excludes)) --exclude deps --environment ci-$(*)

define _convert_dockerignore_to_excludes
awk '{ print "--exclude " $$1 }' < $(BASE_DIR)/.dockerignore
endef
.PHONY: dagger-ci-%
dagger-ci-%: $(DAGGER_ENV)/ci-%
	@printf "\n🤔 $(YELLOW)In repos like this one, uploading app to a remote $(BOLD)BUILDKIT_HOST$(RESET)$(YELLOW) is slow: $(BOLD)392s$(RESET)$(YELLOW) for $(BOLD)3.4GB$(RESET)\n"
	@printf "$(YELLOW)   Even cached, the app operation is still slow: $(BOLD)27s$(RESET)\n"
	@printf "💡 $(GREEN)Introduce $(BOLD).daggerignore$(RESET)$(GREEN) and/or respect $(BOLD).dockerignore$(RESET)\n\n"
	@printf "⭐️ $(GREEN)Multiple $(BOLD)--exclude$(RESETT)$(GREEN) statements worked well - it's something that I intend to document$(RESET)\n"
	@printf "🙌 $(GREEN)My uncached ci app now takes $(BOLD)6s$(RESET)$(GREEN) for $(BOLD)80MB$(RESET)$(GREEN) & $(BOLD)0.5s$(RESET)$(GREEN) cached$(RESET)\n\n"
	$(DAGGER_CTX) up --log-level debug --environment ci-$(*)

.PHONY: dagger-clean
dagger-clean:
	rm -fr $(DAGGER_HOME)
