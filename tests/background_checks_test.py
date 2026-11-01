"""Launch policy without a Godot process: inspect the actual wrapper's engine argv."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BackgroundChecks(unittest.TestCase):
    def launch(self, *arguments, visible=False, launcher="run.command"):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            engine = directory / 'engine'
            engine.write_text('#!/usr/bin/env python3\nimport json,os,sys\nwith open(os.environ["CHECK_ARGV_LOG"],"a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\n')
            engine.chmod(0o755)
            output = directory / 'argv.jsonl'
            env = dict(os.environ, GODOT_BIN=str(engine), CHECK_ARGV_LOG=str(output))
            env.pop('GODOT_VISIBLE_CHECKS', None)
            if visible:
                env['GODOT_VISIBLE_CHECKS'] = '1'
            subprocess.run([str(ROOT / 'tools' / launcher), *arguments], cwd=ROOT, env=env, check=True)
            import json
            return [json.loads(line) for line in output.read_text().splitlines()]

    def test_script_is_headless_and_audio_dummy_by_default(self):
        calls = self.launch('--script', 'tests/smoke_runner.gd')
        self.assertTrue(all('--headless' in args for args in calls))
        self.assertNotIn('--fullscreen', calls[-1])

    def test_windowed_script_still_needs_explicit_visible_override(self):
        self.assertIn('--headless', self.launch('--windowed', '--script', 'tools/capture/capture.gd')[-1])

    def test_explicit_headless_is_preserved(self):
        self.assertIn('--headless', self.launch('--headless', '--script', 'tests/smoke_runner.gd')[-1])

    def test_requested_game_still_opens_fullscreen(self):
        arguments = self.launch()[-1]
        self.assertIn('--fullscreen', arguments)
        self.assertNotIn('--headless', arguments)

    def test_visible_check_is_an_explicit_override(self):
        arguments = self.launch('--script', 'tools/capture/capture.gd', visible=True)[-1]
        self.assertIn('--windowed', arguments)
        self.assertNotIn('--headless', arguments)

    def test_direct_engine_wrapper_also_protects_scripts(self):
        self.assertIn('--headless', self.launch('-s', 'tests/smoke_runner.gd', launcher='godot.sh')[-1])

    def test_driver_options_cannot_override_background_policy(self):
        args = self.launch('--script', 'tests/smoke_runner.gd', '--display-driver', 'macos', '--audio-driver', 'CoreAudio', '--', 'payload')[-1]
        separator = args.index('--')
        self.assertEqual(args[separator - 1], '--headless')
        self.assertEqual(args[separator + 1:], ['payload'])

    def test_script_arguments_do_not_trigger_engine_script_mode(self):
        args = self.launch('--headless', '--', '--script', 'payload', launcher='godot.sh')[-1]
        self.assertEqual(args.count('--headless'), 1)
        self.assertEqual(args[args.index('--') + 1:], ['--script', 'payload'])

    def test_default_make_test_skips_native_tests(self):
        result = subprocess.run(['make', '-n', 'test'], cwd=ROOT, text=True, capture_output=True, check=True)
        self.assertTrue('NOT RUN [requires native renderer]:' in result.stdout, 'make test must skip native-only suites')


if __name__ == '__main__':
    unittest.main()
