.PHONY: run editor test test-headless test-native capture fps map
# Visible GPU checks are opt-in; ordinary test invocations never open a window.
HEADLESS_ONLY ?= 1
run: map
	./tools/run.command
editor: map
	./tools/run.command --editor
map:
	python3 tools/generate_arena_map.py
# Каждый набор: лог в builds/checks/make-test/, зелёным считается только итоговая строка
# «ИМЯ: N checks, 0 failures» — Godot выходит с кодом 0 и при ошибке разбора скрипта (QA-01, З1).
# $(1) — скрипт, $(2) — частота, $(3) — итоговая метка, $(4) — аргументы,
# $(5) — render для настоящих MultiMesh и камеры после native physics;
# $(6) — realtime: без fixed-fps для естественных AudioServer finished callbacks.
define run_godot_test
	@mkdir -p builds/checks/make-test
	@./tools/run.command $(if $(5),,--headless) $(if $(6),,--fixed-fps $(2)) --script tests/$(1).gd $(4) > builds/checks/make-test/$(1)-$(2).log 2>&1; \
	status=$$?; grep -E '^$(3): [0-9]+ checks, [0-9]+ failures' builds/checks/make-test/$(1)-$(2).log; \
	grep -qE '^$(3): [0-9]+ checks, 0 failures' builds/checks/make-test/$(1)-$(2).log && \
	! grep -qE '^SCRIPT ERROR:|^ERROR: CameraRig:|^ERROR: Condition "p_elem->_root" is true' builds/checks/make-test/$(1)-$(2).log && [ $$status -eq 0 ] || \
	{ echo "FAIL: $(1) ($(2) fps), лог builds/checks/make-test/$(1)-$(2).log"; grep -E 'FAIL|SCRIPT ERROR|Parse Error|CameraRig:|p_elem->_root' builds/checks/make-test/$(1)-$(2).log | head -20; exit 1; }
endef

# Безоконный набор явно пропускает проверки, которым нужен настоящий рендер.
define godot_test
$(if $(and $(filter 1,$(HEADLESS_ONLY)),$(5)),@echo "NOT RUN [requires native renderer]: $(1)",$(call run_godot_test,$(1),$(2),$(3),$(4),$(5),$(6)))
endef

test-native: HEADLESS_ONLY=0
test-native: export GODOT_VISIBLE_CHECKS=1
test-native: test

test-headless: HEADLESS_ONLY=1
test-headless: test

