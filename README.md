# Pueblo Muerto

Survival de zombis cooperativo para jugar online entre dos (o hasta cuatro) personas.

| Carpeta | Qué es |
|---|---|
| `godot/` | **Versión nueva** en Godot 4. Aquí sigue el desarrollo. |
| `web/` | Versión original en un solo HTML con Three.js. Se queda como referencia. |

## Abrir el proyecto

1. Descarga **Godot 4.7** (versión estándar, no la .NET) desde <https://godotengine.org/download>.
2. Abre Godot → **Importar** → elige `godot/project.godot`.
3. Pulsa **F5** para jugar.

### Controles

WASD moverte · Ratón mirar · Shift correr · C agacharte · Espacio saltar · Esc menú

## Jugar online

Uno pulsa **Crear partida (anfitrión)** y el otro escribe su IP y pulsa **Unirse**. Se usa el puerto **7777** (UDP).

- **En la misma casa / wifi:** usa la IP local que sale arriba a la izquierda al crear la partida (por ejemplo `192.168.1.35`).
- **Desde casas distintas (recomendado: Tailscale):**
  1. Los dos instaláis [Tailscale](https://tailscale.com/download) y entráis con cuentas que estén en la misma red (el anfitrión puede invitar a la otra persona desde el panel de Tailscale).
  2. El anfitrión crea la partida; su IP de Tailscale empieza por `100.` y también aparece arriba a la izquierda.
  3. La otra persona escribe esa IP `100.x.x.x` y pulsa **Unirse**.

  Así no hace falta abrir puertos en el router.

### Probar el online tú solo

En el editor de Godot: **Depuración → Personalizar instancias de ejecución…** → activa *Habilitar varias instancias* y pon 2. Al pulsar F5 se abren dos ventanas: crea la partida en una y únete con `127.0.0.1` en la otra.

También por línea de comandos:

```
godot --path godot -- --host --name=Miguel
godot --path godot -- --join=127.0.0.1 --name=Invitada
```

## Cómo está organizado

```
godot/
  project.godot        configuración y controles
  scenes/main.tscn     escena principal: mundo, jugadores y spawner de red
  scenes/player.tscn   el personaje (cápsula, cámara, sincronización)
  scripts/network.gd   crear partida / unirse (autoload "Network")
  scripts/main.gd      menú, pausa y alta/baja de jugadores
  scripts/player.gd    movimiento en tercera persona
  scripts/world.gd     el pueblo provisional hecho con cajas
```

Cada jugador controla su propio personaje y el `MultiplayerSynchronizer` envía su posición a los demás. El pueblo se genera con una semilla fija, así que es idéntico en todos los equipos.

## Hoja de ruta

- [x] Pueblo provisional con cajas, personaje en tercera persona
- [x] Multijugador: crear partida / unirse
- [ ] Hambre, sed, salud, sangrado, ciclo día/noche
- [ ] Registrar muebles y coches (ya marcados en el grupo `contenedores`)
- [ ] Inventario **con peso** y sobrecarga
- [ ] Zombis que oyen el ruido, armas cuerpo a cuerpo y pistola
- [ ] Sustituir cajas por modelos propios (`.glb` desde fotos/IA → Blender → Godot)
- [ ] Exportar a Windows y Android
