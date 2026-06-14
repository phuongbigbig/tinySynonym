import Foundation

/// Lightweight English word stemmer that reduces inflected forms to their base.
/// Handles common verb, noun, and adjective inflections.
/// e.g. "evaluating" → "evaluate", "running" → "run", "happier" → "happy"
struct WordStemmer {

    /// Check if a string ends with a doubled consonant (e.g. "runn", "stopp")
    private static func hasDoubledEnd(_ s: String) -> Bool {
        guard s.count >= 2 else { return false }
        let chars = Array(s)
        return chars[chars.count - 1] == chars[chars.count - 2]
    }

    /// Returns an array of candidate stems to try, ordered by likelihood.
    /// The original word is always included as the last fallback.
    static func stems(for word: String) -> [String] {
        let w = word.lowercased()
        var candidates: [String] = []

        // -ing forms (present participle / gerund)
        if w.hasSuffix("ing") && w.count > 5 {
            let base = String(w.dropLast(3))

            // running → run (doubled consonant)
            if hasDoubledEnd(base) {
                candidates.append(String(base.dropLast()))
            }
            // evaluating → evaluate (drop -ing, add -e)
            candidates.append(base + "e")
            // walking → walk (just drop -ing)
            candidates.append(base)
            // dying → die, lying → lie
            if base.hasSuffix("y") {
                candidates.append(String(base.dropLast()) + "ie")
            }
        }

        // -ed forms (past tense)
        if w.hasSuffix("ed") && w.count > 4 {
            let base = String(w.dropLast(2))
            // stopped → stop (doubled consonant)
            if hasDoubledEnd(base) {
                candidates.append(String(base.dropLast()))
            }
            // evaluated → evaluate (drop -d)
            candidates.append(String(w.dropLast(1)))
            // walked → walk (drop -ed)
            candidates.append(base)
        }

        // -s / -es forms (plural / 3rd person)
        if w.hasSuffix("ies") && w.count > 4 {
            // studies → study
            candidates.append(String(w.dropLast(3)) + "y")
        } else if w.hasSuffix("ses") || w.hasSuffix("xes") || w.hasSuffix("zes")
                    || w.hasSuffix("ches") || w.hasSuffix("shes") {
            // watches → watch, boxes → box
            candidates.append(String(w.dropLast(2)))
        } else if w.hasSuffix("s") && !w.hasSuffix("ss") && w.count > 3 {
            // runs → run
            candidates.append(String(w.dropLast(1)))
        }

        // -er forms (comparative)
        if w.hasSuffix("ier") && w.count > 4 {
            // happier → happy
            candidates.append(String(w.dropLast(3)) + "y")
        } else if w.hasSuffix("er") && w.count > 4 {
            let base = String(w.dropLast(2))
            // bigger → big (doubled consonant)
            if hasDoubledEnd(base) {
                candidates.append(String(base.dropLast()))
            }
            // nicer → nice
            candidates.append(base + "e")
            // taller → tall
            candidates.append(base)
        }

        // -est forms (superlative)
        if w.hasSuffix("iest") && w.count > 5 {
            // happiest → happy
            candidates.append(String(w.dropLast(4)) + "y")
        } else if w.hasSuffix("est") && w.count > 5 {
            let base = String(w.dropLast(3))
            if hasDoubledEnd(base) {
                candidates.append(String(base.dropLast()))
            }
            candidates.append(base + "e")
            candidates.append(base)
        }

        // -ly forms (adverb)
        if w.hasSuffix("ly") && w.count > 4 {
            // happily → happy
            if w.hasSuffix("ily") {
                candidates.append(String(w.dropLast(3)) + "y")
            }
            // quickly → quick
            candidates.append(String(w.dropLast(2)))
        }

        // -tion / -sion forms → try verb
        if w.hasSuffix("ation") && w.count > 6 {
            // evaluation → evaluate
            candidates.append(String(w.dropLast(5)) + "ate")
            // information → inform
            candidates.append(String(w.dropLast(5)))
        }
        if w.hasSuffix("tion") && w.count > 5 {
            candidates.append(String(w.dropLast(4)) + "t")
            candidates.append(String(w.dropLast(4)) + "te")
        }

        // -ment forms
        if w.hasSuffix("ment") && w.count > 5 {
            // assessment → assess, movement → move
            candidates.append(String(w.dropLast(4)))
            candidates.append(String(w.dropLast(4)) + "e")
        }

        // -ness forms
        if w.hasSuffix("ness") && w.count > 5 {
            // happiness → happy
            if w.hasSuffix("iness") {
                candidates.append(String(w.dropLast(5)) + "y")
            }
            // darkness → dark
            candidates.append(String(w.dropLast(4)))
        }

        // Always include the original word
        candidates.append(w)

        // Deduplicate while preserving order
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted && $0.count >= 2 }
    }
}

