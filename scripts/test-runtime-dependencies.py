#!/usr/bin/env python3
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location('runtime_check', pathlib.Path(__file__).with_name('check-runtime-dependencies.py'))
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


def commands(minimum='14.0', library='/usr/lib/libSystem.B.dylib'):
    return f'''Load command 0
    cmd LC_BUILD_VERSION
    platform 1
    minos {minimum}
    sdk 27.0
Load command 1
    cmd LC_LOAD_DYLIB
    name {library} (offset 24)
'''


class RuntimeDependenciesTests(unittest.TestCase):
    def test_new_sdk_with_supported_deployment_target(self):
        check.validate_load_commands(commands(), '14.0')

    def test_rejects_launcher_built_for_developer_os(self):
        with self.assertRaisesRegex(ValueError, 'requires macOS 27.0'):
            check.validate_load_commands(commands('27.0'), '14.0')

    def test_rejects_external_and_unresolved_libraries(self):
        for path in ['/opt/homebrew/lib/libssl.dylib', '/usr/local/lib/libz.dylib',
                     '/Applications/Xcode.app/Contents/Developer/lib.dylib', '@rpath/libMissing.dylib']:
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, 'non-system'):
                check.validate_load_commands(commands(library=path), '14.0')

    def test_weak_libraries_and_all_universal_slices_are_checked(self):
        with self.assertRaises(ValueError):
            check.validate_load_commands(commands() + commands('26.0'), '14.0')
        with self.assertRaises(ValueError):
            check.validate_load_commands(commands(library='/opt/homebrew/missing').replace('LC_LOAD_DYLIB', 'LC_LOAD_WEAK_DYLIB'), '14.0')

    def test_missing_platform_and_minimum_are_rejected(self):
        for text in ['', commands().replace('platform 1', 'platform 2'), commands().replace('minos 14.0', '')]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                check.validate_load_commands(text, '14.0')


if __name__ == '__main__':
    unittest.main()
