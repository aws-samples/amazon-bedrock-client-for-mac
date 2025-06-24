//
//  SearchEngine.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2025/06/24.
//

import Foundation
import SwiftUI

// MARK: - Extensions

extension NSRange: Equatable {
    public static func == (lhs: NSRange, rhs: NSRange) -> Bool {
        return lhs.location == rhs.location && lhs.length == rhs.length
    }
}

// MARK: - Search Result Types

struct SearchMatch: Equatable {
    let messageIndex: Int
    let ranges: [NSRange]
    let snippet: String
    let score: Double
    
    static func == (lhs: SearchMatch, rhs: SearchMatch) -> Bool {
        return lhs.messageIndex == rhs.messageIndex &&
               lhs.ranges == rhs.ranges &&
               lhs.snippet == rhs.snippet &&
               lhs.score == rhs.score
    }
}

struct SearchResult: Equatable {
    let matches: [SearchMatch]
    let totalMatches: Int
    let searchTime: TimeInterval
    
    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        return lhs.matches == rhs.matches &&
               lhs.totalMatches == rhs.totalMatches &&
               lhs.searchTime == rhs.searchTime
    }
}

// MARK: - Advanced Search Engine

class SearchEngine: ObservableObject {
    private var searchCache: [String: SearchResult] = [:]
    private let maxCacheSize = 50
    private var lastSearchQuery = ""
    
    // MARK: - Public Search Methods
    
