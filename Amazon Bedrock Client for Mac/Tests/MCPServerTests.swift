//
//  MCPServerTests.swift
//  Amazon Bedrock Client for Mac
//
//  Tests for verifying MCP server connectivity and OAuth metadata discovery
//

import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

/// Test data for MCP servers
struct MCPServerTestData {
    let name: String
    let category: String
    let url: String
    let authType: AuthType
    let maintainer: String
    
    enum AuthType: String {
        case oauth21 = "OAuth2.1"
        case oauth21Protected = "OAuth2.1 🔐"
        case apiKey = "API Key"
        case open = "Open"
    }
}

final class MCPServerTests: XCTestCase {
    
    // MARK: - Test Data
    
    static let oauthServers: [MCPServerTestData] = [
        MCPServerTestData(name: "Asana", category: "Project Management", url: "https://mcp.asana.com/sse", authType: .oauth21, maintainer: "Asana"),
        MCPServerTestData(name: "Audioscrape", category: "RAG-as-a-Service", url: "https://mcp.audioscrape.com", authType: .oauth21, maintainer: "Audioscrape"),
        MCPServerTestData(name: "Atlassian", category: "Software Development", url: "https://mcp.atlassian.com/v1/sse", authType: .oauth21Protected, maintainer: "Atlassian"),
        MCPServerTestData(name: "Box", category: "Document Management", url: "https://mcp.box.com", authType: .oauth21Protected, maintainer: "Box"),
        MCPServerTestData(name: "Buildkite", category: "Software Development", url: "https://mcp.buildkite.com/mcp", authType: .oauth21, maintainer: "Buildkite"),
        MCPServerTestData(name: "Canva", category: "Design", url: "https://mcp.canva.com/mcp", authType: .oauth21, maintainer: "Canva"),
        MCPServerTestData(name: "Carbon Voice", category: "Productivity", url: "https://mcp.carbonvoice.app", authType: .oauth21, maintainer: "Carbon Voice"),
        MCPServerTestData(name: "Close CRM", category: "CRM", url: "https://mcp.close.com/mcp", authType: .oauth21Protected, maintainer: "Close"),
        MCPServerTestData(name: "Cloudflare Workers", category: "Software Development", url: "https://bindings.mcp.cloudflare.com/sse", authType: .oauth21, maintainer: "Cloudflare"),
        MCPServerTestData(name: "Cloudflare Observability", category: "Observability", url: "https://observability.mcp.cloudflare.com/sse", authType: .oauth21, maintainer: "Cloudflare"),
        MCPServerTestData(name: "Cloudinary", category: "Asset Management", url: "https://asset-management.mcp.cloudinary.com/sse", authType: .oauth21, maintainer: "Cloudinary"),
        MCPServerTestData(name: "Dialer", category: "Outbound Phone Calls", url: "https://getdialer.app/sse", authType: .oauth21, maintainer: "Dialer"),
        MCPServerTestData(name: "EAN-Search.org", category: "Product Data", url: "https://www.ean-search.org/mcp", authType: .oauth21, maintainer: "EAN-Search.org"),
        MCPServerTestData(name: "Egnyte", category: "Document Management", url: "https://mcp-server.egnyte.com/sse", authType: .oauth21, maintainer: "Egnyte"),
        MCPServerTestData(name: "Firefly", category: "Productivity", url: "https://api.fireflies.ai/mcp", authType: .oauth21, maintainer: "Firefly"),
        MCPServerTestData(name: "GitHub", category: "Software Development", url: "https://api.githubcopilot.com/mcp", authType: .oauth21Protected, maintainer: "GitHub"),
        MCPServerTestData(name: "Globalping", category: "Software Development", url: "https://mcp.globalping.dev/sse", authType: .oauth21, maintainer: "Globalping"),
        MCPServerTestData(name: "Grafbase", category: "Software Development", url: "https://api.grafbase.com/mcp", authType: .oauth21, maintainer: "Grafbase"),
        MCPServerTestData(name: "Hive Intelligence", category: "Crypto", url: "https://hiveintelligence.xyz/mcp", authType: .oauth21, maintainer: "Hive Intelligence"),
        MCPServerTestData(name: "Instant", category: "Software Development", url: "https://mcp.instantdb.com/mcp", authType: .oauth21, maintainer: "Instant"),
        MCPServerTestData(name: "Intercom", category: "Customer Support", url: "https://mcp.intercom.com/sse", authType: .oauth21, maintainer: "Intercom"),
        MCPServerTestData(name: "Indeed", category: "Job Board", url: "https://mcp.indeed.com/claude/mcp", authType: .oauth21, maintainer: "Indeed"),
        MCPServerTestData(name: "Invideo", category: "Video Platform", url: "https://mcp.invideo.io/sse", authType: .oauth21, maintainer: "Invideo"),
        MCPServerTestData(name: "Jam", category: "Software Development", url: "https://mcp.jam.dev/mcp", authType: .oauth21, maintainer: "Jam.dev"),
        MCPServerTestData(name: "Kollektiv", category: "Documentation", url: "https://mcp.thekollektiv.ai/sse", authType: .oauth21, maintainer: "Kollektiv"),
        MCPServerTestData(name: "Linear", category: "Project Management", url: "https://mcp.linear.app/sse", authType: .oauth21, maintainer: "Linear"),
        MCPServerTestData(name: "Listenetic", category: "Productivity", url: "https://mcp.listenetic.com/v1/mcp", authType: .oauth21, maintainer: "Listenetic"),
        MCPServerTestData(name: "Meta Ads by Pipeboard", category: "Advertising", url: "https://mcp.pipeboard.co/meta-ads-mcp", authType: .oauth21, maintainer: "Pipeboard"),
        MCPServerTestData(name: "MorningStar", category: "Data Analysis", url: "https://mcp.morningstar.com/mcp", authType: .oauth21, maintainer: "MorningStar"),
        MCPServerTestData(name: "monday.com", category: "Productivity", url: "https://mcp.monday.com/sse", authType: .oauth21, maintainer: "monday MCP"),
        MCPServerTestData(name: "mypromind.com", category: "Learning", url: "https://www.mypromind.com/interface/mcp", authType: .oauth21, maintainer: "mypromind MCP"),
        MCPServerTestData(name: "Neon", category: "Software Development", url: "https://mcp.neon.tech/sse", authType: .oauth21, maintainer: "Neon"),
        MCPServerTestData(name: "Netlify", category: "Software Development", url: "https://netlify-mcp.netlify.app/mcp", authType: .oauth21, maintainer: "Netlify"),
        MCPServerTestData(name: "Notion", category: "Project Management", url: "https://mcp.notion.com/sse", authType: .oauth21, maintainer: "Notion"),
        MCPServerTestData(name: "Octagon", category: "Market Intelligence", url: "https://mcp.octagonagents.com/mcp", authType: .oauth21, maintainer: "Octagon"),
        MCPServerTestData(name: "OneContext", category: "RAG-as-a-Service", url: "https://rag-mcp-2.whatsmcp.workers.dev/sse", authType: .oauth21, maintainer: "OneContext"),
        MCPServerTestData(name: "PayPal", category: "Payments", url: "https://mcp.paypal.com/sse", authType: .oauth21, maintainer: "PayPal"),
        MCPServerTestData(name: "Parallel Task MCP", category: "Web Research", url: "https://task-mcp.parallel.ai/mcp", authType: .oauth21, maintainer: "Parallel Web Systems"),
        MCPServerTestData(name: "Parallel Search MCP", category: "Web Search", url: "https://search-mcp.parallel.ai/mcp", authType: .oauth21, maintainer: "Parallel Web Systems"),
        MCPServerTestData(name: "Plaid", category: "Payments", url: "https://api.dashboard.plaid.com/mcp/sse", authType: .oauth21Protected, maintainer: "Plaid"),
        MCPServerTestData(name: "Prisma Postgres", category: "Database", url: "https://mcp.prisma.io/mcp", authType: .oauth21, maintainer: "Prisma Postgres"),
        MCPServerTestData(name: "Ramp", category: "Payments", url: "https://ramp-mcp-remote.ramp.com/mcp", authType: .oauth21, maintainer: "Ramp"),
        MCPServerTestData(name: "Rube", category: "Other", url: "https://rube.app/mcp", authType: .oauth21, maintainer: "Composio"),
        MCPServerTestData(name: "Scorecard", category: "AI Evaluation", url: "https://scorecard-mcp.dare-d5b.workers.dev/sse", authType: .oauth21, maintainer: "Scorecard"),
        MCPServerTestData(name: "Sentry", category: "Software Development", url: "https://mcp.sentry.dev/sse", authType: .oauth21, maintainer: "Sentry"),
        MCPServerTestData(name: "Stack Overflow", category: "Software Development", url: "https://mcp.stackoverflow.com", authType: .oauth21, maintainer: "StackOverflow"),
        MCPServerTestData(name: "Stripe", category: "Payments", url: "https://mcp.stripe.com/", authType: .oauth21, maintainer: "Stripe"),
        MCPServerTestData(name: "Stytch", category: "Authentication", url: "http://mcp.stytch.dev/mcp", authType: .oauth21, maintainer: "Stytch"),
        MCPServerTestData(name: "Supabase", category: "Database", url: "https://mcp.supabase.com/mcp", authType: .oauth21, maintainer: "Supabase"),
        MCPServerTestData(name: "Square", category: "Payments", url: "https://mcp.squareup.com/sse", authType: .oauth21, maintainer: "Square"),
        MCPServerTestData(name: "ThoughtSpot", category: "Data Analytics", url: "https://agent.thoughtspot.app/mcp", authType: .oauth21, maintainer: "ThoughtSpot"),
        MCPServerTestData(name: "Turkish Airlines", category: "Airlines", url: "https://mcp.turkishtechlab.com/mcp", authType: .oauth21, maintainer: "Turkish Technology"),
        MCPServerTestData(name: "Vercel", category: "Software Development", url: "https://mcp.vercel.com/", authType: .oauth21, maintainer: "Vercel"),
        MCPServerTestData(name: "VibeMarketing", category: "Social Media", url: "https://vibemarketing.ninja/mcp", authType: .oauth21, maintainer: "VibeMarketing"),
        MCPServerTestData(name: "Webflow", category: "CMS", url: "https://mcp.webflow.com/sse", authType: .oauth21, maintainer: "Webflow"),
        MCPServerTestData(name: "Wix", category: "CMS", url: "https://mcp.wix.com/sse", authType: .oauth21, maintainer: "Wix"),
        MCPServerTestData(name: "Simplescraper", category: "Web Scraping", url: "https://mcp.simplescraper.io/mcp", authType: .oauth21, maintainer: "Simplescraper"),
        MCPServerTestData(name: "WayStation", category: "Productivity", url: "https://waystation.ai/mcp", authType: .oauth21, maintainer: "WayStation"),
        MCPServerTestData(name: "Zenable", category: "Security", url: "https://mcp.zenable.app/", authType: .oauth21, maintainer: "Zenable"),
        MCPServerTestData(name: "Zine", category: "Memory", url: "https://www.zine.ai/mcp", authType: .oauth21, maintainer: "Zine"),
    ]
    
