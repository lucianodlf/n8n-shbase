.PHONY: help init up down restart logs status reset zrok2-start zrok2-stop activate-workflows deactivate-workflows

# Detectar si hay un .env cargado para mostrar el PROJECT_NAME
-include .env

PROJECT ?= $(PROJECT_NAME)

help: ## Muestra esta ayuda
	@echo ""
	@echo "  n8n-shbase — Comandos disponibles"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sed 's/.*:\([a-zA-Z_-]*\):.*## /\1:/' \
		| awk 'BEGIN {FS = ":"}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo ""

init: ## Inicializa la instancia: crea .env, genera claves, configura .mcp.json
	@bash scripts/init.sh

up: ## Levanta los servicios en background
	@docker compose up -d 2>&1 | tee /tmp/n8n-up.log; \
	if grep -q "port is already allocated" /tmp/n8n-up.log; then \
		echo ""; \
		echo "⚠️  Puerto ya en uso. Otra instancia n8n puede estar corriendo en el mismo puerto."; \
		echo "   Verificá con: docker ps | grep n8n"; \
		echo "   O cambiá N8N_PORT en .env y reejecutá make init && make up"; \
		exit 1; \
	fi

zrok2-stop: ## (temporal) Detiene el proceso zrok2 si está corriendo
	@if pgrep -x zrok2 > /dev/null 2>&1; then \
		pkill -x zrok2 && echo "✅ zrok2 detenido."; \
	else \
		echo "ℹ️  zrok2 no estaba corriendo."; \
	fi

zrok2-start: ## (temporal) Inicia túnel zrok2 público si no está corriendo
	@if pgrep -x zrok2 > /dev/null 2>&1; then \
		echo "ℹ️  zrok2 ya está corriendo, omitiendo."; \
	else \
		zrok2 share public http://localhost:5678 -n public:rafikidlf-mygpzrokurl --headless \
			> /tmp/zrok2-share.log 2>&1 & \
		ZROK_PID=$$!; \
		sleep 2; \
		if ! kill -0 $$ZROK_PID 2>/dev/null; then \
			echo "❌ zrok2 falló al iniciar:"; \
			cat /tmp/zrok2-share.log; \
		else \
			echo "✅ zrok2 tunnel iniciado en background (pid=$$ZROK_PID)"; \
		fi; \
	fi

activate-workflows: ## Activa los workflows listados en N8N_ACTIVATE_WORKFLOWS (IDs separados por coma)
	@if [ -z "$(N8N_API_KEY)" ]; then \
		echo "⚠️  N8N_API_KEY no configurada — omitiendo activación de workflows."; \
		exit 0; \
	fi; \
	if [ -z "$(N8N_ACTIVATE_WORKFLOWS)" ]; then \
		echo "ℹ️  N8N_ACTIVATE_WORKFLOWS vacío — nada que activar."; \
		exit 0; \
	fi; \
	BASE_URL="http://localhost:$(N8N_PORT)"; \
	echo "⏳ Esperando a que la API de n8n esté lista..."; \
	for i in $$(seq 1 30); do \
		if curl -sf "$$BASE_URL/api/v1/workflows" -H "X-N8N-API-KEY: $(N8N_API_KEY)" > /dev/null 2>&1; then \
			echo "✅ API lista."; break; \
		fi; \
		if [ $$i -eq 30 ]; then \
			echo "❌ Timeout esperando n8n (60s). Activar workflows manualmente."; exit 1; \
		fi; \
		sleep 2; \
	done; \
	for WF_ID in $$(echo "$(N8N_ACTIVATE_WORKFLOWS)" | tr ',' ' '); do \
		STATUS=$$(curl -s -o /dev/null -w "%{http_code}" -X POST \
			"$$BASE_URL/api/v1/workflows/$$WF_ID/activate" \
			-H "X-N8N-API-KEY: $(N8N_API_KEY)"); \
		if [ "$$STATUS" = "200" ]; then \
			echo "✅ Workflow $$WF_ID activado."; \
		else \
			echo "⚠️  Workflow $$WF_ID — HTTP $$STATUS (puede ya estar activo o ID incorrecto)."; \
		fi; \
	done

deactivate-workflows: ## Desactiva los workflows listados en N8N_ACTIVATE_WORKFLOWS (IDs separados por coma)
	@if [ -z "$(N8N_API_KEY)" ]; then \
		echo "⚠️  N8N_API_KEY no configurada — omitiendo desactivación de workflows."; \
		exit 0; \
	fi; \
	if [ -z "$(N8N_ACTIVATE_WORKFLOWS)" ]; then \
		echo "ℹ️  N8N_ACTIVATE_WORKFLOWS vacío — nada que desactivar."; \
		exit 0; \
	fi; \
	BASE_URL="http://localhost:$(N8N_PORT)"; \
	for WF_ID in $$(echo "$(N8N_ACTIVATE_WORKFLOWS)" | tr ',' ' '); do \
		STATUS=$$(curl -s -o /dev/null -w "%{http_code}" -X POST \
			"$$BASE_URL/api/v1/workflows/$$WF_ID/deactivate" \
			-H "X-N8N-API-KEY: $(N8N_API_KEY)"); \
		if [ "$$STATUS" = "200" ]; then \
			echo "✅ Workflow $$WF_ID desactivado."; \
		else \
			echo "⚠️  Workflow $$WF_ID — HTTP $$STATUS."; \
		fi; \
	done

down: ## Detiene los servicios
	@docker compose down

restart: ## Reinicia los servicios
	@docker compose restart

logs: ## Muestra los logs en tiempo real
	@docker compose logs -f

status: ## Muestra el estado de los contenedores
	@docker compose ps

reset: ## ⚠️  Revierte al estado de template limpio (elimina .env, claves, volúmenes)
	@bash scripts/reset.sh

reset-hard: ## ⚠️  Reset sin confirmación interactiva (--hard)
	@bash scripts/reset.sh --hard
