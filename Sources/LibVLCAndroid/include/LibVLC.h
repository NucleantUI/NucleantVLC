//
//  LibVLC.h
//  NucleantVLC
//
//  The LibVLC module on Android: the same umbrella as LibVLC.framework's on
//  Apple's platforms, so `import LibVLC` is one spelling everywhere.
//
//  include/vlc is the headers of the libvlc in the LibVLC-android-<abi>
//  artifact bundles — VLC's 3.0.x branch with libvlcjni's patches, made by
//  scripts/fetch_vlc_android.py and identical for every ABI. Update them
//  together with those bundles.
//

#include <vlc/vlc.h>
