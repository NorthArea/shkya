.PHONY: run editor test pack capture fps
run:
	./tools/run.command
editor:
	./tools/run.command --editor
test:
	./tools/run.command --headless --fixed-fps 60 --script tests/smoke_runner.gd
	./tools/run.command --headless --fixed-fps 60 --script tests/mission_director_test.gd
	./tools/run.command --headless --fixed-fps 60 --script tests/grey01_acceptance.gd
	./tools/run.command --headless --fixed-fps 60 --script tests/drive01_acceptance.gd
	./tools/run.command --headless --fixed-fps 60 --script tests/quest01_acceptance.gd
	./tools/run.command --headless --fixed-fps 60 --script tests/polish01_audio.gd
	./tools/run.command --headless --fixed-fps 60 --script tests/polish01_stuck.gd
	./tools/run.command --headless --fixed-fps 60 --script tests/art01_sprite.gd
	./tools/run.command --headless --fixed-fps 120 --script tests/art01_sprite.gd
	mkdir -p builds/checks/qa01 && ./tools/run.command --headless --fixed-fps 60 --script tests/demo_acceptance.gd 2>&1 | tee builds/checks/qa01/make-test.log && grep -q '^DEMO_ACCEPTANCE: [0-9]* checks, 0 failures' builds/checks/qa01/make-test.log
capture:
	./tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tools/capture.gd
pack:
	./tools/run.command --headless --script tools/pack.gd

fps:
	./tools/run.command --resolution 1920x1080 --script tools/fps_probe.gd
