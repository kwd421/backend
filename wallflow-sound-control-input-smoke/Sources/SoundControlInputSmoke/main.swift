import Foundation

enum InputSource: Equatable, Sendable {
    case literal
    case authoredFallback(propertyID: String)
    case userProperty(propertyID: String)
}

struct StringBinding: Equatable, Sendable {
    let propertyID: String
    let fallback: String
}

enum StringField: Equatable, Sendable {
    case literal(String)
    case userBinding(StringBinding)
}

struct BoolBinding: Equatable, Sendable {
    let propertyID: String
    let fallback: Bool
}

enum BoolField: Equatable, Sendable {
    case literal(Bool)
    case userBinding(BoolBinding)
}

struct StringInput: Equatable, Sendable {
    let rawValue: String
    let source: InputSource
}

enum BoolInputValue: Equatable, Sendable {
    case authored(Bool)
    case userPropertyRaw(String)
}

struct BoolInput: Equatable, Sendable {
    let value: BoolInputValue
    let source: InputSource
}

struct SoundReference: Hashable, Sendable {
    let objectIndex: Int
}

struct AuthoredSound: Equatable, Sendable {
    let reference: SoundReference
    let playbackMode: StringField?
    let startSilent: BoolField?
    let mutedInEditor: BoolField?
}

struct ControlInputs: Equatable, Sendable {
    let reference: SoundReference
    let playbackMode: StringInput?
    let startSilent: BoolInput?
    let mutedInEditor: BoolInput?
}

enum ControlCompiler {
    static func compile(
        sound: AuthoredSound,
        properties: [String: String]
    ) -> ControlInputs {
        ControlInputs(
            reference: sound.reference,
            playbackMode: sound.playbackMode.map {
                resolve($0, properties: properties)
            },
            startSilent: sound.startSilent.map {
                resolve($0, properties: properties)
            },
            mutedInEditor: sound.mutedInEditor.map {
                resolve($0, properties: properties)
            }
        )
    }

    private static func resolve(
        _ field: StringField,
        properties: [String: String]
    ) -> StringInput {
        switch field {
        case .literal(let value):
            return StringInput(rawValue: value, source: .literal)
        case .userBinding(let binding):
            if let raw = properties[binding.propertyID] {
                return StringInput(
                    rawValue: raw,
                    source: .userProperty(propertyID: binding.propertyID)
                )
            }
            return StringInput(
                rawValue: binding.fallback,
                source: .authoredFallback(propertyID: binding.propertyID)
            )
        }
    }

    private static func resolve(
        _ field: BoolField,
        properties: [String: String]
    ) -> BoolInput {
        switch field {
        case .literal(let value):
            return BoolInput(value: .authored(value), source: .literal)
        case .userBinding(let binding):
            if let raw = properties[binding.propertyID] {
                return BoolInput(
                    value: .userPropertyRaw(raw),
                    source: .userProperty(propertyID: binding.propertyID)
                )
            }
            return BoolInput(
                value: .authored(binding.fallback),
                source: .authoredFallback(propertyID: binding.propertyID)
            )
        }
    }
}

struct ResolvedAsset: Equatable, Sendable {
    let reference: SoundReference
    let authoredPathIndex: Int
    let rawPath: String
    let bytes: [UInt8]
}

struct ResolvedSoundObject: Equatable, Sendable {
    let sound: AuthoredSound
    let assets: [ResolvedAsset]
}

struct SchedulerInputObject: Equatable, Sendable {
    let sound: AuthoredSound
    let assets: [ResolvedAsset]
    let controls: ControlInputs
}

struct SchedulerInputPlan: Equatable, Sendable {
    let packageHash: String
    let objects: [SchedulerInputObject]
}

enum SchedulerInputError: Error, Equatable, Sendable {
    case duplicateAssetObject(SoundReference)
    case duplicateControlObject(SoundReference)
    case missingControlObject(SoundReference)
    case extraControlObject(SoundReference)
}

