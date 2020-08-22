import AVFoundation
/// 音频编码洗衣
public protocol AudioEncodingTarget {
    /// 激活音轨
    func activateAudioTrack()
    /// 处理音频buffer
    func processAudioBuffer(_ sampleBuffer:CMSampleBuffer)
}
/// 视频文件导出
public class MovieOutput: ImageConsumer, AudioEncodingTarget {
    /// 输入源或者中间层记录
    public let sources = SourceContainer()
    /// 输入数量
    public let maximumInputs:UInt = 1
    /// asset写入
    let assetWriter:AVAssetWriter
    /// 视频输入
    let assetWriterVideoInput:AVAssetWriterInput
    /// 音频输入
    var assetWriterAudioInput:AVAssetWriterInput?
    /// pixelbuffer 输入
    let assetWriterPixelBufferInput:AVAssetWriterInputPixelBufferAdaptor
    /// 画布大小
    let size:Size
    /// 是否在录制标志
    private var isRecording = false
    /// video编码结束
    private var videoEncodingIsFinished = false
    /// 音频编码结束
    private var audioEncodingIsFinished = false
    /// 开始时间
    private var startTime:CMTime?
    /// 上一视频帧的时间
    private var previousFrameTime = CMTime.negativeInfinity
    /// 上一音频帧的时间
    private var previousAudioTime = CMTime.negativeInfinity
    /// liveVideo编码中
    private var encodingLiveVideo:Bool
    /// pixelBuffer
    var pixelBuffer:CVPixelBuffer? = nil
    /// 渲染管线状态
    var renderPipelineState:MTLRenderPipelineState!
    /// 视频方向
    var transform:CGAffineTransform {
        get {
            return assetWriterVideoInput.transform
        }
        set {
            assetWriterVideoInput.transform = newValue
        }
    }
    
    public init(URL:Foundation.URL, size:Size, fileType:AVFileType = AVFileType.mov, liveVideo:Bool = false, settings:[String:AnyObject]? = nil) throws {
        self.size = size
        assetWriter = try AVAssetWriter(url:URL, fileType:fileType)
        // 设置此设置以确保即使在录制中途被切断，也能产生一个功能性的电影。在这种情况下，只应该错过最后一秒.
        assetWriter.movieFragmentInterval = CMTimeMakeWithSeconds(1.0, preferredTimescale: 1000)
        
        var localSettings:[String:AnyObject]
        if let settings = settings {
            localSettings = settings
        } else {
            localSettings = [String:AnyObject]()
        }
        
        localSettings[AVVideoWidthKey] = localSettings[AVVideoWidthKey] ?? NSNumber(value:size.width)
        localSettings[AVVideoHeightKey] = localSettings[AVVideoHeightKey] ?? NSNumber(value:size.height)
        localSettings[AVVideoCodecKey] =  localSettings[AVVideoCodecKey] ?? AVVideoCodecH264 as NSString
        
        assetWriterVideoInput = AVAssetWriterInput(mediaType:AVMediaType.video, outputSettings:localSettings)
        // 指示输入是否应针对实时源调整其对媒体数据的处理
        assetWriterVideoInput.expectsMediaDataInRealTime = liveVideo
        encodingLiveVideo = liveVideo
        // pixelbuffer 格式
        let sourcePixelBufferAttributesDictionary:[String:AnyObject] = [kCVPixelBufferPixelFormatTypeKey as String:NSNumber(value:Int32(kCVPixelFormatType_32BGRA)),
                                                                        kCVPixelBufferWidthKey as String:NSNumber(value:size.width),
                                                                        kCVPixelBufferHeightKey as String:NSNumber(value:size.height)]
        // 关联 assetWriterPixelBufferInput -- assetWriterVideoInput -- assetWriter
        assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:assetWriterVideoInput, sourcePixelBufferAttributes:sourcePixelBufferAttributesDictionary)
        assetWriter.add(assetWriterVideoInput)
        
