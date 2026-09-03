import Foundation

struct AuthoredSound: Equatable, Sendable {
    let objectIndex: Int
    let objectID: Int?
    let paths: [String]
    let volume: String?
    let minimumTime: String?
    let maximumTime: String?
}

enum SoundAdmissionError: Error, Equatable, Sendable {
    case invalidScene
    case unsupportedSoundShape(objectIndex: Int)
    case unrecoveredPlaybackSchedule([AuthoredSound])
}

enum SoundAdmission {
    static func compile(sceneData: Data) throws -> [AuthoredSound] {
        guard let root = try JSONSerialization.jsonObject(with: sceneData) as? [String: Any],
              let objects = root["objects"] as? [Any] else {
            throw SoundAdmissionError.invalidScene
        }

        var result: [AuthoredSound] = []
        for (objectIndex, rawObject) in objects.enumerated() {
            guard let object = rawObject as? [String: Any] else {
                throw SoundAdmissionError.invalidScene
            }
            guard let rawSound = object["sound"] else { continue }
            let paths: [String]
            if let path = rawSound as? String {
                paths = [path]
            } else if let values = rawSound as? [Any],
                      values.allSatisfy({ $0 is String }) {
                paths = values.map { $0 as! String }
            } else {
                throw SoundAdmissionError.unsupportedSoundShape(
                    objectIndex: objectIndex
                )
            }
            result.append(AuthoredSound(
                objectIndex: objectIndex,
                objectID: (object["id"] as? NSNumber)?.intValue,
                paths: paths,
                volume: exactNumber(object["volume"]),
                minimumTime: exactNumber(object["mintime"]),
                maximumTime: exactNumber(object["maxtime"])
            ))
        }
        return result
    }

    static func validateForExactProduct(_ sounds: [AuthoredSound]) throws {
        guard sounds.isEmpty else {
            throw SoundAdmissionError.unrecoveredPlaybackSchedule(sounds)
        }
    }

    private static func exactNumber(_ value: Any?) -> String? {
        guard let number = value as? NSNumber else { return nil }
        return number.stringValue
    }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let archiveAssets = ["sounds/unreferenced.wav"]
let noAuthoredSound = try SoundAdmission.compile(
    sceneData: Data(#"{"objects":[{"image":"models/a.json"}]}"#.utf8)
)
require(noAuthoredSound.isEmpty, "an unreferenced archive sound was selected")
require(archiveAssets.count == 1, "fixture did not retain the unreferenced asset")
try SoundAdmission.validateForExactProduct(noAuthoredSound)

let catLike = try SoundAdmission.compile(sceneData: Data(#"""
{"objects":[
  {"image":"models/a.json"},
  {"id":42,"sound":"sounds/cat.wav","volume":0.5,"mintime":1,"maxtime":5}
]}
"""#.utf8))
require(catLike.count == 1, "authored sound was not discovered")
require(catLike[0].objectIndex == 1, "object-array coordinate was compacted")
require(catLike[0].objectID == 42, "authored object id changed")
require(catLike[0].paths == ["sounds/cat.wav"], "authored path changed")
require(catLike[0].volume == "0.5", "authored volume changed")
require(catLike[0].minimumTime == "1", "authored mintime changed")
require(catLike[0].maximumTime == "5", "authored maxtime changed")
do {
    try SoundAdmission.validateForExactProduct(catLike)
    require(false, "unrecovered timed playback was admitted")
} catch SoundAdmissionError.unrecoveredPlaybackSchedule(let sounds) {
    require(sounds == catLike, "admission diagnostics lost authored data")
}

let multiple = try SoundAdmission.compile(sceneData: Data(#"""
{"objects":[
  {"sound":["sounds/a.wav","sounds/b.wav"]},
  {"name":"ordinary"},
  {"id":9,"sound":"sounds/c.wav","mintime":2}
]}
"""#.utf8))
require(multiple.map(\.objectIndex) == [0, 2], "sound object order changed")
require(multiple.map(\.paths) == [
    ["sounds/a.wav", "sounds/b.wav"],
    ["sounds/c.wav"]
], "sound path shape changed")

print("PASS: authored Scene sound admission remains lossless and fail-closed")
