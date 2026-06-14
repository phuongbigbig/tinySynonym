import Foundation

/// Identifies which source a synonym came from.
enum SynonymSource: String {
    case offline = "offline"
    case dictionary = "dictionary"
    case datamuse = "datamuse"
    case meansLike = "meansLike"
}

/// A synonym with its source for color-coding in the UI.
struct TaggedSynonym: Equatable {
    let word: String
    let source: SynonymSource

    static func == (lhs: TaggedSynonym, rhs: TaggedSynonym) -> Bool {
        lhs.word == rhs.word
    }
}

/// Provides synonyms using multiple sources with smart merging:
/// 1. Check curated offline thesaurus first (best quality for common words)
/// 2. If online enabled, query Datamuse + Free Dictionary API
/// 3. Merge results with source tags for UI color-coding
class SynonymProvider {

    private var offlineThesaurus: [String: [String]] = [:]
    private var cache: [String: [TaggedSynonym]] = [:]
    private let session: URLSession

    /// When true, only use the offline thesaurus (no network requests).
    var offlineOnly: Bool {
        get { UserDefaults.standard.bool(forKey: "offlineOnly") }
        set { UserDefaults.standard.set(newValue, forKey: "offlineOnly") }
    }

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)

        loadOfflineThesaurus()
    }

    // MARK: - Public API

    func getSynonyms(for word: String, maxResults: Int, completion: @escaping ([TaggedSynonym]) -> Void) {
        let key = word.lowercased()

        // Check cache first
        if let cached = cache[key] {
            completion(Array(cached.prefix(maxResults)))
            return
        }

        // Try the word itself, then stemmed forms
        let candidates = WordStemmer.stems(for: key)
        lookupWithStemming(candidates: candidates, originalKey: key, maxResults: maxResults, completion: completion)
    }

    /// Try each stem candidate until we find synonyms.
    private func lookupWithStemming(candidates: [String], originalKey: String, maxResults: Int, completion: @escaping ([TaggedSynonym]) -> Void) {
        guard let candidate = candidates.first else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        let remaining = Array(candidates.dropFirst())

        lookupSingle(word: candidate, maxResults: maxResults) { [weak self] results in
            if !results.isEmpty {
                // Cache under the original key so inflected forms hit cache next time
                self?.cache[originalKey] = results
                DispatchQueue.main.async { completion(Array(results.prefix(maxResults))) }
            } else {
                // Try next stem candidate
                self?.lookupWithStemming(candidates: remaining, originalKey: originalKey, maxResults: maxResults, completion: completion)
            }
        }
    }

    /// Lookup synonyms for a single word (no stemming).
    private func lookupSingle(word: String, maxResults: Int, completion: @escaping ([TaggedSynonym]) -> Void) {
        // Check offline thesaurus (high quality for common words)
        let offlineSyns: [TaggedSynonym] = (offlineThesaurus[word] ?? [])
            .map { TaggedSynonym(word: $0, source: .offline) }

        // Offline-only mode
        if offlineOnly {
            completion(offlineSyns)
            return
        }

        // If we have good offline results, return immediately and enhance in background
        if offlineSyns.count >= 3 {
            completion(offlineSyns)

            fetchOnlineSynonyms(word: word) { [weak self] onlineTagged in
                if !onlineTagged.isEmpty {
                    let merged = self?.mergeTagged(offline: offlineSyns, online: onlineTagged) ?? offlineSyns
                    self?.cache[word] = merged
                }
            }
            return
        }

        // For words not well-covered offline, query online
        fetchOnlineSynonyms(word: word) { [weak self] onlineTagged in
            let merged = self?.mergeTagged(offline: offlineSyns, online: onlineTagged)
                ?? (offlineSyns + onlineTagged)
            let final = merged.isEmpty ? offlineSyns : merged
            completion(final)
        }
    }

    /// Clear cache (e.g. when toggling offline mode)
    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Online Sources

    private func fetchOnlineSynonyms(word: String, completion: @escaping ([TaggedSynonym]) -> Void) {
        let group = DispatchGroup()
        var datamuseSynStrict: [String] = []   // rel_syn: strict synonyms
        var datamuseMeansLike: [String] = []   // ml: "means like" (broader, Word-style)
        var dictSyns: [String] = []

        // Strict synonyms
        group.enter()
        fetchDatamuse(word: word, endpoint: "rel_syn", max: 20) { results in
            datamuseSynStrict = results
            group.leave()
        }

        // "Means like" — broader results, similar to what MS Word returns
        group.enter()
        fetchDatamuse(word: word, endpoint: "ml", max: 25) { results in
            datamuseMeansLike = results
            group.leave()
        }

        group.enter()
        fetchFreeDictionary(word: word) { results in
            dictSyns = results
            group.leave()
        }

        group.notify(queue: .main) {
            var seen = Set<String>()
            var tagged: [TaggedSynonym] = []

            // 1. Strict Datamuse synonyms first (highest relevance)
            for syn in datamuseSynStrict {
                let s = syn.lowercased()
                if s != word && seen.insert(s).inserted && self.isGoodSynonym(s) {
                    tagged.append(TaggedSynonym(word: s, source: .datamuse))
                }
            }
            // 2. Free Dictionary
            for syn in dictSyns {
                let s = syn.lowercased()
                if s != word && seen.insert(s).inserted && self.isGoodSynonym(s) {
                    tagged.append(TaggedSynonym(word: s, source: .dictionary))
                }
            }
            // 3. "Means like" to fill gaps (broader but still relevant)
            for syn in datamuseMeansLike {
                let s = syn.lowercased()
                if s != word && seen.insert(s).inserted && self.isGoodSynonym(s) {
                    tagged.append(TaggedSynonym(word: s, source: .meansLike))
                }
            }

            completion(tagged)
        }
    }

    private func fetchDatamuse(word: String, endpoint: String, max: Int, completion: @escaping ([String]) -> Void) {
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word
        let urlString = "https://api.datamuse.com/words?\(endpoint)=\(encoded)&max=\(max)"

        guard let url = URL(string: urlString) else { completion([]); return }

        let task = session.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { completion([]); return }
            do {
                if let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    let words = results.compactMap { $0["word"] as? String }
                        .filter { !$0.contains(" ") && $0 != word && $0.count >= 2 }
                    completion(words)
                } else { completion([]) }
            } catch { completion([]) }
        }
        task.resume()
    }

    private func fetchFreeDictionary(word: String, completion: @escaping ([String]) -> Void) {
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word
        let urlString = "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)"

        guard let url = URL(string: urlString) else { completion([]); return }

        let task = session.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { completion([]); return }
            do {
                if let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    var synonyms: [String] = []
                    var seen = Set<String>()
                    for entry in entries {
                        if let meanings = entry["meanings"] as? [[String: Any]] {
                            for meaning in meanings {
                                if let syns = meaning["synonyms"] as? [String] {
                                    for s in syns {
                                        let lower = s.lowercased()
                                        if !lower.contains(" ") && lower != word
                                            && lower.count >= 2 && lower.count <= 20
                                            && seen.insert(lower).inserted {
                                            synonyms.append(lower)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    completion(synonyms)
                } else { completion([]) }
            } catch { completion([]) }
        }
        task.resume()
    }

    // MARK: - Merging & Filtering

    private func mergeTagged(offline: [TaggedSynonym], online: [TaggedSynonym]) -> [TaggedSynonym] {
        var seen = Set<String>()
        var merged: [TaggedSynonym] = []

        for t in offline {
            if seen.insert(t.word.lowercased()).inserted && isGoodSynonym(t.word) {
                merged.append(t)
            }
        }
        for t in online {
            let lower = t.word.lowercased()
            if seen.insert(lower).inserted && isGoodSynonym(lower) {
                merged.append(TaggedSynonym(word: lower, source: t.source))
            }
        }
        return merged
    }

    private func isGoodSynonym(_ word: String) -> Bool {
        guard word.count >= 2, word.count <= 25 else { return false }
        guard !word.contains(" ") else { return false }
        guard word.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "'" }) else { return false }

        let junk: Set<String> = [
            "bloody", "damned", "intensifier", "happify", "slutty",
            "sightly", "pulchritudinous", "riant", "halcyon", "elysian"
        ]
        return !junk.contains(word)
    }

    // MARK: - Offline Thesaurus

    private func loadOfflineThesaurus() {
        if let url = Bundle.main.url(forResource: "thesaurus", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] {
            offlineThesaurus = dict
            for (word, syns) in EmbeddedThesaurus.data {
                offlineThesaurus[word] = syns
            }
            return
        }
        offlineThesaurus = EmbeddedThesaurus.data
    }
}
