import SwiftUI
import FirebaseFirestore

/// Minimal list of published levels with Newest / Popular tabs and pagination.
struct BrowseLevelsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var sort: FirestoreLevelsService.SortMode = .newest
    @State private var rows: [FirestoreLevelsService.RemoteLevelSummary] = []
    @State private var lastDoc: DocumentSnapshot?
    @State private var canLoadMore = true
    @State private var loading = false
    @State private var errorMessage: String?

    var onPick: (String) -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Sort", selection: $sort) {
                    Text("Newest").tag(FirestoreLevelsService.SortMode.newest)
                    Text("Popular").tag(FirestoreLevelsService.SortMode.popular)
                }
                .pickerStyle(.segmented)
                .padding()

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .padding(.horizontal)
                }

                List {
                    ForEach(rows) { item in
                        Button {
                            onPick(item.id)
                            dismiss()
                        } label: {
                            HStack {
                                Text(item.difficulty.capitalized)
                                    .font(.headline)
                                Spacer()
                                Text("plays \(item.plays)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    if canLoadMore && !rows.isEmpty {
                        Button(loading ? "Loading…" : "Load more") {
                            loadMore(reset: false)
                        }
                        .disabled(loading)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Play Levels")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                if rows.isEmpty { loadMore(reset: true) }
            }
            .onChange(of: sort) { _ in
                loadMore(reset: true)
            }
        }
        .navigationViewStyle(.stack)
    }

    private func loadMore(reset: Bool) {
        guard !loading else { return }
        if !FirebaseBootstrap.isConfigured {
            errorMessage = "Add GoogleService-Info.plist to enable online levels."
            return
        }
        loading = true
        errorMessage = nil
        let start = reset ? nil : lastDoc
        FirestoreLevelsService.shared.fetchPage(sort: sort, startAfter: start) { result in
            loading = false
            switch result {
            case let .failure(err):
                errorMessage = err.localizedDescription
            case let .success((items, last)):
                if reset {
                    rows = items
                } else {
                    rows.append(contentsOf: items)
                }
                lastDoc = last
                canLoadMore = items.count >= FirestoreLevelsService.pageSize
            }
        }
    }
}
