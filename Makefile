.PHONY: help backend-install backend-run backend-test preview-run backend-service-install backend-service-start backend-service-stop backend-service-restart backend-service-status backend-service-logs

help:
	@echo "Targets:"
	@echo "  make backend-install  - create venv and install backend dev deps"
	@echo "  make backend-run      - run backend API using backend/.env"
	@echo "  make backend-test     - run backend test suite"
	@echo "  make backend-service-install - install and start user-level systemd service"
	@echo "  make backend-service-start   - start backend user service"
	@echo "  make backend-service-stop    - stop backend user service"
	@echo "  make backend-service-restart - restart backend user service"
	@echo "  make backend-service-status  - show backend user service status"
	@echo "  make backend-service-logs    - tail backend user service logs"
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

backend-service-install:
	./scripts/install-backend-user-service.sh

backend-service-start:
	systemctl --user start manga-reader-backend.service

backend-service-stop:
	systemctl --user stop manga-reader-backend.service

backend-service-restart:
	systemctl --user restart manga-reader-backend.service

backend-service-status:
	systemctl --user status manga-reader-backend.service --no-pager

backend-service-logs:
	journalctl --user -u manga-reader-backend.service -f
