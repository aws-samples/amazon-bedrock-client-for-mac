import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class ImagePreviewTests: XCTestCase {
    private func png(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testLargePreviewBoundsDecodedPixelsAndKeepsOriginalBytes() async throws {
        let data = try png(width: 4_096, height: 3_072)
        let worker = ImagePreviewLoader()
        let image = try await worker.load(.encoded(data), maximumPixelSize: 1_024)
        XCTAssertEqual(image.width, 4_096)
        XCTAssertEqual(image.height, 3_072)
        XCTAssertEqual(image.preview.width, 1_024)
        XCTAssertEqual(image.preview.height, 768)
        XCTAssertEqual(image.original, data)
        let copied = try await worker.export(image, as: .png)
        XCTAssertEqual(copied, data, "Copy/export must use original PNG bytes, not the downsampled preview.")
        let again = try await worker.load(.encoded(data), maximumPixelSize: 1_024)
        XCTAssertTrue(again === image, "Reopening should reuse the decoded preview.")
    }

    func testImageConversionAndSaveRetainFullResolution() async throws {
        let data = try png(width: 1_200, height: 900)
        let worker = ImagePreviewLoader()
        let image = try await worker.load(.encoded(data), maximumPixelSize: 480)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pngURL = folder.appendingPathComponent("original.png")
        let jpegURL = folder.appendingPathComponent("converted.jpg")
        try await worker.save(image, to: pngURL)
        XCTAssertEqual(try Data(contentsOf: pngURL), data)
        try await worker.save(image, to: jpegURL)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(jpegURL as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 1_200)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 900)
    }

    func testBulkExportKeepsOriginalBytesAndExistingFilesWithSafeUniqueNames() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = Data("User's existing file".utf8)
        let existing = folder.appendingPathComponent("photo.png")
        try original.write(to: existing)
        let first = try png(width: 120, height: 80)
        let second = try png(width: 80, height: 120)
        let exporter = AttachmentExporter()
        let result = try await exporter.save([
            .init(filename: "photo.gif", source: .encoded(first)),
            .init(filename: "photo.gif", source: .encoded(second)),
            .init(filename: "../../escape.jpeg", source: .encoded(first)),
            .init(filename: "corrupt.png", source: .encoded(Data("invalid".utf8)))
        ], to: folder)
        XCTAssertEqual(result.files.map(\.lastPathComponent), ["photo 2.png", "photo 3.png", "escape.png"])
        XCTAssertEqual(try Data(contentsOf: existing), original)
        XCTAssertEqual(try Data(contentsOf: result.files[0]), first)
        XCTAssertEqual(try Data(contentsOf: result.files[1]), second)
        XCTAssertTrue(result.files.allSatisfy { $0.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL })
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(result.failures[0].contains("corrupt.png"))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasPrefix(".bedrock-export-") })
    }

    func testStoredReferenceUsesExplicitDataDirectoryAndRejectsTraversal() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let reference = "img_\(UUID().uuidString)"
        let data = try png(width: 80, height: 60)
        try data.write(to: folder.appendingPathComponent(reference + ".png"))
        let worker = ImagePreviewLoader()
        let image = try await worker.load(.stored(reference, directory: folder))
        XCTAssertEqual(image.original, data)
        do {
            _ = try await worker.load(.stored("img_../../outside", directory: folder))
            XCTFail("An invalid reference must not access an arbitrary file.")
        } catch { }
    }

    func testCorruptAndCanceledImageLoadsFailWithoutCreatingAnImage() async throws {
        let worker = ImagePreviewLoader()
        do {
            _ = try await worker.load(.encoded(Data("not an image".utf8)))
            XCTFail("Corrupt bytes were accepted.")
        } catch { }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await worker.load(.encoded(Data()))
        }
        do {
            _ = try await task.value
            XCTFail("Canceled image loading completed.")
        } catch is CancellationError { }
    }

    @MainActor
    func testPreviewHasBoundedSheetGeometryBeforeDecoding() throws {
        _ = NSApplication.shared
        let view = NSHostingView(rootView: ImagePreviewModal(source: .encoded(try png(width: 32, height: 32)),
                                                             filename: "Image.png", isPresented: .constant(true)))
        let size = view.fittingSize
        XCTAssertGreaterThan(size.width, 300)
        XCTAssertGreaterThan(size.height, 300)
        XCTAssertLessThanOrEqual(size.width, 840)
        XCTAssertLessThanOrEqual(size.height, 640)
    }
}
