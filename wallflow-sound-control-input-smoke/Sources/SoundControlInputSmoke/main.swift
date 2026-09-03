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

struct AuthoredSound: Equatable, Sendable {
    let playbackMode: StringField?
    let startSilent: BoolField?
    let mutedInEditor: BoolField?
}

struct ControlInputs: Equatable, Sendable {
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

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let literal = ControlCompiler.compile(
    sound: AuthoredSound(
        playbackMode: .literal("single"),
        startSilent: .literal(false),
        mutedInEditor: .literal(true)
    ),
    properties: [:]
)
require(literal.playbackMode == StringInput(rawValue: "single", source: .literal), "literal mode changed")
require(literal.startSilent == BoolInput(value: .authored(false), source: .literal), "literal startsilent changed")
require(literal.mutedInEditor == BoolInput(value: .authored(true), source: .literal), "literal editor mute changed")

let bound = AuthoredSound(
    playbackMode: .userBinding(StringBinding(propertyID: "mode", fallback: "multi")),
    startSilent: .userBinding(BoolBinding(propertyID: "silent", fallback: true)),
    mutedInEditor: .userBinding(BoolBinding(propertyID: "editorMute", fallback: false))
)
let fallback = ControlCompiler.compile(sound: bound, properties: [:])
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

let overridden = ControlCompiler.compile(
    sound: bound,
    properties: [
        "mode": "future-mode",
        "silent": "1",
        "editorMute": "OFF"
    ]
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

let missing = ControlCompiler.compile(
    sound: AuthoredSound(
        playbackMode: nil,
        startSilent: nil,
        mutedInEditor: nil
    ),
    properties: ["mode": "loop"]
)
require(missing == ControlInputs(
    playbackMode: nil,
    startSilent: nil,
    mutedInEditor: nil
), "missing authored controls gained defaults")

print("PASS: WPE sound mode/start/editor controls retain literal, fallback, and raw user-property identity")
