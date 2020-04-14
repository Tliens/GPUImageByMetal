/// 图片方向
/// 旋转时会用到
public enum ImageOrientation {
    // 垂直
    case portrait
//    倒立
    case portraitUpsideDown
//    左横屏
    case landscapeLeft
//    右横屏
    case landscapeRight
    
    /// 根据目标方向，返回需要的旋转方向
    /// - Parameter targetOrientation: 目标方向
    /// - Returns: 相差的旋转方向
    func rotationNeeded(for targetOrientation:ImageOrientation) -> Rotation {
        switch (self, targetOrientation) {
            case (.portrait, .portrait), (.portraitUpsideDown, .portraitUpsideDown), (.landscapeLeft, .landscapeLeft), (.landscapeRight, .landscapeRight): return .noRotation
            case (.portrait, .portraitUpsideDown): return .rotate180
            case (.portraitUpsideDown, .portrait): return .rotate180
            case (.portrait, .landscapeLeft): return .rotateCounterclockwise
            case (.landscapeLeft, .portrait): return .rotateClockwise
            case (.portrait, .landscapeRight): return .rotateClockwise
            case (.landscapeRight, .portrait): return .rotateCounterclockwise
            case (.landscapeLeft, .landscapeRight): return .rotate180
            case (.landscapeRight, .landscapeLeft): return .rotate180
            case (.portraitUpsideDown, .landscapeLeft): return .rotateClockwise
            case (.landscapeLeft, .portraitUpsideDown): return .rotateCounterclockwise
            case (.portraitUpsideDown, .landscapeRight): return .rotateCounterclockwise
            case (.landscapeRight, .portraitUpsideDown): return .rotateClockwise
        }
    }
}

/// 自定义方向枚举
public enum Rotation {
//    无
    case noRotation
//  逆时针旋转
    case rotateCounterclockwise
//    顺时针旋转
    case rotateClockwise
//    旋转180度
    case rotate180
//    水平镜像
    case flipHorizontally
//    垂直镜像
    case flipVertically
//    顺时针旋转并且垂直镜像
    case rotateClockwiseAndFlipVertically
//  顺时针旋转并且水平镜像
    case rotateClockwiseAndFlipHorizontally
    
    
    /// 翻转维度（X维度和Y维度调换）
    /// - Returns:bool
    func flipsDimensions() -> Bool {
        switch self {
            case .noRotation, .rotate180, .flipHorizontally, .flipVertically: return false
            case .rotateCounterclockwise, .rotateClockwise, .rotateClockwiseAndFlipVertically, .rotateClockwiseAndFlipHorizontally: return true
        }
    }
}
