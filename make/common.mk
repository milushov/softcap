# ===========================================================================
# common.mk — the universal make vocabulary shared across these projects.
#
# GENERATED FILE. Do not edit in place: every repo holds a byte-identical
# copy and the checker fails if one drifts.
#
#     source of truth   ~/work/.makestd/common.mk
#     propagate         ~/work/.makestd/sync
#     verify            ~/work/.makestd/sync --check
#
# A root Makefile declares what the repo has, then includes this file:
#
#     STD_PROJECT  := myproject
#     STD_SERVICES := backend    # dir owning docker compose; empty = none
#     STD_OWN      := deploy     # universal targets this repo defines itself
#     include make/common.mk
#
# `check`, `lint` and `test` are deliberately NOT defined here. Their
# composition is the most valuable thing in each repo — in the larger ones it
# is a dozen or more individually named guards — and flattening them would
# destroy real work. They are guaranteed to EXIST in every repo, not to do the
# same amount of work in every repo.
#
# Every target here either does real work or prints SKIPPED and exits 0. None
# of them ever fails with "No rule to make target", which is the whole point:
# a verb you remember works in all thirteen repos.
# ===========================================================================

# GREP_OPTIONS is exported as `--color=always` in the environment these repos
# are driven from, make passes it through to every recipe, and BSD grep on
# macOS honours it — so any grep whose output is then parsed returns ANSI
# escape codes embedded in the value instead of the value.
#
# This is not hypothetical housekeeping. It cost four separate defects in one
# night on 2026-08-31, documented at length in the project where it was first
# diagnosed, and it bit again on 2026-09-29 while auditing these very
# Makefiles: a target-name extraction came back as "\033[01;31m\033[K.PHONY"
# instead of a target name.
#
# This line covers recipes only, not an interactive shell. The --color=never
# on each call site below is the per-call belt to this braces.
unexport GREP_OPTIONS

# --- repo declarations, with safe fallbacks -------------------------------
# A repo that forgets to declare still gets working targets: the project name
# falls back to the directory name and the absence of services is assumed,
# which makes every lifecycle verb print SKIPPED rather than misfire.
STD_PROJECT  ?= $(notdir $(CURDIR))
STD_SERVICES ?=
STD_OWN      ?=

# A bare `make` lists targets. It must never launch a full gate by accident:
# `check` in the larger repos runs fifteen guards and several test suites, and
# that is not what an empty command line asks for.
.DEFAULT_GOAL := help

# --- skip loudly, never silently ------------------------------------------
# $(call std_services,<target>) runs <target> in the services component.
#
# Three outcomes, all exit 0, all of them saying which one happened:
#   no services declared        -> SKIPPED (no local services in <project>)
#   declared but lacks <target> -> SKIPPED (<dir> has no <target> target)
#   present                     -> delegate
#
# The guard is what keeps the promise. Delegating blind would surface the
# component's own "No rule to make target" — the exact failure this file
# exists to eliminate.
#
# It must be awk, and it must read the whole target list. Several backends
# declare two names in one rule:
#
#     start up:
#     	docker compose up -d
#
# so `grep '^up:'` says the target is absent when it is right there. Worse,
# adding `up: start` next to it makes make merge the two rules and run the
# recipe twice — measured on 2026-09-29 in a backend that did exactly this,
# which is how this guard came to be written this way.
define std_services
	@if [ -z "$(STD_SERVICES)" ] || [ ! -f "$(STD_SERVICES)/Makefile" ]; then \
		echo "SKIPPED  $(1) (no local services in $(STD_PROJECT))"; \
	elif awk -v t='$(1)' '/^[^#\t][^:=]*:/ { n = split(substr($$0, 1, index($$0, ":") - 1), a, /[ \t]+/); for (i = 1; i <= n; i++) if (a[i] == t) found = 1 } END { exit !found }' "$(STD_SERVICES)/Makefile"; then \
		$(MAKE) --no-print-directory -C "$(STD_SERVICES)" $(1); \
	else \
		echo "SKIPPED  $(1) ($(STD_SERVICES)/Makefile has no $(1) target)"; \
	fi
endef

# ===========================================================================
# Lifecycle — bringing local background services up and down.
#
# `up` means one thing in every repo: background services, detached, prompt
# returns. A foreground file-watching dev server is `dev`, never `up`.
# ===========================================================================

ifeq ($(filter up,$(STD_OWN)),)
## Bring local background services up, detached.
up:
	$(call std_services,up)
endif

ifeq ($(filter down,$(STD_OWN)),)
## Stop local background services.
down:
	$(call std_services,down)
endif

ifeq ($(filter restart,$(STD_OWN)),)
## Stop and start local background services.
restart:
	$(call std_services,restart)
endif

ifeq ($(filter ps,$(STD_OWN)),)
## Show which local services are running.
ps:
	$(call std_services,ps)
endif

ifeq ($(filter logs,$(STD_OWN)),)
## Tail logs from local services.
logs:
	$(call std_services,logs)
endif

ifeq ($(filter console,$(STD_OWN)),)
## Open an application console / REPL.
console:
	$(call std_services,console)
endif

# The names this vocabulary replaced. Kept working on purpose: every script,
# doc and CLAUDE.md that already says `make start` keeps working, and so does
# the muscle memory of whoever typed it.
ifeq ($(filter start,$(STD_OWN)),)
## Alias for `up`.
start: up
endif

ifeq ($(filter stop,$(STD_OWN)),)
## Alias for `down`.
stop: down
endif

# ===========================================================================
# Setup
# ===========================================================================

