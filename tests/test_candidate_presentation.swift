import Foundation

// Run against the production model, without opening the app or user data.
@main struct PresentationContractTests {
    static func main() throws {
        let bytes = Data("""
        {"candidateID":"candidate-a","originalTitle":"Original","title":"Readable",
         "context":"Synthetic project","originalSourceIDs":["source-a"],
         "observed":"Observed","method":"Suggested","trigger":"When needed","gap":"Not yet tried",
         "sourceNotes":[{"sourceID":"source-a","title":"Evidence","fact":"Observed only"}],
         "checklist":[{"title":"Check","action":"Compare","check":"Matches","result":"Record"}]}
        """.utf8)
        let draft = try JSONDecoder().decode(CandidatePresentation.self, from: bytes)
        func matches(_ id: String = "candidate-a", _ title: String = "Original",
                     _ sources: [String] = ["source-a"], _ available: Set<String> = ["source-a"]) -> Bool {
            draft.applies(to: id, title: title, sourceIDs: sources, availableIDs: available)
        }
        precondition(matches())
        precondition(!matches("other-candidate"), "A reading draft must not leak onto another candidate")
        precondition(!matches("candidate-a", "Changed"), "Changed originals require a new reading draft")
        precondition(!matches("candidate-a", "Original", ["other-source"]), "Unbound evidence must be rejected")
        precondition(!matches("candidate-a", "Original", ["source-a"], []), "Missing source text must be rejected")
        let duplicateNotes = bytes.replacingOccurrences(of: Data("\"sourceNotes\":[{\"sourceID\":\"source-a\",\"title\":\"Evidence\",\"fact\":\"Observed only\"}]".utf8),
            with: Data("\"sourceNotes\":[{\"sourceID\":\"source-a\",\"title\":\"A\",\"fact\":\"A\"},{\"sourceID\":\"source-a\",\"title\":\"B\",\"fact\":\"B\"}]".utf8))
        let duplicate = try JSONDecoder().decode(CandidatePresentation.self, from: duplicateNotes)
        precondition(!duplicate.applies(to: "candidate-a", title: "Original", sourceIDs: ["source-a"], availableIDs: ["source-a"]))
        precondition(readingDraftStatus(hasFeedback: false) == "尚未试用")
        precondition(readingDraftStatus(hasFeedback: true) == "待核验", "Returning to draft must not erase trial history")
        print("Presentation contract: 8 checks passed")
    }
}

private extension Data {
    func replacingOccurrences(of target: Data, with replacement: Data) -> Data {
        Data(String(decoding: self, as: UTF8.self).replacingOccurrences(of: String(decoding: target, as: UTF8.self),
            with: String(decoding: replacement, as: UTF8.self)).utf8)
    }
}
