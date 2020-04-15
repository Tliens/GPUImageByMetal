import Foundation

// This reimplements CMTime such that it can reach across to Linux
public struct TimestampFlags: OptionSet {
    public let rawValue:UInt32
    public init(rawValue:UInt32) { self.rawValue = rawValue }
    /// 有效的
    public static let valid = TimestampFlags(rawValue: 1 << 0)
    /// 无限循环 我猜的
    public static let hasBeenRounded = TimestampFlags(rawValue: 1 << 1)
    /// 正无穷
    public static let positiveInfinity = TimestampFlags(rawValue: 1 << 2)
    /// 负无穷
    public static let negativeInfinity = TimestampFlags(rawValue: 1 << 3)
    /// 不确定的
    public static let indefinite = TimestampFlags(rawValue: 1 << 4)
}
/// 时间戳 这个结构第一眼看到，有点蒙蔽的
/// Comparable可比较的
public struct Timestamp: Comparable {
    /// 值
    let value:Int64
    /// 量化大小
    let timescale:Int32
    /// 标记
    let flags:TimestampFlags
    /// 时代
    let epoch:Int64
    /// 初始化
    /// - parameter value: 值
    /// - parameter timescale: 量化大小，为什么叫量化呢？（因为能量是量化的，即是有最小单位的，普朗克这名熟悉不？量子论）
    /// - parameter flags: 标记
    public init(value:Int64, timescale:Int32, flags:TimestampFlags, epoch:Int64) {
        self.value = value
        self.timescale = timescale
        self.flags = flags
        self.epoch = epoch
    }
    /// 秒
    func seconds() -> Double {
        return Double(value) / Double(timescale)
    }
    /// 0
    public static let zero = Timestamp(value: 0, timescale: 0, flags: .valid, epoch: 0)

}

public func ==(x:Timestamp, y:Timestamp) -> Bool {
    // TODO: Fix this
//    if (x.flags.contains(TimestampFlags.PositiveInfinity) && y.flags.contains(TimestampFlags.PositiveInfinity)) {
//        return true
//    } else if (x.flags.contains(TimestampFlags.NegativeInfinity) && y.flags.contains(TimestampFlags.NegativeInfinity)) {
//        return true
//    } else if (x.flags.contains(TimestampFlags.Indefinite) || y.flags.contains(TimestampFlags.Indefinite) || x.flags.contains(TimestampFlags.NegativeInfinity) || y.flags.contains(TimestampFlags.NegativeInfinity) || x.flags.contains(TimestampFlags.PositiveInfinity) && y.flags.contains(TimestampFlags.PositiveInfinity)) {
//        return false
//    }
    
    let correctedYValue:Int64
    if (x.timescale != y.timescale) {
        correctedYValue = Int64(round(Double(y.value) * Double(x.timescale) / Double(y.timescale)))
    } else {
        correctedYValue = y.value
    }
    
    return ((x.value == correctedYValue) && (x.epoch == y.epoch))
}

public func <(x:Timestamp, y:Timestamp) -> Bool {
    // TODO: Fix this
//    if (x.flags.contains(TimestampFlags.PositiveInfinity) || y.flags.contains(TimestampFlags.NegativeInfinity)) {
//        return false
//    } else if (x.flags.contains(TimestampFlags.NegativeInfinity) || y.flags.contains(TimestampFlags.PositiveInfinity)) {
//        return true
//    }

    if (x.epoch < y.epoch) {
        return true
    } else if (x.epoch > y.epoch) {
        return false
    }

    let correctedYValue:Int64
    if (x.timescale != y.timescale) {
        correctedYValue = Int64(round(Double(y.value) * Double(x.timescale) / Double(y.timescale)))
    } else {
        correctedYValue = y.value
    }

    return (x.value < correctedYValue)
}
