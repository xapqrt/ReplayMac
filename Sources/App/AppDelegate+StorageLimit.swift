import Foundation
import Feedback
import UI

@MainActor
extension AppDelegate {
    /// Applies the storage cap after a save, off the main actor (it scans the
    /// output folder), and tells the user what was recycled.
    func enforceStorageLimitAfterSave() {
        guard AppSettings.storageLimitEnabled else { return }
        Task.detached(priority: .utility) {
            guard let plan = StorageLimitEnforcer.enforceIfNeeded() else { return }
            let freed = ByteCountFormatter.string(fromByteCount: plan.bytesFreed, countStyle: .file)
            let count = plan.toTrash.count
            await MainActor.run {
                var body = "Moved \(count) older \(count == 1 ? "clip" : "clips") (\(freed)) to the Trash to stay under the limit."
                if plan.bytesStillOver > 0 {
                    body += " Still over by \(ByteCountFormatter.string(fromByteCount: plan.bytesStillOver, countStyle: .file)): favorites and protected clips are not deleted."
                }
                NotificationManager.shared.showOperationalNotification(title: "Storage Limit Applied", body: body)
            }
        }
    }
}
