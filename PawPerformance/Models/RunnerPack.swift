import AppKit
import Foundation

struct RunnerPack: Identifiable {
    let id: String
    let name: String
    let speedMultiplier: Double
    let frameSize: CGSize
    let framesByState: [RunnerState: [NSImage]]
}

struct RunnerPackMetadata: Decodable {
    struct FrameSize: Decodable {
        let width: Int
        let height: Int
    }

    struct StateSpec: Decodable {
        let frames: Int
    }

    struct StateEntry: Decodable {
        let state: RunnerState
        let frames: Int
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case speedMultiplier
        case frameSize
        case states
    }

    let id: String
    let name: String
    let speedMultiplier: Double?
    let frameSize: FrameSize
    let states: [RunnerState: StateSpec]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        speedMultiplier = try container.decodeIfPresent(Double.self, forKey: .speedMultiplier)
        frameSize = try container.decode(FrameSize.self, forKey: .frameSize)

        if let keyedStates = try? container.decode([String: StateSpec].self, forKey: .states) {
            var mapped: [RunnerState: StateSpec] = [:]
            for (raw, spec) in keyedStates {
                if let state = RunnerState(rawValue: raw.lowercased()) {
                    mapped[state] = spec
                }
            }
            states = mapped
            return
        }

        let entries = try container.decode([StateEntry].self, forKey: .states)
        var mapped: [RunnerState: StateSpec] = [:]
        for entry in entries {
            mapped[entry.state] = StateSpec(frames: entry.frames)
        }
        states = mapped
    }
}
