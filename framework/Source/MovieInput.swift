import AVFoundation
import Metal
/// 视频输入，视频源，处理视频使用，是一个大类
public class MovieInput: ImageSource {
    /// 目标容器
    public let targets = TargetContainer()
    /// 是否运行基准
    public var runBenchmark = false
    /// 视频纹理缓存
    var videoTextureCache: CVMetalTextureCache?
    /// yuv转换渲染管线
    let yuvConversionRenderPipelineState:MTLRenderPipelineState
    /// yuv渲染信息记录
    var yuvLookupTable:[String:(Int, MTLDataType)] = [:]
    /// 音视频资源
    let asset:AVAsset
    /// 音视频资源读取操作员
    let assetReader:AVAssetReader
    /// 是否用真是速度播放，（—导出视频时为false，播放时为true）
    let playAtActualSpeed:Bool
    /// 循环播放吗？
    let loop:Bool
    /// 视频编码是否完成
    var videoEncodingIsFinished = false
    /// 之前的帧时长
    var previousFrameTime = CMTime.zero
    /// 之前的真实帧时长
    var previousActualFrameTime = CFAbsoluteTimeGetCurrent()
    /// 采集的帧数
    var numberOfFramesCaptured = 0
    /// 采集的帧数所需所有时长
    var totalFrameTimeDuringCapture:Double = 0.0

    // TODO: Add movie reader synchronization
    // TODO: Someone will have to add back in the AVPlayerItem logic, because I don't know how that works
    
    /// 初始化操作
    /// - Parameters:
    ///   - asset: 音视频资源
    ///   - playAtActualSpeed: 真实速度播放？
    ///   - loop: 循环吗？
    /// - Throws: 错误信息
    public init(asset:AVAsset, playAtActualSpeed:Bool = false, loop:Bool = false) throws {
        self.asset = asset
        self.playAtActualSpeed = playAtActualSpeed
        self.loop = loop
        let (pipelineState, lookupTable) = generateRenderPipelineState(device:sharedMetalRenderingDevice, vertexFunctionName:"twoInputVertex", fragmentFunctionName:"yuvConversionFullRangeFragment", operationName:"YUVToRGB")
        self.yuvConversionRenderPipelineState = pipelineState
        self.yuvLookupTable = lookupTable
        let _ = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, sharedMetalRenderingDevice.device, nil, &videoTextureCache)

        assetReader = try AVAssetReader(asset:self.asset)
        
        let outputSettings:[String:Any] = [kCVPixelBufferMetalCompatibilityKey as String: true,
                                                 (kCVPixelBufferPixelFormatTypeKey as String):NSNumber(value:Int32(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange))]
        let readerVideoTrackOutput = AVAssetReaderTrackOutput(track:self.asset.tracks(withMediaType: AVMediaType.video)[0], outputSettings:outputSettings)
        readerVideoTrackOutput.alwaysCopiesSampleData = false
        assetReader.add(readerVideoTrackOutput)
        // TODO: Audio here
    }
    
    /// 便捷初始化操作
    /// - Parameters:
    ///   - url: 资源url路径
    ///   - playAtActualSpeed: 真实速度播放
    ///   - loop: 是否循环
    /// - Throws: 初始化错误信息
    public convenience init(url:URL, playAtActualSpeed:Bool = false, loop:Bool = false) throws {
        let inputOptions = [AVURLAssetPreferPreciseDurationAndTimingKey:NSNumber(value:true)]
        let inputAsset = AVURLAsset(url:url, options:inputOptions)
        try self.init(asset:inputAsset, playAtActualSpeed:playAtActualSpeed, loop:loop)
    }

    // MARK: -
    // MARK: Playback control
    /// 开始处理，循环取帧，用了do while循环
    /// 作者还没有完善loop情况
    public func start() {
        asset.loadValuesAsynchronously(forKeys:["tracks"], completionHandler:{
            DispatchQueue.global().async(execute: {
                guard (self.asset.statusOfValue(forKey: "tracks", error:nil) == .loaded) else { return }

                guard self.assetReader.startReading() else {
                    print("Couldn't start reading")
                    return
                }
                
                var readerVideoTrackOutput:AVAssetReaderOutput? = nil;
                
                for output in self.assetReader.outputs {
                    if(output.mediaType == AVMediaType.video) {
                        readerVideoTrackOutput = output;
                    }
                }
                
                while (self.assetReader.status == .reading) {
                    self.readNextVideoFrame(from:readerVideoTrackOutput!)
                }
                
                if (self.assetReader.status == .completed) {
                    self.assetReader.cancelReading()
                    
                    if (self.loop) {
                        // TODO: Restart movie processing
                    } else {
                        self.endProcessing()
                    }
                }
            })
        })
    }
    /// 取消
    public func cancel() {
        assetReader.cancelReading()
        self.endProcessing()
    }
    /// 结束 作者还没写，我的天，GPUImage3 我感觉遥遥无期了
    func endProcessing() {
        
    }
    
    // MARK: -
    // MARK: Internal processing functions
    
    /// 读帧，要是按照实际速度，就休眠
    /// - Parameter videoTrackOutput: 视频轨道输出
    func readNextVideoFrame(from videoTrackOutput:AVAssetReaderOutput) {
        if ((assetReader.status == .reading) && !videoEncodingIsFinished) {
            if let sampleBuffer = videoTrackOutput.copyNextSampleBuffer() {
                if (playAtActualSpeed) {
                    // Do this outside of the video processing queue to not slow that down while waiting
                    let currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
                    let differenceFromLastFrame = CMTimeSubtract(currentSampleTime, previousFrameTime)
                    let currentActualTime = CFAbsoluteTimeGetCurrent()
                    
                    let frameTimeDifference = CMTimeGetSeconds(differenceFromLastFrame)
                    let actualTimeDifference = currentActualTime - previousActualFrameTime
                    
                    if (frameTimeDifference > actualTimeDifference) {
                        usleep(UInt32(round(1000000.0 * (frameTimeDifference - actualTimeDifference))))
                    }
                    
                    previousFrameTime = currentSampleTime
                    previousActualFrameTime = CFAbsoluteTimeGetCurrent()
                }

//                sharedImageProcessingContext.runOperationSynchronously{
                    self.process(movieFrame:sampleBuffer)
                    CMSampleBufferInvalidate(sampleBuffer)
//                }
            } else {
                if (!loop) {
                    videoEncodingIsFinished = true
                    if (videoEncodingIsFinished) {
                        self.endProcessing()
                    }
                }
            }
        }
//        else if (synchronizedMovieWriter != nil) {
//            if (assetReader.status == .Completed) {
//                self.endProcessing()
//            }
//        }

    }
    
    /// 处理 CMSampleBuffer
    /// - Parameter frame: CMSampleBuffer
    func process(movieFrame frame:CMSampleBuffer) {
        let currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(frame)
        let movieFrame = CMSampleBufferGetImageBuffer(frame)!
    
//        processingFrameTime = currentSampleTime
        self.process(movieFrame:movieFrame, withSampleTime:currentSampleTime)
    }
    
    /// 处理 CVPixelBuffer，然后给目标容器，让其更新纹理
    /// - Parameters:
    ///   - movieFrame: 视频帧
    ///   - withSampleTime: 时间戳
    func process(movieFrame:CVPixelBuffer, withSampleTime:CMTime) {
        let bufferHeight = CVPixelBufferGetHeight(movieFrame)
        let bufferWidth = CVPixelBufferGetWidth(movieFrame)
        CVPixelBufferLockBaseAddress(movieFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))

        let conversionMatrix = colorConversionMatrix601FullRangeDefault
        // TODO: Get this color query working
