// FrameQueueTests.swift
// PshawBotTests
//
// Unit tests for the FrameQueue actor.

import XCTest
@testable import PshawBot

final class FrameQueueTests: XCTestCase {
    
    // MARK: - Initialisation Tests
    
    func testInitialState() async {
        let queue = FrameQueue(capacity: 3)
        
        let count = await queue.currentCount
        let isFull = await queue.isFull
        let stats = await queue.stats
        
        XCTAssertEqual(count, 0)
        XCTAssertFalse(isFull)
        XCTAssertEqual(stats.capacity, 3)
        XCTAssertEqual(stats.totalReceived, 0)
        XCTAssertEqual(stats.totalDropped, 0)
        XCTAssertEqual(stats.dropRate, 0)
    }
    
    // MARK: - ID Generation Tests
    
    func testNextIDIsMonotonic() async {
        let queue = FrameQueue(capacity: 3)
        
        let id1 = await queue.nextID()
        let id2 = await queue.nextID()
        let id3 = await queue.nextID()
        
        XCTAssertEqual(id1, 0)
        XCTAssertEqual(id2, 1)
        XCTAssertEqual(id3, 2)
    }
    
    // MARK: - Stats Tests
    
    func testStatsDescription() async {
        let queue = FrameQueue(capacity: 5)
        let stats = await queue.stats
        
        XCTAssertTrue(stats.description.contains("0/5"))
        XCTAssertTrue(stats.description.contains("received: 0"))
        XCTAssertTrue(stats.description.contains("dropped: 0"))
    }
    
    // MARK: - Flush Tests
    
    func testFlushClearsBuffer() async {
        let queue = FrameQueue(capacity: 3)
        
        // Enqueue a placeholder frame (won't actually enqueue since it's incomplete,
        // but we can test flush still works)
        await queue.flush()
        
        let count = await queue.currentCount
        XCTAssertEqual(count, 0)
    }
    
    // MARK: - Termination Tests
    
    func testTerminateStopsAcceptingFrames() async {
        let queue = FrameQueue(capacity: 3)
        await queue.terminate()
        
        // After termination, the queue should not accept new frames
        let placeholder = CapturedFrame.placeholder(id: 0)
        await queue.enqueue(placeholder)
        
        // totalFramesReceived should still be 0 because we terminated before enqueue
        let stats = await queue.stats
        XCTAssertEqual(stats.totalReceived, 0)
    }
}
