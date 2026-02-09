import Foundation

@Observable
@MainActor
final class FileWatcherService {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private(set) var lastChangeDate: Date?

    var onFilesChanged: (() -> Void)?

    private let ignoreDirs = Set([".git", "node_modules", ".venv", "__pycache__", ".build", ".next", "dist", "build"])

    func startWatching(path: String) {
        stopWatching()

        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .link],
            queue: .global(qos: .utility)
        )

        source?.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.lastChangeDate = Date()
                self?.onFilesChanged?()
            }
        }

        source?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
        }

        source?.resume()
    }

    func stopWatching() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    nonisolated deinit {
        // Cleanup handled by stopWatching() calls
    }
}