ifeq ($(filter setup,$(STD_OWN)),)
## First-time setup for a fresh clone: services, then git hooks.
setup:
	$(call std_services,setup)
	@if [ -d scripts/git-hooks ]; then \
		git config core.hooksPath scripts/git-hooks && \
		echo "hooks    core.hooksPath -> scripts/git-hooks"; \
	else \
		echo "SKIPPED  git hooks (no scripts/git-hooks in $(STD_PROJECT))"; \
	fi
endif

# ===========================================================================
# Quality verbs that are mechanical enough to share.
#
# `check`, `lint` and `test` are NOT here — see the header.
# ===========================================================================

ifeq ($(filter typecheck,$(STD_OWN)),)
## Type-check what the project can type-check.
typecheck:
	$(call std_services,typecheck)
endif

ifeq ($(filter fmt,$(STD_OWN)),)
## Auto-format code in place (safe corrections only).
fmt:
	$(call std_services,fmt)
endif

ifeq ($(filter security,$(STD_OWN)),)
## Run the security scanners.
security:
	$(call std_services,security)
endif

# ===========================================================================
# Conditional verbs — one agreed name wherever the thing exists at all.
# ===========================================================================

ifeq ($(filter dev,$(STD_OWN)),)
## Run a foreground dev server with file watching (blocks).
dev:
	$(call std_services,dev)
endif

ifeq ($(filter build,$(STD_OWN)),)
## Build the project's artifacts.
build:
	$(call std_services,build)
endif

ifeq ($(filter deploy,$(STD_OWN)),)
## Deploy to production.
deploy:
	$(call std_services,deploy)
endif

ifeq ($(filter e2e,$(STD_OWN)),)
## Run end-to-end tests.
e2e:
	$(call std_services,e2e)
endif

ifeq ($(filter db-migrate,$(STD_OWN)),)
## Run pending database migrations.
db-migrate:
	$(call std_services,db-migrate)
endif

ifeq ($(filter db-seed,$(STD_OWN)),)
## Seed the development database.
db-seed:
	$(call std_services,db-seed)
endif

ifeq ($(filter db-reset,$(STD_OWN)),)
## Drop, recreate, migrate and seed the development database.
db-reset:
	$(call std_services,db-reset)
endif

# ===========================================================================
# help
# ===========================================================================
# Renders every documented target, universal ones first, so the answer to
# "what can I run here" never depends on which repo you are standing in.
#
# Two doc conventions are in use across these repos and both are supported:
#
#     ## one-line summary        (block above the target)
#     up:
#
#     up: ## one-line summary    (trailing on the target line)
#
# Both are in use across these projects, so both must keep working.
#
# A `##` block may be written either way round, so help reads the first
# paragraph -- every contiguous `##` line up to a bare `##` -- and joins it:
#
#     ## one-line summary        a bare ## closes the paragraph, so the
#     ##                         reasoning below it is not shown
#     ## reasoning...
#
#     ## a summary long enough   no bare ##, so both lines are one paragraph
#     ## to wrap over two lines  and are joined rather than cut mid-clause
#
# An over-long result is elided with an ellipsis. Taking only the physical
# first line, as the older hand-written help targets did, truncated 108 of
# these summaries across these projects, several of them mid-word.
#
# awk, not a grep chain: --no-group-separator is GNU-only and BSD grep on
# macOS answers with a usage error instead.
#
# Grouping comes from FILENAME over $(MAKEFILE_LIST): anything read out of
# common.mk is universal, anything out of the root Makefile is this project's
# own. Targets with no doc comment are intentionally invisible — the internal
# -impl halves and the dozens of named guards would bury the verbs.

ifeq ($(filter help,$(STD_OWN)),)
## List available targets.
help:
	@awk -v proj="$(STD_PROJECT)" -v own="$(STD_OWN)" ' \
		BEGIN { n = split(own, a, " "); for (i = 1; i <= n; i++) owned[a[i]] = 1 } \
		FILENAME ~ /common\.mk$$/ { universal = 1 } \
		FILENAME !~ /common\.mk$$/ { universal = 0 } \
		/^##/ { \
			d = substr($$0, 3); sub(/^ +/, "", d); \
			if (d == "") { closed = 1 } \
			else if (!closed) { doc = (doc == "" ? d : doc " " d) } \
			next; \
		} \
		/^[a-zA-Z0-9_.:\\-]+[ 	]*:/ { \
			tgt = $$0; sub(/[ 	]*:.*$$/, "", tgt); gsub(/\\:/, ":", tgt); \
			inline = ""; \
			if ($$0 ~ /## /) { inline = $$0; sub(/^.*## /, "", inline); } \
			text = (inline != "" ? inline : doc); \
			if (length(text) > 78) text = substr(text, 1, 75) "..."; \
			if (text != "" && substr(tgt, 1, 1) != "." && !(universal && owned[tgt])) { \
				if (universal) { u[++nu] = sprintf("  %-16s %s", tgt, text); } \
				else { p[++np] = sprintf("  %-16s %s", tgt, text); } \
			} \
			doc = ""; closed = 0; next; \
		} \
		{ doc = ""; closed = 0 } \
		END { \
			printf "\n%s\n", proj; \
			if (nu > 0) { \
				printf "\n  universal — the same in every project\n"; \
				for (i = 1; i <= nu; i++) print u[i]; \
			} \
			if (np > 0) { \
				printf "\n  %s only\n", proj; \
				for (i = 1; i <= np; i++) print p[i]; \
			} \
			printf "\n"; \
		}' $(MAKEFILE_LIST)
endif

.PHONY: up down restart ps logs console start stop setup typecheck fmt \
        security dev build deploy e2e db-migrate db-seed db-reset help