    static let openServers: [MCPServerTestData] = [
        MCPServerTestData(name: "AWS Knowledge", category: "Software Development", url: "https://knowledge-mcp.global.api.aws", authType: .open, maintainer: "AWS"),
        MCPServerTestData(name: "Cloudflare Docs", category: "Documentation", url: "https://docs.mcp.cloudflare.com/sse", authType: .open, maintainer: "Cloudflare"),
        MCPServerTestData(name: "Astro Docs", category: "Documentation", url: "https://mcp.docs.astro.build/mcp", authType: .open, maintainer: "Astro"),
        MCPServerTestData(name: "Context Awesome", category: "Specialised Dataset", url: "https://www.context-awesome.com/api/mcp", authType: .open, maintainer: "Context Awesome"),
        MCPServerTestData(name: "DeepWiki", category: "RAG-as-a-Service", url: "https://mcp.deepwiki.com/sse", authType: .open, maintainer: "Devin"),
        MCPServerTestData(name: "Exa Search", category: "Search", url: "https://mcp.exa.ai/mcp", authType: .open, maintainer: "Exa"),
        MCPServerTestData(name: "Hugging Face", category: "Software Development", url: "https://hf.co/mcp", authType: .open, maintainer: "Hugging Face"),
        MCPServerTestData(name: "Semgrep", category: "Software Development", url: "https://mcp.semgrep.ai/sse", authType: .open, maintainer: "Semgrep"),
        MCPServerTestData(name: "Remote MCP", category: "MCP Directory", url: "https://mcp.remote-mcp.com", authType: .open, maintainer: "Remote MCP"),
        MCPServerTestData(name: "OpenMesh", category: "Service Discovery", url: "https://api.openmesh.dev/mcp", authType: .open, maintainer: "OpenMesh"),
        MCPServerTestData(name: "OpenZeppelin Cairo", category: "Software Development", url: "https://mcp.openzeppelin.com/contracts/cairo/mcp", authType: .open, maintainer: "OpenZeppelin"),
        MCPServerTestData(name: "OpenZeppelin Solidity", category: "Software Development", url: "https://mcp.openzeppelin.com/contracts/solidity/mcp", authType: .open, maintainer: "OpenZeppelin"),
        MCPServerTestData(name: "OpenZeppelin Stellar", category: "Software Development", url: "https://mcp.openzeppelin.com/contracts/stellar/mcp", authType: .open, maintainer: "OpenZeppelin"),
        MCPServerTestData(name: "OpenZeppelin Stylus", category: "Software Development", url: "https://mcp.openzeppelin.com/contracts/stylus/mcp", authType: .open, maintainer: "OpenZeppelin"),
        MCPServerTestData(name: "LLM Text", category: "Data Analysis", url: "https://mcp.llmtxt.dev/sse", authType: .open, maintainer: "LLM Text"),
        MCPServerTestData(name: "GitMCP", category: "Software Development", url: "https://gitmcp.io/docs", authType: .open, maintainer: "GitMCP"),
        MCPServerTestData(name: "Find-A-Domain", category: "Productivity", url: "https://api.findadomain.dev/mcp", authType: .open, maintainer: "Find-A-Domain"),
        MCPServerTestData(name: "Peek.com", category: "Other", url: "https://mcp.peek.com", authType: .open, maintainer: "Peek.com"),
        MCPServerTestData(name: "Manifold", category: "Forecasting", url: "https://api.manifold.markets/v0/mcp", authType: .open, maintainer: "Manifold"),
        MCPServerTestData(name: "Javadocs", category: "Software Development", url: "https://www.javadocs.dev/mcp", authType: .open, maintainer: "Javadocs.dev"),
        MCPServerTestData(name: "Ferryhopper", category: "Other", url: "https://mcp.ferryhopper.com/mcp", authType: .open, maintainer: "Ferryhopper"),
        MCPServerTestData(name: "zip1.io", category: "Link shortener", url: "https://zip1.io/mcp", authType: .open, maintainer: "zip1.io"),
    ]
    
