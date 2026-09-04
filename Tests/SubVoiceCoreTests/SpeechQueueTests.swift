import Testing
@testable import SubVoiceCore

@Test func firstEnqueueStartsSpeakingImmediately() {
    var queue = SpeechQueue()
    #expect(queue.enqueue("câu một") == "câu một")
    #expect(queue.isSpeaking)
    #expect(queue.pendingCount == 0)
}

@Test func enqueueWhileSpeakingBuffersInsteadOfReturning() {
    var queue = SpeechQueue()
    _ = queue.enqueue("câu một")

    #expect(queue.enqueue("câu hai") == nil)
    #expect(queue.pendingCount == 1)
}

@Test func finishedReturnsNextQueuedSentence() {
    var queue = SpeechQueue()
    _ = queue.enqueue("câu một")
    _ = queue.enqueue("câu hai")

    #expect(queue.finished() == "câu hai")
    #expect(queue.pendingCount == 0)
}

@Test func finishedWithEmptyQueueStopsSpeaking() {
    var queue = SpeechQueue()
    _ = queue.enqueue("câu một")

    #expect(queue.finished() == nil)
    #expect(!queue.isSpeaking)
}

@Test func queueNeverDropsASentence() {
    var queue = SpeechQueue()
    _ = queue.enqueue("đang đọc")
    for text in ["một", "hai", "ba", "bốn", "năm"] {
        #expect(queue.enqueue(text) == nil)
    }

    #expect(queue.pendingCount == 5)
    #expect(queue.finished() == "một")
    #expect(queue.finished() == "hai")
    #expect(queue.finished() == "ba")
    #expect(queue.finished() == "bốn")
    #expect(queue.finished() == "năm")
    #expect(queue.finished() == nil)
    #expect(!queue.isSpeaking)
}

@Test func queuePreservesOrderUnderInterleavedUse() {
    var queue = SpeechQueue()
    #expect(queue.enqueue("một") == "một")
    _ = queue.enqueue("hai")
    #expect(queue.finished() == "hai")
    _ = queue.enqueue("ba")
    _ = queue.enqueue("bốn")
    #expect(queue.finished() == "ba")
    #expect(queue.finished() == "bốn")
    #expect(queue.finished() == nil)
}

@Test func resetClearsEverything() {
    var queue = SpeechQueue()
    _ = queue.enqueue("câu một")
    _ = queue.enqueue("câu hai")

    queue.reset()

    #expect(queue.pendingCount == 0)
    #expect(!queue.isSpeaking)
    #expect(queue.enqueue("câu mới") == "câu mới")
}

@Test func dropPendingClearsTheBacklogButKeepsTheSentenceBeingSpoken() {
    var queue = SpeechQueue()
    _ = queue.enqueue("đang đọc")
    _ = queue.enqueue("chờ một")
    _ = queue.enqueue("chờ hai")

    queue.dropPending()

    // Câu đang phát dở vẫn được đọc hết, nên hàng đợi vẫn ở trạng thái "đang đọc".
    #expect(queue.isSpeaking)
    #expect(queue.pendingCount == 0)
    // Backend báo xong câu đang đọc -> không còn gì để đọc tiếp.
    #expect(queue.finished() == nil)
    #expect(!queue.isSpeaking)
}

@Test func dropPendingOnAnIdleQueueChangesNothing() {
    var queue = SpeechQueue()
    queue.dropPending()

    #expect(!queue.isSpeaking)
    #expect(queue.pendingCount == 0)
    #expect(queue.enqueue("câu mới") == "câu mới")
}