//        if let colorAttachments = CVBufferGetAttachment(movieFrame, kCVImageBufferYCbCrMatrixKey, nil) {
//            if(CFStringCompare(colorAttachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == .EqualTo) {
//                _preferredConversion = kColorConversion601FullRange
//            } else {
//                _preferredConversion = kColorConversion709
//            }
//        } else {
//            _preferredConversion = kColorConversion601FullRange
//        }
        
        let startTime = CFAbsoluteTimeGetCurrent()

        let texture:Texture?
        var luminanceTextureRef:CVMetalTexture? = nil
        var chrominanceTextureRef:CVMetalTexture? = nil
        // Luminance plane
        let _ = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, self.videoTextureCache!, movieFrame, nil, .r8Unorm, bufferWidth, bufferHeight, 0, &luminanceTextureRef)
        // Chrominance plane
        let _ = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, self.videoTextureCache!, movieFrame, nil, .rg8Unorm, bufferWidth / 2, bufferHeight / 2, 1, &chrominanceTextureRef)
        
        if let concreteLuminanceTextureRef = luminanceTextureRef, let concreteChrominanceTextureRef = chrominanceTextureRef,
            let luminanceTexture = CVMetalTextureGetTexture(concreteLuminanceTextureRef), let chrominanceTexture = CVMetalTextureGetTexture(concreteChrominanceTextureRef) {
            let outputTexture = Texture(device:sharedMetalRenderingDevice.device, orientation:.portrait, width:bufferWidth, height:bufferHeight, timingStyle:.videoFrame(timestamp:Timestamp(withSampleTime)))
            
            convertYUVToRGB(pipelineState:self.yuvConversionRenderPipelineState, lookupTable:self.yuvLookupTable,
                            luminanceTexture:Texture(orientation:.portrait, texture:luminanceTexture),
                            chrominanceTexture:Texture(orientation:.portrait, texture:chrominanceTexture),
                            resultTexture:outputTexture, colorConversionMatrix:conversionMatrix)
            texture = outputTexture
        } else {
            texture = nil
        }
        

        CVPixelBufferUnlockBaseAddress(movieFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))

        if texture != nil {
            self.updateTargetsWithTexture(texture!)
        }
        
        if self.runBenchmark {
            let currentFrameTime = (CFAbsoluteTimeGetCurrent() - startTime)
            self.numberOfFramesCaptured += 1
            self.totalFrameTimeDuringCapture += currentFrameTime
            print("Average frame time : \(1000.0 * self.totalFrameTimeDuringCapture / Double(self.numberOfFramesCaptured)) ms")
            print("Current frame time : \(1000.0 * currentFrameTime) ms")
        }
    }
    /// 把当前存在的纹理传给目标，atIndex表示指定，如：有新的target时
    public func transmitPreviousImage(to target:ImageConsumer, atIndex:UInt) {
        // Not needed for movie inputs
    }
}
/// extension 别瞎放，放到一起吧，不然以后懵逼
public extension Timestamp {
    init(_ time:CMTime) {
        self.value = time.value
        self.timescale = time.timescale
        self.flags = TimestampFlags(rawValue:time.flags.rawValue)
        self.epoch = time.epoch
    }
    
    var asCMTime:CMTime {
        get {
            return CMTimeMakeWithEpoch(value: value, timescale: timescale, epoch: epoch)
        }
    }
}