enum SchedulerInputCompiler {
    static func compile(
        packageHash: String,
        resolvedObjects: [ResolvedSoundObject],
        properties: [String: String]
    ) throws -> SchedulerInputPlan {
        var controls: [SoundReference: ControlInputs] = [:]
        for object in resolvedObjects {
            let input = ControlCompiler.compile(
                sound: object.sound,
                properties: properties
            )
            guard controls.updateValue(input, forKey: input.reference) == nil else {
                throw SchedulerInputError.duplicateControlObject(input.reference)
            }
        }

        var seen: Set<SoundReference> = []
        let objects = try resolvedObjects.map { object in
            let reference = object.sound.reference
            guard seen.insert(reference).inserted else {
                throw SchedulerInputError.duplicateAssetObject(reference)
            }
            guard let input = controls.removeValue(forKey: reference) else {
                throw SchedulerInputError.missingControlObject(reference)
            }
            return SchedulerInputObject(
                sound: object.sound,
                assets: object.assets,
                controls: input
            )
        }
        if let extra = controls.keys.sorted(
            by: { $0.objectIndex < $1.objectIndex }
        ).first {
            throw SchedulerInputError.extraControlObject(extra)
        }
        return SchedulerInputPlan(
            packageHash: packageHash,
            objects: objects
        )
    }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let literalSound = AuthoredSound(
    reference: SoundReference(objectIndex: 0),
    playbackMode: .literal("single"),
    startSilent: .literal(false),
    mutedInEditor: .literal(true)
)
let literal = ControlCompiler.compile(
    sound: literalSound,
    properties: [:]
)
require(literal.playbackMode == StringInput(rawValue: "single", source: .literal), "literal mode changed")
require(literal.startSilent == BoolInput(value: .authored(false), source: .literal), "literal startsilent changed")
require(literal.mutedInEditor == BoolInput(value: .authored(true), source: .literal), "literal editor mute changed")

let boundSound = AuthoredSound(
    reference: SoundReference(objectIndex: 2),
    playbackMode: .userBinding(StringBinding(propertyID: "mode", fallback: "multi")),
    startSilent: .userBinding(BoolBinding(propertyID: "silent", fallback: true)),
    mutedInEditor: .userBinding(BoolBinding(propertyID: "editorMute", fallback: false))
)
let fallback = ControlCompiler.compile(sound: boundSound, properties: [:])
require(fallback.playbackMode == StringInput(
    rawValue: "multi",
    source: .authoredFallback(propertyID: "mode")
), "mode fallback changed")
require(fallback.startSilent == BoolInput(
    value: .authored(true),
    source: .authoredFallback(propertyID: "silent")
), "startsilent fallback changed")
require(fallback.mutedInEditor == BoolInput(
    value: .authored(false),
    source: .authoredFallback(propertyID: "editorMute")
), "editor mute fallback changed")

let properties = [
    "mode": "future-mode",
    "silent": "1",
    "editorMute": "OFF"
]
let overridden = ControlCompiler.compile(
    sound: boundSound,
    properties: properties
)
require(overridden.playbackMode == StringInput(
    rawValue: "future-mode",
    source: .userProperty(propertyID: "mode")
), "user mode was normalized")
require(overridden.startSilent == BoolInput(
    value: .userPropertyRaw("1"),
    source: .userProperty(propertyID: "silent")
), "user startsilent was coerced")
require(overridden.mutedInEditor == BoolInput(
    value: .userPropertyRaw("OFF"),
    source: .userProperty(propertyID: "editorMute")
), "user editor mute was coerced")

let missingSound = AuthoredSound(
    reference: SoundReference(objectIndex: 4),
    playbackMode: nil,
    startSilent: nil,
    mutedInEditor: nil
)
let missing = ControlCompiler.compile(
    sound: missingSound,
    properties: ["mode": "loop"]
)
require(missing == ControlInputs(
    reference: missingSound.reference,
    playbackMode: nil,
    startSilent: nil,
    mutedInEditor: nil
), "missing authored controls gained defaults")

let plan = try SchedulerInputCompiler.compile(
    packageHash: "package-sha256",
    resolvedObjects: [
        ResolvedSoundObject(
            sound: literalSound,
            assets: [
                ResolvedAsset(
                    reference: literalSound.reference,
                    authoredPathIndex: 0,
                    rawPath: "sounds/a.wav",
                    bytes: [1, 2, 3]
                ),
                ResolvedAsset(
                    reference: literalSound.reference,
                    authoredPathIndex: 1,
                    rawPath: "sounds/a.wav",
                    bytes: [1, 2, 3]
                )
            ]
        ),
        ResolvedSoundObject(
            sound: boundSound,
            assets: [
                ResolvedAsset(
                    reference: boundSound.reference,
                    authoredPathIndex: 0,
                    rawPath: "sounds/b.wav",
                    bytes: [4, 5]
                )
            ]
        )
    ],
    properties: properties
)
require(plan.packageHash == "package-sha256", "package identity changed")
require(plan.objects.map { $0.sound.reference.objectIndex } == [0, 2], "object order changed")
require(plan.objects[0].assets.map(\.rawPath) == ["sounds/a.wav", "sounds/a.wav"], "duplicate authored path was compacted")
require(plan.objects[1].controls == overridden, "controls were re-resolved after joining")

let duplicateReference = SoundReference(objectIndex: 9)
do {
    _ = try SchedulerInputCompiler.compile(
        packageHash: "package-sha256",
        resolvedObjects: [
            ResolvedSoundObject(
                sound: AuthoredSound(
                    reference: duplicateReference,
                    playbackMode: nil,
                    startSilent: nil,
                    mutedInEditor: nil
                ),
                assets: []
            ),
            ResolvedSoundObject(
                sound: AuthoredSound(
                    reference: duplicateReference,
                    playbackMode: .literal("single"),
                    startSilent: nil,
                    mutedInEditor: nil
                ),
                assets: []
            )
        ],
        properties: [:]
    )
    require(false, "duplicate scheduler object identity was accepted")
} catch SchedulerInputError.duplicateControlObject(let reference) {
    require(reference == duplicateReference, "duplicate diagnostics changed identity")
}

print("PASS: WPE sound assets and literal/fallback/raw controls join atomically by authored object identity")
