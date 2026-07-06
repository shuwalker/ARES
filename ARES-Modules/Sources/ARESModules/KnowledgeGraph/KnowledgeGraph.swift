// Auto-extracted from gbrain (TypeScript)
// Source: gbrain
// Date: 2026-06-23 12:49
//
// Port of gbrain's core knowledge graph architecture to Swift.
// Key patterns: Page types, hybrid search (keyword + vector RRF),
// fact extraction, entity resolution, emotional weight scoring.

import Foundation

// MARK: - Page Types

/// Canonical page types from gbrain's type system
public enum PageType: String, Codable, CaseIterable, Sendable {
    case person, company, deal, yc, civic, project, concept
    case source, media, writing, analysis, guide, hardware
    case architecture, meeting, note, email, slack, calendarEvent = "calendar-event"
    case code, image, synthesis
}

/// A knowledge page — the core unit of the graph
public struct Page: Codable, Sendable, Identifiable {
    public let id: Int
    public let slug: String
    public let type: PageType
    public let title: String
    public let compiledTruth: String
    public let timeline: String
    public let frontmatter: [String: AnyCodable]
    public let contentHash: String?
    public var emotionalWeight: Double?
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?
    public let effectiveDate: Date?
    public let importFilename: String?
    public let salienceTouchedAt: Date?

    public init(id: Int, slug: String, type: PageType, title: String, compiledTruth: String = "",
                timeline: String = "", frontmatter: [String: AnyCodable] = [:],
                contentHash: String? = nil, emotionalWeight: Double? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date(),
                deletedAt: Date? = nil, effectiveDate: Date? = nil,
                importFilename: String? = nil, salienceTouchedAt: Date? = nil) {
        self.id = id
        self.slug = slug
        self.type = type
        self.title = title
        self.compiledTruth = compiledTruth
        self.timeline = timeline
        self.frontmatter = frontmatter
        self.contentHash = contentHash
        self.emotionalWeight = emotionalWeight
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.effectiveDate = effectiveDate
        self.importFilename = importFilename
        self.salienceTouchedAt = salienceTouchedAt
    }
}

// MARK: - Content Chunks

/// A chunk of content within a page, with embedding support
public struct ContentChunk: Codable, Sendable, Identifiable {
    public let id: Int
    public let pageId: Int
    public let slug: String
    public let content: String
    public let contentType: ChunkType
    public let embedding: [Float]?
    public let embeddingModel: String?
    public let tokenCount: Int
    public let position: Int

    public init(id: Int, pageId: Int, slug: String, content: String, contentType: ChunkType,
                embedding: [Float]? = nil, embeddingModel: String? = nil,
                tokenCount: Int, position: Int) {
        self.id = id
        self.pageId = pageId
        self.slug = slug
        self.content = content
        self.contentType = contentType
        self.embedding = embedding
        self.embeddingModel = embeddingModel
        self.tokenCount = tokenCount
        self.position = position
    }

    public enum ChunkType: String, Codable, Sendable {
        case compiledTruth = "compiled_truth"
        case content
        case code
        case image
        case synthesis
    }
}

// MARK: - Search Types

/// Search result from hybrid search
public struct SearchResult: Codable, Sendable, Identifiable {
    public let slug: String
    public let pageId: Int
    public let pageType: PageType
    public let title: String
    public let snippet: String
    public let score: Double
    public let rrfScore: Double
    public let cosineScore: Double?
    public let backlinkCount: Int
    public let recencyDays: Int
    public let emotionalWeight: Double?

    public var id: String { slug }
}

/// Search options
public struct SearchOptions: Codable, Sendable {
    public let query: String
    public let limit: Int
    public let offset: Int
    public let pageTypes: [PageType]?
    public let minScore: Double?
    public let includeDeleted: Bool
    public let recencyBoost: Bool
    public let emotionalWeightBoost: Bool

    public static let `default` = SearchOptions(
        query: "", limit: 20, offset: 0, pageTypes: nil,
        minScore: nil, includeDeleted: false,
        recencyBoost: true, emotionalWeightBoost: true
    )
}

// MARK: - Hybrid Search (RRF Fusion)

