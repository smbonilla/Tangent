"""Checks that switching profiles preserves source paths and package references."""
import json
import contextlib
import io
from pathlib import Path
import shutil
import subprocess
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
        shutil.copytree(environment.ROOT / 'BuildProfiles', root / 'BuildProfiles')
        self.original = (source / 'project.pbxproj').read_bytes()
        for name, value in [('ROOT', root), ('SOURCE', source)]:
            patcher = patch.object(environment, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def read_project(self, profile):
        target = environment.generate(profile)
        return json.loads(subprocess.check_output([
            'plutil', '-convert', 'json', '-o', '-', str(target / 'project.pbxproj')
        ]))

    def test_legacy_graph_and_shared_project_unchanged(self):
        data = self.read_project('xcode16')
        objects = data['objects']
        products = {o['productName'] for o in objects.values() if o['isa'] == 'XCSwiftPackageProductDependency'}
        self.assertEqual(products, {'MLXLLM', 'MLXVLM', 'MLXLMCommon', 'Hub', 'Tokenizers'})
        packages = {o['repositoryURL']: o['requirement']['version'] for o in objects.values() if o['isa'] == 'XCRemoteSwiftPackageReference'}
        self.assertEqual(set(packages.values()), {'2.29.2', '1.1.0'})
        for obj in objects.values():
            for key in ['productRef', 'package']:
                if key in obj:
                    self.assertIn(obj[key], objects)
            for key in ['packageReferences', 'packageProductDependencies', 'files']:
                for reference in obj.get(key, []):
                    self.assertIn(reference, objects)
            settings = obj.get('buildSettings', {})
            if 'SWIFT_VERSION' in settings:
                self.assertIn('TANGENT_LEGACY_MLX', settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'])
        self.assertEqual((environment.SOURCE / 'project.pbxproj').read_bytes(), self.original)

    def test_modern_round_trip_and_lock_isolation(self):
        modern = environment.generate('modern')
        self.assertEqual(modern, environment.SOURCE)
        legacy = environment.generate('xcode16')
        self.assertEqual((modern / 'project.pbxproj').read_bytes(), self.original)
        lock = 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
        self.assertEqual((modern / lock).read_bytes(), (environment.SOURCE / lock).read_bytes())
        self.assertEqual((legacy / lock).read_bytes(), (environment.ROOT / 'BuildProfiles/xcode16.resolved').read_bytes())
        environment.generate('xcode16')
        self.assertEqual((modern / 'project.pbxproj').read_bytes(), self.original)

    def test_team_override_is_local(self):
        target = environment.generate('xcode16', 'ABCDE12345')
        self.assertIn('DEVELOPMENT_TEAM = ABCDE12345;', (target / 'project.pbxproj').read_text())
        self.assertEqual((environment.SOURCE / 'project.pbxproj').read_bytes(), self.original)
        with self.assertRaises(ValueError):
            environment.generate('modern', 'bad;value')

    def test_auto_selects_compiler_profile(self):
        for version, profile in [('6.0.3', 'xcode16'), ('6.1.2', 'modern'), ('6.2', 'modern')]:
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
        target = Path('/tmp/Tangent-xcode16.xcodeproj')
        with patch('sys.argv', ['environment.py', '--open']), \
             patch('subprocess.check_output', side_effect=[
                 'Apple Swift version 6.0.3', '/Applications/Xcode-16.2.app/Contents/Developer\n'
             ]), \
             patch.object(environment, 'generate', return_value=target), \
             patch('subprocess.run') as run, \
             contextlib.redirect_stdout(io.StringIO()):
            environment.main()
            run.assert_called_once_with([
                'open', '-a', '/Applications/Xcode-16.2.app', str(target)
            ], check=True)


if __name__ == '__main__':
    unittest.main()
