import Darwin
import Foundation

final class DocumentChangeMonitor {
    private var fileSource: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?

    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        let queue = DispatchQueue(label: "com.dualface.mdviewer.document-change-monitor")
        fileSource = Self.makeSource(
            path: url.path,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: queue,
            onChange: onChange
        )
        directorySource = Self.makeSource(
            path: url.deletingLastPathComponent().path,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: queue,
            onChange: onChange
        )
    }

    deinit {
        cancel()
    }

    func cancel() {
        fileSource?.cancel()
        fileSource = nil
        directorySource?.cancel()
        directorySource = nil
    }

    private static func makeSource(
        path: String,
        eventMask: DispatchSource.FileSystemEvent,
        queue: DispatchQueue,
        onChange: @escaping @Sendable () -> Void
    ) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            return nil
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: eventMask,
            queue: queue
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        return source
    }
}