    static let apiKeyServers: [MCPServerTestData] = [
        MCPServerTestData(name: "Cortex", category: "Internal Developer Portal", url: "https://mcp.cortex.io/mcp", authType: .apiKey, maintainer: "Cortex"),
        MCPServerTestData(name: "Close", category: "CRM", url: "https://mcp.close.com/mcp", authType: .apiKey, maintainer: "Close"),
        MCPServerTestData(name: "HubSpot", category: "CRM", url: "https://app.hubspot.com/mcp/v1/http", authType: .apiKey, maintainer: "HubSpot"),
        MCPServerTestData(name: "Needle", category: "RAG-as-a-service", url: "https://mcp.needle-ai.com/mcp", authType: .apiKey, maintainer: "Needle"),
        MCPServerTestData(name: "Zapier", category: "Automation", url: "https://mcp.zapier.com/api/mcp/mcp", authType: .apiKey, maintainer: "Zapier"),
        MCPServerTestData(name: "Apify", category: "Web Data Extraction", url: "https://mcp.apify.com", authType: .apiKey, maintainer: "Apify"),
        MCPServerTestData(name: "Dappier", category: "RAG-as-a-Service", url: "https://mcp.dappier.com/mcp", authType: .apiKey, maintainer: "Dappier"),
        MCPServerTestData(name: "Mercado Libre", category: "E-Commerce", url: "https://mcp.mercadolibre.com/mcp", authType: .apiKey, maintainer: "Mercado Libre"),
        MCPServerTestData(name: "Mercado Pago", category: "Payments", url: "https://mcp.mercadopago.com/mcp", authType: .apiKey, maintainer: "Mercado Pago"),
        MCPServerTestData(name: "Short.io", category: "Link shortener", url: "https://ai-assistant.short.io/mcp", authType: .apiKey, maintainer: "Short.io"),
        MCPServerTestData(name: "Telnyx", category: "Communication", url: "https://api.telnyx.com/v2/mcp", authType: .apiKey, maintainer: "Telnyx"),
        MCPServerTestData(name: "Dodo Payments", category: "Payments", url: "https://mcp.dodopayments.com/sse", authType: .apiKey, maintainer: "Dodo Payments"),
        MCPServerTestData(name: "Polar Signals", category: "Software Development", url: "https://api.polarsignals.com/api/mcp/", authType: .apiKey, maintainer: "Polar Signals"),
        MCPServerTestData(name: "CustomGPT.ai", category: "RAG-as-a-service", url: "https://mcp.customgpt.ai", authType: .apiKey, maintainer: "CustomGPT.ai"),
    ]
    
