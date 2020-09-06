//操作组
open class OperationGroup: ImageProcessingOperation {
    let inputImageRelay = ImageRelay()
    let outputImageRelay = ImageRelay()
    
    public var sources:SourceContainer { get { return inputImageRelay.sources } }
    public var targets:TargetContainer { get { return outputImageRelay.targets } }
    public let maximumInputs:UInt = 1
    
    public init() {
    }
    
    public func newTextureAvailable(_ texture:Texture, fromSourceIndex:UInt) {
        inputImageRelay.newTextureAvailable(texture, fromSourceIndex:fromSourceIndex)
    }
    
    public func configureGroup(_ configurationOperation:(_ input:ImageRelay, _ output:ImageRelay) -> ()) {
        configurationOperation(inputImageRelay, outputImageRelay)
    }
    /// 把当前存在的纹理传给目标，atIndex表示指定，如：有新的target时
    public func transmitPreviousImage(to target:ImageConsumer, atIndex:UInt) {
        outputImageRelay.transmitPreviousImage(to:target, atIndex:atIndex)
    }
}
