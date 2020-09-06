#if canImport(UIKit)
import UIKit
#else
import Cocoa
#endif
import MetalKit
/// 图片输入，渲染链中的输入环节，相对于Camera要简单，只需要把image转为纹理就好
public class PictureInput: ImageSource {
    /// 目标容器
    public let targets = TargetContainer()
    /// 内部纹理，贮存使用，不用每次都搞个新的
    var internalTexture:Texture?
    /// 是否已经处理过图片，一个标记
    var hasProcessedImage:Bool = false
    /// 内部图片
    var internalImage:CGImage?
    
    /// 初始化
    /// - Parameters:
    ///   - image: 图像 CGImage
    ///   - smoothlyScaleOutput: 顺滑缩放
    ///   - orientation: 图片方向
    /// 很明显，作者还没写完
    public init(image:CGImage, smoothlyScaleOutput:Bool = false, orientation:ImageOrientation = .portrait) {
        internalImage = image
    }
    /// 以下均为初始化
    #if canImport(UIKit)
    public convenience init(image:UIImage, smoothlyScaleOutput:Bool = false, orientation:ImageOrientation = .portrait) {
        self.init(image: image.cgImage!, smoothlyScaleOutput: smoothlyScaleOutput, orientation: orientation)
    }
    
    public convenience init(imageName:String, smoothlyScaleOutput:Bool = false, orientation:ImageOrientation = .portrait) {
        guard let image = UIImage(named:imageName) else { fatalError("No such image named: \(imageName) in your application bundle") }
        self.init(image:image, smoothlyScaleOutput:smoothlyScaleOutput, orientation:orientation)
    }
    #else
    public convenience init(image:NSImage, smoothlyScaleOutput:Bool = false, orientation:ImageOrientation = .portrait) {
        self.init(image:image.cgImage(forProposedRect:nil, context:nil, hints:nil)!, smoothlyScaleOutput:smoothlyScaleOutput, orientation:orientation)
    }
    
    public convenience init(imageName:String, smoothlyScaleOutput:Bool = false, orientation:ImageOrientation = .portrait) {
        let imageName = NSImage.Name(imageName)
        guard let image = NSImage(named:imageName) else { fatalError("No such image named: \(imageName) in your application bundle") }
        self.init(image:image.cgImage(forProposedRect:nil, context:nil, hints:nil)!, smoothlyScaleOutput:smoothlyScaleOutput, orientation:orientation)
    }
    #endif
    
    /// 处理图片
    /// - Parameter synchronously: 区分同步还是异步
    public func processImage(synchronously:Bool = false) {
        if let texture = internalTexture {
            if synchronously {
                self.updateTargetsWithTexture(texture)
                self.hasProcessedImage = true
            } else {
                DispatchQueue.global().async{
                    self.updateTargetsWithTexture(texture)
                    self.hasProcessedImage = true
                }
            }
        } else {
            let textureLoader = MTKTextureLoader(device: sharedMetalRenderingDevice.device)
            if synchronously {
                do {
                    let imageTexture = try textureLoader.newTexture(cgImage:internalImage!, options: [MTKTextureLoader.Option.SRGB : false])
                    internalImage = nil
                    self.internalTexture = Texture(orientation: .portrait, texture: imageTexture)
                    self.updateTargetsWithTexture(self.internalTexture!)
                    self.hasProcessedImage = true
                } catch {
                    fatalError("Failed loading image texture")
                }
            } else {
                textureLoader.newTexture(cgImage: internalImage!, options: [MTKTextureLoader.Option.SRGB : false], completionHandler: { (possibleTexture, error) in
                    guard (error == nil) else { fatalError("Error in loading texture: \(error!)") }
                    guard let texture = possibleTexture else { fatalError("Nil texture received") }
                    self.internalImage = nil
                    self.internalTexture = Texture(orientation: .portrait, texture: texture)
                    DispatchQueue.global().async{
                        self.updateTargetsWithTexture(self.internalTexture!)
                        self.hasProcessedImage = true
                    }
                })
            }
        }
    }
    /// 把当前存在的纹理传给目标，atIndex表示指定，如：有新的target时
    public func transmitPreviousImage(to target:ImageConsumer, atIndex:UInt) {
        if hasProcessedImage {
            target.newTextureAvailable(self.internalTexture!, fromSourceIndex:atIndex)
        }
    }
}
