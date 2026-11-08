#!/usr/bin/env python3
# MARK: Swiftgram Mod — make fake codesigning profiles for a bundle id other than
# ph.telegra.Telegraph, so the mod installs next to Telegram instead of replacing it.
#
# Reads every build-system/fake-codesigning/profiles/<Name>.mobileprovision (the
# ph.telegra.Telegraph set), replaces the bundle id everywhere in its plist (application
# identifier, app group, iCloud and keychain ids), gives it a fresh UUID and re-signs it
# with the repo's fake SelfSigned identity. Writes Mod<Name>.mobileprovision next to the
# originals: Make.py picks profiles by "<team>.<bundle id>", so both sets can coexist.
#
# Usage: build-system/sg-mod/retarget-fake-profiles.py app.swiftgram.mod
# Needs OpenSSL 3 (uses -legacy to read the p12, whose password is empty).
import os
import plistlib
import subprocess
import sys
import tempfile
import uuid

SOURCE_BUNDLE_ID = 'ph.telegra.Telegraph'

root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'fake-codesigning'))
profiles_dir = os.path.join(root, 'profiles')
p12_path = os.path.join(root, 'certs', 'SelfSigned.p12')


def run(args, input_data=None):
    return subprocess.run(args, input=input_data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout


def replace_bundle_id(value, bundle_id):
    if isinstance(value, str):
        return value.replace(SOURCE_BUNDLE_ID, bundle_id)
    if isinstance(value, list):
        return [replace_bundle_id(item, bundle_id) for item in value]
    if isinstance(value, dict):
        return {key: replace_bundle_id(item, bundle_id) for key, item in value.items()}
    return value


def main():
    if len(sys.argv) != 2:
        sys.exit('usage: retarget-fake-profiles.py <bundle id>')
    bundle_id = sys.argv[1]
    with tempfile.TemporaryDirectory() as temp_dir:
        key_path = os.path.join(temp_dir, 'key.pem')
        cert_path = os.path.join(temp_dir, 'cert.pem')
        run(['openssl', 'pkcs12', '-in', p12_path, '-passin', 'pass:', '-legacy', '-nodes', '-nocerts', '-out', key_path])
        run(['openssl', 'pkcs12', '-in', p12_path, '-passin', 'pass:', '-legacy', '-nokeys', '-out', cert_path])

        for file_name in sorted(os.listdir(profiles_dir)):
            if not file_name.endswith('.mobileprovision') or file_name.startswith('Mod'):
                continue
            source_path = os.path.join(profiles_dir, file_name)
            profile = plistlib.loads(run(['openssl', 'cms', '-verify', '-noverify', '-inform', 'DER', '-in', source_path]))
            if SOURCE_BUNDLE_ID not in profile['Entitlements']['application-identifier']:
                print('skip {}: not a {} profile'.format(file_name, SOURCE_BUNDLE_ID))
                continue

            updated = {}
            for key, value in profile.items():
                if key in ('DeveloperCertificates', 'DER-Encoded-Profile'):
                    updated[key] = value
                else:
                    updated[key] = replace_bundle_id(value, bundle_id)
            updated['UUID'] = str(uuid.uuid4())

            plist_path = os.path.join(temp_dir, file_name + '.plist')
            with open(plist_path, 'wb') as f:
                plistlib.dump(updated, f, fmt=plistlib.FMT_XML)
            output_path = os.path.join(profiles_dir, 'Mod' + file_name)
            run(['openssl', 'cms', '-sign', '-binary', '-nodetach', '-outform', 'DER', '-signer', cert_path, '-inkey', key_path, '-in', plist_path, '-out', output_path])
            print('{} -> {} ({})'.format(file_name, os.path.basename(output_path), updated['Entitlements']['application-identifier']))


if __name__ == '__main__':
    main()
