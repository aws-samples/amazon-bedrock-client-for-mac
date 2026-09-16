# Contributing

Bedrock for Mac is a native Swift client with direct AWS inference and local storage. Contributions should keep the interface focused, preserve existing conversations and preferences, and make common interactions fast.

## Report a problem

Search existing issues first. Include the app version, macOS version, Mac architecture, reproduction steps, expected behavior, and what actually happened. For a model error, include the model ID and region. For a performance regression, describe the conversation size, attachments, build configuration, and the interaction that stalls.

A short recording or a minimal synthetic conversation helps. Remove credentials, private prompts, account identifiers, and unrelated desktop content before sharing diagnostics.

## Develop a change

1. Start from the latest `main` and keep the change focused.
2. Follow the [source layout and build instructions](docs/DEVELOPMENT.md).
3. Add a regression that exercises the reported behavior. Use isolated local data and the existing protocol/MCP fixtures where appropriate.
4. Run the relevant suites and describe the results in your pull request.

After adding or moving files:

```sh
python3 scripts/register-workbench-sources.py
python3 scripts/validate-project-layout.py
python3 scripts/validate-documentation.py
```

The local core suite is a quick starting point:

```sh
python3 scripts/validate-local-core.py --output .build/validation/core
```

Rendering, clipboard, app integration, and native UI test commands are in [Development](docs/DEVELOPMENT.md#regression-suites). CI runs the optimized app and preserves its test results, screenshots, and local protocol request evidence. See [CI coverage](docs/CI_COVERAGE.md) for the scenario map.

## Review expectations

Explain the user-visible problem, the resulting behavior, and the checks you ran. Include both Light and Dark screenshots for visual changes. Performance changes should identify the workload, build configuration, and comparable measurements; a successful build is not a responsiveness test.

Keep expensive parsing, image preparation, and repeated file work off the main actor. Preserve bounded history rendering, cancellation, exact attachment bytes, and atomic storage. A migration must retain existing data and explicit preferences. Tests must not use a developer's production data or silently invoke paid services.

Do not commit signing material or credentials. Signing and notarization run only in the release workflow after validation succeeds.

## Security reports

Report suspected vulnerabilities through the [AWS vulnerability reporting page](https://aws.amazon.com/security/vulnerability-reporting/), rather than a public issue.

## Conduct and license

This project follows the [Amazon Open Source Code of Conduct](CODE_OF_CONDUCT.md). Contributions use the repository's [MIT-0 license](LICENSE).