/// Reciprocal Rank Fusion constants
public enum RRF {
    /// Default RRF constant
    public static let k: Double = 60
    /// Boost for compiled_truth chunks
    public static let compiledTruthBoost: Double = 2.0
    /// Backlink boost coefficient
    public static let backlinkBoostCoef: Double = 0.05
    /// Cosine re-score blend weight
    public static let cosineBlendWeight: Double = 0.3
    /// RRF blend weight
    public static let rrfBlendWeight: Double = 0.7
}

/// Hybrid search engine combining keyword + vector search with RRF fusion
public actor HybridSearchEngine {
    private var chunks: [ContentChunk] = []
    private var keywordIndex: [String: [(chunkId: Int, score: Double)]] = [:]
    private var vectorDimension: Int = 0

    public init() {}

    /// Index a set of chunks for search
    public func index(_ newChunks: [ContentChunk]) {
        chunks.append(contentsOf: newChunks)
        rebuildKeywordIndex()
        if let first = newChunks.first?.embedding {
            vectorDimension = first.count
        }
    }

    /// Perform hybrid search with RRF fusion
    public func search(_ options: SearchOptions) async -> [SearchResult] {
        let query = options.query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }

        // 1. Keyword search
        let keywordResults = keywordSearch(query, limit: options.limit * 2)

        // 2. Vector search (if embeddings available)
        let vectorResults = vectorSearch(query, limit: options.limit * 2)

        // 3. RRF Fusion
        let fused = fuseResults(keyword: keywordResults, vector: vectorResults, limit: options.limit)

        // 4. Apply boosts
        var boosted = applyBoosts(fused, options: options)

        // 5. Sort by final score
        boosted.sort { $0.score > $1.score }

        return Array(boosted.prefix(options.limit))
    }

    // MARK: - Private

    private func rebuildKeywordIndex() {
        keywordIndex.removeAll()
        for chunk in chunks {
            let words = chunk.content.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
            let totalWords = words.count
            let wordFreq = NSCountedSet()
            words.forEach { wordFreq.add($0) }

            for word in Set(words) {
                let tf = Double(wordFreq.count(for: word)) / Double(max(totalWords, 1))
                let idf = log(Double(chunks.count) / Double(1 + countDocsContaining(word)))
                let score = tf * idf
                keywordIndex[word, default: []].append((chunk.id, score))
            }
        }
    }

    private func countDocsContaining(_ word: String) -> Int {
        keywordIndex[word]?.count ?? 0
    }

    private func keywordSearch(_ query: String, limit: Int) -> [(chunkId: Int, score: Double)] {
        let queryWords = Set(query.components(separatedBy: .whitespaces).filter { $0.count > 2 })
        guard !queryWords.isEmpty else { return [] }

        var scores: [Int: Double] = [:]
        for word in queryWords {
            guard let postings = keywordIndex[word] else { continue }
            for (chunkId, score) in postings {
                scores[chunkId, default: 0] += score
            }
        }

        return scores.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { ($0.key, $0.value) }
    }

    private func vectorSearch(_ query: String, limit: Int) -> [(chunkId: Int, score: Double)] {
        guard vectorDimension > 0 else { return [] }
        // Simple token overlap as vector proxy when no real embeddings
        let queryTokens = Set(query.lowercased().components(separatedBy: .whitespaces))
        var scores: [Int: Double] = [:]

        for chunk in chunks where chunk.embedding == nil {
            let chunkTokens = Set(chunk.content.lowercased().components(separatedBy: .whitespaces))
            let intersection = queryTokens.intersection(chunkTokens)
            let union = queryTokens.union(chunkTokens)
            if !union.isEmpty {
                scores[chunk.id] = Double(intersection.count) / Double(union.count)
            }
        }

        return scores.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { ($0.key, $0.value) }
    }

    private func fuseResults(keyword: [(chunkId: Int, score: Double)],
                             vector: [(chunkId: Int, score: Double)],
                             limit: Int) -> [SearchResult] {
        // Build ranked lists
        let keywordRanked = keyword.enumerated().map { (idx, item) in
            (chunkId: item.chunkId, rank: idx + 1, score: item.score)
        }
        let vectorRanked = vector.enumerated().map { (idx, item) in
            (chunkId: item.chunkId, rank: idx + 1, score: item.score)
        }

        // RRF fusion
        var fusedScores: [Int: (rrf: Double, keywordScore: Double, vectorScore: Double)] = [:]

        for item in keywordRanked {
            let rrf = 1.0 / (RRF.k + Double(item.rank))
            fusedScores[item.chunkId] = (rrf, item.score, 0)
        }

        for item in vectorRanked {
            let rrf = 1.0 / (RRF.k + Double(item.rank))
            if var existing = fusedScores[item.chunkId] {
                existing.rrf += rrf
                existing.vectorScore = item.score
                fusedScores[item.chunkId] = existing
            } else {
                fusedScores[item.chunkId] = (rrf, 0, item.score)
            }
        }

        // Build results
        let chunkMap = Dictionary(uniqueKeysWithValues: chunks.map { ($0.id, $0) })
        var results: [SearchResult] = []

        for (chunkId, scores) in fusedScores {
            guard let chunk = chunkMap[chunkId] else { continue }
            let finalScore = RRF.rrfBlendWeight * scores.rrf + RRF.cosineBlendWeight * max(scores.keywordScore, scores.vectorScore)
            results.append(SearchResult(
                slug: chunk.slug,
                pageId: chunk.pageId,
                pageType: .note, // Would need page lookup
                title: chunk.slug,
                snippet: String(chunk.content.prefix(200)),
                score: finalScore,
                rrfScore: scores.rrf,
                cosineScore: max(scores.keywordScore, scores.vectorScore),
                backlinkCount: 0,
                recencyDays: 0,
                emotionalWeight: nil
            ))
        }

        return results.sorted { $0.score > $1.score }.prefix(limit).map { $0 }
    }

    private func applyBoosts(_ results: [SearchResult], options: SearchOptions) -> [SearchResult] {
        results.map { result in
            var score = result.score

            // Compiled truth boost
            if result.slug.contains("compiled") {
                score *= RRF.compiledTruthBoost
            }

            // Recency boost
            if options.recencyBoost && result.recencyDays < 30 {
                score *= 1.0 + (1.0 - Double(result.recencyDays) / 30.0) * 0.5
            }

            // Emotional weight boost
            if options.emotionalWeightBoost, let ew = result.emotionalWeight {
                score *= 1.0 + ew * 0.3
            }

            return SearchResult(
                slug: result.slug, pageId: result.pageId,
                pageType: result.pageType, title: result.title,
                snippet: result.snippet, score: score,
                rrfScore: result.rrfScore, cosineScore: result.cosineScore,
                backlinkCount: result.backlinkCount,
                recencyDays: result.recencyDays,
                emotionalWeight: result.emotionalWeight
            )
        }
    }
}

