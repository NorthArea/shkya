.PHONY: run editor test pack capture fps
run:
	./tools/run.command
editor:
	./tools/run.command --editor
# Каждый набор: лог в builds/checks/make-test/, зелёным считается только итоговая строка
# «ИМЯ: N checks, 0 failures» — Godot выходит с кодом 0 и при ошибке разбора скрипта (QA-01, З1).
# $(1) — скрипт в tests/, $(2) — частота кадров, $(3) — метка итоговой строки.
define godot_test
	@mkdir -p builds/checks/make-test
	@./tools/run.command --headless --fixed-fps $(2) --script tests/$(1).gd > builds/checks/make-test/$(1)-$(2).log 2>&1; \
	status=$$?; grep -E '^$(3): [0-9]+ checks, [0-9]+ failures' builds/checks/make-test/$(1)-$(2).log; \
	grep -qE '^$(3): [0-9]+ checks, 0 failures' builds/checks/make-test/$(1)-$(2).log && [ $$status -eq 0 ] || \
	{ echo "FAIL: $(1) ($(2) fps), лог builds/checks/make-test/$(1)-$(2).log"; grep -E 'FAIL|SCRIPT ERROR|Parse Error' builds/checks/make-test/$(1)-$(2).log | head -20; exit 1; }
endef

test:
	$(call godot_test,smoke_runner,60,SMOKE)
	$(call godot_test,mission_director_test,60,MISSION)
	$(call godot_test,grey01_acceptance,60,GREY01)
	$(call godot_test,drive01_acceptance,60,DRIVE01)
	$(call godot_test,quest01_acceptance,60,QUEST01)
	$(call godot_test,polish01_audio,60,AUDIO)
	$(call godot_test,polish01_stuck,60,STUCK)
	$(call godot_test,art01_sprite,60,ART01)
	$(call godot_test,art01_sprite,120,ART01)
	$(call godot_test,demo_acceptance,60,DEMO_ACCEPTANCE)
capture:
	./tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tools/capture.gd
pack:
	./tools/run.command --headless --script tools/pack.gd

fps:
	./tools/run.command --resolution 1920x1080 --script tools/fps_probe.gd
