
import Foundation
import NIO
import NIOSSH

struct BuiltInSSHAuthenticationValidator: NIOSSHClientUserAuthenticationDelegate {
    enum AuthenticationError: Error {
        case unavailableMethod
    }

    let authentication: SSHAuthentication

    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods,
                                nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>)
    {
        switch authentication.method.implementation {
        case .none:
            nextChallengePromise.succeed(
                NIOSSHUserAuthenticationOffer(
                    username: authentication.username,
                    serviceName: "",
                    offer: .none
                )
            )
        case .password(let password):
            guard availableMethods.contains(.password) else {
                nextChallengePromise.fail(AuthenticationError.unavailableMethod)
                return
            }
            nextChallengePromise.succeed(
                NIOSSHUserAuthenticationOffer(
                    username: authentication.username,
                    serviceName: "",
                    offer: .password(
                        NIOSSHUserAuthenticationOffer.Offer.Password(
                            password: password.password
                        )
                    )
                )
            )
        case .custom(let delegate):
            delegate.nextAuthenticationType(availableMethods: availableMethods, nextChallengePromise: nextChallengePromise)
        }
    }
}

struct BuiltInSSHClientServerAuthenticationValidator: NIOSSHClientServerAuthenticationDelegate {
    let validation: SSHAuthentication.HostKeyValidation

    func validateHostKey(hostKey: NIOSSHPublicKey,
                         validationCompletePromise: EventLoopPromise<Void>) {
        switch validation.implementation {
        case .acceptAll:
            validationCompletePromise.succeed(())
        case .custom(let delegate):
            delegate.validateHostKey(hostKey: hostKey, validationCompletePromise: validationCompletePromise)
        }
    }
}

class SSHAuthenticationHandler: ChannelInboundHandler {
    enum AuthenticationError: Error {
        case timeout
        case endedChannel
    }

    typealias InboundIn = Any

    private let promise: EventLoopPromise<Void>
    public var authenticated: EventLoopFuture<Void> {
        promise.futureResult
    }

    private let task: Scheduled<Void>

    init(eventLoop: EventLoop, timeout: TimeAmount) {
        let promise = eventLoop.makePromise(of: Void.self)
        self.promise = promise
        task = eventLoop.scheduleTask(in: timeout) {
            promise.fail(AuthenticationError.timeout)
        }
    }

    deinit {
        task.cancel()
        promise.fail(AuthenticationError.endedChannel)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is UserAuthSuccessEvent {
            promise.succeed(())
        }
        context.fireUserInboundEventTriggered(event)
    }
}