// MARK: - Fact Extraction

/// Types of facts that can be extracted from conversations
public enum FactKind: String, Codable, Sendable, CaseIterable {
    case event, preference, commitment, belief, fact
}

/// A fact extracted from a conversation turn
public struct Fact: Codable, Sendable {
    public let factId: Int
    public let kind: FactKind
    public let content: String
    public let confidence: Double
    public let source: String
    public let sessionId: String?
    public let entitySlug: String?
    public let embedding: [Float]?
    public let createdAt: Date
    public let expiresAt: Date?
}

/// Fact extraction engine — extracts structured facts from conversation turns
public actor FactExtractor {
    private var facts: [Fact] = []
    private var nextId: Int = 1

    public init() {}

    /// Extract facts from a conversation turn
    public func extract(from turnText: String, source: String, sessionId: String? = nil) -> [Fact] {
        let lower = turnText.lowercased()
        var extracted: [Fact] = []

        // Pattern-based extraction (heuristic — in production this uses an LLM)
        let patterns: [(FactKind, String)] = [
            (.preference, "i prefer"),
            (.preference, "i like"),
            (.preference, "i want"),
            (.preference, "i need"),
            (.commitment, "i will"),
            (.commitment, "i'll"),
            (.commitment, "let's"),
            (.belief, "i think"),
            (.belief, "i believe"),
            (.belief, "in my opinion"),
            (.fact, "it is"),
            (.fact, "it's a"),
            (.fact, "this means"),
            (.event, "happened"),
            (.event, "occurred"),
            (.event, "was on"),
        ]

        for (kind, pattern) in patterns {
            if lower.contains(pattern) {
                // Find the sentence containing the pattern
                let sentences = turnText.components(separatedBy: CharacterSet(charactersIn: ".!?"))
                for sentence in sentences {
                    if sentence.lowercased().contains(pattern) {
                        let trimmed = sentence.trimmingCharacters(in: .whitespaces)
                        if trimmed.count > 10 {
                            let fact = Fact(
                                factId: nextId,
                                kind: kind,
                                content: String(trimmed.prefix(500)),
                                confidence: kind == .fact ? 0.7 : 0.5,
                                source: source,
                                sessionId: sessionId,
                                entitySlug: resolveEntity(from: trimmed),
                                embedding: nil,
                                createdAt: Date(),
                                expiresAt: kind == .event ? Date().addingTimeInterval(86400 * 30) : nil
                            )
                            extracted.append(fact)
                            nextId += 1
                            break
                        }
                    }
                }
            }
        }

        facts.append(contentsOf: extracted)
        return extracted
    }

    /// Query facts by kind and entity
    public func query(kind: FactKind? = nil, entitySlug: String? = nil, limit: Int = 20) -> [Fact] {
        var results = facts

        if let kind = kind {
            results = results.filter { $0.kind == kind }
        }
        if let entitySlug = entitySlug {
            results = results.filter { $0.entitySlug == entitySlug }
        }

        // Filter expired
        results = results.filter { fact in
            guard let expiresAt = fact.expiresAt else { return true }
            return expiresAt > Date()
        }

        return results.sorted { $0.createdAt > $1.createdAt }.prefix(limit).map { $0 }
    }

    /// Decay fact confidence over time
    public func decay() {
        let now = Date()
        facts = facts.map { fact in
            guard fact.confidence > 0.1 else { return fact }
            let age = now.timeIntervalSince(fact.createdAt)
            let daysOld = age / 86400
            let decayFactor = max(0.1, 1.0 - (daysOld / 90.0))
            return Fact(
                factId: fact.factId, kind: fact.kind, content: fact.content,
                confidence: fact.confidence * decayFactor,
                source: fact.source, sessionId: fact.sessionId,
                entitySlug: fact.entitySlug, embedding: fact.embedding,
                createdAt: fact.createdAt, expiresAt: fact.expiresAt
            )
        }
    }

    // MARK: - Private

    private func resolveEntity(from text: String) -> String? {
        // Simple entity extraction — looks for capitalized words
        let words = text.components(separatedBy: .whitespaces)
        for word in words {
            let cleaned = word.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if cleaned.count >= 2,
               cleaned.first?.isUppercase == true,
               cleaned.lowercased() != cleaned {
                return cleaned.lowercased()
            }
        }
        return nil
    }
}

