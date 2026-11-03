"""Launch policy without a Godot process: inspect the actual wrapper's engine argv."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BackgroundChecks(unittest.TestCase):
    def launch(self, *arguments, visible=False, audible=False, launcher="run.command", fixed_environment=False, inherited_fixed=None, make_target=None, window_environment=False):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            engine = directory / 'engine'
            engine.write_text('#!/usr/bin/env python3\nimport json,os,sys\nwith open(os.environ["CHECK_ARGV_LOG"],"a") as f: f.write(json.dumps({"argv":sys.argv[1:],"fixed":os.getenv("GODOT_FIXED_FPS_WORKLOAD"),"window":os.getenv("GODOT_WINDOW_MODE_WORKLOAD")})+"\\n")\n')
            engine.chmod(0o755)
            output = directory / 'argv.jsonl'
            env = dict(os.environ, GODOT_BIN=str(engine), CHECK_ARGV_LOG=str(output), GODOT_WINDOW_MODE_WORKLOAD='fullscreen')
            env.pop('GODOT_VISIBLE_CHECKS', None)
            env.pop('GODOT_FIXED_FPS_WORKLOAD', None)
            env.pop('GODOT_ALLOW_AUDIO', None)
            if inherited_fixed is not None:
                env['GODOT_FIXED_FPS_WORKLOAD'] = inherited_fixed
            if visible:
                env['GODOT_VISIBLE_CHECKS'] = '1'
            if audible:
                env['GODOT_ALLOW_AUDIO'] = '1'
            command = ['make', '-o', 'map', make_target] if make_target else [str(ROOT / 'tools' / launcher), *arguments]
            subprocess.run(command, cwd=ROOT, env=env, check=True, stdout=subprocess.DEVNULL)
            import json
            calls = [json.loads(line) for line in output.read_text().splitlines()]
            return [call['window' if window_environment else 'fixed' if fixed_environment else 'argv'] for call in calls]

    def test_consumed_window_mode_is_reported_with_last_engine_option(self):
        for arguments, expected in [(('--fullscreen', '-w'), 'windowed'),
                                    (('--windowed', '-f'), 'fullscreen'),
                                    (('--', '--windowed'), 'unspecified')]:
            with self.subTest(arguments=arguments):
                self.assertEqual(self.launch(*arguments, launcher='godot.sh', window_environment=True), [expected])

    def test_positive_fixed_fps_is_reported_to_the_engine(self):
        for arguments in [('--fixed-fps', '60'), ('--fixed-fps=120',)]:
            with self.subTest(arguments=arguments):
                self.assertEqual(self.launch(*arguments, launcher='godot.sh', fixed_environment=True), ['1'])

    def test_fixed_fps_uses_the_last_engine_option(self):
        self.assertEqual(self.launch('--fixed-fps', '60', '--fixed-fps', '-1', launcher='godot.sh', fixed_environment=True), ['0'])
        self.assertEqual(self.launch('--fixed-fps=-1', '--fixed-fps', '80', launcher='godot.sh', fixed_environment=True), ['1'])

    def test_payload_fixed_fps_and_inherited_marker_do_not_change_workload(self):
        self.assertEqual(self.launch('--', '--fixed-fps', '60', launcher='godot.sh', fixed_environment=True, inherited_fixed='1'), ['0'])

    def test_import_and_runtime_get_their_own_fixed_fps_marker(self):
        self.assertEqual(self.launch('--headless', '--fixed-fps', '60', '--script', 'tests/smoke_runner.gd', fixed_environment=True), ['0', '1'])

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

    def test_game_and_visible_checks_are_silent_by_default(self):
        for launcher in ['godot.sh', 'run.command']:
            for arguments in [(), ('--script', 'tests/smoke_runner.gd')]:
                with self.subTest(launcher=launcher, arguments=arguments):
                    for call in self.launch(*arguments, launcher=launcher, visible=True):
                        self.assertEqual(self.last_audio_driver(call), 'Dummy')

    def test_audio_driver_cannot_override_silence_without_explicit_permission(self):
        args = self.launch('--audio-driver', 'CoreAudio', '--', '--audio-driver', 'payload', visible=True)[-1]
        self.assertEqual(self.last_audio_driver(args), 'Dummy')
        self.assertEqual(args[args.index('--') + 1:], ['--audio-driver', 'payload'])

    def test_explicit_audio_permission_preserves_requested_driver(self):
        args = self.launch('--audio-driver', 'CoreAudio', audible=True, visible=True)[-1]
        self.assertEqual(self.last_audio_driver(args), 'CoreAudio')

    def test_owner_make_run_preserves_audio(self):
        calls = self.launch(make_target='run')
        self.assertNotEqual(self.last_audio_driver(calls[-1]), 'Dummy')
        self.assertIn('--fullscreen', calls[-1])

    def test_agent_make_run_is_silent_even_with_inherited_audio_permission(self):
        calls = self.launch(make_target='run-agent', audible=True)
        self.assertTrue(all(self.last_audio_driver(args) == 'Dummy' for args in calls))
        self.assertIn('--fullscreen', calls[-1])

    def test_fps_target_requests_verified_fullscreen_without_appkit_transition(self):
        args = self.launch(make_target='fps')[-1]
        self.assertIn('--windowed', args)
        self.assertNotIn('--fullscreen', args)
        self.assertIn('--borderless-fullscreen', args[args.index('--') + 1:])
        self.assertEqual(self.last_audio_driver(args), 'Dummy')

    def last_audio_driver(self, args):
        options = args[:args.index('--')] if '--' in args else args
        drivers = [options[i + 1] for i, option in enumerate(options[:-1]) if option == '--audio-driver']
        return drivers[-1] if drivers else None

    def test_visible_check_is_an_explicit_override(self):
        arguments = self.launch('--script', 'tools/capture/capture.gd', visible=True)[-1]
        self.assertIn('--windowed', arguments)
        self.assertNotIn('--headless', arguments)

    def test_direct_engine_wrapper_also_protects_scripts(self):
        self.assertIn('--headless', self.launch('-s', 'tests/smoke_runner.gd', launcher='godot.sh')[-1])

    def test_driver_options_cannot_override_background_policy(self):
        args = self.launch('--script', 'tests/smoke_runner.gd', '--display-driver', 'macos', '--audio-driver', 'CoreAudio', '--', 'payload')[-1]
        separator = args.index('--')
        self.assertIn('--headless', args[:separator])
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