test: map
	@python3 tests/background_checks_test.py
	$(call godot_test,smoke_runner,60,SMOKE)
	$(call godot_test,resolution01_test,60,RESOLUTION01)
	$(call godot_test,resolution01_ui_test,60,RESOLUTION01_UI)
	$(call godot_test,screen01_test,60,SCREEN01,--windowed --resolution 960x600,render)
	$(call godot_test,intro_test,60,INTRO)
	$(call godot_test,mission_director_test,60,MISSION)
	$(call godot_test,story02_test,60,STORY02)
	$(call godot_test,grey01_acceptance,60,GREY01)
	$(call godot_test,play04_motion_test,60,PLAY04_MOTION)
	$(call godot_test,play04_response_test,60,PLAY04_RESPONSE)
	$(call godot_test,play04_route_response_test,60,PLAY04_ROUTE_RESPONSE)
	$(call godot_test,play04_sprint_test,60,PLAY04_SPRINT)
	$(call godot_test,play04_wall_slide_test,60,PLAY04_WALL_SLIDE)
	$(call godot_test,play04_car_test,60,PLAY04_CAR)
	$(call godot_test,drive01_acceptance,60,DRIVE01)
	$(call godot_test,vehicle_impact_test,60,VEHICLE_IMPACT)
	$(call godot_test,vehicle_impact_acceptance,60,VEHICLE_INDEPENDENT)
	$(call godot_test,driver_ai_test,60,DRIVER_AI)
	$(call godot_test,driver_ai_acceptance,60,DRIVER_ACCEPTANCE)
	$(call godot_test,driver01_recovery_test,60,DRIVER01_RECOVERY)
	$(call godot_test,driver01_impact_composition_test,60,DRIVER_IMPACT_COMPOSITION)
	$(call godot_test,quest01_acceptance,60,QUEST01)
	$(call godot_test,polish01_audio,60,AUDIO)
	$(call godot_test,radio_music_test,60,RADIO01,--max-fps 60 --resolution 1920x1080,,realtime)
	$(call godot_test,radio02_news_test,60,RADIO02,--max-fps 60,,realtime)
	$(call godot_test,radio02_interleaving_test,60,RADIO02_INTERLEAVE,--max-fps 60,,realtime)
	$(call godot_test,radio_playlist_interleaving_test,60,RADIO_PLAYLIST_INTERLEAVE,--max-fps 60,,realtime)
	$(call godot_test,polish01_stuck,60,STUCK)
	$(call godot_test,art01_sprite,60,ART01)
	$(call godot_test,art01_sprite,120,ART01)
	$(call godot_test,art09_test,60,ART09)
	$(call godot_test,ip01_runtime_test,60,IP01_INDEPENDENT_RUNTIME)
	$(call godot_test,ip01_legacy_likeness_test,60,IP01_LIKENESS)
	$(call godot_test,ip01_hero_details_test,60,IP01_HERO_DETAILS)
	$(call godot_test,ip01_civilian_geometry_test,60,IP01_CIVILIAN_GEOMETRY)
	$(call godot_test,ip01_civilian_runtime_test,60,IP01_CIVILIAN_RUNTIME)
	$(call godot_test,ip01_xray_test,60,IP01_INDEPENDENT_XRAY,,render)
	$(call godot_test,demo_acceptance,60,DEMO_ACCEPTANCE)
	$(call godot_test,stealth_test,60,STEALTH)
	$(call godot_test,traffic_test,60,TRAFFIC)
	$(call godot_test,car01_cabin_clearance_test,60,CAR01_CABIN)
	$(call godot_test,trolley01_driver_clearance_test,60,TROLLEY01_DRIVER)
	$(call godot_test,light01_occlusion_test,60,LIGHT01_OCCLUSION_CONFIG)
	$(call godot_test,car02_family_test,60,CAR02_INDEPENDENT)
	$(call godot_test,car02_gazelle_test,60,CAR02_GAZELLE)
	$(call godot_test,car02_gazelle_runtime_test,60,CAR02_GAZELLE_RUNTIME)
	$(call godot_test,car02_gsum_test,60,CAR02_GSUM)
	$(call godot_test,car02_fleet_runtime_test,60,CAR02_FLEET_RUNTIME)
	$(call godot_test,car02_composition_acceptance,60,CAR02_COMPOSITION)
	$(call godot_test,residents_test,60,RESIDENTS)
	$(call godot_test,ambient_test,60,AMBIENT)
	$(call godot_test,hide_core_test,60,HIDE_CORE)
	$(call godot_test,hide_box_test,60,HIDE_BOX)
	$(call godot_test,hide_snow_test,60,HIDE_SNOW)
	$(call godot_test,hide_barrel_test,60,HIDE_BARREL)
	$(call godot_test,coins_test,60,COINS)
	$(call godot_test,punch_test,60,PUNCH)
	$(call godot_test,punch02_view_test,60,PUNCH02_VIEW)
	$(call godot_test,knock_test,60,KNOCK)
	$(call godot_test,break_test,60,BREAK)
	$(call godot_test,break03_acceptance,60,BREAK03_ACCEPTANCE,,render)
	$(call godot_test,break03_stealth,60,STEALTH)
	$(call godot_test,drive02_snow,60,DRIVE02)
	$(call godot_test,pad01_test,60,PAD01)
	$(call godot_test,pad02_symmetry_test,60,PAD02)
	$(call godot_test,pad03_phone_camera_test,60,PAD03)
	$(call godot_test,phone02_navigation_test,60,PHONE02)
	$(call godot_test,achievements_test,60,ACHIEVE-01)
	$(call godot_test,text01_test,60,TEXT01)
	$(call godot_test,life01_test,60,LIFE01)
	$(call godot_test,polish03_camera_safety,60,CAMERA_SAFETY,--max-fps 60 --resolution 1920x1080,render)
	$(call godot_test,city03_test,60,CITY03)
	$(call godot_test,city03_bags_test,60,CITY03_BAGS)
	$(call godot_test,dog01_test,60,DOG01)
	$(call godot_test,phone01_test,60,PHONE01)
	$(call godot_test,arena03_tracks_test,60,ARENA03_TRACKS)
	$(call godot_test,arena03_life_test,60,ARENA03_LIFE)
	$(call godot_test,arena03_audio_test,60,ARENA03_AUDIO)
	$(call godot_test,arena03_activity_test,60,ARENA03_ACTIVITY)
	$(call godot_test,road01_test,60,ROAD01)
	$(call godot_test,world02_edges_test,60,WORLD02)
	$(call godot_test,apartment01_test,60,APARTMENT01)
	$(call godot_test,cross01_test,60,CROSS01)
	$(call godot_test,arena03_city_life_test,60,ARENA03_CITY_LIFE,-- break)
	$(call godot_test,arena03_exit_test,60,ARENA03_EXIT)
capture: map
	./tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tools/capture/capture.gd

fps: map
	./tools/run.command --resolution 1920x1080 --script tools/fps_probe.gd
