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

@Test func fourPendingSentencesDropTheTwoOldestAndCatchUp() {
    var queue = SpeechQueue()
    #expect(queue.enqueue("text 1") == "text 1")
    _ = queue.enqueue("text 2")
    #expect(queue.finished() == "text 2")
    _ = queue.enqueue("text 3")
    _ = queue.enqueue("text 4")
    _ = queue.enqueue("text 5")
    #expect(queue.finished() == "text 3")
    _ = queue.enqueue("text 6")
    #expect(queue.pendingCount == 3)
    _ = queue.enqueue("text 7")
    #expect(queue.pendingCount == 2)
    #expect(queue.isSpeaking)
    #expect(queue.finished() == "text 6")
    _ = queue.enqueue("text 8")
    #expect(queue.finished() == "text 7")
    #expect(queue.finished() == "text 8")
    #expect(queue.finished() == nil)
    #expect(queue.enqueue("text 9") == "text 9")
}

@Test func threePendingSentencesArePreserved() {
    var queue = SpeechQueue()
    _ = queue.enqueue("current")
    for text in ["one", "two", "three"] { _ = queue.enqueue(text) }
    #expect(queue.pendingCount == 3)
    for text in ["one", "two", "three"] { #expect(queue.finished() == text) }
    #expect(queue.finished() == nil)
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
