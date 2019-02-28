import Dispatch
import PromiseKit
import XCTest

fileprivate let queueIDKey = DispatchSpecificKey<Int>()

class RecordingDispatcher: Dispatcher {
    
    static var queueIndex = 1
    
    var dispatchCount = 0
    let queue: DispatchQueue
    
    init() {
        queue = DispatchQueue(label: "org.promisekit.testqueue \(RecordingDispatcher.queueIndex)")
        RecordingDispatcher.queueIndex += 1
    }
    
    func dispatch(_ body: @escaping () -> Void) {
        dispatchCount += 1
        queue.async(execute: body)
    }
    
}

class DispatcherTests: XCTestCase {
    
    var dispatcher = RecordingDispatcher()
    var dispatcherB = RecordingDispatcher()

    override func setUp() {
        dispatcher = RecordingDispatcher()
        dispatcherB = RecordingDispatcher()
    }
    
    func testConfD() {
        let ex = expectation(description: "conf.D")
        let oldConf = PromiseKit.conf.D
        PromiseKit.conf.D.map = dispatcher
        PromiseKit.conf.D.return = dispatcherB
        XCTAssertNil(PromiseKit.conf.Q.map, "conf.Q.map not nil")    // Not representable as DispatchQueues
        XCTAssertNil(PromiseKit.conf.Q.return, "conf.Q.return not nil")
        Promise { seal in
            seal.fulfill(42)
        }.map {
            $0 + 10
        }.done() {
            XCTAssertEqual($0, 52, "summation result != 52")
            XCTAssertEqual(self.dispatcher.dispatchCount, 1, "map dispatcher count != 1")
            XCTAssertEqual(self.dispatcherB.dispatchCount, 1, "return dispatcher count != 1")
            ex.fulfill()
        }.cauterize()
        waitForExpectations(timeout: 1)
        let testQueue = DispatchQueue(label: "test queue")
        PromiseKit.conf.D.map = testQueue  // Assign DispatchQueue to Dispatcher variable
        PromiseKit.conf.Q.return = testQueue   // Assign DispatchQueue to DispatchQueue variable
        XCTAssert(PromiseKit.conf.Q.map === testQueue, "did not get main DispatchQueue back from map")
        XCTAssert((PromiseKit.conf.D.return as? DispatchQueue)! === testQueue, "did not get main DispatchQueue back from return")
        PromiseKit.conf.D = oldConf
    }
    
    func testDispatcherWithThrow() {
        let ex = expectation(description: "Dispatcher with throw")
        Promise { seal in
            seal.fulfill(42)
        }.map(on: dispatcher) { _ in
            throw PMKError.badInput
        }.catch(on: dispatcher) { _ in
            ex.fulfill()
        }
        waitForExpectations(timeout: 1)
        XCTAssertEqual(self.dispatcher.dispatchCount, 2)
    }
    
    func testDispatchQueueSelection() {
        
        let ex = expectation(description: "DispatchQueue compatibility")
        
        let oldConf = PromiseKit.conf.D
        PromiseKit.conf.D = (map: dispatcher, return: dispatcher)
        
        let background = DispatchQueue.global(qos: .background)
        background.setSpecific(key: queueIDKey, value: 100)
        DispatchQueue.main.setSpecific(key: queueIDKey, value: 102)
        dispatcher.queue.setSpecific(key: queueIDKey, value: 103)
        
        Promise.value(42).map(on: .global(qos: .background), flags: .barrier) { (x: Int) -> Int in
            let queueID = DispatchQueue.getSpecific(key: queueIDKey)
            XCTAssertNotNil(queueID)
            XCTAssertEqual(queueID!, 100)
            return x + 10
        }.then(on: .main, flags: []) { (x: Int) -> Promise<Int> in
            XCTAssertEqual(x, 52)
            let queueID = DispatchQueue.getSpecific(key: queueIDKey)
            XCTAssertNotNil(queueID)
            XCTAssertEqual(queueID!, 102)
            return Promise.value(50)
        }.map(on: nil) { (x: Int) -> Int in
            let queueID = DispatchQueue.getSpecific(key: queueIDKey)
            XCTAssertNotNil(queueID)
            XCTAssertEqual(queueID!, 102)
            return x + 10
        }.map { (x: Int) -> Int in
            XCTAssertEqual(x, 60)
            let queueID = DispatchQueue.getSpecific(key: queueIDKey)
            XCTAssertNotNil(queueID)
            XCTAssertEqual(queueID!, 103)
            return x + 10
        }.done(on: background) {
            XCTAssertEqual($0, 70)
            let queueID = DispatchQueue.getSpecific(key: queueIDKey)
            XCTAssertNotNil(queueID)
            XCTAssertEqual(queueID!, 100)
            ex.fulfill()
        }.cauterize()
        
        waitForExpectations(timeout: 1)
        PromiseKit.conf.D = oldConf
        
    }

    @available(macOS 10.10, iOS 2.0, tvOS 10.0, watchOS 2.0, *)
    func testDispatcherExtensionReturnsGuarantee() {
        let ex = expectation(description: "Dispatcher.promise")
        dispatcher.dispatch(.promise) { () -> Int in
            XCTAssertFalse(Thread.isMainThread)
            return 1
        }.done { one in
            XCTAssertEqual(one, 1)
            ex.fulfill()
        }
        waitForExpectations(timeout: 1)
    }
    
    @available(macOS 10.10, iOS 2.0, tvOS 10.0, watchOS 2.0, *)
    func testDispatcherExtensionCanThrowInBody() {
        let ex = expectation(description: "Dispatcher.promise")
        dispatcher.dispatch(.promise) { () -> Int in
            throw PMKError.badInput
        }.done { _ in
            XCTFail()
        }.catch { _ in
            ex.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

}