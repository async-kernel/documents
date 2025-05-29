
BIND ?= 0.0.0.0
PORT ?= 3001

baseURL ?= ""

check-hugo:
	@command -v hugo> /dev/null 2>&1 || { echo "Hugo is not installed. Please install it first."; exit 1; }
	@echo "Hugo is installed."

update-home: check-hugo
	@cp README.md content/_index.md

new: update-home
	@hugo new $(doc)

serve: update-home
	@hugo server --minify --theme hugo-book --bind $(BIND) --port $(PORT)

generate: update-home
	@hugo --theme hugo-book $(if $(baseURL),--baseURL=$(baseURL))
