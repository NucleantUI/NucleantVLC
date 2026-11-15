//
//  VlcInstance+Android.swift
//  NucleantVLC
//
//  Where libvlc's plugins are on Android: built into libvlc.so itself
//  (Android loads no plugins at run time) — see scripts/fetch_vlc_android.py.
//  There is nothing to point libvlc at.
//

#if os(Android)
extension VlcInstance {

    /// Nothing to prepare: the plugins are in libvlc itself.
    static func prepareEnvironment() {}
}
#endif
