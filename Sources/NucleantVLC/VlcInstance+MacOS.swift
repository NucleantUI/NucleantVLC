//
//  VlcInstance+MacOS.swift
//  NucleantVLC
//
//  Where libvlc's plugins are on macOS: inside LibVLC.framework, next to
//  libvlc itself (Versions/A/plugins, Versions/A/share) — see
//  scripts/fetch_vlc.py.
//

#if os(macOS)
import Darwin
import LibVLC

extension VlcInstance {

    /// Point libvlc at the framework's plugins and lua scripts, before the
    /// first instance is made — unless the environment names others already.
    static func prepareEnvironment() {
        _ = environmentPrepared
    }

    private static let environmentPrepared: Bool = {
        let entry: @convention(c) (Int32, UnsafePointer<UnsafePointer<CChar>?>?) -> OpaquePointer? = libvlc_new
        var info = Dl_info()
        guard dladdr(unsafeBitCast(entry, to: UnsafeRawPointer.self), &info) != 0, let binary = info.dli_fname else {
            return false
        }
        // …/LibVLC.framework/Versions/A/LibVLC
        var directory = String(cString: binary)
        if let slash = directory.lastIndex(of: "/") {
            directory = String(directory[..<slash])
        }
        setenv("VLC_PLUGIN_PATH", directory + "/plugins", 0)
        setenv("VLC_DATA_PATH", directory + "/share", 0)
        return true
    }()
}
#endif
