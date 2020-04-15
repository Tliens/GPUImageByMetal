import Foundation
import AVFoundation
import Metal
/// 相机原始数据回调
public protocol CameraDelegate {
    func didCaptureBuffer(_ sampleBuffer: CMSampleBuffer)
}
/// 前后置枚举
public enum PhysicalCameraLocation {
    case backFacing
    case frontFacing
    
    /// 根据摄像头返回图像方向
    /// - Returns: 图像方向
    func imageOrientation() -> ImageOrientation {
        switch self {
            case .backFacing: return .landscapeRight
#if os(iOS)
            case .frontFacing: return .landscapeLeft
#else
            case .frontFacing: return .portrait
#endif
        }
    }
    /// 获取摄像头位置
    func captureDevicePosition() -> AVCaptureDevice.Position {
        switch self {
        case .backFacing: return .back
        case .frontFacing: return .front
        }
    }
    /// 获取设备
    func device() -> AVCaptureDevice? {
        let devices = AVCaptureDevice.devices(for:AVMediaType.video)
        for case let device in devices {
            if (device.position == self.captureDevicePosition()) {
                return device
            }
        }
        
        return AVCaptureDevice.default(for: AVMediaType.video)
    }
}

public struct CameraError: Error {
}
/// 初始化忽略基准帧数
let initialBenchmarkFramesToIgnore = 5