        let (pipelineState, _) = generateRenderPipelineState(device:sharedMetalRenderingDevice, vertexFunctionName:"oneInputVertex", fragmentFunctionName:"passthroughFragment", operationName:"RenderView")
        self.renderPipelineState = pipelineState
    }
    
    /// 开始记录
    public func startRecording(transform:CGAffineTransform? = nil) {
        if let transform = transform {
            assetWriterVideoInput.transform = transform
        }
        startTime = nil
        self.isRecording = self.assetWriter.startWriting()
    }
    /// 结束记录
    public func finishRecording(_ completionCallback:(() -> Void)? = nil) {
        self.isRecording = false
        
        if (self.assetWriter.status == .completed || self.assetWriter.status == .cancelled || self.assetWriter.status == .unknown) {
            DispatchQueue.global().async{
                completionCallback?()
            }
            return
        }
        if ((self.assetWriter.status == .writing) && (!self.videoEncodingIsFinished)) {
            self.videoEncodingIsFinished = true
            self.assetWriterVideoInput.markAsFinished()
        }
        if ((self.assetWriter.status == .writing) && (!self.audioEncodingIsFinished)) {
            self.audioEncodingIsFinished = true
            self.assetWriterAudioInput?.markAsFinished()
        }
        
        // Why can't I use ?? here for the callback?
        if let callback = completionCallback {
            self.assetWriter.finishWriting(completionHandler: callback)
        } else {
            self.assetWriter.finishWriting{}
            
        }
    }
    
    public func newTextureAvailable(_ texture:Texture, fromSourceIndex:UInt) {
        guard isRecording else { return }
        // Ignore still images and other non-video updates (do I still need this?)
        guard let frameTime = texture.timingStyle.timestamp?.asCMTime else { return }
        // If two consecutive times with the same value are added to the movie, it aborts recording, so I bail on that case
        guard (frameTime != previousFrameTime) else { return }
        
        if (startTime == nil) {
            if (assetWriter.status != .writing) {
                assetWriter.startWriting()
            }
            // 为接收方启动一个示例编写会话
            assetWriter.startSession(atSourceTime: frameTime)
            startTime = frameTime
        }
        
        // TODO: Run the following on an internal movie recording dispatch queue, context
        guard (assetWriterVideoInput.isReadyForMoreMediaData || (!encodingLiveVideo)) else {
            debugPrint("Had to drop a frame at time \(frameTime)")
            return
        }
        
        var pixelBufferFromPool:CVPixelBuffer? = nil
        // Creates a new PixelBuffer object from the pool
        let pixelBufferStatus = CVPixelBufferPoolCreatePixelBuffer(nil, assetWriterPixelBufferInput.pixelBufferPool!, &pixelBufferFromPool)
        guard let pixelBuffer = pixelBufferFromPool, (pixelBufferStatus == kCVReturnSuccess) else { return }
        
        /// 纹理转pixelBuffer
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        renderIntoPixelBuffer(pixelBuffer, texture:texture)
        
        /// pixelBuffer添加到assetWriterPixelBufferInput中
        if (!assetWriterPixelBufferInput.append(pixelBuffer, withPresentationTime:frameTime)) {
            print("Problem appending pixel buffer at time: \(frameTime)")
        }
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
    }
    
    /// 把texture放到pixelBuffer
    /// - Parameters:
    ///   - pixelBuffer: CVPixelBufferPoolCreatePixelBuffer 得到的pixelBuffer
    ///   - texture: texture 传入的纹理
    func renderIntoPixelBuffer(_ pixelBuffer:CVPixelBuffer, texture:Texture) {
        guard let pixelBufferBytes = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            print("Could not get buffer bytes")
            return
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        let outputTexture:Texture
        if (Int(round(self.size.width)) != texture.texture.width) && (Int(round(self.size.height)) != texture.texture.height) {
            let commandBuffer = sharedMetalRenderingDevice.commandQueue.makeCommandBuffer()
            
            outputTexture = Texture(device:sharedMetalRenderingDevice.device, orientation: .portrait, width: Int(round(self.size.width)), height: Int(round(self.size.height)), timingStyle: texture.timingStyle)

            commandBuffer?.renderQuad(pipelineState: renderPipelineState, inputTextures: [0:texture], outputTexture: outputTexture)
            commandBuffer?.commit()
            commandBuffer?.waitUntilCompleted()
        } else {
            outputTexture = texture
        }
        
        let region = MTLRegionMake2D(0, 0, outputTexture.texture.width, outputTexture.texture.height)
        
        outputTexture.texture.getBytes(pixelBufferBytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
    }
    
    // MARK: -
    // MARK: Audio support
    /// 激活音轨
    public func activateAudioTrack() {
        // TODO: Add ability to set custom output settings
        assetWriterAudioInput = AVAssetWriterInput(mediaType:AVMediaType.audio, outputSettings:nil)
        assetWriter.add(assetWriterAudioInput!)
        assetWriterAudioInput?.expectsMediaDataInRealTime = encodingLiveVideo
    }
    /// 处理音频数据buffer
    public func processAudioBuffer(_ sampleBuffer:CMSampleBuffer) {
        guard let assetWriterAudioInput = assetWriterAudioInput else { return }
        
        let currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
        if (self.startTime == nil) {
            if (self.assetWriter.status != .writing) {
                self.assetWriter.startWriting()
            }
            
            self.assetWriter.startSession(atSourceTime: currentSampleTime)
            self.startTime = currentSampleTime
        }
        
        guard (assetWriterAudioInput.isReadyForMoreMediaData || (!self.encodingLiveVideo)) else {
            return
        }
        
        if (!assetWriterAudioInput.append(sampleBuffer)) {
            print("Trouble appending audio sample buffer")
        }
    }
}
