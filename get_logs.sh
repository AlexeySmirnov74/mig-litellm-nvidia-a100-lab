docker compose --env-file .env -f compose/docker-compose.yml logs --tail=100 tgi-tiny tgi-fast tgi-general open-webui litellm
