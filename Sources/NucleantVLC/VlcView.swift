//
//  VlcView.swift
//  NucleantVLC
//
//  A libvlc player's video as a NucleantUI view.
//

import NucleantUI

/// Shows the video of `remote`'s player.
///
/// ```swift
/// @State var remote = MyVlcRemote()
///
/// VlcView(remote: remote)
///     .frame(width: 960, height: 540)
/// ```
///
/// Built on `TextureView`: every frame libvlc decodes is fitted to the
/// view's own pixel size, the video's shape kept and the rest black, and
/// copied GPU to GPU into the view's texture as it arrives — nothing in the
/// view tree rebuilds for the video to play. It takes the space it is
/// offered; black until the first frame.
@View
public struct VlcView<Remote: VlcRemote> {
    let remote: Remote

    public init(remote: Remote, _viewID: ViewID = #viewID) {
        self.remote = remote
        self._viewID = _viewID
    }

    public var body: some View {
        TextureView(source: remote)
            .background(Color.black)
    }
}
