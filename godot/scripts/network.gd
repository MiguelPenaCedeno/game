extends Node
## Conexión online (autoload "Network").
## Uno crea la partida (anfitrión) y el otro se une con su IP.
## Entre casas distintas, lo más fácil es usar Tailscale o ZeroTier
## y unirse con la IP 100.x.x.x que te da la app.

const PORT := 7777
const MAX_CLIENTS := 3

var player_name := "Superviviente"


func host() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func join(address: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func play_solo() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func is_online() -> bool:
	return not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


## IPv4 de este equipo, para decírselas a quien se une.
func local_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			out.append(ip)
	return out


## Color fijo para cada jugador: el anfitrión siempre naranja.
func color_for(id: int) -> Color:
	if id == 1:
		return Color(0.86, 0.52, 0.2)
	return Color.from_hsv(float(absi(hash(id)) % 1000) / 1000.0, 0.55, 0.85)
