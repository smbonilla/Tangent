#!/usr/bin/env python3
"""Select the Xcode project, generating a local compatibility copy when needed."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Tangent/Tangent.xcodeproj"


def generate(profile, team=None):
    # Newer toolchains use the shared Xcode project directly. A generated copy
    # is needed only for compatibility or a machine-specific signing override.
    if profile == 'modern' and not team:
        return SOURCE
    project = (SOURCE / "project.pbxproj").read_text()
    if profile == "xcode16":
        for expected in ('version = 3.31.3;', 'version = 1.3.0;', 'productName = MLXHuggingFace;', 'productName = HuggingFace;'):
            if expected not in project:
                raise ValueError('Shared package settings changed; update the xcode16 profile before regenerating')
        # Remove the newer macro product and standalone HuggingFace package.
        project = re.sub(r'\t\t5CE7E2A4305D2BBB007DC982 /\* MLXHuggingFace \*/ = \{.*?\n\t\t\};\n', '', project, flags=re.S)
        project = re.sub(r'\t\t5CE7E2C0305D2BBB007DC982 /\* XCRemoteSwiftPackageReference "swift-huggingface" \*/ = \{.*?\n\t\t\};\n', '', project, flags=re.S)
        project = '\n'.join(line for line in project.split('\n') if not any(
            key in line for key in ('5CE7E2B4305D2BBB007DC982', '5CE7E2A4305D2BBB007DC982', '5CE7E2C0305D2BBB007DC982 /* XCRemoteSwiftPackageReference "swift-huggingface" */,')
        ))
        project = project.replace('5CE7E2C0305D2BBB007DC982 /* XCRemoteSwiftPackageReference "swift-huggingface" */', '5CE7E2E0305D2BBB007DC982 /* XCRemoteSwiftPackageReference "swift-transformers" */')
        project = project.replace('HuggingFace', 'Hub')
        project = project.replace('version = 3.31.3;', 'version = 2.29.2;')
        project = project.replace('version = 1.3.0;', 'version = 1.1.0;')
        project = project.replace('SWIFT_VERSION = 5.0;', 'SWIFT_VERSION = 5.0;\n\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) TANGENT_LEGACY_MLX";')
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
    pinned = (ROOT / 'BuildProfiles/xcode16.resolved' if profile == 'xcode16' else SOURCE / 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved')
    shutil.copyfile(pinned, lock)
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('profile', choices=['auto', 'xcode16', 'modern'], nargs='?', default='auto')
    parser.add_argument('--team', default=os.environ.get('TANGENT_DEVELOPMENT_TEAM'))
    parser.add_argument('--resolve', action='store_true', help='Download pinned packages using the selected Xcode')
    parser.add_argument('--open', action='store_true', help='Open the selected project in Xcode')
    args = parser.parse_args()
    version = subprocess.check_output(['xcrun', 'swift', '--version'], text=True, stderr=subprocess.STDOUT)
    match = re.search(r'Swift version (\d+)\.(\d+)', version)
    if not match:
        parser.error('Cannot detect Swift version; select a full Xcode installation with DEVELOPER_DIR')
    swift = tuple(map(int, match.groups()))
    profile = ('xcode16' if swift < (6, 1) else 'modern') if args.profile == 'auto' else args.profile
    if swift < ((6, 0) if profile == 'xcode16' else (6, 1)):
        parser.error(f'{profile} requires a newer Swift compiler than the selected Xcode provides')
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
