.PHONY: help backend-install backend-run backend-test preview-run

help:
	@echo "Targets:"
	@echo "  make backend-install  - create venv and install backend dev deps"
	@echo "  make backend-run      - run backend API using backend/.env"
	@echo "  make backend-test     - run backend test suite"
	@echo "  make preview-run      - run browser UI simulator on port 4173"

backend-install:
	test -d backend/.venv || python3 -m venv backend/.venv
	cd backend && . .venv/bin/activate && pip install -r requirements-dev.txt

backend-run:
	cd backend && ./run.sh

backend-test:
	cd backend && . .venv/bin/activate && PYTHONPATH=. pytest -q

preview-run:
	cd preview && python3 -m http.server 4173