/// Camera 滤镜链上的输入，在Swift中，我建议代理用extension来做，看起来更清晰
public class Camera: NSObject, ImageSource, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// 前后置摄像头
    public var location:PhysicalCameraLocation {
        didSet {
            // TODO: Swap the camera locations, framebuffers as needed
        }
    }
    /// 是否运行基准
    public var runBenchmark:Bool = false
    /// 是否输出FPS
    public var logFPS:Bool = false
    /// 目标输出容器
    public let targets = TargetContainer()
    /// 纹理输出代理
    public var delegate: CameraDelegate?
    /// 音视频采集会话
    public let captureSession:AVCaptureSession
    /// 图片方向
    public var orientation:ImageOrientation?
    /// 摄像头设备
    public let inputCamera:AVCaptureDevice!
    /// 视频输入
    let videoInput:AVCaptureDeviceInput!
    /// 视频输出
    let videoOutput:AVCaptureVideoDataOutput!
    /// 视频纹理缓存
    var videoTextureCache: CVMetalTextureCache?
    /// 是否支持YUV
    var supportsFullYUVRange:Bool = false
    /// 是否采集YUV格式
    let captureAsYUV:Bool
    /// yuv转换渲染管线
    let yuvConversionRenderPipelineState:MTLRenderPipelineState?
    /// yuv渲染信息记录
    var yuvLookupTable:[String:(Int, MTLDataType)] = [:]
    /// 用于帧渲染的信号量（锁）
    let frameRenderingSemaphore = DispatchSemaphore(value:1)
    /// 相机处理队列，全局并发队列
    let cameraProcessingQueue = DispatchQueue.global()
    /// 相机帧处理队列，串行队列
    let cameraFrameProcessingQueue = DispatchQueue(
        label: "com.sunsetlakesoftware.GPUImage.cameraFrameProcessingQueue",
        attributes: [])
    /// 允许掉帧数量
    let framesToIgnore = 5
    /// 帧数采集数量
    var numberOfFramesCaptured = 0
    /// 所有的帧采集时长
    var totalFrameTimeDuringCapture:Double = 0.0
    /// 上一次监测的帧数
    var framesSinceLastCheck = 0
    /// 上一次监测的时间
    var lastCheckTime = CFAbsoluteTimeGetCurrent()
    
    /// 初始化camera
    /// - Parameters:
    ///   - sessionPreset: 音视频采集会话
    ///   - cameraDevice: 音视频采集设备
    ///   - location: 摄像头位置
    ///   - orientation: 图像方向
    ///   - captureAsYUV: 是否按照YUV数据采集
    /// - Throws: 初始化错误信息
    public init(sessionPreset:AVCaptureSession.Preset, cameraDevice:AVCaptureDevice? = nil, location:PhysicalCameraLocation = .backFacing, orientation:ImageOrientation? = nil, captureAsYUV:Bool = true) throws {
        self.location = location
        self.orientation = orientation

        self.captureSession = AVCaptureSession()
        self.captureSession.beginConfiguration()
        
        self.captureAsYUV = captureAsYUV
        
        if let cameraDevice = cameraDevice {
            self.inputCamera = cameraDevice
        } else {
            if let device = location.device() {
                self.inputCamera = device
            } else {
                self.videoInput = nil
                self.videoOutput = nil
                self.inputCamera = nil
                self.yuvConversionRenderPipelineState = nil
                super.init()
                throw CameraError()
            }
        }
        
        do {
            self.videoInput = try AVCaptureDeviceInput(device:inputCamera)
        } catch {
            self.videoInput = nil
            self.videoOutput = nil
            self.yuvConversionRenderPipelineState = nil
            super.init()
            throw error
        }
        
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        }
        
        // Add the video frame output
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = false
        
        if captureAsYUV {
            supportsFullYUVRange = false
            let supportedPixelFormats = videoOutput.availableVideoPixelFormatTypes
            for currentPixelFormat in supportedPixelFormats {
                if ((currentPixelFormat as NSNumber).int32Value == Int32(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)) {
                    supportsFullYUVRange = true
                }
            }
            if (supportsFullYUVRange) {
                let (pipelineState, lookupTable) = generateRenderPipelineState(device:sharedMetalRenderingDevice, vertexFunctionName:"twoInputVertex", fragmentFunctionName:"yuvConversionFullRangeFragment", operationName:"YUVToRGB")
                self.yuvConversionRenderPipelineState = pipelineState
                self.yuvLookupTable = lookupTable
                videoOutput.videoSettings = [kCVPixelBufferMetalCompatibilityKey as String: true,
                                             kCVPixelBufferPixelFormatTypeKey as String:NSNumber(value:Int32(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange))]
            } else {
                let (pipelineState, lookupTable) = generateRenderPipelineState(device:sharedMetalRenderingDevice, vertexFunctionName:"twoInputVertex", fragmentFunctionName:"yuvConversionVideoRangeFragment", operationName:"YUVToRGB")
                self.yuvConversionRenderPipelineState = pipelineState
                self.yuvLookupTable = lookupTable
                videoOutput.videoSettings = [kCVPixelBufferMetalCompatibilityKey as String: true,
                                             kCVPixelBufferPixelFormatTypeKey as String:NSNumber(value:Int32(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange))]
            }
        } else {
            self.yuvConversionRenderPipelineState = nil
            videoOutput.videoSettings = [kCVPixelBufferMetalCompatibilityKey as String: true,
                                         kCVPixelBufferPixelFormatTypeKey as String:NSNumber(value:Int32(kCVPixelFormatType_32BGRA))]
        }

        if (captureSession.canAddOutput(videoOutput)) {
            captureSession.addOutput(videoOutput)
        }
        
        captureSession.sessionPreset = sessionPreset
        captureSession.commitConfiguration()
        
        super.init()
        
        let _ = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, sharedMetalRenderingDevice.device, nil, &videoTextureCache)

        videoOutput.setSampleBufferDelegate(self, queue:cameraProcessingQueue)
    }
    ///销毁时，停止采集，最好手动调用下，确保无误
    deinit {
        cameraFrameProcessingQueue.sync {
            self.stopCapture()
            self.videoOutput?.setSampleBufferDelegate(nil, queue:nil)
        }
    }
    
    /// AVCaptureVideoDataOutputSampleBufferDelegate
    /// - Parameters:
    ///   - output: 音视频采集输出
    ///   - sampleBuffer: 原始采样数据
    ///   - connection: 音视频采集连接
    /// 在这里可以用来把采集到的数据转成纹理，给其他中间件，做处理
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard (frameRenderingSemaphore.wait(timeout:DispatchTime.now()) == DispatchTimeoutResult.success) else { return }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let cameraFrame = CMSampleBufferGetImageBuffer(sampleBuffer)!
        let bufferWidth = CVPixelBufferGetWidth(cameraFrame)
        let bufferHeight = CVPixelBufferGetHeight(cameraFrame)
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        CVPixelBufferLockBaseAddress(cameraFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
        
        cameraFrameProcessingQueue.async {
            self.delegate?.didCaptureBuffer(sampleBuffer)
            CVPixelBufferUnlockBaseAddress(cameraFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
            
            let texture:Texture?
            if self.captureAsYUV {
                var luminanceTextureRef:CVMetalTexture? = nil
                var chrominanceTextureRef:CVMetalTexture? = nil
                // Luminance plane
                let _ = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, self.videoTextureCache!, cameraFrame, nil, .r8Unorm, bufferWidth, bufferHeight, 0, &luminanceTextureRef)
                // Chrominance plane
                let _ = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, self.videoTextureCache!, cameraFrame, nil, .rg8Unorm, bufferWidth / 2, bufferHeight / 2, 1, &chrominanceTextureRef)
                
                if let concreteLuminanceTextureRef = luminanceTextureRef, let concreteChrominanceTextureRef = chrominanceTextureRef,
                    let luminanceTexture = CVMetalTextureGetTexture(concreteLuminanceTextureRef), let chrominanceTexture = CVMetalTextureGetTexture(concreteChrominanceTextureRef) {
                    
                    let conversionMatrix:Matrix3x3
                    if (self.supportsFullYUVRange) {
                        conversionMatrix = colorConversionMatrix601FullRangeDefault
                    } else {
                        conversionMatrix = colorConversionMatrix601Default
                    }
                    
                    let outputWidth:Int
                    let outputHeight:Int
                    if (self.orientation ?? self.location.imageOrientation()).rotationNeeded(for:.portrait).flipsDimensions() {
                        outputWidth = bufferHeight
                        outputHeight = bufferWidth
                    } else {
                        outputWidth = bufferWidth
                        outputHeight = bufferHeight
                    }
                    let outputTexture = Texture(device:sharedMetalRenderingDevice.device, orientation:.portrait, width:outputWidth, height:outputHeight, timingStyle: .videoFrame(timestamp: Timestamp(currentTime)))
                    
                    convertYUVToRGB(pipelineState:self.yuvConversionRenderPipelineState!, lookupTable:self.yuvLookupTable,
                                    luminanceTexture:Texture(orientation: self.orientation ?? self.location.imageOrientation(), texture:luminanceTexture),
                                    chrominanceTexture:Texture(orientation: self.orientation ?? self.location.imageOrientation(), texture:chrominanceTexture),
                                    resultTexture:outputTexture, colorConversionMatrix:conversionMatrix)
                    texture = outputTexture
                } else {
                    texture = nil
                }
            } else {
                var textureRef:CVMetalTexture? = nil
                let _ = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, self.videoTextureCache!, cameraFrame, nil, .bgra8Unorm, bufferWidth, bufferHeight, 0, &textureRef)
                if let concreteTexture = textureRef, let cameraTexture = CVMetalTextureGetTexture(concreteTexture) {
                    texture = Texture(orientation: self.orientation ?? self.location.imageOrientation(), texture: cameraTexture, timingStyle: .videoFrame(timestamp: Timestamp(currentTime)))
                } else {
                    texture = nil
                }
            }
            
            if texture != nil {
                self.updateTargetsWithTexture(texture!)
            }

            if self.runBenchmark {
                self.numberOfFramesCaptured += 1
                if (self.numberOfFramesCaptured > initialBenchmarkFramesToIgnore) {
                    let currentFrameTime = (CFAbsoluteTimeGetCurrent() - startTime)
                    self.totalFrameTimeDuringCapture += currentFrameTime
                    print("Average frame time : \(1000.0 * self.totalFrameTimeDuringCapture / Double(self.numberOfFramesCaptured - initialBenchmarkFramesToIgnore)) ms")
                    print("Current frame time : \(1000.0 * currentFrameTime) ms")
                }
            }

            if self.logFPS {
                if ((CFAbsoluteTimeGetCurrent() - self.lastCheckTime) > 1.0) {
                    self.lastCheckTime = CFAbsoluteTimeGetCurrent()
                    print("FPS: \(self.framesSinceLastCheck)")
                    self.framesSinceLastCheck = 0
                }

                self.framesSinceLastCheck += 1
            }

            self.frameRenderingSemaphore.signal()
        }
    }
    /// 开始采集
    public func startCapture() {
        
        let _ = frameRenderingSemaphore.wait(timeout:DispatchTime.distantFuture)
        self.numberOfFramesCaptured = 0
        self.totalFrameTimeDuringCapture = 0
        self.frameRenderingSemaphore.signal()
        
        if (!captureSession.isRunning) {
            captureSession.startRunning()
        }
    }
    /// 停止采集
    public func stopCapture() {
        if (captureSession.isRunning) {
            let _ = frameRenderingSemaphore.wait(timeout:DispatchTime.distantFuture)
            
            captureSession.stopRunning()
            self.frameRenderingSemaphore.signal()
        }
    }
    /// source 协议
    public func transmitPreviousImage(to target: ImageConsumer, atIndex: UInt) {
        // Not needed for camera
    }
}
