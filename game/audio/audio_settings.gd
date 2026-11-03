extends Node
## Mixer preferences sit above authored players and the menu's pause lowpass.

signal changed

const MASTER_BUS := &"SettingsMaster"
const MUSIC_BUS := &"SettingsMusic"
const EFFECTS_BUS := &"Effects"
const CHANNEL_BUSES := {&"master": MASTER_BUS, &"music": MUSIC_BUS, &"effects": EFFECTS_BUS}
const MIN_DB := -80.0

@export var config_path := "user://audio.cfg"
var _volumes := {&"master": 1.0, &"music": 1.0, &"effects": 1.0}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"audio_settings")
	ensure_buses()
	var config := ConfigFile.new()
	if config.load(config_path) == OK:
		for channel: StringName in CHANNEL_BUSES:
			var value: Variant = config.get_value("audio", String(channel), 1.0)
			if (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and _valid_volume(float(value)):
				_volumes[channel] = float(value)
	for channel: StringName in CHANNEL_BUSES:
		_apply(channel)

## Called by standalone world/audio tests too; repeat calls preserve current gains.
static func ensure_buses() -> void:
	_ensure_bus(MASTER_BUS, &"Master")
	_ensure_bus(MUSIC_BUS, MASTER_BUS)
	_ensure_bus(EFFECTS_BUS, MASTER_BUS)

static func _ensure_bus(bus: StringName, send: StringName) -> void:
	if AudioServer.get_bus_index(bus) != -1:
		return
	var index := AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus)
	AudioServer.set_bus_send(index, send)

static func _valid_volume(value: float) -> bool:
	return is_finite(value) and value >= 0.0 and value <= 1.0

func get_volume(channel: StringName) -> float:
	return _volumes.get(channel, 1.0)

func set_volume(channel: StringName, value: float) -> Error:
	if not CHANNEL_BUSES.has(channel) or not _valid_volume(value):
		return ERR_INVALID_PARAMETER
	var config := ConfigFile.new()
	for key: StringName in CHANNEL_BUSES:
		config.set_value("audio", String(key), value if key == channel else _volumes[key])
	var error := config.save(config_path)
	if error != OK:
		return error
	_volumes[channel] = value
	_apply(channel)
	changed.emit()
	return OK

func _apply(channel: StringName) -> void:
	var index := AudioServer.get_bus_index(CHANNEL_BUSES[channel])
	var value: float = _volumes[channel]
	# AudioServer ramps bus gains; finite silence avoids log(0), mute guarantees zero.
	AudioServer.set_bus_volume_db(index, linear_to_db(value) if value > 0.0 else MIN_DB)
	AudioServer.set_bus_mute(index, value == 0.0)
