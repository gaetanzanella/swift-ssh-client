
import Foundation
import NIOCore
import NIOEmbedded
import NIOSSH
@testable import SSHClient
import XCTest

class IOSSHShellTests: XCTestCase {
    func testSuccessfulSSHChannelStart() throws {
        let context = IOShellContext()
        try context.assertStart()
    }

    func testFailedOnOutboundSSHChannelStart() throws {
        let context = IOShellContext()
        context.harness.channel.shouldFailOnOutboundEvent = true
        let promise = try context.harness.start(context.shell)
        context.harness.channel.run()
        XCTAssertThrowsError(try promise.wait())
        XCTAssertEqual(context.recordedData, [])
        XCTAssertEqual(context.recordedStates, [.failed(.unknown)])
    }

    func testReadingWhenConnected() throws {
        let context = IOShellContext()
        try context.assertStart()
        let data = context.harness.channel.triggerInboundChannelString("Data")
        context.harness.channel.run()
        XCTAssertEqual(context.recordedData, [data])
        let error = context.harness.channel.triggerInboundChannelString("Error")
        context.harness.channel.run()
        XCTAssertEqual(context.recordedData, [data, error])
    }

    func testReadingWhenNotConnected() throws {
        let context = IOShellContext()
        let _ = context.harness.channel.triggerInboundChannelString("Data")
        context.harness.channel.run()
        XCTAssertEqual(context.recordedData, [])
    }

    func testWritingWhenConnected() throws {
        let context = IOShellContext()
        try context.assertStart()
        let data = "Data".data(using: .utf8)!
        let future = context.shell.write(data)
        context.harness.channel.run()
        try future.wait()
        XCTAssertEqual(
            try context.harness.channel.readAllOutbound(),
            [SSHChannelData(type: .channel, data: .byteBuffer(.init(data: data)))]
        )
    }

    func testWritingWhenNotConnected() throws {
        let context = IOShellContext()
        let data = "Data".data(using: .utf8)!
        let future = context.shell.write(data)
        context.harness.channel.run()
        XCTAssertThrowsError(try future.wait())
    }

    func testServerDisconnection() throws {
        let context = IOShellContext()
        try context.assertStart()
        try context.harness.channel.close().wait()
        context.harness.channel.run()
        XCTAssertEqual(context.recordedStates, [.ready, .failed(.unknown)])
    }

    func testClientDisconnection() throws {
        let context = IOShellContext()
        try context.assertStart()
        let future = context.shell.close()
        context.harness.channel.run()
        try future.wait()
        XCTAssertEqual(context.recordedStates, [.ready, .closed])
    }
}

private class IOShellContext {
    let harness: SSHSessionHarness
    let shell: IOSSHShell

    private(set) var recordedStates: [SSHShell.State] = []
    private(set) var recordedData: [Data] = []

    init() {
        harness = SSHSessionHarness()
        shell = IOSSHShell(eventLoop: harness.channel.loop)
        shell.stateUpdateHandler = { [weak self] state in
            self?.recordedStates.append(state)
        }
        shell.readHandler = { [weak self] data in
            self?.recordedData.append(data)
        }
    }

    func assertStart() throws {
        let promise = try harness.start(shell)
        harness.channel.run()
        XCTAssertTrue(harness.channel.isActive)
        XCTAssertEqual(
            harness.channel.outboundEvents,
            [SSHChannelRequestEvent.ShellRequest(wantReply: true)]
        )
        XCTAssertEqual(recordedData, [])
        XCTAssertEqual(recordedStates, [])
        harness.channel.triggerInbound(ChannelSuccessEvent())
        harness.channel.run()
        try promise.wait()
        XCTAssertEqual(recordedData, [])
        XCTAssertEqual(recordedStates, [.ready])
    }
}
