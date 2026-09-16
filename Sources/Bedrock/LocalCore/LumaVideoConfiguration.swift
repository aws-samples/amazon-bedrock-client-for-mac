import Foundation

struct LumaVideoConfiguration: Codable, Equatable, Sendable {
    var aspectRatio = "16:9"
    var duration = "5s"
    var resolution = "720p"
    var loop = false
    var outputBucket = ""

    static let aspectRatios = ["16:9", "9:16", "1:1", "4:3", "3:4", "21:9", "9:21"]
    static let durations = ["5s", "9s"]
    static let resolutions = ["540p", "720p"]

    func request(prompt: String, images: [String] = []) throws -> Data {
        guard (1...5_000).contains(prompt.count) else { throw LocalWorkbenchError.invalid("Use a video prompt between 1 and 5,000 characters.") }
        guard Self.aspectRatios.contains(aspectRatio), Self.durations.contains(duration), Self.resolutions.contains(resolution) else {
            throw LocalWorkbenchError.invalid("Reset the video response settings to supported values.")
        }
        guard images.count <= 2 else { throw LocalWorkbenchError.invalid("Luma accepts up to two keyframes: a start image and an end image.") }
        var body: [String: Any] = ["prompt": prompt, "aspect_ratio": aspectRatio,
                                   "duration": duration, "resolution": resolution, "loop": loop]
        if !images.isEmpty {
            var frames: [String: Any] = [:]
            for (index, image) in images.enumerated() {
                guard let data = Data(base64Encoded: image) else { throw LocalWorkbenchError.invalid("A video keyframe could not be decoded.") }
                let type: String
                if data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) { type = "image/png" }
                else if data.starts(with: [255, 216, 255]) { type = "image/jpeg" }
                else { throw LocalWorkbenchError.invalid("Video keyframes must be PNG or JPEG images.") }
                frames["frame\(index)"] = ["type": "image", "source": ["type": "base64", "media_type": type, "data": image]]
            }
            body["keyframes"] = frames
        }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
}
