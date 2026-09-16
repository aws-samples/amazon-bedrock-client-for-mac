import AppKit
import SwiftUI

struct MCPToolDefinitionView: View {
    let tool: MCPToolInfo
    @Environment(\.dismiss) private var dismiss
    private var schema: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(tool.tool.inputSchema),
              let text = String(data: data, encoding: .utf8) else { return "Schema unavailable." }
        return text
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tool.toolName).font(.system(size: 20, weight: .semibold))
                    Text(tool.serverName).font(DesignTokens.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                Text(tool.description).font(DesignTokens.body).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 100)
            HStack {
                Text("Input schema").font(DesignTokens.label)
                Spacer()
                Button("Copy schema") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(schema, forType: .string)
                }
            }
            ScrollView([.horizontal, .vertical]) {
                Text(schema).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading).padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.canvas, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(24).frame(width: 620, height: 460)
        .accessibilityIdentifier("mcp.toolDefinition")
    }
}
