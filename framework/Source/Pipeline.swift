// MARK: -
// MARK: Basic types
import Foundation

/// 关键协议
/// 理解为可输入协议，名字不好，用ImageInputable 可能更明确
public protocol ImageSource {
    /// 输入容器，输入源中有个输入容器，下文有介绍
    var targets:TargetContainer { get }
    /// 把当前存在的纹理传给目标，atIndex表示指定，如：有新的target时
    func transmitPreviousImage(to target:ImageConsumer, atIndex:UInt)
}
/// 理解为可输出协议，名字不好，用ImageOutputable 可能更明确
public protocol ImageConsumer:AnyObject {
    /// 最大的输入个数
    var maximumInputs:UInt { get }
    /// 输出容器，里边有很多弱引用的输入，下文有介绍
    var sources:SourceContainer { get }
    /// 得到新的纹理时，调用这个，如果自己是中间层，就把纹理传递给下一层
    func newTextureAvailable(_ texture:Texture, fromSourceIndex:UInt)
}
/// 所有作为中间操作的必须遵守这个协议，名字不好应该，用ImageMiddleable
public protocol ImageProcessingOperation: ImageConsumer, ImageSource {
}
/// 自定义操作，这个比较6了
infix operator --> : AdditionPrecedence
//precedencegroup ProcessingOperationPrecedence {
//    associativity: left
////    higherThan: Multiplicative
//}
/// 添加到目标输出
@discardableResult public func --><T:ImageConsumer>(source:ImageSource, destination:T) -> T {
    source.addTarget(destination)
    return destination
}

// MARK: -
// MARK: Extensions and supporting types

public extension ImageSource {
    
    /// 给自己添加目标输出，即我手中的资源接下来给谁
    /// - Parameters:
    ///   - target: 目标输出
    ///   - atTargetIndex: 在第几个
    func addTarget(_ target:ImageConsumer, atTargetIndex:UInt? = nil) {
        if let targetIndex = atTargetIndex {
            target.setSource(self, atIndex:targetIndex)
            targets.append(target, indexAtTarget:targetIndex)
            transmitPreviousImage(to:target, atIndex:targetIndex)
        } else if let indexAtTarget = target.addSource(self) {
            targets.append(target, indexAtTarget:indexAtTarget)
            transmitPreviousImage(to:target, atIndex:indexAtTarget)
        } else {
            debugPrint("Warning: tried to add target beyond target's input capacity")
        }
    }
    /// 移除我身上的所有输出，比如：GPUImageView，以及一切和我相关的下层目标
    func removeAllTargets() {
        for (target, index) in targets {
            target.removeSourceAtIndex(index)
        }
        targets.removeAll()
    }
    // 更新所有目标的纹理，通常是有新的纹理产生了
    func updateTargetsWithTexture(_ texture:Texture) {
//        if targets.count == 0 { // Deal with the case where no targets are attached by immediately returning framebuffer to cache
//            framebuffer.lock()
//            framebuffer.unlock()
//        } else {
//            // Lock first for each output, to guarantee proper ordering on multi-output operations
//            for _ in targets {
//                framebuffer.lock()
//            }
//        }
        for (target, index) in targets {
            target.newTextureAvailable(texture, fromSourceIndex:index)
        }
    }
}

public extension ImageConsumer {
    /// 添加资源，即我手中的资源应该从哪里来
    func addSource(_ source:ImageSource) -> UInt? {
        return sources.append(source, maximumInputs:maximumInputs)
    }
    /// 添加资源，和addSource 一样，只不过多了索引，通常是用于多文里输入
    func setSource(_ source:ImageSource, atIndex:UInt) {
        _ = sources.insert(source, atIndex:atIndex, maximumInputs:maximumInputs)
    }
    /// 移除索引index处的资源
    func removeSourceAtIndex(_ index:UInt) {
        sources.removeAtIndex(index)
    }
}
/// 为了防止，资源，输出相互引用，抽象出来的弱引用输出
class WeakImageConsumer {
    weak var value:ImageConsumer?
    let indexAtTarget:UInt
    init (value:ImageConsumer, indexAtTarget:UInt) {
        self.indexAtTarget = indexAtTarget
        self.value = value
    }
}
/// 目标容器，即输出到何处的容器，可能一个资源要输出到多个地方，比如，拍视频时，同时输出到屏幕和文件中
/// Sequence 遵守了这个协议，意味着可以遍历，像数组一样
public class TargetContainer:Sequence {
    /// 目标弱引用
    var targets = [WeakImageConsumer]()
    /// 目标数量
    var count:Int { get {return targets.count}}
    /// 处理的串行队列，使用的时候也没加把锁，尴尬
    let dispatchQueue = DispatchQueue(label:"com.sunsetlakesoftware.GPUImage.targetContainerQueue", attributes: [])

