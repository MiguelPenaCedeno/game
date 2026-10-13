#!/usr/bin/env bash
# Ejecuta todas las pruebas automáticas. Uso: tests/run_all.sh /ruta/a/godot
# Falla si alguna comprobación falla o si aparece cualquier error de script.
set -u
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
fail=0
LOG=$(mktemp -d)

echo "### Importando proyecto"
"$GODOT" --headless --import >/dev/null 2>&1 || true

echo "### Prueba en solitario"
timeout 360 "$GODOT" --headless -- --test=solo > "$LOG/solo.log" 2>&1 || fail=1
grep -v "^Godot Engine" "$LOG/solo.log"

echo "### Prueba con dos jugadores"
timeout 240 "$GODOT" --headless -- --test=host > "$LOG/host.log" 2>&1 &
HOST=$!
sleep 3
timeout 200 "$GODOT" --headless -- --test=client > "$LOG/client.log" 2>&1 || fail=1
wait $HOST || fail=1
grep -v "^Godot Engine" "$LOG/client.log"
grep -v "^Godot Engine" "$LOG/host.log"

if grep -q "SCRIPT ERROR\|Parse Error\|Failed to load script" "$LOG"/*.log; then
	echo "### Hay errores de script en la salida"
	fail=1
fi

if [ $fail -eq 0 ]; then echo "### TODO OK"; else echo "### HAY FALLOS"; fi
exit $fail
