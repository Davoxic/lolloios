#!/usr/bin/env python3
"""Configura Info.plist e Podfile per la build unsigned di Lollo su iOS."""
import os
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IOS_DIR = ROOT / "ios"
RUNNER_DIR = IOS_DIR / "Runner"
INFO_PLIST = RUNNER_DIR / "Info.plist"
PODFILE = IOS_DIR / "Podfile"

def configure_info_plist():
    print("Configuro Info.plist per iOS...")
    if not INFO_PLIST.exists():
        print(f"Info.plist non trovato in {INFO_PLIST}")
        return

    with open(INFO_PLIST, "rb") as f:
        plist = plistlib.load(f)

    plist["CFBundleDisplayName"] = "Lollo"
    plist["CFBundleName"] = "lolloios"

    # Background audio playback (musica continua a schermo spento)
    bg_modes = plist.get("UIBackgroundModes", [])
    if "audio" not in bg_modes:
        bg_modes.append("audio")
    plist["UIBackgroundModes"] = bg_modes

    # Condivisione file
    plist["UIFileSharingEnabled"] = True
    plist["LSSupportsOpeningDocumentsInPlace"] = True

    # App Transport Security per stream audio da CDN YouTube
    ats = plist.get("NSAppTransportSecurity", {})
    ats["NSAllowsArbitraryLoads"] = True
    plist["NSAppTransportSecurity"] = ats

    with open(INFO_PLIST, "wb") as f:
        plistlib.dump(plist, f)
    print("Info.plist configurato con successo.")

def configure_podfile():
    print("Configuro Podfile per target iOS 14.0 e no-signing...")
    if not PODFILE.exists():
        print("Podfile non ancora generato.")
        return

    content = PODFILE.read_text(encoding="utf-8")

    lines = []
    for line in content.splitlines():
        if line.strip().startswith("# platform :ios") or line.strip().startswith("platform :ios"):
            lines.append("platform :ios, '14.0'")
        else:
            lines.append(line)
    content = "\n".join(lines)
    if "platform :ios" not in content:
        content = "platform :ios, '14.0'\n" + content

    patch_snippet = """
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
      config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
      config.build_settings['CODE_SIGN_IDENTITY'] = ''
      config.build_settings['EXPANDED_CODE_SIGN_IDENTITY'] = ''
    end"""

    if "flutter_additional_ios_build_settings(target)" in content and patch_snippet not in content:
        content = content.replace(
            "flutter_additional_ios_build_settings(target)",
            "flutter_additional_ios_build_settings(target)\n" + patch_snippet
        )

    PODFILE.write_text(content, encoding="utf-8")
    print("Podfile configurato con successo.")

if __name__ == "__main__":
    configure_info_plist()
    configure_podfile()
    print("Configurazione iOS completata.")
