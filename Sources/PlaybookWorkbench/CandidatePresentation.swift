import Foundation

func readingDraftStatus(hasFeedback: Bool) -> String {
    hasFeedback ? "待核验" : "尚未试用"
}

// Local reading drafts are separate from the original analysis and feedback.
struct CandidatePresentation: Decodable {
    struct SourceNote: Decodable {
        let sourceID, title, fact: String
    }
    struct Step: Decodable {
        let title, action, check, result: String
    }
    let candidateID, originalTitle, title, context: String
    let originalSourceIDs: [String]
    let observed, method, trigger, gap: String
    let checklistTitle: String?
    let sourceNotes: [SourceNote]
    let checklist: [Step]

    func applies(to id: String, title: String, sourceIDs: [String], availableIDs: Set<String>) -> Bool {
        let expected = Set(sourceIDs)
        let notes = Set(sourceNotes.map(\.sourceID))
        return candidateID == id && originalTitle == title && !expected.isEmpty &&
            Set(originalSourceIDs) == expected && notes == expected &&
            sourceNotes.count == expected.count && expected.isSubset(of: availableIDs) &&
            !checklist.isEmpty && [self.title, context, observed, method, trigger, gap].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct CandidatePresentationFile: Decodable {
    let schemaVersion: Int
    let candidates: [CandidatePresentation]
}
