import Foundation

/// 奇怪了，既然引入了UIKit，为什不加一个UIColor的extension，而是自己写一个Color的struct
#if os(iOS)
import UIKit
#endif
/// 三维点坐标
public struct Position {
    public let x:Float
    public let y:Float
    public let z:Float?
    
    public init (_ x:Float, _ y:Float, _ z:Float? = nil) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let center = Position(0.5, 0.5)
    public static let zero = Position(0.0, 0.0)
}

/// 二维点坐标，作者不讲究，为什么Position不是Position3D
public struct Position2D {
    public let x:Float
    public let y:Float
    
    public init (_ x:Float, _ y:Float) {
        self.x = x
        self.y = y
    }
    
    public static let center = Position(0.5, 0.5)
    public static let zero = Position(0.0, 0.0)
}
