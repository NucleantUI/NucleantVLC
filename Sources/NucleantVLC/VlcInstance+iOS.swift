//
//  VlcInstance+iOS.swift
//  NucleantVLC
//
//  Where libvlc's plugins are on iOS: built into LibVLC.framework's binary
//  (iOS loads no plugins at run time) — see scripts/fetch_vlc.py. There is
//  nothing to point libvlc at.
//

#if os(iOS)
extension VlcInstance {

    /// Nothing to prepare: the plugins are in libvlc itself.
    static func prepareEnvironment() {}
}
#endif
