import Foundation
import UIKit

/// Avatar bytes stay on this phone, named by the baby id. Cancel never calls save.
enum BabyAvatarStore {
    static func url(for id: UUID) -> URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BabyAvatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(id.uuidString + ".jpg")
    }

    static func image(for id: UUID) -> UIImage? {
        let file = url(for: id)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return UIImage(data: data)
    }

    static func save(_ image: UIImage, for id: UUID) {
        let scaled = image.preparingThumbnail(of: CGSize(width: 256, height: 256)) ?? image
        guard let data = scaled.jpegData(compressionQuality: 0.7) else { return }
        try? data.write(to: url(for: id), options: .atomic)
    }

    static func remove(id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }
}
