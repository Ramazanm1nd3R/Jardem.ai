# Jardem.ai — common tasks. Run `make help`.
.PHONY: help up down logs build-web build-mobile test test-backend test-web test-mobile mutation experiments data

help:
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

up: build-web ## build the site and start the whole cluster on http://localhost:8080
	docker compose up -d --build

down: ## stop the cluster (keeps the database volume)
	docker compose down

logs: ## follow backend logs
	docker compose logs -f backend

build-web: ## build the landing site into web/dist
	cd web && npm install && npm run build

build-mobile: ## build both Flutter apps for the web (served by the gateway)
	cd mobile/citizen && flutter build web --release --base-href /app/citizen/
	cd mobile/responder && flutter build web --release --base-href /app/responder/
	docker compose restart gateway

test: test-backend test-web test-mobile ## run every test suite

test-backend:
	cd backend && uv run pytest -q

test-web:
	cd web && npm test

test-mobile:
	cd mobile/packages/jardem_core && flutter test
	cd mobile/citizen && flutter test
	cd mobile/responder && flutter test

mutation: ## mutation testing: backend domain (mutmut) and web logic (Stryker)
	cd backend && rm -rf mutants && uv run mutmut run
	cd web && npm run test:mutation

experiments: ## compare dispatch strategies; writes docs/experiments/results.md
	cd backend && uv run python -m experiments.compare

data: ## rebuild the road graph and department catalogue from the raw OSM extracts
	cd backend && python3 scripts/build_graph.py data/raw/almaty_roads.json app/data/almaty_graph.json.gz
	cd backend && python3 scripts/build_departments.py data/raw/almaty_pois.json app/data/almaty_departments.json
