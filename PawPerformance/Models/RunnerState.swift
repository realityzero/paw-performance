import Foundation

enum RunnerState: String, CaseIterable, Codable {
    case idle
    case trot
    case sprint
    case panic
}
