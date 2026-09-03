import Foundation

struct Entry: Equatable, Sendable {
    let rawPath: String
    let data: Data
}

enum VFSFailure: Error, Equatable, Sendable {
    case collision(String, String)
    case missing(String)
    case unsafe(String)
}

struct PackageVFS: Sendable {
    private let byKey: [String: Entry]

    init(entries: [Entry]) throws {
        var result: [String: Entry] = [:]
        for entry in entries {
            let key = Self.key(entry.rawPath)
            if let existing = result[key] {
                throw VFSFailure.collision(existing.rawPath, entry.rawPath)
            }
            result[key] = entry
        }
        byKey = result
    }

    func resolve(_ path: String) throws -> Entry {
        guard Self.isSafe(path) else {
            throw VFSFailure.unsafe(path)
        }
        guard let entry = byKey[Self.key(path)] else {
            throw VFSFailure.missing(path)
        }
        return entry
    }

    private static func key(_ path: String) -> String {
        String(decoding: path.utf8.map { byte in
            byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte
        }, as: UTF8.self)
    }

    private static func isSafe(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~") else {
            return false
        }
        return !path.split(separator: "/", omittingEmptySubsequences: false)
            .contains("..")
    }
}

struct AuthoredPath: Equatable, Sendable {
    let objectIndex: Int
    let pathIndex: Int?
    let value: String
}

struct ResolvedAsset: Equatable, Sendable {
    let authored: AuthoredPath
    let entry: Entry
}

struct SoundAssetPlan: Equatable, Sendable {
    let objects: [[ResolvedAsset]]
}

enum SoundAssetPlanCompiler {
    static func compile(
        objects: [[AuthoredPath]],
        vfs: PackageVFS
    ) throws -> SoundAssetPlan {
        let resolved = try objects.map { paths in
            try paths.map { path in
                ResolvedAsset(authored: path, entry: try vfs.resolve(path.value))
            }
        }
        return SoundAssetPlan(objects: resolved)
    }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let vfs = try PackageVFS(entries: [
    Entry(rawPath: "sounds/a.WAV", data: Data([1, 2, 3])),
    Entry(rawPath: "sounds/b.wav", data: Data([4, 5])),
    Entry(rawPath: "sounds/unreferenced.wav", data: Data([9]))
])
let authored = [[
    AuthoredPath(objectIndex: 3, pathIndex: 0, value: "sounds/A.wav"),
    AuthoredPath(objectIndex: 3, pathIndex: 1, value: "sounds/b.wav"),
    AuthoredPath(objectIndex: 3, pathIndex: 2, value: "sounds/A.wav")
]]
let plan = try SoundAssetPlanCompiler.compile(objects: authored, vfs: vfs)
let assets = plan.objects[0]
require(assets.map(\.authored.pathIndex) == [0, 1, 2], "authored path coordinates changed")
require(assets.map(\.entry.rawPath) == ["sounds/a.WAV", "sounds/b.wav", "sounds/a.WAV"], "VFS resolution changed order or duplicate identity")
require(assets.map(\.entry.data) == [Data([1, 2, 3]), Data([4, 5]), Data([1, 2, 3])], "resolved bytes changed")
require(assets.allSatisfy { $0.entry.rawPath != "sounds/unreferenced.wav" }, "unreferenced archive sound was selected")

do {
    _ = try SoundAssetPlanCompiler.compile(
        objects: [[
            AuthoredPath(objectIndex: 0, pathIndex: 0, value: "sounds/a.wav"),
            AuthoredPath(objectIndex: 0, pathIndex: 1, value: "sounds/missing.wav")
        ]],
        vfs: vfs
    )
    require(false, "partial plan was returned for a missing authored asset")
} catch VFSFailure.missing(let path) {
    require(path == "sounds/missing.wav", "missing path diagnostic changed")
}

do {
    _ = try SoundAssetPlanCompiler.compile(
        objects: [[AuthoredPath(objectIndex: 0, pathIndex: nil, value: "../outside.wav")]],
        vfs: vfs
    )
    require(false, "unsafe authored path reached VFS lookup")
} catch VFSFailure.unsafe(let path) {
    require(path == "../outside.wav", "unsafe path diagnostic changed")
}

do {
    _ = try PackageVFS(entries: [
        Entry(rawPath: "sounds/A.wav", data: Data([1])),
        Entry(rawPath: "sounds/a.wav", data: Data([2]))
    ])
    require(false, "case-colliding package paths were accepted")
} catch VFSFailure.collision(let first, let second) {
    require(first == "sounds/A.wav" && second == "sounds/a.wav", "collision provenance changed")
}

print("PASS: authored WPE sound assets resolve atomically without scheduling guesses")
