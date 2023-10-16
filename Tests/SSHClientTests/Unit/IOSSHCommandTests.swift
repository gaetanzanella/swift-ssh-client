
import Foundation
import NIOCore
import NIOEmbedded
import NIOSSH
@testable import SSHClient
import XCTest

class IOSSHCommandTests: XCTestCase {
    func testSimpleInvocation() throws {
        let context = IOSSHCommandTestsContext(command: SSHCommand("echo"))
        let future = try context.assertStart()
        try context.serverEnd()
        XCTAssertNoThrow(try future.wait())
    }

    func testRegularInvocation() throws {
        let context = IOSSHCommandTestsContext(command: SSHCommand("echo main"))
        let future = try context.assertStart()
        var isCompleted = false
        future.whenComplete { _ in isCompleted = true }
        let data = context.harness.channel.triggerInboundChannelString("main")
        XCTAssertEqual(
            [SSHCommandChunk(channel: .standard, data: data)],
            context.chunks
        )
        let error = context.harness.channel.triggerInboundSTDErrString("error")
        XCTAssertEqual(
            [
                SSHCommandChunk(channel: .standard, data: data),
                SSHCommandChunk(channel: .error, data: error),
            ],
            context.chunks
        )
        let exitStatus = SSHChannelRequestEvent.ExitStatus(exitStatus: 1)
        context.harness.channel.triggerInbound(exitStatus)
        XCTAssertEqual(
            [SSHCommandStatus(exitStatus: exitStatus.exitStatus)],
            context.status
        )
        XCTAssertFalse(isCompleted)
        try context.serverEnd()
        XCTAssertNoThrow(try future.wait())
    }

    func testChannelClosingOnInputClosed() throws {
        let context = IOSSHCommandTestsContext(command: SSHCommand("echo"))
        let future = try context.assertStart()
        try context.harness.channel.close().wait()
        context.harness.run()
        XCTAssertThrowsError(try future.wait())
    }

    func testChannelClosingOnError() throws {
        let context = IOSSHCommandTestsContext(command: SSHCommand("echo"))
        let future = try context.assertStart()
        context.harness.channel.fireErrorCaught()
        context.harness.run()
        XCTAssertThrowsError(try future.wait())
    }

    func testChannelClosingOnOutboundFailure() throws {
        let context = IOSSHCommandTestsContext(command: SSHCommand("echo"))
        context.harness.channel.shouldFailOnOutboundEvent = true
        try context.harness.channel.connect().wait()
        let futur = try context.harness.start(context.session)
        context.harness.run()
        XCTAssertThrowsError(try futur.wait())
    }
}

private class IOSSHCommandTestsContext {
    private(set) var invocation: SSHCommandInvocation!
    private(set) var session: SSHCommandSession!
    let harness = SSHSessionHarness()

    private(set) var chunks: [SSHCommandChunk] = []
    private(set) var status: [SSHCommandStatus] = []

    private let channel = EmbeddedSSHChannel()

    init(command: SSHCommand) {
        invocation = SSHCommandInvocation(
            command: command,
            onChunk: { self.chunks.append($0) },
            onStatus: { self.status.append($0) }
        )
        session = SSHCommandSession(invocation: invocation)
    }

    func assertStart() throws -> Future<Void> {
        try channel.connect().wait()
        let promise = try harness.start(session)
        harness.channel.run()
        XCTAssertTrue(harness.channel.isActive)
        XCTAssertEqual(
            harness.channel.outboundEvents,
            [SSHChannelRequestEvent.ExecRequest(
                command: invocation.command.command,
                wantReply: true
            )]
        )
        XCTAssertEqual(chunks, [])
        XCTAssertEqual(status, [])
        return promise
    }

    func serverEnd() throws {
        let closing = ChannelEvent.inputClosed
        harness.channel.triggerInbound(closing)
        harness.run()
    }
}
