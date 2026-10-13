class_name Difficulty
extends RefCounted
## Niveles de dificultad. Se eligen al crear una partida nueva y se guardan
## con el mundo; el anfitrión se los pasa a quien se une.

const ORDER: Array[String] = ["facil", "normal", "dificil", "pesadilla"]
const NAMES := {"facil": "Fácil", "normal": "Normal", "dificil": "Difícil", "pesadilla": "Pesadilla"}
const DESCRIPTIONS := {
	"facil": "Menos zombis y más lentos, más botín, menos hambre. Hordas cada 9 noches.",
	"normal": "Como está pensado. Hordas cada 7 noches.",
	"dificil": "Más zombis, más rápidos y que muerden más fuerte. Poco botín. Hordas cada 5 noches.",
	"pesadilla": "Todo en contra: muchos zombis, mordiscos que infectan y hordas cada 4 noches.",
}
## zombies: cuántos · zombie_dmg: daño de sus golpes · zombie_speed: velocidad
## loot: probabilidad de encontrar cosas · hunger: hambre y sed · horde_every: noches entre hordas
## infection: probabilidad de infección · xp: experiencia de las habilidades
const PRESETS := {
	"facil": {"zombies": 0.6, "zombie_dmg": 0.6, "zombie_speed": 0.85, "loot": 1.4, "hunger": 0.7, "horde_every": 9, "infection": 0.5, "xp": 1.3},
	"normal": {"zombies": 1.0, "zombie_dmg": 1.0, "zombie_speed": 1.0, "loot": 1.0, "hunger": 1.0, "horde_every": 7, "infection": 1.0, "xp": 1.0},
	"dificil": {"zombies": 1.3, "zombie_dmg": 1.3, "zombie_speed": 1.1, "loot": 0.75, "hunger": 1.25, "horde_every": 5, "infection": 1.5, "xp": 0.9},
	"pesadilla": {"zombies": 1.7, "zombie_dmg": 1.6, "zombie_speed": 1.2, "loot": 0.55, "hunger": 1.5, "horde_every": 4, "infection": 2.0, "xp": 0.8},
}


static func value(level: String, key: String) -> float:
	return float(PRESETS.get(level, PRESETS.normal)[key])