    func search(query: String, in messages: [MessageData]) -> SearchResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Return empty result for empty query
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SearchResult(matches: [], totalMatches: 0, searchTime: 0)
        }
        
        let normalizedQuery = normalizeQuery(query)
        
        // Check cache first
        if let cachedResult = searchCache[normalizedQuery] {
            return cachedResult
        }
        
        let matches = performSearch(query: normalizedQuery, messages: messages)
        let searchTime = CFAbsoluteTimeGetCurrent() - startTime
        
        let result = SearchResult(
            matches: matches,
            totalMatches: matches.reduce(0) { $0 + $1.ranges.count },
            searchTime: searchTime
        )
        
        // Cache the result
        cacheResult(query: normalizedQuery, result: result)
        
        return result
    }
    
    // MARK: - Private Search Implementation
    
    private func performSearch(query: String, messages: [MessageData]) -> [SearchMatch] {
        let searchTerms = tokenizeQuery(query)
        var matches: [SearchMatch] = []
        
        for (index, message) in messages.enumerated() {
            let messageText = message.text
            let ranges = findMatches(searchTerms: searchTerms, in: messageText)
            
            if !ranges.isEmpty {
                let score = calculateRelevanceScore(
                    ranges: ranges,
                    messageText: messageText,
                    searchTerms: searchTerms
                )
                
                let snippet = generateSnippet(
                    text: messageText,
                    ranges: ranges,
                    maxLength: 150
                )
                
                matches.append(SearchMatch(
                    messageIndex: index,
                    ranges: ranges,
                    snippet: snippet,
                    score: score
                ))
            }
        }
        
        // Sort by message index (chronological order) instead of relevance score
        return matches.sorted { $0.messageIndex < $1.messageIndex }
    }
    
    private func findMatches(searchTerms: [String], in text: String) -> [NSRange] {
        var allRanges: [NSRange] = []
        let lowercaseText = text.lowercased()
        
        for term in searchTerms {
            let ranges = findAllOccurrences(of: term, in: lowercaseText, originalText: text)
            allRanges.append(contentsOf: ranges)
        }
        
        // Merge overlapping ranges and sort
        return mergeOverlappingRanges(allRanges).sorted { $0.location < $1.location }
    }
    
    private func findAllOccurrences(of term: String, in lowercaseText: String, originalText: String) -> [NSRange] {
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: lowercaseText.count)
        
        while searchRange.location < lowercaseText.count {
            let foundRange = (lowercaseText as NSString).range(
                of: term,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            )
            
            if foundRange.location == NSNotFound {
                break
            }
            
            ranges.append(foundRange)
            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = lowercaseText.count - searchRange.location
        }
        
        return ranges
    }
    
    private func mergeOverlappingRanges(_ ranges: [NSRange]) -> [NSRange] {
        guard !ranges.isEmpty else { return [] }
        
        let sortedRanges = ranges.sorted { $0.location < $1.location }
        var mergedRanges: [NSRange] = []
        var currentRange = sortedRanges[0]
        
        for range in sortedRanges.dropFirst() {
            if range.location <= currentRange.location + currentRange.length {
                // Overlapping ranges - merge them
                let endLocation = max(
                    currentRange.location + currentRange.length,
                    range.location + range.length
                )
                currentRange = NSRange(
                    location: currentRange.location,
                    length: endLocation - currentRange.location
                )
            } else {
                // Non-overlapping range - add current and start new
                mergedRanges.append(currentRange)
                currentRange = range
            }
        }
        
        mergedRanges.append(currentRange)
        return mergedRanges
    }
    
    private func calculateRelevanceScore(ranges: [NSRange], messageText: String, searchTerms: [String]) -> Double {
        let textLength = Double(messageText.count)
        let matchLength = Double(ranges.reduce(0) { $0 + $1.length })
        let matchCount = Double(ranges.count)
        
        // Base score: percentage of text matched
        let coverageScore = matchLength / textLength
        
        // Bonus for multiple matches
        let frequencyScore = min(matchCount / 10.0, 1.0)
        
        // Bonus for exact phrase matches
        let exactMatchBonus = searchTerms.contains { term in
            messageText.lowercased().contains(term.lowercased())
        } ? 0.2 : 0.0
        
        // Penalty for very long messages (prefer concise matches)
        let lengthPenalty = textLength > 1000 ? 0.1 : 0.0
        
        return coverageScore + frequencyScore + exactMatchBonus - lengthPenalty
    }
    
    private func generateSnippet(text: String, ranges: [NSRange], maxLength: Int) -> String {
        guard let firstRange = ranges.first else { return "" }
        
        let snippetStart = max(0, firstRange.location - maxLength / 4)
        let snippetEnd = min(text.count, firstRange.location + firstRange.length + maxLength / 2)
        
        let startIndex = text.index(text.startIndex, offsetBy: snippetStart)
        let endIndex = text.index(text.startIndex, offsetBy: snippetEnd)
        
        var snippet = String(text[startIndex..<endIndex])
        
        // Add ellipsis if truncated
        if snippetStart > 0 {
            snippet = "..." + snippet
        }
        if snippetEnd < text.count {
            snippet = snippet + "..."
        }
        
        return snippet.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Query Processing
    
    private func normalizeQuery(_ query: String) -> String {
        return query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    private func tokenizeQuery(_ query: String) -> [String] {
        // Split by whitespace and filter out empty strings
        let tokens = query.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        // For now, return the full query as a single term for phrase matching
        // and individual words for partial matching
        var searchTerms = [query] // Full phrase
        searchTerms.append(contentsOf: tokens) // Individual words
        
        return Array(Set(searchTerms)) // Remove duplicates
    }
    
    // MARK: - Cache Management
    
    private func cacheResult(query: String, result: SearchResult) {
        // Implement LRU cache
        if searchCache.count >= maxCacheSize {
            // Remove oldest entry (simple implementation)
            if let firstKey = searchCache.keys.first {
                searchCache.removeValue(forKey: firstKey)
            }
        }
        
        searchCache[query] = result
    }
    
    func clearCache() {
        searchCache.removeAll()
    }
}

// MARK: - Text Highlighting Utilities

struct HighlightedText {
    let attributedString: AttributedString
    let ranges: [NSRange]
}

class TextHighlighter {
    static func createHighlightedText(
        text: String,
        searchRanges: [NSRange],
        fontSize: CGFloat,
        highlightColor: Color = .yellow,
        textColor: Color = .primary,
        currentMatchIndex: Int = -1
    ) -> HighlightedText {
        
        if #available(macOS 12.0, *) {
            var attributed = AttributedString(text)
            
            // Apply base styling
            attributed.font = .system(size: fontSize)
            attributed.foregroundColor = textColor
            
            // Apply highlights - convert NSRange to String.Index ranges
            for (index, range) in searchRanges.enumerated() {
                guard range.location != NSNotFound,
                      range.location >= 0,
                      range.location + range.length <= text.count else {
                    continue
                }
                
                let startIndex = text.index(text.startIndex, offsetBy: range.location)
                let endIndex = text.index(text.startIndex, offsetBy: range.location + range.length)
                
                if let start = AttributedString.Index(startIndex, within: attributed),
                   let end = AttributedString.Index(endIndex, within: attributed) {
                    let attrRange = start..<end
                    
                    // Use different colors for current match vs other matches
                    if index == currentMatchIndex {
                        attributed[attrRange].backgroundColor = Color.orange.opacity(0.9)
                        attributed[attrRange].foregroundColor = .white
                    } else {
                        attributed[attrRange].backgroundColor = highlightColor.opacity(0.8)
                        attributed[attrRange].foregroundColor = .black
                    }
                }
            }
            
            return HighlightedText(attributedString: attributed, ranges: searchRanges)
        } else {
            // Fallback for older versions
            let attributed = AttributedString(text)
            return HighlightedText(attributedString: attributed, ranges: searchRanges)
        }
    }
}

// MARK: - Search Performance Monitor

class SearchPerformanceMonitor {
    private var searchTimes: [TimeInterval] = []
    private let maxSamples = 100
    
    func recordSearchTime(_ time: TimeInterval) {
        searchTimes.append(time)
        if searchTimes.count > maxSamples {
            searchTimes.removeFirst()
        }
    }
    
    var averageSearchTime: TimeInterval {
        guard !searchTimes.isEmpty else { return 0 }
        return searchTimes.reduce(0, +) / Double(searchTimes.count)
    }
    
    var maxSearchTime: TimeInterval {
        return searchTimes.max() ?? 0
    }
    
    func reset() {
        searchTimes.removeAll()
    }
}