    // MARK: - Test Results Storage
    
    struct TestResult {
        let server: MCPServerTestData
        let reachable: Bool
        let responseCode: Int?
        let hasOAuthMetadata: Bool?
        let oauthEndpoints: OAuthEndpoints?
        let error: String?
        let latencyMs: Int
        
        struct OAuthEndpoints {
            let authorizationEndpoint: String?
            let tokenEndpoint: String?
        }
    }
    
    // MARK: - Tests
    
    /// Test connectivity to all OAuth servers
    func testOAuthServerConnectivity() async throws {
        let results = await testServers(Self.oauthServers)
        printResults(results, title: "OAuth Servers")
        
        let reachableCount = results.filter { $0.reachable }.count
        XCTAssertGreaterThan(reachableCount, 0, "At least some OAuth servers should be reachable")
    }
    
    /// Test connectivity to all Open servers
    func testOpenServerConnectivity() async throws {
        let results = await testServers(Self.openServers)
        printResults(results, title: "Open Servers")
        
        let reachableCount = results.filter { $0.reachable }.count
        XCTAssertGreaterThan(reachableCount, 0, "At least some Open servers should be reachable")
    }
    
    /// Test connectivity to all API Key servers
    func testAPIKeyServerConnectivity() async throws {
        let results = await testServers(Self.apiKeyServers)
        printResults(results, title: "API Key Servers")
        
        let reachableCount = results.filter { $0.reachable }.count
        XCTAssertGreaterThan(reachableCount, 0, "At least some API Key servers should be reachable")
    }
    
