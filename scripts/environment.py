#!/usr/bin/env python3
"""Open the Xcode 27 project, with an optional local signing override."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Tangent/Tangent.xcodeproj"


def generate(profile, team=None):
    # Keep machine-specific signing overrides out of the shared project.
    if profile == 'modern' and not team:
        return SOURCE
    project = (SOURCE / "project.pbxproj").read_text()
    if team:
        if not re.fullmatch(r'[A-Z0-9]{10}', team):
            raise ValueError('Apple development team must be a 10-character team ID')
        project = re.sub(r'DEVELOPMENT_TEAM = [^;]+;', f'DEVELOPMENT_TEAM = {team};', project)
    target = ROOT / f'Tangent/Tangent-{profile}.xcodeproj'
    target.mkdir(exist_ok=True)
    (target / 'project.pbxproj').write_text(project)
    workspace = target / 'project.xcworkspace'
    workspace.mkdir(exist_ok=True)
    shutil.copyfile(SOURCE / 'project.xcworkspace/contents.xcworkspacedata', workspace / 'contents.xcworkspacedata')
    lock = workspace / 'xcshareddata/swiftpm/Package.resolved'
    lock.parent.mkdir(parents=True, exist_ok=True)
    pinned = SOURCE / 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    shutil.copyfile(pinned, lock)
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('profile', choices=['auto', 'modern'], nargs='?', default='auto')
    parser.add_argument('--team', default=os.environ.get('TANGENT_DEVELOPMENT_TEAM'))
    parser.add_argument('--resolve', action='store_true', help='Download pinned packages using the selected Xcode')
    parser.add_argument('--open', action='store_true', help='Open the selected project in Xcode')
    args = parser.parse_args()
    version = subprocess.check_output(['xcrun', 'swift', '--version'], text=True, stderr=subprocess.STDOUT)
    match = re.search(r'Swift version (\d+)\.(\d+)', version)
    if not match:
        parser.error('Cannot detect Swift version; select a full Xcode installation with DEVELOPER_DIR')
    swift = tuple(map(int, match.groups()))
    profile = 'modern'
    if swift < (6, 4):
        parser.error('Tangent requires Xcode 27 with the iOS 27 SDK and Swift 6.4 or newer')
    target = generate(profile, args.team)
    print(f'Profile: {profile}\nOpen: {target}', flush=True)
    if args.resolve:
        subprocess.run(['xcodebuild', '-resolvePackageDependencies', '-project', str(target), '-scheme', 'Tangent', '-clonedSourcePackagesDirPath', str(ROOT / f'.build/packages-{profile}'), '-onlyUsePackageVersionsFromResolvedFile'], check=True)
    if args.open:
        developer_dir = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
        xcode = developer_dir.parent.parent
        subprocess.run(['open', '-a', str(xcode), str(target)], check=True)


if __name__ == '__main__':
    main()
