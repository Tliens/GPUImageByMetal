/// 图片生成器，似乎没啥用，遇到再说
/// 纯色图片，这个用到了 SolidColorGenerator
public class ImageGenerator: ImageSource {
    public var size:Size

    public let targets = TargetContainer()
    var internalTexture:Texture!
    /// 初始化
    public init(size:Size) {
        self.size = size
        internalTexture = Texture(device:sharedMetalRenderingDevice.device, orientation:.portrait, width:Int(size.width), height:Int(size.height), timingStyle:.stillImage)
    }
    /// 把当前存在的纹理传给目标，atIndex表示指定，如：有新的target时
    public func transmitPreviousImage(to target:ImageConsumer, atIndex:UInt) {
        target.newTextureAvailable(internalTexture, fromSourceIndex:atIndex)
    }
    /// 通知其他的目标文件
    func notifyTargets() {
        updateTargetsWithTexture(internalTexture)
    }
}