    /// Test OAuth metadata discovery for OAuth servers
    func testOAuthMetadataDiscovery() async throws {
        var successCount = 0
        var failureCount = 0
        
        print("\n" + String(repeating: "=", count: 80))
        print("OAuth Metadata Discovery Test")
        print(String(repeating: "=", count: 80))
        
        for server in Self.oauthServers {
            guard let url = URL(string: server.url) else { continue }
            
            let result = await testOAuthMetadata(for: url, serverName: server.name)
            
            if result.hasOAuthMetadata == true {
                successCount += 1
                print("✅ \(server.name): OAuth metadata found")
                if let endpoints = result.oauthEndpoints {
                    print("   Auth: \(endpoints.authorizationEndpoint ?? "N/A")")
                    print("   Token: \(endpoints.tokenEndpoint ?? "N/A")")
                }
            } else {
                failureCount += 1
                print("❌ \(server.name): \(result.error ?? "No OAuth metadata")")
            }
        }
        
        print("\n" + String(repeating: "-", count: 80))
        print("Summary: \(successCount) success, \(failureCount) failed")
        print(String(repeating: "=", count: 80))
    }

    
    // MARK: - Helper Methods
    
    private func testServers(_ servers: [MCPServerTestData]) async -> [TestResult] {
        var results: [TestResult] = []
        
        await withTaskGroup(of: TestResult.self) { group in
            for server in servers {
                group.addTask {
                    await self.testServer(server)
                }
            }
            
            for await result in group {
                results.append(result)
            }
        }
        
        return results.sorted { $0.server.name < $1.server.name }
    }
    
