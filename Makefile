.PHONY: run editor test pack
run:
	./tools/run.command
editor:
	./tools/run.command --editor
test:
	./tools/run.command --headless --fixed-fps 60 --script tests/smoke_runner.gd
pack:
	./tools/run.command --headless --script tools/pack.gd
