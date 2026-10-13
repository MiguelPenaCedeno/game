# Pueblo Muerto

Survival de zombis cooperativo para jugar online entre dos (o hasta cuatro) personas.

| Carpeta | Qué es |
|---|---|
| `godot/` | **Versión nueva** en Godot 4. Aquí sigue el desarrollo. |
| `web/` | Versión original en un solo HTML con Three.js. Se queda como referencia. |

## Jugar sin instalar Godot (Windows)

Cada vez que se sube un cambio a `main`, GitHub prueba el juego y genera el ejecutable:
ve a **Releases → Pueblo Muerto (última versión)** en la página del repositorio, descarga
`PuebloMuerto-windows.zip`, descomprímelo y abre `PuebloMuerto.exe`. Windows avisará de que
es una app desconocida (no está firmada): *Más información → Ejecutar de todas formas*.

## Abrir el proyecto

1. Descarga **Godot 4.7** (versión estándar, no la .NET) desde <https://godotengine.org/download>.
2. Abre Godot → **Importar** → elige `godot/project.godot`.
3. Pulsa **F5** para jugar.

### Controles

| Tecla | Acción |
|---|---|
| WASD / Ratón | moverte / mirar |
| Shift | correr (hace ruido, gasta energía) |
| C | agacharte (sigilo: casi no haces ruido y te ven de más cerca) |
| Espacio | saltar |
| Clic izquierdo | golpear o disparar |
| E | registrar muebles y maleteros |
| Q | cambiar de arma |
| 1 · 2 · 3 | comer · beber · vendarte |
| Tab | mochila (ver peso y soltar cosas) |
| E (con un mueble abierto) | cerrar la ventana del mueble |
| Esc | menú |

### Supervivencia

- **Salud, energía, hambre y sed** como en la versión web. Los arañazos te hacen sangrar (véndate) y alguna mordida te infecta.
- **Peso:** cada objeto pesa (lata 0,4 kg, botella 0,5 kg, hacha 2,2 kg…). Hasta 8 kg vas normal; a partir de ahí cada vez más lento, por encima de 14 kg no puedes correr y con 20 kg ya no cabe nada más: lo que sobra se queda en el mueble. Con Tab puedes soltar cosas (si estás junto a un mueble, se quedan dentro).
- **Zombis:** los controla el anfitrión. Oyen el ruido que haces (andar, correr, golpear y sobre todo disparar) y ven lo que tienen delante; agachado es más difícil que te vean. Esquivan paredes y entran por las puertas.
- **Minimapa** arriba a la derecha: gira contigo. Cuadraditos amarillos = muebles sin registrar, puntos rojos = zombis cercanos, flechas de color = tus compañeros.

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

## Guardado

La partida se guarda sola cada minuto, al salir al menú y al cerrar la ventana. El anfitrión
guarda el mundo (muebles, bultos, cadáveres) y cada jugador su personaje, en
`%APPDATA%/Godot/app_userdata/Pueblo Muerto/`. Al volver a crear la partida continúas;
marca *Empezar de cero* en el menú para borrarla. Si al morir llevabas cosas, tu mochila
queda junto al cadáver (cuadro rojo en el minimapa).

## Pruebas automáticas

```
godot/tests/run_all.sh /ruta/a/godot
```

Prueba una partida en solitario (registrar, peso, bultos, cadáver, guardado, combate, pausa)
y una partida con dos jugadores conectados. GitHub las ejecuta en cada cambio.

## Estilo visual: novela gráfica

Todo se dibuja como un cómic de terror:

- **Sombreado en 3 tonos** (`shaders/toon.gdshader`): luz, media luz y sombra planas, con la sombra azulada como tinta aguada.
- **Postproceso de tinta y papel** (`shaders/ink_post.gdshader`): contornos negros que "tiemblan" como dibujados a mano, trama diagonal en las sombras, color apagado salvo el **rojo** (sangre, ojos de zombi), grano de papel y viñeta. Los valores se pueden ajustar en el material del nodo `InkPass`.
- **Niebla color papel**: lo lejano se funde con el fondo, como en una viñeta.
- **Tipografías**: Special Elite (títulos) y Barlow Condensed (interfaz), las mismas que la versión web.

Requiere el renderizador **Forward+** (el de PC). El MSAA debe quedar desactivado: con él, Godot no pasa la profundidad al postproceso y desaparecen los contornos.

## Cómo está organizado

```
godot/
  project.godot        configuración y controles
  scenes/main.tscn     escena principal: mundo, jugadores y spawner de red
  scenes/player.tscn   el personaje (cápsula, cámara, sincronización)
  scripts/network.gd   crear partida / unirse (autoload "Network")
  scripts/main.gd      menú, pausa y alta/baja de jugadores
  scripts/player.gd    movimiento en tercera persona
  scripts/human_figure.gd  figura humana articulada y animada por código
  scripts/zombie.gd    IA de los zombis (solo corre en el anfitrión)
  scripts/items.gd     objetos, pesos, armas y botín
  scripts/hud.gd       interfaz: estadísticas, mochila, avisos, muerte
  scripts/minimap.gd   minimapa
  scripts/save_game.gd guardado de mundo y personaje
  scripts/settings.gd  ajustes (autoload "Settings")
  scripts/mesh_batcher.gd  fusiona mallas para dibujar menos piezas
  scripts/data/        tipos de datos (ItemData, ContainerData)
  data/items/          un .tres por objeto: nombre, peso, estadísticas de arma…
  data/containers/     un .tres por mueble: tiempo de registro y botín
  tests/               pruebas automáticas
  scripts/world.gd     el pueblo: casas con tejado, vallas, postes, coches, árboles
  shaders/             sombreado de cómic y postproceso de tinta
  fonts/               tipografías (licencias OFL / Apache incluidas)
```

Cada jugador controla su propio personaje y el `MultiplayerSynchronizer` envía su posición a los demás. El pueblo se genera con una semilla fija, así que es idéntico en todos los equipos.

## Hoja de ruta

Decisiones tomadas: construcción **híbrida** (fortificar casas y construir libremente),
mapa **semiprocedural con lugares hechos a mano**, y al morir **la mochila queda en el cadáver**.

- [x] Prototipo: pueblo, personaje en tercera persona, multijugador
- [x] Estilo novela gráfica y figura humana animada
- [x] Supervivencia, registrar muebles, peso, zombis, armas, minimapa
- [x] **Fase 0 · Cimientos:** geometría fusionada (5× menos llamadas de dibujo), suavizado en red,
  objetos en `.tres`, ventana de registro objeto a objeto, bultos y mochila en el cadáver,
  guardado, ajustes, pausa en solitario, pruebas automáticas y `.exe` automático
- [ ] **Fase 1 · Ambiente:** día y noche con linterna, sonido, onomatopeyas, sensación de golpe,
  caer herido y que tu compañero te levante
- [ ] **Fase 2 · Fabricación:** desmontar muebles, materiales, banco de trabajo, hoguera, recetas, reparar
- [ ] **Fase 3 · Refugio:** fortificar casas (barricadas con vida), construcción libre, almacenes,
  cama, hordas cada 7 noches
- [ ] **Fase 4 · Mundo grande:** mapa por zonas con lugares hechos a mano, casas de dos pisos,
  vehículos, mapa de papel
- [ ] **Fase 5 · Profundidad:** ropa y mochilas, habilidades, más zombis, granja y caza, historia
- [ ] **Fase 6 · Pulido:** Android, mando, dificultad configurable
