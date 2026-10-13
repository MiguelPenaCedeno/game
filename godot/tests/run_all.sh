#!/usr/bin/env bash
# Ejecuta todas las pruebas automáticas. Uso: tests/run_all.sh /ruta/a/godot
set -u
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
fail=0

echo "### Importando proyecto"
"$GODOT" --headless --import >/dev/null 2>&1 || true

echo "### Prueba en solitario"
timeout 120 "$GODOT" --headless -- --test=solo || fail=1

echo "### Prueba con dos jugadores"
timeout 90 "$GODOT" --headless -- --test=host > /tmp/pm_host.log 2>&1 &
HOST=$!
sleep 3
timeout 60 "$GODOT" --headless -- --test=client || fail=1
wait $HOST || fail=1
cat /tmp/pm_host.log | grep -v "^Godot Engine"

if [ $fail -eq 0 ]; then echo "### TODO OK"; else echo "### HAY FALLOS"; fi
exit $fail
