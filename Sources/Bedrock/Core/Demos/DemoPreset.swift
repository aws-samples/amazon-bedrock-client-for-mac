import Foundation

enum DemoCategory: String, Codable, CaseIterable, Sendable {
    case text = "Conversation", reasoning = "Reasoning", documents = "Documents", vision = "Vision"
    case tools = "Local tools", images = "Images", video = "Video", embeddings = "Embeddings"
    var symbol: String {
        switch self {
        case .text: "bubble.left"
        case .reasoning: "brain"
        case .documents: "doc.text"
        case .vision: "eye"
        case .tools: "terminal"
        case .images: "photo"
        case .video: "film"
        case .embeddings: "point.3.filled.connected.trianglepath.dotted"
        }
    }
}

struct DemoPreset: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var summary: String
    var category: DemoCategory
    var prompt: String
    var systemPrompt = ""
    var skillIDs: [String] = []
    var isBuiltIn = false

    var variables: [String] {
        guard let expression = try? NSRegularExpression(pattern: #"\{\{([A-Za-z][A-Za-z0-9_ ]*)\}\}"#) else { return [] }
        let range = NSRange(prompt.startIndex..., in: prompt)
        var result: [String] = []
        for match in expression.matches(in: prompt, range: range) {
            guard let range = Range(match.range(at: 1), in: prompt) else { continue }
            let key = String(prompt[range])
            if !result.contains(key) { result.append(key) }
        }
        return result
    }

    func renderedPrompt(values: [String: String]) throws -> String {
        for variable in variables {
            guard let value = values[variable], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LocalOperationError.invalid("Fill in “\(variable)” before using this demo.")
            }
        }
        guard let expression = try? NSRegularExpression(pattern: #"\{\{([A-Za-z][A-Za-z0-9_ ]*)\}\}"#) else { return prompt }
        var rendered = prompt
        // Replace original matches from the end. User values never become template syntax.
        for match in expression.matches(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)).reversed() {
            guard let keyRange = Range(match.range(at: 1), in: prompt), let range = Range(match.range, in: rendered),
                  let value = values[String(prompt[keyRange])] else { continue }
            rendered.replaceSubrange(range, with: value)
        }
        return rendered
    }

    static let builtIns: [DemoPreset] = [
        .init(id: "explain", title: "Make something clear", summary: "Turn a complex topic into a concise explanation.", category: .text,
              prompt: "Explain {{topic}} with a concrete example, a small diagram if useful, and three practical takeaways. Be precise and keep the answer readable.", isBuiltIn: true),
        .init(id: "reasoning", title: "Think through a decision", summary: "Compare alternatives and inspect model reasoning.", category: .reasoning,
              prompt: "Design an event-driven order processing system on AWS. Compare SQS, EventBridge, and Step Functions for retries, ordering, failure recovery, and operating cost. State assumptions and recommend a design.", isBuiltIn: true),
        .init(id: "document", title: "Ask your documents", summary: "Attach a PDF or document and extract grounded answers.", category: .documents,
              prompt: "Analyze the attached document. Summarize its purpose, extract the most important facts into a table, and list unanswered questions. Cite pages or sections where possible. Do not invent information absent from the document.",
              skillIDs: ["document-analysis"], isBuiltIn: true),
        .init(id: "vision", title: "Look closer", summary: "Attach an image, screenshot, or architecture diagram.", category: .vision,
              prompt: "Describe what you can actually see in the attached image. Identify important details, explain any visible workflow, and suggest three concrete improvements. Clearly distinguish observations from assumptions.", isBuiltIn: true),
        .init(id: "structured", title: "From text to JSON", summary: "Explore structured extraction with a concrete schema.", category: .text,
              prompt: """
              Extract the following support ticket into valid JSON only.
              Schema: {"category":"billing|technical|account","priority":"low|medium|high","summary":"string","action_items":["string"],"missing_information":["string"]}.
              Ticket: We deployed a new version yesterday and checkout now fails for customers in Tokyo. We have 17 reports so far. The payment service returns a timeout after 30 seconds.
              """, isBuiltIn: true),
        .init(id: "project-review", title: "Explore a local folder", summary: "Enter a local path and review its files with built-in tools.", category: .tools,
              prompt: "Inspect the local folder at {{folder path}}. Read its README and key source files, identify the architecture, then report three concrete improvements with file references. Use the available tools to verify your observations. Do not modify files.",
              skillIDs: ["code-review"], isBuiltIn: true),
        .init(id: "image", title: "Create an image", summary: "Generate an image with a compatible model in your AWS region.", category: .images,
              prompt: "A refined editorial photograph of a small architectural model on a warm oak desk, soft morning window light, precise materials, restrained colors, generous negative space, no text.", isBuiltIn: true),
        .init(id: "video", title: "Bring a scene to life", summary: "Generate a video with Luma Ray and your S3 output bucket.", category: .video,
              prompt: "A slow cinematic dolly shot across a miniature coastal town at sunrise, soft golden light, calm water, realistic materials, smooth camera motion.", isBuiltIn: true),
        .init(id: "embeddings", title: "See a text embedding", summary: "Inspect a real embedding vector and its dimensions.", category: .embeddings,
              prompt: "Amazon Bedrock brings foundation models to applications through a unified API.", isBuiltIn: true),
        .init(id: "compare", title: "Compare model responses", summary: "Start independent threads with the same evaluation prompt.", category: .text,
              prompt: "A service processes 600 requests per second. Each request takes 250 ms, and instances should stay below 60% concurrency utilization with a limit of 50 concurrent requests per instance. How many instances are needed? Show the calculation, state assumptions, and explain what changes under a 2× traffic spike.",
              isBuiltIn: true)
    ]
}
