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
| E | registrar muebles y maleteros · mantener junto a un compañero caído para levantarlo |
| Q | cambiar de arma |
| 1 · 2 · 3 | comer (el guiso primero) · beber · vendarte |
| 4 | lanzar un cóctel molotov |
| R / clic derecho | girar / cancelar al colocar una estructura |
| E (mirando lo construido) | abrir/cerrar puertas · dormir en la cama · reparar (1 tablón o chatarra) |
| R (mirando lo construido) | quitarlo (devuelve la mitad del material) |
| F | linterna (de noche los zombis te ven de más lejos si la llevas encendida) |
| Tab | mochila y **fabricar** (ver peso, soltar cosas, recetas) |
| E (con un mueble abierto) | cerrar la ventana del mueble |
| Esc | menú |

### Supervivencia

- **Salud, energía, hambre y sed** como en la versión web. Los arañazos te hacen sangrar (véndate) y alguna mordida te infecta.
- **Peso:** cada objeto pesa (lata 0,4 kg, botella 0,5 kg, hacha 2,2 kg…). Hasta 8 kg vas normal; a partir de ahí cada vez más lento, por encima de 14 kg no puedes correr y con 20 kg ya no cabe nada más: lo que sobra se queda en el mueble. Con Tab puedes soltar cosas (si estás junto a un mueble, se quedan dentro).
- **Zombis:** los controla el anfitrión. Oyen el ruido que haces (andar, correr, golpear y sobre todo disparar) y ven lo que tienen delante; agachado es más difícil que te vean. Esquivan paredes y entran por las puertas.
- **Día y noche:** un día dura 6 minutos (1 s = 4 min de juego). De noche todo se vuelve blanco y negro, los zombis van un 30% más rápido, hay más, y solo te ven de cerca… salvo que lleves la linterna encendida. Cada día aparecen más.
- **Caer y levantar (cooperativo):** a 0 de salud caes al suelo y tienes 40 s para que tu compañero te levante (manteniendo E a tu lado). Si te siguen mordiendo, el tiempo baja más rápido. Jugando solo, a 0 de salud mueres.
- **Sonido:** generado por el propio juego (golpes, disparos, pasos, gruñidos, viento, grillos de noche, latido con poca salud). Si pones grabaciones reales en `godot/sounds/` con el mismo nombre (`shot.ogg`, `groan0.wav`…), se usan en su lugar.
- **Cómic:** onomatopeyas al golpear (¡CRACK!, ¡BANG!, ¡CHOF!), temblor de cámara y una viñeta en blanco y negro puro en los golpes fuertes.
- **Fabricación:** en la mochila (Tab) está la columna *Fabricar* con lo que puedes hacer según dónde estés:
  - *a mano*: vendas de trapos, cóctel molotov, lanza, y colocar una **hoguera** o un **banco de trabajo**;
  - *junto al banco*: bate con clavos, machete, martillo, **caja de almacenaje** y reparar el arma que llevas en la mano;
  - *junto a la hoguera*: guiso caliente (llena mucho más que una lata) y vendas hervidas.
  Las recetas son archivos en `godot/data/recipes/`: se pueden cambiar o añadir desde Godot.
- **Materiales:** tablones, clavos, chatarra, trapos, cuerda, cinta, alcohol y botellas vacías (beber deja la botella). Salen de los muebles y, sobre todo, de **desmontarlos**: abre un mueble o maletero vacío y pulsa *Desmontar* (necesitas hacha o martillo; hace ruido). El mueble desaparece y deja sus materiales en el suelo.
- **Estructuras:** banco, hoguera y caja se colocan con una vista previa (roja si no cabe). Se ven en los dos equipos y se guardan con la partida. La hoguera alumbra de noche; la caja guarda lo que quieras.
- **Refugio:** fortifica casas o construye desde cero:
  - *barricada* (a mano, con martillo o hacha) para tapar puertas; *empalizada* de estacas que pincha a quien la golpea;
  - en el banco: *muro de madera* o *de chatarra* (el doble de resistente), *puerta* que se abre y cierra con E, *trampa de pinchos* que hiere y frena a los zombis (se desgasta);
  - *cama* (a mano): duerme en ella con E y reaparecerás ahí al morir.
  Los muros y puertas encajan en una rejilla de 1 m. Cada pieza tiene vida: los zombis que se topan con ella la golpean hasta derribarla (se oscurece al dañarse). Repárala con E. Los zombis no "ven" lo construido al buscar camino: van directos y chocan.
- **Hordas:** cada 7 noches (el reloj indica cuántos días faltan). Al atardecer avisa; al caer la noche entra una horda por un borde del mapa y va hacia vuestra base (el centro de lo construido, o donde estéis si no hay nada). De noche, además, las hogueras atraen a los zombis cercanos.
- **Molotov:** se lanza con 4 hacia donde miras y deja 7 s un charco de fuego que quema zombis… y a ti si lo pisas.
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
  scripts/sfx.gd       sonidos sintetizados (autoload "Sfx")
  scripts/structures.gd  estructuras colocadas (banco, hoguera, caja) y fuego
  scripts/mesh_batcher.gd  fusiona mallas para dibujar menos piezas
  scripts/data/        tipos de datos (ItemData, ContainerData, RecipeData)
  data/items/          un .tres por objeto: nombre, peso, estadísticas de arma…
  data/containers/     un .tres por mueble: tiempo de registro, botín y lo que da al desmontarlo
  data/recipes/        un .tres por receta: dónde se fabrica, ingredientes y resultado
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
- [x] **Fase 1 · Ambiente:** día y noche con linterna, sonido, onomatopeyas, sensación de golpe,
  caer herido y que tu compañero te levante
- [x] **Fase 2 · Fabricación:** desmontar muebles, materiales, banco de trabajo, hoguera, caja, recetas, reparar, molotov
- [x] **Fase 3 · Refugio:** barricadas, muros, puertas, empalizadas y trampas con vida, cama para
  reaparecer, hordas cada 7 noches
- [ ] **Fase 4 · Mundo grande:** mapa por zonas con lugares hechos a mano, casas de dos pisos,
  vehículos, mapa de papel
- [ ] **Fase 5 · Profundidad:** ropa y mochilas, habilidades, más zombis, granja y caza, historia
- [ ] **Fase 6 · Pulido:** Android, mando, dificultad configurable
