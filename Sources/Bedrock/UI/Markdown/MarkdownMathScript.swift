import Foundation

enum MarkdownMathAssets {
    /// Loaded once, and installed only in WebViews that actually contain math.
    static let javascript: String = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "katex.min", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return source.replacingOccurrences(of: "</script", with: "<\\/script") + "\n;void 0;"
    }()

    static let css = """
    .bedrock-math { font-size: 1.06em; color: inherit; }
    .bedrock-math math { font-family: "STIX Two Math", "STIXGeneral", math; color: inherit; }
    .bedrock-math.math-display {
        display: block; margin: 8px 0; padding: 6px 0;
        max-width: 100%; overflow-x: auto; overflow-y: hidden;
    }
    .bedrock-math.math-display math { margin: 0 auto; }
    .bedrock-math[data-math-error] {
        font-family: "SF Mono", Menlo, monospace; font-size: .92em;
        white-space: pre-wrap; overflow-wrap: anywhere;
    }
    """
}

enum MarkdownMathScript {
    static let source = #"""
    const bedrockMathCache = new Map();
    let bedrockMathCacheBytes = 0;
    window.bedrockRenderMath = fragment => {
        if (typeof katex === 'undefined') return;
        let count = 0;
        for (const element of fragment.querySelectorAll('span[data-bedrock-math]')) {
            if (++count > 128) break;
            try {
                const bytes = Uint8Array.from(atob(element.dataset.bedrockMath), character => character.charCodeAt(0));
                if (bytes.length > 4096) continue;
                const source = new TextDecoder('utf-8', {fatal: true}).decode(bytes);
                const display = element.dataset.mathDisplay === 'true';
                const key = `${display}|${source}`;
                let rendered = bedrockMathCache.get(key);
                if (rendered === undefined) {
                    try {
                        rendered = katex.renderToString(source, {
                            displayMode: display, output: 'mathml', throwOnError: true,
                            trust: false, strict: 'ignore', maxExpand: 256, maxSize: 20
                        });
                    } catch { rendered = null; }
                    const cost = (rendered?.length || source.length) * 2;
                    while (bedrockMathCache.size &&
                           (bedrockMathCache.size >= 128 || bedrockMathCacheBytes + cost > 2 * 1024 * 1024)) {
                        const oldest = bedrockMathCache.keys().next().value;
                        const value = bedrockMathCache.get(oldest);
                        bedrockMathCacheBytes -= (value?.length || oldest.slice(oldest.indexOf('|') + 1).length) * 2;
                        bedrockMathCache.delete(oldest);
                    }
                    if (cost <= 2 * 1024 * 1024) {
                        bedrockMathCache.set(key, rendered);
                        bedrockMathCacheBytes += cost;
                    }
                }
                if (rendered === null) {
                    element.textContent = source;
                    element.dataset.mathError = 'true';
                } else {
                    // Only trusted, bounded KaTeX output enters this branch,
                    // after all model-supplied HTML has been sanitized.
                    element.innerHTML = rendered;
                }
            } catch { /* Preserve the readable fallback for invalid input. */ }
        }
    };
    """#
}