    public init() {
    }
    /// 在索引处添加一个目标
    public func append(_ target:ImageConsumer, indexAtTarget:UInt) {
        // TODO: Don't allow the addition of a target more than once
        dispatchQueue.async{
            self.targets.append(WeakImageConsumer(value:target, indexAtTarget:indexAtTarget))
        }
    }
    ///这个应该是Sequence的内容了，查找
    public func makeIterator() -> AnyIterator<(ImageConsumer, UInt)> {
        var index = 0
        
        return AnyIterator { () -> (ImageConsumer, UInt)? in
            return self.dispatchQueue.sync{
                if (index >= self.targets.count) {
                    return nil
                }
                
                while (self.targets[index].value == nil) {
                    self.targets.remove(at:index)
                    if (index >= self.targets.count) {
                        return nil
                    }
                }
                
                index += 1
                return (self.targets[index - 1].value!, self.targets[index - 1].indexAtTarget)
           }
        }
    }
    /// 移除所有目标
    public func removeAll() {
        dispatchQueue.async{
            self.targets.removeAll()
        }
    }
}
/// 这里又搞了一个输入容器，使用类似场景是，lookup滤镜有多输入，一个原片，一个颜色查找表
public class SourceContainer {
    var sources:[UInt:ImageSource] = [:]
    
    public init() {
    }
    /// 添加一个输入，最大的输入个数是maximumInputs
    /// maximumInputs的目的是用来找到对应的索引，以及控制，这里不好，添加时就可以改变，初始化时直接锁定不好吗? 不这样，为什么不设置个默认值？maximumInputs也没有记录，我的天
    /// - parameter return: 该输入对应索引值
    public func append(_ source:ImageSource, maximumInputs:UInt) -> UInt? {
        var currentIndex:UInt = 0
        while currentIndex < maximumInputs {
            if (sources[currentIndex] == nil) {
                sources[currentIndex] = source
                return currentIndex
            }
            currentIndex += 1
        }
        
        return nil
    }
    /// 插入输入，同上，设计的不好
    public func insert(_ source:ImageSource, atIndex:UInt, maximumInputs:UInt) -> UInt {
        guard (atIndex < maximumInputs) else { fatalError("ERROR: Attempted to set a source beyond the maximum number of inputs on this operation") }
        sources[atIndex] = source
        return atIndex
    }
    /// 移除 index 处的资源
    public func removeAtIndex(_ index:UInt) {
        sources[index] = nil
    }
}
/// ImageProcessingOperation 意味着 ImageRelay是个中间操作
public class ImageRelay: ImageProcessingOperation {
    /// 新纹理回调
    public var newImageCallback:((Texture) -> ())?
    /// 输入源容器
    public let sources = SourceContainer()
    /// 输出源容器
    public let targets = TargetContainer()
    /// 最大输入
    public let maximumInputs:UInt = 1
    /// 防止转播，意思是，你有新纹理的话，不允许给别人了，一般情况下，为false
    public var preventRelay:Bool = false
    
    public init() {
    }
    /// 把当前存在的纹理传给目标，atIndex表示指定，如：有新的target时
    public func transmitPreviousImage(to target:ImageConsumer, atIndex:UInt) {
        /// 为何是0呢？这明显有优化控件 ，作者的 atIndex 还没用
        /// 从0开始，是因为这是个链，可以保证所有链上的都走一遍
        sources.sources[0]?.transmitPreviousImage(to:self, atIndex:0)
    }
    /// 获得了新的纹理，这个明显是为了输出源准备的
    public func newTextureAvailable(_ texture: Texture, fromSourceIndex: UInt) {
        if let newImageCallback = newImageCallback {
            newImageCallback(texture)
        }
        /// 防止转播，意思是，你有新纹理的话，不允许给别人了，一般情况下，为false
        if (!preventRelay) {
            
            /// 传给下一个输出 fromSourceIndex也没用到
            relayTextureOnward(texture)
        }
    }
    /// 这里居然把所有的输入遍历的一遍，确实没毛病，这个应该在这里写个条件语句吧
    public func relayTextureOnward(_ texture:Texture) {
        // Need to override to guarantee a removal of the previously applied lock
//        for _ in targets {
//            framebuffer.lock()
//        }
//        framebuffer.unlock()
        for (target, index) in targets {
            target.newTextureAvailable(texture, fromSourceIndex:index)
        }
    }
}
