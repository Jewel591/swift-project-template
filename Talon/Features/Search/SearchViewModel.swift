import Foundation
import Observation

@Observable
@MainActor
final class SearchViewModel {
    var searchText = ""
    private(set) var results: [Asset] = []
    private(set) var isSearching = false
    private(set) var searchHistory: [String] = []

    // Filter state
    var selectedTags: [String] = []
    var selectedFileTypes: [String] = []
    var minRating: Int = 0
    var dateFrom: Date?
    var dateTo: Date?

    private var searchTask: Task<Void, Never>?
    private let historyKey = "com.talon.searchHistory"

    init() {
        searchHistory = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
    }

    func performSearch(coordinator: SearchCoordinator) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            isSearching = true
            let query = SearchQuery(
                keyword: searchText.isEmpty ? nil : searchText,
                tags: selectedTags.isEmpty ? nil : selectedTags,
                fileTypes: selectedFileTypes.isEmpty ? nil : selectedFileTypes,
                ratingMin: minRating > 0 ? minRating : nil,
                dateFrom: dateFrom,
                dateTo: dateTo
            )
            do {
                results = try await coordinator.search(query)
            } catch {}
            isSearching = false

            if !searchText.isEmpty {
                saveToHistory(searchText)
            }
        }
    }

    func clearFilters() {
        selectedTags = []
        selectedFileTypes = []
        minRating = 0
        dateFrom = nil
        dateTo = nil
    }

    private func saveToHistory(_ text: String) {
        searchHistory.removeAll { $0 == text }
        searchHistory.insert(text, at: 0)
        if searchHistory.count > 50 { searchHistory = Array(searchHistory.prefix(50)) }
        UserDefaults.standard.set(searchHistory, forKey: historyKey)
    }
}
