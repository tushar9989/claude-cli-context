# Installs the status line and the Chat themes into Claude Code's config folder, or removes them.
#   make install                        into ~/.claude
#   make install CLAUDE_DIR=<folder>    somewhere else, e.g. to try it out first
#   make uninstall [CLAUDE_DIR=<folder>]
# A file it would replace or remove that differs from this repo's copy is backed up first as
# <file>.bak-<date>-<time>, so nothing is lost; running either again changes nothing.
# Works with the make that ships with macOS (3.81).

CLAUDE_DIR ?= $(HOME)/.claude
SETTINGS := $(CLAUDE_DIR)/settings.json
THEMES := $(CLAUDE_DIR)/themes
THEMES_EXISTED := $(wildcard $(THEMES))
STAMP := $(shell date +%Y%m%d-%H%M%S)
DEFAULT_DIR := $(filter $(HOME)/.claude,$(CLAUDE_DIR))
# The "~" form in the default place, as the README shows it.
COMMAND := $(if $(DEFAULT_DIR),~/.claude/statusline.sh,$(CLAUDE_DIR)/statusline.sh)
STATUS_LINE := {"type":"command","command":"$(COMMAND)","padding":0,"refreshInterval":60}
# The status line's usage history (see statusline.sh); every install shares it.
CACHE := $(or $(XDG_CACHE_HOME),$(HOME)/.cache)/claude-statusline
# jq: drop statusLine if it runs this script, and theme if it is one of the Chat themes.
UNSET := if (.statusLine | type) == "object" and (.statusLine.command == $$a or .statusLine.command == $$b) \
  then del(.statusLine) else . end \
  | if .theme == "custom:chat-dark" or .theme == "custom:chat-light" or .theme == "custom:chat-auto" \
  then del(.theme) else . end

# $(call put,source,destination,mode): copy, backing up a destination that differs.
put = if cmp -s "$(1)" "$(2)"; then echo "  unchanged  $(2)"; else \
  if [ -e "$(2)" ]; then cp -p "$(2)" "$(2).bak-$(STAMP)"; echo "  backed up  $(2).bak-$(STAMP)"; fi; \
  install -m $(3) "$(1)" "$(2)"; echo "  installed  $(2)"; fi

# $(call drop,source,destination): remove the destination, backing it up first if it differs from source.
drop = if [ -e "$(2)" ] || [ -L "$(2)" ]; then \
  if ! cmp -s "$(1)" "$(2)"; then cp -p "$(2)" "$(2).bak-$(STAMP)"; echo "  backed up  $(2).bak-$(STAMP)"; fi; \
  rm -f "$(2)"; echo "  removed    $(2)"; fi

.PHONY: help install uninstall check-settings

help:
	@echo "make install                      install the status line and Chat themes into $(CLAUDE_DIR)"
	@echo "make install CLAUDE_DIR=<folder>  install somewhere else"
	@echo "make uninstall                    remove them again (CLAUDE_DIR works the same)"

# Both targets stop before changing anything if settings.json can't be edited safely.
check-settings:
	@command -v jq >/dev/null || { echo "jq is needed: brew install jq" >&2; exit 1; }
	@if [ -s "$(SETTINGS)" ] && ! jq -e 'type == "object"' "$(SETTINGS)" >/dev/null 2>&1; then \
	  echo "$(SETTINGS) is not a JSON object, so nothing was changed. Fix it, or edit statusLine by hand (see README)." >&2; \
	  exit 1; fi

install: check-settings
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

uninstall: check-settings
	@# Settings first, so Claude Code stops running the script and using the themes before they go.
	@set -e; if [ -s "$(SETTINGS)" ]; then \
	  old=$$(jq . "$(SETTINGS)"); \
	  new=$$(jq --arg a '$(COMMAND)' --arg b '$(CLAUDE_DIR)/statusline.sh' '$(UNSET)' "$(SETTINGS)"); \
	  if [ "$$new" = "$$old" ]; then echo "  unchanged  $(SETTINGS)"; else \
	    gone=$$(jq -rn --argjson o "$$old" --argjson n "$$new" '($$o | keys) - ($$n | keys) | join(" and ")'); \
	    cp -p "$(SETTINGS)" "$(SETTINGS).bak-$(STAMP)"; echo "  backed up  $(SETTINGS).bak-$(STAMP)"; \
	    printf '%s\n' "$$new" >"$(SETTINGS)"; echo "  updated    $(SETTINGS) (removed $$gone)"; \
	  fi; fi
	@set -e; $(call drop,statusline.sh,$(CLAUDE_DIR)/statusline.sh)
	@set -e; $(call drop,themes/chat-dark.json,$(THEMES)/chat-dark.json)
	@set -e; $(call drop,themes/chat-light.json,$(THEMES)/chat-light.json)
	@# chat-auto.json is generated by the status line, a copy of one of the two above.
	@set -e; f="$(THEMES)/chat-auto.json"; if [ -e "$$f" ]; then rm -f "$$f"; echo "  removed    $$f"; fi
	@if [ -d "$(THEMES)" ] && rmdir "$(THEMES)" 2>/dev/null; then echo "  removed    $(THEMES)/ (it was empty)"; fi
	@# The usage history is shared, so it goes only with the install in the default place.
	@set -e; if [ -n "$(DEFAULT_DIR)" ]; then \
	  for f in "$(CACHE)/5h.txt" "$(CACHE)/week.txt" "$(CACHE)/5h-archive.txt" "$(CACHE)/week-archive.txt"; do \
	    if [ -e "$$f" ]; then rm -f "$$f"; echo "  removed    $$f"; fi; done; \
	  if [ -d "$(CACHE)" ] && rmdir "$(CACHE)" 2>/dev/null; then echo "  removed    $(CACHE)/ (it was empty)"; fi; \
	fi
	@echo "Done. Backups ending in .bak-<date>-<time> are kept; restore one by hand to get an earlier file back."
