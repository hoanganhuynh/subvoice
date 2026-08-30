import Testing
@testable import SubVoiceCore

@Test func normalizeCollapsesWhitespace() {
    #expect(TextGate.normalize("  Xin   chào\n bạn  ") == "Xin chào bạn")
}

@Test func normalizeRejectsTooShortInput() {
    #expect(TextGate.normalize("a") == nil)
    #expect(TextGate.normalize("   ") == nil)
}

@Test func normalizeRejectsInputWithoutLetters() {
    #expect(TextGate.normalize("--- 123 ---") == nil)
}

@Test func normalizeStripsStandaloneNoiseTokens() {
    #expect(TextGate.normalize("| Xin chào —") == "Xin chào")
}

@Test func firstTextIsSpoken() {
    var gate = TextGate()
    #expect(gate.admit("Xin chào bạn") == .speak("Xin chào bạn"))
}

@Test func identicalTextIsDropped() {
    var gate = TextGate()
    _ = gate.admit("Xin chào bạn")
    #expect(gate.admit("Xin chào bạn") == .drop)
}

@Test func identicalTextIsDroppedAcrossWhitespaceDifferences() {
    var gate = TextGate()
    _ = gate.admit("Xin chào bạn")
    #expect(gate.admit("  Xin  chào   bạn ") == .drop)
}

@Test func fadeInSpeaksOnlyTheNewSuffix() {
    var gate = TextGate()

    // OCR bắt được câu lúc chữ mới hiện một nửa.
    #expect(gate.admit("Tôi không nghĩ chúng ta") == .speak("Tôi không nghĩ chúng ta"))

    // Khung sau chữ đã hiện đủ: chỉ đọc phần đuôi, không đọc lại từ đầu.
    #expect(gate.admit("Tôi không nghĩ chúng ta còn nhiều thời gian đâu.")
            == .speak("còn nhiều thời gian đâu."))
}

@Test func fadeInThenIdenticalIsDropped() {
    var gate = TextGate()
    _ = gate.admit("Tôi không nghĩ chúng ta")
    _ = gate.admit("Tôi không nghĩ chúng ta còn nhiều thời gian đâu.")

    #expect(gate.admit("Tôi không nghĩ chúng ta còn nhiều thời gian đâu.") == .drop)
}

@Test func nearIdenticalTextIsDroppedAsOCRNoise() {
    var gate = TextGate()
    _ = gate.admit("Anh ấy đã rời khỏi thành phố từ sáng sớm hôm qua.")

    // Một ký tự sai do OCR trên cùng một câu -> không được đọc lại.
    #expect(gate.admit("Anh ấy đã rời khỏi thành phô từ sáng sớm hôm qua.") == .drop)
}

@Test func genuinelyDifferentTextIsSpokenInFull() {
    var gate = TextGate()
    _ = gate.admit("Anh ấy đã rời khỏi thành phố từ sáng sớm hôm qua.")

    #expect(gate.admit("Đừng nói với ai về chuyện này, được chứ?")
            == .speak("Đừng nói với ai về chuyện này, được chứ?"))
}

@Test func clearAllowsIdenticalLineToBeSpokenAgain() {
    var gate = TextGate()
    _ = gate.admit("Cẩn thận!")

    // Vùng phụ đề trống đi giữa hai lần -> câu lặp lại phải được đọc lại.
    gate.clear()

    #expect(gate.admit("Cẩn thận!") == .speak("Cẩn thận!"))
}

@Test func similarityIsOneForIdenticalStrings() {
    #expect(TextGate.similarity("xin chào", "xin chào") == 1.0)
}

@Test func similarityIsZeroForFullyDifferentStrings() {
    #expect(TextGate.similarity("abc", "xyz") == 0.0)
}

@Test func similarityHandlesEmptyStrings() {
    #expect(TextGate.similarity("", "") == 1.0)
}
