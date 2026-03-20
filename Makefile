.PHONY: help init up down restart logs status reset

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
