.PHONY: run editor test capture fps map
run: map
	./tools/run.command
editor: map
	./tools/run.command --editor
map:
	python3 tools/generate_arena_map.py
# Каждый набор: лог в builds/checks/make-test/, зелёным считается только итоговая строка
# «ИМЯ: N checks, 0 failures» — Godot выходит с кодом 0 и при ошибке разбора скрипта (QA-01, З1).
# $(1) — скрипт в tests/, $(2) — частота кадров, $(3) — метка итоговой строки.
define godot_test
	@mkdir -p builds/checks/make-test
	@./tools/run.command --headless --fixed-fps $(2) --script tests/$(1).gd > builds/checks/make-test/$(1)-$(2).log 2>&1; \
	status=$$?; grep -E '^$(3): [0-9]+ checks, [0-9]+ failures' builds/checks/make-test/$(1)-$(2).log; \
	grep -qE '^$(3): [0-9]+ checks, 0 failures' builds/checks/make-test/$(1)-$(2).log && \
	! grep -qE '^SCRIPT ERROR:|^ERROR: Condition "p_elem->_root" is true' builds/checks/make-test/$(1)-$(2).log && [ $$status -eq 0 ] || \
	{ echo "FAIL: $(1) ($(2) fps), лог builds/checks/make-test/$(1)-$(2).log"; grep -E 'FAIL|SCRIPT ERROR|Parse Error|p_elem->_root' builds/checks/make-test/$(1)-$(2).log | head -20; exit 1; }
endef

test: map
	$(call godot_test,smoke_runner,60,SMOKE)
	$(call godot_test,intro_test,60,INTRO)
	$(call godot_test,mission_director_test,60,MISSION)
	$(call godot_test,story02_test,60,STORY02)
	$(call godot_test,grey01_acceptance,60,GREY01)
	$(call godot_test,play04_motion_test,60,PLAY04_MOTION)
	$(call godot_test,play04_wall_slide_test,60,PLAY04_WALL_SLIDE)
	$(call godot_test,play04_car_test,60,PLAY04_CAR)
	$(call godot_test,drive01_acceptance,60,DRIVE01)
	$(call godot_test,quest01_acceptance,60,QUEST01)
	$(call godot_test,polish01_audio,60,AUDIO)
	$(call godot_test,polish01_stuck,60,STUCK)
	$(call godot_test,art01_sprite,60,ART01)
	$(call godot_test,art01_sprite,120,ART01)
	$(call godot_test,art09_test,60,ART09)
	$(call godot_test,demo_acceptance,60,DEMO_ACCEPTANCE)
	$(call godot_test,stealth_test,60,STEALTH)
	$(call godot_test,traffic_test,60,TRAFFIC)
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
	$(call godot_test,drive02_snow,60,DRIVE02)
	$(call godot_test,pad01_test,60,PAD01)
	$(call godot_test,text01_test,60,TEXT01)
	$(call godot_test,life01_test,60,LIFE01)
	$(call godot_test,polish03a_test,60,POLISH03A)
	$(call godot_test,city03_test,60,CITY03)
	$(call godot_test,city03_bags_test,60,CITY03_BAGS)
	$(call godot_test,dog01_test,60,DOG01)
	$(call godot_test,phone01_test,60,PHONE01)
	$(call godot_test,arena03_tracks_test,60,ARENA03_TRACKS)
	$(call godot_test,arena03_life_test,60,ARENA03_LIFE)
	$(call godot_test,arena03_audio_test,60,ARENA03_AUDIO)
	$(call godot_test,arena03_activity_test,60,ARENA03_ACTIVITY)
	$(call godot_test,road01_test,60,ROAD01)
	$(call godot_test,cross01_test,60,CROSS01)
	$(call godot_test,arena03_city_life_test,60,ARENA03_CITY_LIFE)
	$(call godot_test,arena03_exit_test,60,ARENA03_EXIT)
capture: map
	./tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tools/capture/capture.gd

fps: map
	./tools/run.command --resolution 1920x1080 --script tools/fps_probe.gd
