import SwiftUI

/// Pick difficulty and publish the current verified level to Firestore.
struct PublishLevelView: View {
    @Environment(\.dismiss) private var dismiss

    let level: LevelModel

    @State private var difficulty: String = "easy"
    @State private var busy = false
    @State private var banner: String?

    private let options = ["easy", "hard", "evil"]

    var body: some View {
        NavigationView {
            Form {
                if let banner {
                    Section {
                        Text(banner)
                            .foregroundColor(banner.hasPrefix("Published") ? .green : .red)
                            .font(.footnote)
                    }
                }
                Section("Difficulty") {
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(options, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button(busy ? "Publishing…" : "Publish to global list") {
                        publish()
                    }
                    .disabled(busy)
                }
            }
            .navigationTitle("Publish")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func publish() {
        if let err = LevelModel.validationErrorForPublishing(level) {
            banner = err
            return
        }
        guard FirebaseBootstrap.isConfigured else {
            banner = "Add GoogleService-Info.plist from the Firebase Console."
            return
        }
        busy = true
        banner = nil
        FirestoreLevelsService.shared.publishLevel(level, difficulty: difficulty) { result in
            DispatchQueue.main.async {
                busy = false
                switch result {
                case let .success(id):
                    banner = "Published (id: \(id))"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        dismiss()
                    }
                case let .failure(err):
                    banner = err.localizedDescription
                }
            }
        }
    }
}
