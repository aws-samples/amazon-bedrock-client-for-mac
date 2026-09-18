import Foundation
import XCTest
@testable import BedrockCore

final class MarkdownMathTests: XCTestCase {
    func testInlineAndDisplayEquationsPreserveTheirTeXBeforeMarkdownParsing() {
        let examples: [(String, String, Bool)] = [
            (#"Energy $E = mc^2$."#, "E = mc^2", false),
            (#"Value \(\alpha_i + \beta\)."#, #"\alpha_i + \beta"#, false),
            ("$$\n\\frac{a}{b}\n$$", #"\frac{a}{b}"#, true),
            (#"\[\begin{matrix} a & b \\ c & d \end{matrix}\]"#, #"\begin{matrix} a & b \\ c & d \end{matrix}"#, true)
        ]
        for (source, latex, display) in examples {
            let result = MarkdownMath.prepare(source)
            XCTAssertTrue(result.contains("data-bedrock-math=\"\(Data(latex.utf8).base64EncodedString())\""))
            XCTAssertTrue(result.contains("data-math-display=\"\(display)\""))
        }
    }

    func testCodeEscapedDollarsCurrencyAndLinkDestinationsRemainUnchanged() {
        for source in [
            #"`$x^2$`"#, #"``\(\alpha\)``"#, #"\$5 and \$10"#, "Price: $5.00 or $10.00.",
            "```latex\n$x^2$\n\\[x\\]\n```", "~~~\n$x^2$\n~~~", "    $x^2$\n",
            "> ```latex\n> $x^2$\n> ```", "- ```latex\n  $x^2$\n  ```",
            #"<code>$x^2$</code>"#, #"<span title="$x$">Title</span>"#,
            #"[link](https://example.com/$a$/value)"#
        ] {
            XCTAssertEqual(MarkdownMath.prepare(source), source, source)
        }
    }

    func testUnfinishedMathStaysReadableUntilTheClosingDelimiterArrives() {
        for prefix in [#"Value $x^2"#, #"Value \(\frac{1}{2}"#, "\\[\nx_1 + x_2"] {
            XCTAssertEqual(MarkdownMath.prepare(prefix), prefix)
        }
        XCTAssertTrue(MarkdownMath.prepare("\\[\nx_1 + x_2\n\\]").contains("data-bedrock-math"))
        XCTAssertFalse(MarkdownMath.prepare("$ a $").contains("data-bedrock-math"))
    }

    func testExpressionSizeAndCountAreBoundedAndHTMLCharactersCannotEscape() {
        let large = "$" + String(repeating: "x", count: 8_000) + "$"
        XCTAssertEqual(MarkdownMath.prepare(large), large)
        let repeated = MarkdownMath.prepare(String(repeating: "$x$ ", count: 200))
        XCTAssertEqual(repeated.components(separatedBy: "data-bedrock-math=").count - 1, 128)
        let hostile = MarkdownMath.prepare(#"$</span><script>alert(1)</script>$"#)
        XCTAssertFalse(hostile.contains("<script>"))
        XCTAssertTrue(hostile.contains("data-bedrock-math"))
    }

    func testMalformedDelimiterLookaheadDoesNotGrowQuadratically() {
        for source in [String(repeating: "$x\\", count: 80_000),
                       String(repeating: "<code>$x$</code> ", count: 15_000),
                       String(repeating: "<span $x", count: 20_000)] {
            let started = Date()
            _ = MarkdownMath.prepare(source)
            XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        }
    }
}
