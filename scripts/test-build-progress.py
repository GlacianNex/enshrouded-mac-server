#!/usr/bin/env python3
import contextlib
import importlib.util
import io
import json
import pathlib
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('build_progress', pathlib.Path(__file__).resolve().parents[1] / 'Runtime/build-progress.py')
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)


class BuildProgressTests(unittest.TestCase):
    def run_command(self, phase, code):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = monitor.run(phase, [sys.executable, '-u', '-c', code], interval=0.05)
        events = [json.loads(line.split('[ESM_SETUP] ', 1)[1]) for line in output.getvalue().splitlines() if '[ESM_SETUP] ' in line]
        return result, output.getvalue(), events

    def test_real_percent_and_exit_failure_are_preserved(self):
        result, output, events = self.run_command('build', 'print("[ 12%] Building file"); print("[ 9%] Parallel output"); print("compiler failed"); raise SystemExit(7)')
        self.assertEqual(result, 7)
        self.assertIn('compiler failed', output)
        self.assertEqual(max(e.get('percent', 0) for e in events), 12)
        self.assertFalse(events[-1]['running'])
        self.assertNotEqual(events[-1].get('percent'), 100)

    def test_quiet_command_reports_liveness_without_fake_percent(self):
        result, _, events = self.run_command('configure', 'import time; time.sleep(0.22)')
        self.assertEqual(result, 0)
        self.assertGreaterEqual(sum(e['running'] for e in events), 3)
        self.assertTrue(all('percent' not in e for e in events))
        self.assertTrue(all(e['phase'] == 'configure' for e in events))

    def test_split_progress_lines_and_install_do_not_reuse_build_percent(self):
        _, _, events = self.run_command('build', 'import time; print("[ 4", end=""); time.sleep(.1); print("2%] Building"); print("[999%] invalid")')
        self.assertEqual(events[-1]['percent'], 42)
        _, _, events = self.run_command('install', 'print("[100%] Built target")')
        self.assertTrue(all('percent' not in e for e in events))

    def test_cpu_samples_only_include_command_descendants(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            for pid, parent, ticks in [(100, 1, 2), (101, 100, 10), (102, 101, 20), (200, 1, 999)]:
                path = root / str(pid)
                path.mkdir()
                fields = ['S', str(parent)] + ['0'] * 9 + [str(ticks), '0']
                (path / 'stat').write_text(f'{pid} (command with spaces) ' + ' '.join(fields))
            self.assertEqual(monitor.cpu_snapshot(100, root), {100: 2, 101: 10, 102: 20})


if __name__ == '__main__':
    unittest.main()