// MARK: - Entity Resolution

/// A resolved entity in the knowledge graph
public struct Entity: Codable, Sendable, Identifiable {
    public let slug: String
    public let name: String
    public let type: EntityType
    public let aliases: [String]
    public let description: String
    public let pageIds: [Int]
    public let factIds: [Int]
    public let emotionalWeight: Double
    public let createdAt: Date
    public let updatedAt: Date

    public var id: String { slug }
}

public enum EntityType: String, Codable, Sendable {
    case person, organization, project, concept, technology, location, event
}

/// Entity resolver — resolves names to entities and maintains aliases
public actor EntityResolver {
    private var entities: [String: Entity] = [:]
    private var aliasIndex: [String: String] = [:]

    public init() {}

    public func register(_ entity: Entity) {
        entities[entity.slug] = entity
        for alias in entity.aliases {
            aliasIndex[alias.lowercased()] = entity.slug
        }
        aliasIndex[entity.name.lowercased()] = entity.slug
    }

    public func resolve(_ name: String) -> Entity? {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let slug = aliasIndex[key] {
            return entities[slug]
        }
        // Fuzzy match
        for (alias, slug) in aliasIndex {
            if alias.contains(key) || key.contains(alias) {
                return entities[slug]
            }
        }
        return nil
    }

    public func search(_ query: String) -> [Entity] {
        let lower = query.lowercased()
        return entities.values.filter { entity in
            entity.name.lowercased().contains(lower) ||
            entity.aliases.contains { $0.lowercased().contains(lower) } ||
            entity.description.lowercased().contains(lower)
        }.sorted { $0.emotionalWeight > $1.emotionalWeight }
    }
}

