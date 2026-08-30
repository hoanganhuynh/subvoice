import Foundation

/// Hằng số tinh chỉnh, gom một chỗ vì chắc chắn phải sửa lại trên nội dung phim thật.
public enum DetectorTuning {
    /// Độ sáng chuẩn hoá, trên mức này coi là pixel thuộc về chữ.
    public static let luminanceThreshold: Float = 0.75
    /// Bước nhảy lấy mẫu, áp dụng cho cả hai chiều.
    public static let sampleStride = 2
    /// Số cột của hồ sơ một chiều.
    public static let columnCount = 64
    /// Tỉ lệ pixel sáng tối thiểu để coi là vùng có chữ.
    public static let blankFloor: Float = 0.002
    /// Khoảng cách L1 chuẩn hoá để coi là đã đổi.
    public static let changeThreshold: Float = 0.02
    /// Giới hạn tần suất OCR cứng, tính bằng giây.
    public static let minOCRInterval: Double = 0.08
}

public enum FrameVerdict: Equatable, Sendable {
    /// Vùng không có chữ. Bên gọi phải xoá trạng thái lọc trùng của TextGate.
    case blank
    /// Có chữ nhưng vẫn là câu cũ. Bỏ qua.
    case unchanged
    /// Nội dung chữ đã đổi. Đáng chạy OCR.
    case changed
}

/// Chữ ký của mặt nạ chữ trong một khung hình.
public struct BrightnessSignature: Equatable, Sendable {
    /// Tỉ lệ pixel sáng của từng cột, `DetectorTuning.columnCount` phần tử.
    public var columns: [Float]
    /// Tỉ lệ pixel sáng của toàn vùng.
    public var total: Float
}

public struct ChangeDetector {
    private var previous: BrightnessSignature?

    public init() {}

    /// Xoá lịch sử. Khung hình kế tiếp chắc chắn được coi là `.changed`.
    public mutating func reset() {
        previous = nil
    }

    /// Tính chữ ký từ buffer BGRA.
    ///
    /// Ngưỡng hoá theo độ sáng TRƯỚC khi so sánh chính là mấu chốt: nền video
    /// chuyển động nằm dưới ngưỡng nên bị loại hẳn, chỉ còn lại hình dạng chữ.
    public static func signature(
        bgra: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) -> BrightnessSignature {
        let stride = DetectorTuning.sampleStride
        let columnCount = DetectorTuning.columnCount
        var bright = [Float](repeating: 0, count: columnCount)
        var sampled = [Float](repeating: 0, count: columnCount)

        var y = 0
        while y < height {
            let row = bgra + y * bytesPerRow
            var x = 0
            while x < width {
                let p = row + x * 4
                let b = Float(p[0]) / 255
                let g = Float(p[1]) / 255
                let r = Float(p[2]) / 255
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b

                let bucket = min(x * columnCount / width, columnCount - 1)
                sampled[bucket] += 1
                if luma > DetectorTuning.luminanceThreshold {
                    bright[bucket] += 1
                }
                x += stride
            }
            y += stride
        }

        var totalBright: Float = 0
        var totalSampled: Float = 0
        for i in 0..<columnCount {
            totalBright += bright[i]
            totalSampled += sampled[i]
            bright[i] = sampled[i] > 0 ? bright[i] / sampled[i] : 0
        }

        return BrightnessSignature(
            columns: bright,
            total: totalSampled > 0 ? totalBright / totalSampled : 0
        )
    }

    /// So chữ ký này với chữ ký của khung trước.
    public mutating func evaluate(_ signature: BrightnessSignature) -> FrameVerdict {
        defer { previous = signature }

        guard signature.total >= DetectorTuning.blankFloor else {
            return .blank
        }
        guard let previous else {
            return .changed
        }

        var distance: Float = 0
        for i in 0..<signature.columns.count {
            distance += abs(signature.columns[i] - previous.columns[i])
        }
        distance /= Float(signature.columns.count)

        return distance < DetectorTuning.changeThreshold ? .unchanged : .changed
    }
}
