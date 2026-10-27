class_name DemoWorld
extends Node3D
## DemoWorld: собирает квартал, ставит участников по Layout (C1) и отдаёт снимок HUD (C6).
## Состояние миссии читается из MissionDirector; команды миссии подключает QUEST-01.

const Layout = preload("res://game/world/layout.gd")

var control_mode: StringName = &"on_foot"
## true, пока открыт диалог или панель: мышь видна и не захватывается по клику (выставляет QuestFlow).
var ui_blocking := false

@onready var player: Ilyusha = $Ilyusha
@onready var camera_rig: CameraRig = $CameraRig
@onready var mission: MissionDirector = $MissionDirector
@onready var babka: Node3D = $Babka
@onready var vendor: Node3D = $Vendor
@onready var car: Node3D = $Car
@onready var kiosk_zone: Area3D = $KioskZone

func _ready() -> void:
	babka.position = Layout.BABKA
	babka.rotation.y = 0.0  # лицом на север, к двору
	vendor.position = Layout.VENDOR
	vendor.interactable.position = Layout.VENDOR_WINDOW - Layout.VENDOR
	car.position = Layout.CAR_SPAWN
	car.rotation.y = Layout.CAR_SPAWN_YAW
	player.camera_rig = camera_rig
	player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	camera_rig.yaw = Layout.SPAWN_YAW
	camera_rig.follow(player, &"on_foot")
	_sync_prompts()

func _physics_process(_delta: float) -> void:
	_sync_prompts()

## Тексты и доступность зон E — только из MissionDirector (C3).
func _sync_prompts() -> void:
	for npc in [babka, vendor]:
		var zone: Interactable = npc.interactable
		zone.prompt = mission.prompt_for(zone.interaction_id)
		zone.enabled = zone.prompt != ""

func anchor_position(id: StringName) -> Vector3:
	match id:
		&"babka": return babka.global_position
		&"vendor": return Layout.VENDOR_WINDOW
		&"kiosk": return Layout.KIOSK
		&"car": return car.global_position
	return Vector3.INF

## C6 — снимок для HUD. HUD только читает его каждый кадр.
func get_hud_state() -> Dictionary:
	var objective := mission.objective()
	var prompt := ""
	if control_mode == &"on_foot":
		var zone := player.current_interactable()
		if zone:
			prompt = zone.prompt
	var target_id: StringName = objective.get("target_id", &"")
	return {
		"title": objective.get("title", ""),
		"task": objective.get("task", ""),
		"prompt": prompt,
		"target_position": null if target_id == &"" else anchor_position(target_id),
		"babka_marker": mission.babka_marker(),
		"speed_kmh": -1.0,
		"toast": $QuestFlow.toast_text(),
		"complete": mission.state == MissionDirector.COMPLETE,
	}
