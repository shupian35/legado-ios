//
//  Dictionary.swift
//  LegadoCore
//
//  The dictionary lookup (词典).
//
//  Upstream `app/src/main/java/io/legado/app/data/entities/DictRule.kt:40`
//  (`DictRule.search`):
//
//  * `AnalyzeUrl(urlRule, key = word)` performs the request — the word is
//    the `key` of the URL rule,
//  * when the `showRule` is blank the BODY is the result,
//  * otherwise `AnalyzeRule.getString(showRule, mContent = body)` extracts
//    the definition out of the body.
//
//  The port reproduces that behaviour; the UI lives in `LegadoUI`.
//

import Foundation

/// The result of a dictionary lookup.
public struct DictSearchResult: Sendable, Equatable {

    /// The definition.
    public let text: String
    /// The name of the rule that answered.
    public let ruleName: String

    public init(text: String, ruleName: String) {
        self.text = text
        self.ruleName = ruleName
    }
}

/// The dictionary lookup.
public enum DictSearcher {

    /// Searches the word with the rule.
    ///
    /// - Parameters:
    ///   - rule: the dictionary rule (its `urlRule` is the address, its
    ///     `showRule` extracts the definition).
    ///   - word: the word to look up.
    ///   - dependencies: the network dependencies.
    public static func search(
        rule: DictRule,
        word: String,
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async throws -> String {
        let analyzeUrl = AnalyzeUrl(url: rule.urlRule, key: word, dependencies: dependencies)
        let response = try await analyzeUrl.strResponse()
        let body = response.body ?? ""
        if rule.showRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return body
        }
        let analyzeRule = AnalyzeRule(content: RuleContent.text(body))
        return try analyzeRule.getString(rule.showRule)
    }

    /// Searches the word with the first enabled rule that answers.
    ///
    /// Upstream `DictViewModel.dict` shows the result of the rule the user
    /// picked; the port falls back to the first rule that returns a non
    /// empty result.
    public static func search(
        word: String,
        rules: [DictRule],
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async throws -> DictSearchResult {
        var lastError: Error?
        for rule in rules where rule.enabled {
            do {
                let result = try await search(rule: rule, word: word, dependencies: dependencies)
                if !result.isEmpty {
                    return DictSearchResult(text: result, ruleName: rule.name)
                }
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return DictSearchResult(text: "", ruleName: "")
    }
}
