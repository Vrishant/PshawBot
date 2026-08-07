// FrameQueue.swift
// PshawBot
//
// An actor-based bounded ring buffer that receives captured frames from
// ScreenCaptureKit and emits them to downstream pipeline consumers.
//
// Design decisions:
// - Actor isolation guarantees thread-safe access without locks.
// - Bounded buffer with frame-dropping prevents memory buildup when the
//   pipeline is slower than the capture rate.
// - AsyncStream provides a pull-based consumption model so downstream
//   stages process frames at their own pace.

import Foundation
import CoreMedia

// MARK: - FrameQueue

/// A thread-safe, bounded frame buffer that connects the screen capture
/// layer to the analysis pipeline.
///
/// The queue uses a ring buffer with a configurable capacity. When the buffer
/// is full, the **oldest** frame is dropped — this is the correct policy for
/// real-time processing where the latest frame is always more valuable than
/// older ones.
///
/// ## Usage
/// ```swift
/// let queue = FrameQueue(capacity: 3)
///
/// // Producer side (ScreenCaptureManager)
/// await queue.enqueue(frame)
///
/// // Consumer side (PipelineCoordinator)
/// for await frame in queue.frames {
///     process(frame)
/// }
/// ```
actor FrameQueue {
    
    // MARK: - Configuration
    
    /// Maximum number of frames held in the buffer before dropping.
    let capacity: Int
    
    // MARK: - State
    
    /// The ring buffer backing store.
    private var buffer: [CapturedFrame?]
    
    /// Write index into the ring buffer.
    private var writeIndex: Int = 0
    
    /// Read index into the ring buffer.
    private var readIndex: Int = 0
    
    /// Current number of frames in the buffer.
    private var count: Int = 0
    
    /// Monotonically increasing frame counter.
    private var nextFrameID: UInt64 = 0
    
    /// Total frames received since creation.
    private(set) var totalFramesReceived: UInt64 = 0
    
    /// Total frames dropped due to buffer overflow.
    private(set) var totalFramesDropped: UInt64 = 0
    
    /// The continuation for the output AsyncStream.
    /// We hold a single continuation because there should be exactly one consumer.
    private var continuation: AsyncStream<CapturedFrame>.Continuation?
    
    /// Whether the queue has been terminated.
    private var isTerminated: Bool = false
    
    // MARK: - Initialisation
    
    /// Creates a new frame queue with the specified buffer capacity.
    ///
    /// - Parameter capacity: Maximum frames to hold. Recommended: 2–4 for
    ///   real-time pipelines. Higher values add latency without benefit.
    init(capacity: Int = 3) {
        precondition(capacity > 0, "FrameQueue capacity must be positive")
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }
    
    // MARK: - Producer API
    
    /// Enqueues a captured frame, dropping the oldest frame if the buffer is full.
    ///
    /// This method is called from the `SCStreamOutput` delegate callback.
    /// It should be fast — the only heavy work is incrementing counters and
    /// copying a struct.
    ///
    /// - Parameter frame: The frame to enqueue.
    func enqueue(_ frame: CapturedFrame) {
        guard !isTerminated else { return }
        
        totalFramesReceived += 1
        
        // Skip incomplete or unchanged frames early
        guard frame.isComplete else { return }
        
        // Drop oldest if full
        if count == capacity {
            totalFramesDropped += 1
            // Advance read index past the dropped frame
            readIndex = (readIndex + 1) % capacity
            count -= 1
        }
        
        // Write the frame
        buffer[writeIndex] = frame
        writeIndex = (writeIndex + 1) % capacity
        count += 1
        
        // Push to the async stream if a consumer is attached
        continuation?.yield(frame)
    }
    
    /// Generates the next frame ID. Called by `ScreenCaptureManager` when
    /// constructing a `CapturedFrame`.
    func nextID() -> UInt64 {
        let id = nextFrameID
        nextFrameID += 1
        return id
    }
    
    // MARK: - Consumer API
    
    /// An `AsyncStream` that emits frames as they arrive.
    ///
    /// Only **one** consumer should read from this stream. Multiple consumers
    /// will compete for frames, which is not the intended usage pattern.
    ///
    /// The stream terminates when `terminate()` is called.
    var frames: AsyncStream<CapturedFrame> {
        AsyncStream { continuation in
            self.continuation = continuation
            
            continuation.onTermination = { @Sendable _ in
                Task { await self.handleStreamTermination() }
            }
        }
    }
    
    // MARK: - Lifecycle
    
    /// Terminates the queue, finishing the output stream.
    ///
    /// After termination, no more frames are accepted and the consumer's
    /// `for await` loop will exit.
    func terminate() {
        isTerminated = true
        continuation?.finish()
        continuation = nil
    }
    
    /// Clears all buffered frames without terminating the queue.
    func flush() {
        buffer = Array(repeating: nil, count: capacity)
        readIndex = 0
        writeIndex = 0
        count = 0
    }
    
    // MARK: - Diagnostics
    
    /// Current number of frames in the buffer.
    var currentCount: Int { count }
    
    /// Whether the buffer is at capacity.
    var isFull: Bool { count == capacity }
    
    /// The drop rate as a fraction (0.0–1.0).
    var dropRate: Double {
        guard totalFramesReceived > 0 else { return 0 }
        return Double(totalFramesDropped) / Double(totalFramesReceived)
    }
    
    /// Summary statistics for debugging.
    var stats: FrameQueueStats {
        FrameQueueStats(
            capacity: capacity,
            currentCount: count,
            totalReceived: totalFramesReceived,
            totalDropped: totalFramesDropped,
            dropRate: dropRate
        )
    }
    
    // MARK: - Private
    
    private func handleStreamTermination() {
        continuation = nil
    }
}

// MARK: - FrameQueueStats

/// Diagnostic statistics for the frame queue.
struct FrameQueueStats: Sendable, CustomStringConvertible {
    let capacity: Int
    let currentCount: Int
    let totalReceived: UInt64
    let totalDropped: UInt64
    let dropRate: Double
    
    var description: String {
        "FrameQueue(\(currentCount)/\(capacity), " +
        "received: \(totalReceived), dropped: \(totalDropped), " +
        "drop rate: \(String(format: "%.1f%%", dropRate * 100)))"
    }
}
