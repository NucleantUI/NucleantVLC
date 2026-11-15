# wrap libvlc in swift

for now just focus on macOS

# renake enum cases in swift
c enums always seems to be terrible to use in swift


```swift

public enum VLCEnum: Int32, CaseIterable {
    case setting1 = 23 // comment original next to it
}
```

# Protocol + Generics where it makes sense
DONT JUST MAKE A GENERAL CLASS / TYPE TO HANDLE EVERYTHING.. 
DONT TYPE ERASE GENERICS STUFF IT RUINS THE WHOKE PURPOSE


# ExternalTextureNode<NucleantRenderNode>
figure out how we can push video pixels most direct way to the View
not sure what vlc allows of playback directly to vulkan texture
going to be abit fucked up if we need to introduce another shadernode for this
soo first see what vlc can do with target existing VkImage..

```swift

public protocol VlcRemote: AnyObject {
    // for making Observable class to control what it should play, and general remote control
}

@View
public struct VlcView<Remote: VlcRemote> {
    let remote: Remote
}

@State var remote: MyVlcRemote = .init()

VlcView(remote: remote)
```


so ofc this should have nucleantui as dep

and adds extensions etc to NucleantUI


