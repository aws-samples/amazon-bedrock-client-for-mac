# Dependency refresh — September 17, 2026

Stable releases were checked against the maintainers' release lists. The app's
three retained direct Swift package requirements and their compatible resolution
are updated. `Package.resolved` is now tracked in the Xcode workspace so CI and
local Xcode builds use the same 30-package graph.

| Dependency | Previous checkout | Updated stable release | Primary source |
| --- | --- | --- | --- |
| AWS SDK for Swift | 1.6.97 | 1.7.85 | [AWS release](https://github.com/awslabs/aws-sdk-swift/releases/tag/1.7.85) |
| MCP Swift SDK | 0.12.0 | 0.12.1 | [MCP release](https://github.com/modelcontextprotocol/swift-sdk/releases/tag/0.12.1) |
| MarkdownKit | 1.3.0 | 1.4.1 | [MarkdownKit release](https://github.com/objecthub/swift-markdownkit/releases/tag/1.4.1) |
| Bundled Highlight.js | 11.5.1 | 11.12.0 | [Maintainer CDN distribution](https://github.com/highlightjs/cdn-release/tree/11.12.0/build) |

The unused Vapor product and package reference have been removed. This also
removes AsyncKit, ConsoleKit, MultipartKit, RoutingKit, Swift Metrics and
WebSocketKit from resolution: 37 packages become 30, with every retained version
and revision unchanged. The source-membership validator now rejects directly
linked package products with no app import.

Transitive packages were resolved to compatible stable versions, including
Smithy 0.252.0, AWS CRT 0.64.1, Swift Collections 1.6.0 and Swift Log 1.15.1.
The lockfile records all versions and revisions; a transitive package's next
incompatible major version is not silently substituted.

A further check on September 17 compared all 30 resolved packages with their
maintainers' stable tags. AWS SDK 1.7.85 and its Smithy 0.252.0 dependency were
newly available and are now resolved in the committed graph. The other 28
packages were unchanged: 29 packages are at their latest stable release, and
Swift Crypto is at its latest compatible 4.x release, 4.5.2. Highlight.js and all
six GitHub Actions were checked again and remain at their latest stable tags.

[Swift Crypto 5.0.0](https://github.com/apple/swift-crypto/releases/tag/5.0.0)
was released on September 16. Swift Certificates 1.20.0, reached through NIO SSL,
[requires Crypto below 5.0.0](https://github.com/apple/swift-certificates/blob/1.20.0/Package.swift).
Forcing 5.0.0 would make that dependency graph unsatisfiable. Keep 4.5.2 until the
maintained certificate package accepts 5.x; do not patch vendored manifests or
replace TLS dependencies to bypass the constraint.

| Transitive package | Resolved stable version |
| --- | --- |
| async-http-client | 1.36.1 |
| aws-crt-swift | 0.64.1 |
| eventsource | 1.5.1 |
| smithy-swift | 0.252.0 |
| swift-algorithms | 1.2.1 |
| swift-argument-parser | 1.8.2 |
| swift-asn1 | 1.7.2 |
| swift-async-algorithms | 1.1.5 |
| swift-atomics | 1.3.1 |
| swift-certificates | 1.20.0 |
| swift-collections | 1.6.0 |
| swift-commandlinekit | 1.1.1 |
| swift-configuration | 1.2.0 |
| swift-crypto | 4.5.2 |
| swift-distributed-tracing | 1.4.1 |
| swift-http-structured-headers | 1.7.0 |
| swift-http-types | 1.8.0 |
| swift-log | 1.15.1 |
| swift-nio | 2.102.0 |
| swift-nio-extras | 1.35.1 |
| swift-nio-http2 | 1.46.0 |
| swift-nio-ssl | 2.37.4 |
| swift-nio-transport-services | 1.28.0 |
| swift-numerics | 1.1.1 |
| swift-service-context | 1.3.0 |
| swift-service-lifecycle | 2.12.0 |
| swift-system | 1.8.1 |

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

The validation workflow runs on main and release-branch pushes, pull requests,
and on demand. Release tags call the same workflow before packaging. The pinned
source graph is cached; compiled test and distribution products are built separately.

- Checkout 7.0.1; Upload Artifact 7.0.1; setup-xcode 1.7.0; Cache 6.1.0.
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

The full optimized app and UI suite is documented in
[Development](development.md#regression-suites). Its scheme provides isolated
storage, offline mode and fixture paths. UI tests create fresh data per case.
Normal launches and distribution Release builds retain the production identity
and do not enable the fixture transport.

Executed local and GitHub results belong in [validation-log.md](quality/validation-log.md)
and the [CI scenario map](testing.md). Compilation, executed tests, live AWS
access, and signed/notarized distribution are separate validation stages.
