# Dependency refresh — September 16, 2026

Stable releases were checked against the maintainers' release lists. The app's
four direct Swift package requirements and the complete compatible resolution
are updated. `Package.resolved` is now tracked in the Xcode workspace so CI and
local Xcode builds use the same 37-package graph.

| Dependency | Previous checkout | Updated stable release | Primary source |
| --- | --- | --- | --- |
| AWS SDK for Swift | 1.6.97 | 1.7.84 | [AWS release](https://github.com/awslabs/aws-sdk-swift/releases/tag/1.7.84) |
| MCP Swift SDK | 0.12.0 | 0.12.1 | [MCP release](https://github.com/modelcontextprotocol/swift-sdk/releases/tag/0.12.1) |
| MarkdownKit | 1.3.0 | 1.4.1 | [MarkdownKit release](https://github.com/objecthub/swift-markdownkit/releases/tag/1.4.1) |
| Vapor | 4.119.0 | 4.122.1 | [Vapor release](https://github.com/vapor/vapor/releases/tag/4.122.1) |
| Bundled Highlight.js | 11.5.1 | 11.12.0 | [Maintainer CDN distribution](https://github.com/highlightjs/cdn-release/tree/11.12.0/build) |

Vapor 5.0.0-beta.1 is excluded because it is a preview. Transitive packages are
resolved to the newest versions compatible with this stable graph, including
Smithy 0.251.0, AWS CRT 0.64.1, Swift Collections 1.6.0 and Swift Log 1.15.1.
The lockfile records all versions and revisions; a transitive package's next
incompatible major version is not silently substituted.

The bundled highlighter remains offline. Its source, license and checksums are
recorded in `Sources/Bedrock/Resources/Highlight/README.md`.

## Integration changes

- Use the new AWS `BedrockClientConfig`, `BedrockRuntimeClientConfig`,
  `TranscribeStreamingClientConfig` and `S3ClientConfig` APIs.
- Implement Swift Log's `log(event:)` entry point.
- Encode MCP content using the SDK's Codable wire representation. Text,
  annotations, resource bodies, resource links and structured results survive;
  image/audio base64 is not encoded a second time.
- Track and cancel MCP requests explicitly. Timeout, immediate cancellation,
  reconnect, duplicate tool names, literal process arguments and stderr
  backpressure have local process integration tests.
- Use one native text view for selection across Markdown paragraphs, bullets,
  tables and code. Keep the bounded WebKit renderer for long/HTML responses.

## CI

The validation workflow runs on pull requests and on demand. Release builds
depend on this workflow completing successfully.

- Checkout 7.0.1; Upload Artifact 7.0.1; setup-xcode 1.7.0.
- Release workflow: import-codesign-certs 7.0.0; action-gh-release 3.0.3.
- Core filesystem, parser, migration, queue, attachment and skill tests.
- Production native Markdown/clipboard tests.
- App integration tests with a real local MCP subprocess.
- Native UI tests for settings, themes, shortcuts, model switching, skills and
  pasted attachment recovery.
- Test-only offline mode, isolated storage, separate CI app identity, fixed
  package versions, saved test logs and an xcresult bundle.

Public MCP endpoint diagnostics are opt-in with `BEDROCK_LIVE_NETWORK_TESTS=1`.
They are not part of the deterministic suite and do not establish support for
every remote MCP service.

## Local validation

Core:

```sh
python3 scripts/validate-local-core.py --output /tmp/bedrock-core-tests
```

Native renderer and clipboard, using the resolved MarkdownKit checkout:

```sh
python3 scripts/validate-markdown-rendering.py \
  --markdown-package /path/to/swift-markdownkit \
  --output /tmp/bedrock-rendering-tests
```

Both scripts accept `--developer-dir` and `--xcode`. They fail if no XCTest
bundle or no executed tests are found.

Full app and UI suite, with an installed, licensed Xcode:

```sh
xcodebuild test \
  -project "Amazon Bedrock Client for Mac.xcodeproj" \
  -scheme "Amazon Bedrock Client for Mac" \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath /tmp/BedrockTestsDerived \
  -resultBundlePath /tmp/BedrockTests.xcresult \
  -disableAutomaticPackageResolution \
  -parallel-testing-enabled NO \
  BEDROCK_APP_BUNDLE_IDENTIFIER=AWS.Amazon-Bedrock-Client-for-Mac.UITestHost \
  CODE_SIGNING_ALLOWED=NO
```

The test action explicitly supplies isolated storage, offline mode and fixture
paths to the hosted test process. UI tests additionally create a fresh data
directory for each case. Normal app launch and Release builds retain the
original bundle identifier and behavior.

Executed results are recorded in `PILOT_VALIDATION.md`. GitHub CI has not been
triggered from this uncommitted workspace. The installed Xcode currently awaits
license acceptance; local validation uses the CLT compiler and Xcode's XCTest
runner, plus actual app interaction. It does not establish macOS 27 runtime
compatibility or signed Release/notarization success.
