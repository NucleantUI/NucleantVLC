//
//  VlcInstance.swift
//  NucleantVLC
//
//  `libvlc_instance_t`: one libvlc — its plugins, its settings, its log.
//  Media and players are made from an instance; most apps need only the
//  shared one.
//

import Foundation
import LibVLC

/// What libvlc refused.
public enum VlcError: Error, Sendable, CustomStringConvertible {
    /// `libvlc_new` failed — usually its plugins were not found.
    case instanceFailed(String)
    /// A media could not be made for this location.
    case mediaFailed(String)

    public var description: String {
        switch self {
        case .instanceFailed(let message): "libvlc did not start: \(message)"
        case .mediaFailed(let location): "libvlc could not make a media for \(location)"
        }
    }

    /// libvlc's last error message on this thread.
    static var lastMessage: String {
        libvlc_errmsg().map { String(cString: $0) } ?? "no message"
    }
}

/// One libvlc.
///
/// ```swift
/// let instance = try VlcInstance(arguments: ["--no-video-title-show"])
/// let player = VlcMediaPlayer(instance: instance)
/// ```
///
/// `arguments` are VLC's command-line options. libvlc is thread-safe; an
/// instance can be used from anywhere.
public final class VlcInstance: @unchecked Sendable {

    let handle: OpaquePointer

    /// An instance for the whole app, made on first use — with the title VLC
    /// would otherwise draw over the start of every video turned off.
    public static let shared: VlcInstance = {
        do {
            return try VlcInstance(arguments: ["--no-video-title-show"])
        } catch {
            fatalError("NucleantVLC: \(error)")
        }
    }()

    public init(arguments: [String] = []) throws {
        Self.prepareEnvironment()
        let copies = arguments.map { strdup($0) }
        defer { copies.forEach { free($0) } }
        var argv = copies.map { UnsafePointer($0) }
        let made = argv.withUnsafeMutableBufferPointer { buffer in
            libvlc_new(Int32(buffer.count), buffer.baseAddress)
        }
        guard let made else { throw VlcError.instanceFailed(VlcError.lastMessage) }
        handle = made
    }

    deinit {
        libvlc_log_unset(handle)
        libvlc_release(handle)
        logHandler?.release()
    }

    /// libvlc's version, e.g. "3.0.24 Vetinari".
    public static var version: String { String(cString: libvlc_get_version()) }

    /// The compiler libvlc was built with.
    public static var compiler: String { String(cString: libvlc_get_compiler()) }

    /// libvlc's source revision.
    public static var changeset: String { String(cString: libvlc_get_changeset()) }

    /// The name and HTTP user agent libvlc gives network servers.
    public func setUserAgent(name: String, http: String) {
        libvlc_set_user_agent(handle, name, http)
    }

    /// The application's identity, for the system's media controls.
    public func setAppID(_ id: String, version: String, icon: String) {
        libvlc_set_app_id(handle, id, version, icon)
    }

    // MARK: - Log

    /// The box `libvlc_log_set`'s callback reaches the handler through.
    private final class LogHandler: @unchecked Sendable {
        let minimum: VlcLogLevel
        let handle: @Sendable (VlcLogLevel, String) -> Void
        init(minimum: VlcLogLevel, handle: @escaping @Sendable (VlcLogLevel, String) -> Void) {
            self.minimum = minimum
            self.handle = handle
        }
    }

    private var logHandler: Unmanaged<LogHandler>?

    /// Hand libvlc's log to `handler` — messages at `minimum` and above,
    /// already formatted — instead of the standard error. `nil` puts the
    /// standard error back. Called on libvlc's threads.
    public func setLogHandler(
        minimum: VlcLogLevel = .notice,
        _ handler: (@Sendable (VlcLogLevel, String) -> Void)?
    ) {
        // Unset first: libvlc_log_unset waits for a callback under way.
        libvlc_log_unset(handle)
        logHandler?.release()
        logHandler = nil
        guard let handler else { return }
        let box = Unmanaged.passRetained(LogHandler(minimum: minimum, handle: handler))
        logHandler = box
        libvlc_log_set(handle, { data, level, _, format, arguments in
            guard let data, let format, let arguments else { return }
            let handler = Unmanaged<LogHandler>.fromOpaque(data).takeUnretainedValue()
            let level = VlcLogLevel(rawValue: level) ?? .debug
            guard level >= handler.minimum else { return }
            var buffer = [CChar](repeating: 0, count: 1024)
            _ = buffer.withUnsafeMutableBufferPointer { vsnprintf($0.baseAddress, $0.count, format, arguments) }
            handler.handle(level, String(cString: buffer))
        }, box.toOpaque())
    }
}
