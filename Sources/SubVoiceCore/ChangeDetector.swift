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
    /// Mức đổi TƯƠNG ĐỐI so với lượng chữ đang có, để coi là đã đổi.
    ///
    /// Đo tuyệt đối là sai: chữ phụ đề chỉ chiếm khoảng 2% pixel của vùng, nên
    /// thay cả câu cũng chỉ tạo ra khoảng cách L1 chừng 0.02 — lẫn hẳn vào
    /// nhiễu của nền video, và càng chọn vùng rộng thì tín hiệu càng loãng.
    /// Chia cho lượng chữ ít hơn của hai khung thì "thay trọn một câu" luôn
    /// cho tỉ số quanh 1.0 bất kể vùng to nhỏ, và không phụ thuộc câu dài hay
    /// ngắn đến trước.
    public static let relativeChangeThreshold: Float = 0.60
    /// Sàn tuyệt đối, chặn trường hợp độ sáng rất thấp làm tỉ số vọt lên.
    public static let minAbsoluteDistance: Float = 0.002
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

    /// Kết quả của khung trước, để bên gọi chỉ ghi log khi trạng thái đổi.
    public private(set) var previousVerdict: FrameVerdict?

    public init() {}

    /// Xoá lịch sử. Khung hình kế tiếp chắc chắn được coi là `.changed`.
    public mutating func reset() {
        previous = nil
        previousVerdict = nil
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
        let verdict = verdictFor(signature)
        previous = signature
        previousVerdict = verdict
        return verdict
    }

    /// Tỉ lệ pixel sáng của khung vừa xét. Dùng khi chỉnh `blankFloor`.
    public private(set) var lastTotalBrightness: Float = 0

    private mutating func verdictFor(_ signature: BrightnessSignature) -> FrameVerdict {
        lastTotalBrightness = signature.total

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
        lastDistance = distance

        // Dùng lượng chữ ÍT HƠN trong hai khung. Một câu ngắn bị thay hẳn bởi
        // câu dài vẫn là thay đổi lớn đối với câu ngắn; chia riêng cho khung
        // mới sẽ làm kết quả phụ thuộc chiều chuyển câu và có thể bỏ sót nó.
        let referenceBrightness = max(
            min(signature.total, previous.total),
            DetectorTuning.blankFloor
        )
        let relative = distance / referenceBrightness
        lastRelativeDistance = relative

        guard distance >= DetectorTuning.minAbsoluteDistance else { return .unchanged }
        return relative < DetectorTuning.relativeChangeThreshold ? .unchanged : .changed
    }

    /// Khoảng cách L1 tuyệt đối của khung vừa xét.
    public private(set) var lastDistance: Float = 0
    /// Khoảng cách đã chia cho độ sáng. Đây mới là số dùng để chỉnh ngưỡng.
    public private(set) var lastRelativeDistance: Float = 0
}
