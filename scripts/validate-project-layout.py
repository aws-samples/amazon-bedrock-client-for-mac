#!/usr/bin/env python3
"""Check Xcode source membership and local paths after repository changes."""
from collections import Counter
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys


def main():
    root = Path(__file__).resolve().parents[1]
    project = root / "Amazon Bedrock Client for Mac.xcodeproj/project.pbxproj"
    graph = json.loads(subprocess.check_output(
        ["plutil", "-convert", "json", "-o", "-", str(project)], text=True
    ))
    objects = graph["objects"]
    parents = {child: key for key, item in objects.items() for child in item.get("children", [])}
    errors = []

    def resolve(identifier):
        item = objects[identifier]
        path = Path(item.get("path", ""))
        tree = item.get("sourceTree", "<group>")
        if tree == "SOURCE_ROOT":
            return root / path
        if tree == "<absolute>":
            return path
        if tree == "<group>":
            parent = resolve(parents[identifier]) if identifier in parents else root
            return parent / path if parent is not None else None
        # SDK frameworks and build products are resolved by Xcode.
        return None

    for identifier, item in objects.items():
        if item.get("isa") in {"PBXFileReference", "XCVersionGroup"}:
            path = resolve(identifier)
            if path is not None and not path.exists():
                errors.append(f"Missing project reference: {path.relative_to(root)}")

    expected = {
        "Amazon Bedrock Client for Mac": set((root / "Sources/Bedrock").rglob("*.swift")),
        "Amazon Bedrock Client for MacTests": set((root / "Tests/Integration").glob("*.swift")),
        "Amazon Bedrock Client for MacUITests": set((root / "Tests/UITests").glob("*.swift")),
    }
    imported_modules = {
        module
        for path in expected["Amazon Bedrock Client for Mac"]
        for module in re.findall(r"^\s*(?:@\w+\s+)?import\s+(\w+)", path.read_text(), re.M)
    }
    # A package product can expose a differently named module. Keep intentional
    # aliases explicit so an unused linked framework cannot quietly return.
    product_modules = {"SystemPackage": "System"}
    counts = {}
    for target in (item for item in objects.values() if item.get("isa") == "PBXNativeTarget"):
        name = target["name"]
        sources = []
        for phase_id in target["buildPhases"]:
            phase = objects[phase_id]
            if phase["isa"] != "PBXSourcesBuildPhase":
                continue
            for build_id in phase.get("files", []):
                reference = objects[build_id].get("fileRef")
                if reference:
                    path = resolve(reference)
                    if path and path.suffix == ".swift":
                        sources.append(path)
        for path, count in Counter(sources).items():
            if count != 1:
                errors.append(f"{name}: {path.name} compiled {count} times")
        if name in expected:
            for path in sorted(expected[name] - set(sources)):
                errors.append(f"{name}: missing source membership for {path.relative_to(root)}")
            for path in sorted(set(sources) - expected[name]):
                errors.append(f"{name}: unexpected source membership for {path.relative_to(root)}")
        counts[name] = len(sources)
        if name == "Amazon Bedrock Client for Mac":
            for dependency in target.get("packageProductDependencies", []):
                product = objects[dependency]["productName"]
                if product_modules.get(product, product) not in imported_modules:
                    errors.append(f"Unused app package product: {product} has no import in the app sources.")

        configurations = objects[target["buildConfigurationList"]]["buildConfigurations"]
        for configuration in configurations:
            settings = objects[configuration].get("buildSettings", {})
            for key, value in settings.items():
                if key.startswith("INFOPLIST_FILE") or key == "CODE_SIGN_ENTITLEMENTS":
                    if value and "$(" not in value and not (root / value).is_file():
                        errors.append(f"{name}: {key} does not exist: {value}")
                if key == "DEVELOPMENT_ASSET_PATHS":
                    for asset in shlex.split(value):
                        if "$(" not in asset and not (root / asset).exists():
                            errors.append(f"{name}: preview assets do not exist: {asset}")
            if name == "Amazon Bedrock Client for Mac":
                if settings.get("BEDROCK_APP_BUNDLE_IDENTIFIER") != "AWS.Amazon-Bedrock-Client-for-Mac":
                    errors.append("The default app bundle identifier changed; existing preferences would be lost.")
                if settings.get("PRODUCT_MODULE_NAME") not in (None, "Amazon_Bedrock_Client_for_Mac"):
                    errors.append("The app module name changed; Core Data and integration imports need migration.")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("Project paths and source membership verified:")
    for name, count in counts.items():
        print(f"  {name}: {count} Swift files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
