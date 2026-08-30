import Testing
import CoreGraphics
@testable import SubVoiceCore

@Test func assemblesSingleLine() {
    let lines = [OCRLine(text: "Xin chào", confidence: 0.9, midY: 0.5, minX: 0.1)]
    #expect(OCRAssembler.assemble(lines) == "Xin chào")
}

@Test func ordersLinesTopToBottom() {
    // midY lớn hơn = nằm cao hơn trên màn hình (Vision dùng gốc dưới-trái).
    let lines = [
        OCRLine(text: "dòng dưới", confidence: 0.9, midY: 0.2, minX: 0.1),
        OCRLine(text: "dòng trên", confidence: 0.9, midY: 0.8, minX: 0.1),
    ]
    #expect(OCRAssembler.assemble(lines) == "dòng trên dòng dưới")
}

@Test func ordersFragmentsOnSameLineLeftToRight() {
    let lines = [
        OCRLine(text: "phải", confidence: 0.9, midY: 0.50, minX: 0.6),
        OCRLine(text: "trái", confidence: 0.9, midY: 0.51, minX: 0.1),
    ]
    #expect(OCRAssembler.assemble(lines) == "trái phải")
}

@Test func dropsLowConfidenceLines() {
    let lines = [
        OCRLine(text: "chắc chắn", confidence: 0.9, midY: 0.5, minX: 0.1),
        OCRLine(text: "rác", confidence: 0.1, midY: 0.4, minX: 0.1),
    ]
    #expect(OCRAssembler.assemble(lines) == "chắc chắn")
}

@Test func keepsLinesExactlyAtConfidenceThreshold() {
    let lines = [OCRLine(text: "vừa đủ", confidence: 0.30, midY: 0.5, minX: 0.1)]
    #expect(OCRAssembler.assemble(lines) == "vừa đủ")
}

@Test func returnsEmptyStringWhenAllLinesRejected() {
    let lines = [OCRLine(text: "rác", confidence: 0.05, midY: 0.5, minX: 0.1)]
    #expect(OCRAssembler.assemble(lines) == "")
}

@Test func returnsEmptyStringForNoLines() {
    #expect(OCRAssembler.assemble([]) == "")
}
