import Foundation

struct PendingImport: Codable {
    let id: String
    let fileRelativePath: String  // relative to app group container
    let fileExtension: String
    let isAudio: Bool
    let collectionId: String
    let collectionName: String
    let itemId: String
    let itemName: String
    let importedAt: Date
}
