import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Global published levels (`levels` collection). Anonymous auth only; no user profiles.
final class FirestoreLevelsService {
    static let shared = FirestoreLevelsService()
    static let pageSize = 20

    private let collectionName = "levels"

    private init() {}

    // MARK: - Auth

    func ensureAnonymousSignedIn(completion: @escaping (Error?) -> Void) {
        guard FirebaseBootstrap.isConfigured else {
            completion(Self.makeError("Firebase is not configured. Add GoogleService-Info.plist."))
            return
        }
        if Auth.auth().currentUser != nil {
            completion(nil)
            return
        }
        Auth.auth().signInAnonymously { _, error in
            completion(error)
        }
    }

    // MARK: - Publish

    func publishLevel(
        _ level: LevelModel,
        difficulty: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        if let err = LevelModel.validationErrorForPublishing(level) {
            completion(.failure(Self.makeError(err)))
            return
        }
        let diff = Self.normalizeDifficulty(difficulty)
        ensureAnonymousSignedIn { [weak self] authError in
            guard let self else { return }
            if let authError {
                completion(.failure(authError))
                return
            }
            let ref = Firestore.firestore().collection(self.collectionName).document()
            let data: [String: Any] = [
                "grid": level.tiles,
                "replayMs": level.replayTapTimestampsMs,
                "verified": true,
                "createdAt": FieldValue.serverTimestamp(),
                "difficulty": diff,
                "plays": 0,
            ]
            ref.setData(data) { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(ref.documentID))
                }
            }
        }
    }

    // MARK: - Browse

    enum SortMode: String, CaseIterable {
        case newest
        case popular
    }

    struct RemoteLevelSummary: Identifiable, Equatable {
        let id: String
        let difficulty: String
        let plays: Int
        let createdAt: Date?
    }

    func fetchPage(
        sort: SortMode,
        startAfter: DocumentSnapshot?,
        completion: @escaping (Result<([RemoteLevelSummary], DocumentSnapshot?), Error>) -> Void
    ) {
        ensureAnonymousSignedIn { [weak self] authError in
            guard let self else { return }
            if let authError {
                completion(.failure(authError))
                return
            }
            var q: Query = Firestore.firestore().collection(self.collectionName)
            switch sort {
            case .newest:
                q = q.order(by: "createdAt", descending: true)
            case .popular:
                q = q.order(by: "plays", descending: true).order(by: "createdAt", descending: true)
            }
            q = q.limit(to: Self.pageSize)
            if let startAfter {
                q = q.start(afterDocument: startAfter)
            }
            q.getDocuments { snap, error in
                if let error {
                    completion(.failure(error))
                    return
                }
                guard let snap else {
                    completion(.success(([], nil)))
                    return
                }
                let items: [RemoteLevelSummary] = snap.documents.compactMap { doc in
                    let d = doc.data()
                    let diff = (d["difficulty"] as? String) ?? "easy"
                    let plays = (d["plays"] as? NSNumber)?.intValue ?? (d["plays"] as? Int) ?? 0
                    let created = (d["createdAt"] as? Timestamp)?.dateValue()
                    return RemoteLevelSummary(id: doc.documentID, difficulty: diff, plays: plays, createdAt: created)
                }
                let last = snap.documents.last
                completion(.success((items, last)))
            }
        }
    }

    func loadLevelForPlay(
        documentId: String,
        completion: @escaping (Result<LevelModel, Error>) -> Void
    ) {
        ensureAnonymousSignedIn { [weak self] authError in
            guard let self else { return }
            if let authError {
                completion(.failure(authError))
                return
            }
            Firestore.firestore().collection(self.collectionName).document(documentId).getDocument { snap, error in
                if let error {
                    completion(.failure(error))
                    return
                }
                guard let snap, snap.exists, let d = snap.data() else {
                    completion(.failure(Self.makeError("Level not found.")))
                    return
                }
                guard let grid = d["grid"] as? [Int], LevelModel.isValidGridArray(grid) else {
                    completion(.failure(Self.makeError("Invalid level data.")))
                    return
                }
                let replay = (d["replayMs"] as? [NSNumber])?.map { $0.int64Value }
                    ?? (d["replayMs"] as? [Int64])
                    ?? (d["replayMs"] as? [Int])?.map { Int64($0) }
                    ?? []
                let verified = (d["verified"] as? Bool) ?? false
                let level = LevelModel(tiles: grid, verified: verified, replayTapTimestampsMs: replay)
                completion(.success(level))
            }
        }
    }

    func incrementPlays(documentId: String, completion: ((Error?) -> Void)? = nil) {
        guard FirebaseBootstrap.isConfigured else {
            completion?(Self.makeError("Firebase not configured."))
            return
        }
        let ref = Firestore.firestore().collection(collectionName).document(documentId)
        ref.updateData(["plays": FieldValue.increment(Int64(1))]) { error in
            completion?(error)
        }
    }

    // MARK: - Helpers

    private static func normalizeDifficulty(_ raw: String) -> String {
        let s = raw.lowercased()
        if s == "hard" || s == "evil" { return s }
        return "easy"
    }

    private static func makeError(_ message: String) -> NSError {
        NSError(domain: "CubeRunLevels", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
