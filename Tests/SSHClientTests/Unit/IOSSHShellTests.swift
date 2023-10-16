
import Foundation
import XCTest
import NIOCore
import NIOEmbedded
import NIOSSH
@testable import SSHClient

class IOSSHShellTests: XCTestCase {

    func testSuccessfulSSHChannelStart() throws {
        let shell = EmbeddedIOShell()
        try shell.assertStart()
    }

    func testFailedSSHChannelStart() throws {
        let shell = EmbeddedIOShell()
        let promise = try shell.start()
        shell.run()
        try shell.channel.close().wait()
        shell.run()
        XCTAssertEqual(shell.recordedData, [])
        XCTAssertEqual(shell.recordedStates, [.failed(.unknown)])
        XCTAssertThrowsError(try promise.futureResult.wait())
    }

    func testFailedOnOutboundSSHChannelStart() throws {
        let shell = EmbeddedIOShell()
        let promise = try shell.start()
        shell.channel.shouldFailOnOutboundEvent = true
        XCTAssertTrue(shell.channel.isActive)
        shell.run()
        XCTAssertFalse(shell.channel.isActive)
        XCTAssertEqual(shell.recordedData, [])
        XCTAssertEqual(shell.recordedStates, [.failed(.unknown)])
        XCTAssertThrowsError(try promise.futureResult.wait())
    }

    func testReadingWhenConnected() throws {
        let shell = EmbeddedIOShell()
        try shell.assertStart()
        let data = shell.channel.triggerInboundChannelString("Data")
        shell.run()
        XCTAssertEqual(shell.recordedData, [data])
        let error = shell.channel.triggerInboundChannelString("Error")
        shell.run()
        XCTAssertEqual(shell.recordedData, [data, error])
    }

    func testReadingWhenNotConnected() throws {
        let shell = EmbeddedIOShell()
        let _ = shell.channel.triggerInboundChannelString("Data")
        shell.run()
        XCTAssertEqual(shell.recordedData, [])
    }

    func testWritingWhenConnected() throws {
        let shell = EmbeddedIOShell()
        try shell.assertStart()
        let data = "Data".data(using: .utf8)!
        let future = shell.shell.write(data)
        shell.run()
        try future.wait()
        XCTAssertEqual(
            try shell.channel.readAllOutbound(),
            [SSHChannelData(type: .channel, data: .byteBuffer(.init(data: data)))]
        )
    }

    func testWritingWhenNotConnected() throws {
        let shell = EmbeddedIOShell()
        let data = "Data".data(using: .utf8)!
        let future = shell.shell.write(data)
        shell.run()
        XCTAssertThrowsError(try future.wait())
    }

    func testServerDisconnection() throws {
        let shell = EmbeddedIOShell()
        try shell.assertStart()
        try shell.channel.close().wait()
        shell.run()
        XCTAssertEqual(shell.recordedStates, [.ready, .failed(.unknown)])
    }

    func testClientDisconnection() throws {
        let shell = EmbeddedIOShell()
        try shell.assertStart()
        let future = shell.shell.close()
        shell.run()
        try future.wait()
        XCTAssertEqual(shell.recordedStates, [.ready, .closed])
    }
}

private class EmbeddedIOShell {

    let channel = EmbeddedSSHChannel()
    let shell: IOSSHShell

    private(set) var recordedStates: [SSHShell.State] = []
    private(set) var recordedData: [Data] = []

    init() {
        shell = IOSSHShell(eventLoop: channel.loop)
        shell.stateUpdateHandler = { [weak self] state in
            self?.recordedStates.append(state)
        }
        shell.readHandler = { [weak self] data in
            self?.recordedData.append(data)
        }
    }

    func start() throws -> Promise<Void> {
        let promise = channel.loop.makePromise(of: Void.self)
        try channel.connect().wait()
        let context = SSHSessionContext(
            channel: channel.channel,
            promise: promise
        )
        shell.start(in: context)
        try channel.startMonitoringOutbound()
        return promise
    }

    func assertStart() throws {
        let promise = try start()
        run()
        XCTAssertTrue(channel.isActive)
        XCTAssertEqual(
            channel.outboundEvents,
            [SSHChannelRequestEvent.ShellRequest(wantReply: true)]
        )
        XCTAssertEqual(recordedData, [])
        XCTAssertEqual(recordedStates, [])
        channel.triggerInbound(ChannelSuccessEvent())
        run()
        try promise.futureResult.wait()
        XCTAssertEqual(recordedData, [])
        XCTAssertEqual(recordedStates, [.ready])
    }

    func run() {
        channel.run()
    }
}
