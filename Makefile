# Installs the status line and the Chat themes into Claude Code's config folder.
#   make install                      into ~/.claude
#   make install CLAUDE_DIR=<folder>  somewhere else, e.g. to try it out first
# A file it would replace with something different is backed up first as <file>.bak-<date>-<time>,
# so nothing is lost and running it again changes nothing. Works with the make that ships with macOS (3.81).

CLAUDE_DIR ?= $(HOME)/.claude
SETTINGS := $(CLAUDE_DIR)/settings.json
THEMES := $(CLAUDE_DIR)/themes
THEMES_EXISTED := $(wildcard $(THEMES))
STAMP := $(shell date +%Y%m%d-%H%M%S)
# The "~" form in the default place, as the README shows it.
COMMAND := $(if $(filter $(HOME)/.claude,$(CLAUDE_DIR)),~/.claude/statusline.sh,$(CLAUDE_DIR)/statusline.sh)
STATUS_LINE := {"type":"command","command":"$(COMMAND)","padding":0,"refreshInterval":60}

# $(call put,source,destination,mode): copy, backing up a destination that differs.
put = if cmp -s "$(1)" "$(2)"; then echo "  unchanged  $(2)"; else \
  if [ -e "$(2)" ]; then cp -p "$(2)" "$(2).bak-$(STAMP)"; echo "  backed up  $(2).bak-$(STAMP)"; fi; \
  install -m $(3) "$(1)" "$(2)"; echo "  installed  $(2)"; fi

.PHONY: help install

help:
	@echo "make install                      install the status line and Chat themes into $(CLAUDE_DIR)"
	@echo "make install CLAUDE_DIR=<folder>  install somewhere else"

install:
	@command -v jq >/dev/null || { echo "jq is needed: brew install jq" >&2; exit 1; }
	@if [ -s "$(SETTINGS)" ] && ! jq -e 'type == "object"' "$(SETTINGS)" >/dev/null 2>&1; then \
	  echo "$(SETTINGS) is not a JSON object, so nothing was installed. Fix it, or set statusLine by hand (see README)." >&2; \
	  exit 1; fi
	@mkdir -p "$(THEMES)"
	@set -e; $(call put,statusline.sh,$(CLAUDE_DIR)/statusline.sh,755)
	@set -e; $(call put,themes/chat-dark.json,$(THEMES)/chat-dark.json,644)
	@set -e; $(call put,themes/chat-light.json,$(THEMES)/chat-light.json,644)
	@# The status line rewrites chat-auto.json to match the macOS appearance, so only create it.
	@set -e; if [ -e "$(THEMES)/chat-auto.json" ]; then echo "  kept       $(THEMES)/chat-auto.json"; else \
	  jq '.name = "Chat (auto)"' themes/chat-dark.json >"$(THEMES)/chat-auto.json"; \
	  echo "  created    $(THEMES)/chat-auto.json"; fi
	@# Set statusLine in settings.json and keep everything else.
	@set -e; want='$(STATUS_LINE)'; \
	if [ ! -s "$(SETTINGS)" ]; then \
	  jq -n --argjson s "$$want" '{statusLine: $$s}' >"$(SETTINGS)"; echo "  created    $(SETTINGS)"; \
	elif jq -e --argjson s "$$want" '.statusLine == $$s' "$(SETTINGS)" >/dev/null; then \
	  echo "  unchanged  $(SETTINGS)"; \
	else \
	  tmp=$$(mktemp); jq --argjson s "$$want" '.statusLine = $$s' "$(SETTINGS)" >"$$tmp"; \
	  cp -p "$(SETTINGS)" "$(SETTINGS).bak-$(STAMP)"; echo "  backed up  $(SETTINGS).bak-$(STAMP)"; \
	  cat "$$tmp" >"$(SETTINGS)"; rm -f "$$tmp"; echo "  updated    $(SETTINGS) (statusLine)"; \
	fi
	@echo "Done. Pick a Chat theme with /theme in Claude Code."
	@$(if $(THEMES_EXISTED),true,echo "Restart Claude Code first: it only sees new themes if $(THEMES) existed when it started.")
