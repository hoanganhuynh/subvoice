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

@Test func queueDropsOldestWhenOverCapacity() {
    var queue = SpeechQueue()
    _ = queue.enqueue("đang đọc")
    _ = queue.enqueue("chờ một")
    _ = queue.enqueue("chờ hai")
    _ = queue.enqueue("chờ ba")   // vượt trần -> "chờ một" bị bỏ

    #expect(queue.pendingCount == SpeechQueue.maxPending)
    #expect(queue.finished() == "chờ hai")
    #expect(queue.finished() == "chờ ba")
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

@Test func maxPendingMatchesSpec() {
    #expect(SpeechQueue.maxPending == 2)
}

@Test func queueCountsSentencesDroppedByCapacity() {
    var queue = SpeechQueue()
    _ = queue.enqueue("đang đọc")
    _ = queue.enqueue("chờ một")
    _ = queue.enqueue("chờ hai")
    #expect(queue.droppedCount == 0)

    _ = queue.enqueue("chờ ba")
    #expect(queue.droppedCount == 1)

    _ = queue.enqueue("chờ bốn")
    #expect(queue.droppedCount == 2)
}

@Test func resetClearsDroppedCount() {
    var queue = SpeechQueue()
    for text in ["a", "b", "c", "d"] { _ = queue.enqueue(text) }
    #expect(queue.droppedCount > 0)

    queue.reset()
    #expect(queue.droppedCount == 0)
}
