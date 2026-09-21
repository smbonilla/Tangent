"""Checks Xcode 27 selection and isolation of local signing overrides."""
import contextlib
import io
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

import environment


class EnvironmentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        source = root / 'Tangent/Tangent.xcodeproj'
        shutil.copytree(environment.SOURCE, source, ignore=shutil.ignore_patterns('xcuserdata'))
        self.original = (source / 'project.pbxproj').read_bytes()
        for name, value in [('ROOT', root), ('SOURCE', source)]:
            patcher = patch.object(environment, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_modern_uses_shared_project(self):
        self.assertEqual(environment.generate('modern'), environment.SOURCE)
        self.assertEqual((environment.SOURCE / 'project.pbxproj').read_bytes(), self.original)

    def test_team_override_is_local(self):
        target = environment.generate('modern', 'ABCDE12345')
        self.assertIn('DEVELOPMENT_TEAM = ABCDE12345;', (target / 'project.pbxproj').read_text())
        self.assertEqual((environment.SOURCE / 'project.pbxproj').read_bytes(), self.original)
        with self.assertRaises(ValueError):
            environment.generate('modern', 'bad;value')

    def test_auto_selects_compiler_profile(self):
        for version, profile in [('6.4', 'modern'), ('6.4.1', 'modern'), ('6.5', 'modern')]:
            with patch('sys.argv', ['environment.py', 'auto']), \
                 patch('subprocess.check_output', return_value=f'Apple Swift version {version}'), \
                 patch.object(environment, 'generate', return_value=Path('project')) as generate, \
                 contextlib.redirect_stdout(io.StringIO()):
                environment.main()
                self.assertEqual(generate.call_args.args[0], profile)

    def test_modern_rejects_old_compiler_before_writing(self):
        with patch('sys.argv', ['environment.py', 'modern']), \
             patch('subprocess.check_output', return_value='Apple Swift version 6.0.3'), \
             patch.object(environment, 'generate') as generate, \
             contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                environment.main()
            generate.assert_not_called()

    def test_open_uses_selected_xcode_and_compatible_project(self):
        target = Path('/tmp/Tangent-modern.xcodeproj')
        with patch('sys.argv', ['environment.py', '--open']), \
             patch('subprocess.check_output', side_effect=[
                 'Apple Swift version 6.4', '/Applications/Xcode.app/Contents/Developer\n'
             ]), \
             patch.object(environment, 'generate', return_value=target), \
             patch('subprocess.run') as run, \
             contextlib.redirect_stdout(io.StringIO()):
            environment.main()
            run.assert_called_once_with([
                'open', '-a', '/Applications/Xcode.app', str(target)
            ], check=True)


if __name__ == '__main__':
    unittest.main()