// MARK: - Emotional Weight / Salience

/// Emotional weight calculator — scores pages by salience
public actor SalienceScorer {
    private var backlinkCounts: [String: Int] = [:]
    private var recencyCache: [String: Date] = [:]

    public init() {}

    public func recordAccess(slug: String) {
        recencyCache[slug] = Date()
    }

    public func recordBacklink(from: String, to: String) {
        backlinkCounts[to, default: 0] += 1
    }

    /// Compute emotional weight for a page
    public func computeWeight(for page: Page) -> Double {
        let backlinks = Double(backlinkCounts[page.slug] ?? 0)
        let recency: Double
        if let lastAccess = recencyCache[page.slug] {
            let daysSinceAccess = Date().timeIntervalSince(lastAccess) / 86400
            recency = max(0, 1.0 - daysSinceAccess / 30.0)
        } else {
            recency = 0.1
        }

        let age = Date().timeIntervalSince(page.createdAt) / 86400
        let ageFactor = min(1.0, 30.0 / max(1, age))

        // Weighted combination
        let backlinkScore = min(1.0, backlinks / 10.0) * 0.3
        let recencyScore = recency * 0.4
        let ageScore = ageFactor * 0.3

        return backlinkScore + recencyScore + ageScore
    }
}

// MARK: - Knowledge Graph (Orchestrator)

/// The main knowledge graph — orchestrates search, facts, entities, and salience
public actor KnowledgeGraph {
    public let search: HybridSearchEngine
    public let facts: FactExtractor
    public let entities: EntityResolver
    public let salience: SalienceScorer

    private var pages: [String: Page] = [:]

    public init() {
        self.search = HybridSearchEngine()
        self.facts = FactExtractor()
        self.entities = EntityResolver()
        self.salience = SalienceScorer()
    }

    /// Ingest a page into the knowledge graph
    public func ingest(page: Page, chunks: [ContentChunk]) async {
        pages[page.slug] = page
        await search.index(chunks)
        await salience.recordAccess(slug: page.slug)
    }

    /// Extract facts from a conversation turn and link to entities
    public func learn(from turnText: String, source: String, sessionId: String? = nil) async -> [Fact] {
        let extracted = await facts.extract(from: turnText, source: source, sessionId: sessionId)
        for fact in extracted {
            if let entitySlug = fact.entitySlug {
                if await entities.resolve(entitySlug) == nil {
                    let entity = Entity(
                        slug: entitySlug,
                        name: entitySlug.capitalized,
                        type: .concept,
                        aliases: [],
                        description: "Auto-discovered from conversation",
                        pageIds: [],
                        factIds: [fact.factId],
                        emotionalWeight: 0.1,
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    await entities.register(entity)
                }
            }
        }
        return extracted
    }

    /// Search the knowledge graph
    public func searchGraph(query: String, limit: Int = 20) async -> [SearchResult] {
        let options = SearchOptions(
            query: query, limit: limit, offset: 0,
            pageTypes: nil, minScore: nil, includeDeleted: false,
            recencyBoost: true, emotionalWeightBoost: true
        )
        return await search.search(options)
    }

    /// Get salience-weighted recommendations
    public func recommendations(limit: Int = 10) async -> [Page] {
        let allSlugs = pages.keys.filter { pages[$0]?.deletedAt == nil }
        var scored: [Page] = []
        for slug in allSlugs {
            guard var page = pages[slug] else { continue }
            page.emotionalWeight = await salience.computeWeight(for: page)
            scored.append(page)
        }
        return scored
            .sorted { ($0.emotionalWeight ?? 0) > ($1.emotionalWeight ?? 0) }
            .prefix(limit)
            .map { $0 }
    }

    /// Run maintenance — decay facts, prune old data
    public func maintain() async {
        await facts.decay()
    }
}

// MARK: - Helper

/// Type-erased codable value for flexible frontmatter
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array
        } else {
            value = ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let dict = value as? [String: AnyCodable] {
            try container.encode(dict)
        } else if let array = value as? [AnyCodable] {
            try container.encode(array)
        } else {
            try container.encode("")
        }
    }
}