    private func testServer(_ server: MCPServerTestData) async -> TestResult {
        guard let url = URL(string: server.url) else {
            return TestResult(
                server: server,
                reachable: false,
                responseCode: nil,
                hasOAuthMetadata: nil,
                oauthEndpoints: nil,
                error: "Invalid URL",
                latencyMs: 0
            )
        }
        
        let startTime = Date()
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 10
            
            let (_, response) = try await URLSession.shared.data(for: request)
            let latency = Int(Date().timeIntervalSince(startTime) * 1000)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return TestResult(
                    server: server,
                    reachable: false,
                    responseCode: nil,
                    hasOAuthMetadata: nil,
                    oauthEndpoints: nil,
                    error: "Invalid response",
                    latencyMs: latency
                )
            }
            
            // 401 is expected for OAuth servers, 200/405 for others
            let isReachable = [200, 401, 403, 405, 406].contains(httpResponse.statusCode)
            
            return TestResult(
                server: server,
                reachable: isReachable,
                responseCode: httpResponse.statusCode,
                hasOAuthMetadata: nil,
                oauthEndpoints: nil,
                error: isReachable ? nil : "HTTP \(httpResponse.statusCode)",
                latencyMs: latency
            )
        } catch {
            let latency = Int(Date().timeIntervalSince(startTime) * 1000)
            return TestResult(
                server: server,
                reachable: false,
                responseCode: nil,
                hasOAuthMetadata: nil,
                oauthEndpoints: nil,
                error: error.localizedDescription,
                latencyMs: latency
            )
        }
    }
    
    private func testOAuthMetadata(for serverURL: URL, serverName: String) async -> TestResult {
        let startTime = Date()
        
        // Try multiple OAuth metadata URL patterns
        let metadataURLs = buildMetadataURLs(for: serverURL)
        
        for metadataURL in metadataURLs {
            do {
                var request = URLRequest(url: metadataURL)
                request.httpMethod = "GET"
                request.timeoutInterval = 10
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    continue
                }
                
                // Try to decode OAuth protected resource metadata
                if let resourceMetadata = try? JSONDecoder().decode(OAuthProtectedResourceMetadata.self, from: data),
                   let authServerURL = resourceMetadata.authorizationServers?.first,
                   let authURL = URL(string: authServerURL) {
                    
                    // Fetch auth server metadata
                    let authMetadata = try await fetchAuthServerMetadata(authServerURL: authURL)
                    let latency = Int(Date().timeIntervalSince(startTime) * 1000)
                    
                    return TestResult(
                        server: MCPServerTestData(name: serverName, category: "", url: serverURL.absoluteString, authType: .oauth21, maintainer: ""),
                        reachable: true,
                        responseCode: 200,
                        hasOAuthMetadata: true,
                        oauthEndpoints: TestResult.OAuthEndpoints(
                            authorizationEndpoint: authMetadata.authorizationEndpoint,
                            tokenEndpoint: authMetadata.tokenEndpoint
                        ),
                        error: nil,
                        latencyMs: latency
                    )
                }
            } catch {
                continue
            }
        }
        
        let latency = Int(Date().timeIntervalSince(startTime) * 1000)
        return TestResult(
            server: MCPServerTestData(name: serverName, category: "", url: serverURL.absoluteString, authType: .oauth21, maintainer: ""),
            reachable: true,
            responseCode: nil,
            hasOAuthMetadata: false,
            oauthEndpoints: nil,
            error: "OAuth metadata not found",
            latencyMs: latency
        )
    }
    
    private func buildMetadataURLs(for serverURL: URL) -> [URL] {
        var urls: [URL] = []
        let pathComponents = serverURL.pathComponents.filter { $0 != "/" }
        let serviceName = pathComponents.first ?? ""
        
        // Pattern 1: Root level without service name (Box style)
        if let rootURL = URL(string: "\(serverURL.scheme ?? "https")://\(serverURL.host ?? "")/.well-known/oauth-protected-resource") {
            urls.append(rootURL)
        }
        
        // Pattern 2: With service name in path
        if !serviceName.isEmpty,
           let serviceURL = URL(string: "\(serverURL.scheme ?? "https")://\(serverURL.host ?? "")/.well-known/oauth-protected-resource/\(serviceName)") {
            urls.append(serviceURL)
        }
        
        // Pattern 3: Path-based
        urls.append(serverURL.deletingLastPathComponent()
            .appendingPathComponent(".well-known/oauth-protected-resource"))
        
        return urls
    }
    
    private func fetchAuthServerMetadata(authServerURL: URL) async throws -> OAuthMetadata {
        let metadataURL = authServerURL.appendingPathComponent(".well-known/oauth-authorization-server")
        
        var request = URLRequest(url: metadataURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            // Fallback: construct endpoints
            let baseURL = authServerURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return OAuthMetadata(
                issuer: baseURL,
                authorizationEndpoint: "\(baseURL)/oauth/authorize",
                tokenEndpoint: "\(baseURL)/oauth/token",
                scopesSupported: nil,
                responseTypesSupported: ["code"],
                codeChallengeMethodsSupported: ["S256"]
            )
        }
        
        return try JSONDecoder().decode(OAuthMetadata.self, from: data)
    }
    
    private func printResults(_ results: [TestResult], title: String) {
        print("\n" + String(repeating: "=", count: 80))
        print(title)
        print(String(repeating: "=", count: 80))
        
        let reachable = results.filter { $0.reachable }
        let unreachable = results.filter { !$0.reachable }
        
        print("\n✅ Reachable (\(reachable.count)):")
        for result in reachable {
            let latency = result.latencyMs > 0 ? " (\(result.latencyMs)ms)" : ""
            let code = result.responseCode.map { " [HTTP \($0)]" } ?? ""
            print("  • \(result.server.name)\(code)\(latency)")
        }
        
        if !unreachable.isEmpty {
            print("\n❌ Unreachable (\(unreachable.count)):")
            for result in unreachable {
                print("  • \(result.server.name): \(result.error ?? "Unknown error")")
            }
        }
        
        print("\n" + String(repeating: "-", count: 80))
        print("Summary: \(reachable.count)/\(results.count) servers reachable")
        print(String(repeating: "=", count: 80))
    }
}

// MARK: - Local OAuth Models for Testing

private struct OAuthProtectedResourceMetadata: Codable {
    let resource: String?
    let authorizationServers: [String]?
    let scopesSupported: [String]?
    
    enum CodingKeys: String, CodingKey {
        case resource
        case authorizationServers = "authorization_servers"
        case scopesSupported = "scopes_supported"
    }
}

private struct OAuthMetadata: Codable {
    let issuer: String?
    let authorizationEndpoint: String?
    let tokenEndpoint: String?
    let scopesSupported: [String]?
    let responseTypesSupported: [String]?
    let codeChallengeMethodsSupported: [String]?
    
    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case scopesSupported = "scopes_supported"
        case responseTypesSupported = "response_types_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
    }
}
