import AppKit
import Foundation

/// A compound mobility set: one rep = center → A → center → B → center (wellness only).
struct NeckExercise: Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String
    let targetReps: Int
    let motion: ExerciseMotionKind
    let firstImageName: String
    let secondImageName: String
    let centerImageName: String

    static let catalog: [NeckExercise] = [
        .init(
            id: "look",
            title: "Look Down & Up",
            summary: "Center → down → center → up → center",
            targetReps: 4,
            motion: .vertical,
            firstImageName: "look-down",
            secondImageName: "look-up",
            centerImageName: "look-center"
        ),
        .init(
            id: "tilt",
            title: "Tilt Left & Right",
            summary: "Center → left → center → right → center",
            targetReps: 4,
            motion: .tilt,
            firstImageName: "tilt-left",
            secondImageName: "tilt-right",
            centerImageName: "tilt-center"
        ),
        .init(
            id: "turn",
            title: "Turn Left & Right",
            summary: "Center → left → center → right → center",
            targetReps: 4,
            motion: .turn,
            firstImageName: "turn-left",
            secondImageName: "turn-right",
            centerImageName: "turn-center"
        ),
    ]

    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 16
        return cache
    }()

    /// Cached load — never re-read PNG from disk on every SwiftUI frame.
    static func image(named name: String) -> NSImage? {
        let key = name as NSString
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        let loaded: NSImage?
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "exercises") {
            loaded = NSImage(contentsOf: url)
        } else if let url = Bundle.main.url(forResource: name, withExtension: "png") {
            loaded = NSImage(contentsOf: url)
        } else {
            loaded = NSImage(named: name)
        }
        if let loaded {
            imageCache.setObject(loaded, forKey: key)
        }
        return loaded
    }
}

enum NeckExerciseNotification {
    static let categoryID = "avert.neckExercises"
    static let actionOpen = "OPEN_EXERCISES"
    static let requestID = "avert.neckExercises.repeating"
    static let userInfoKey = "avert.action"
    static let userInfoOpen = "openNeckExercises"
}
