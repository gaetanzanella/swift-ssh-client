# Swift SSH Client

This project provides high-level SSH client interfaces using [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh).

## Requirements

`Swift SSH Client` is compatible with iOS 13.0+ and macOS 10.5+.

## Getting started

SSH is a multiplexed protocol: each SSH connection is subdivided into multiple bidirectional communication channels.    

`Swift SSH Client` reflects this pattern. The first step is to set a connection up:

```swift
let connection = SSHConnection(
    host: "my_host",
    port: my_port,
    authentication: SSHAuthentication(
        username: "my_username",
        method: .password(.init("my_password")),
        hostKeyValidation: .acceptAll()
    )
)

try await connection.start()
```
 
Once connected, you can start executing concrete SSH operations on child communication channels. As `SSH Client` means to be a high level interface, you do not directly interact with them. Instead you use interfaces dedicated to your use case.

- SSH shell
```swift
let shell = try await connection.requestShell()
for try await chunk in shell.data {
    // ...
}
```

- SFTP client
```swift
let sftpClient = try await connection.requestSFTPClient()
// sftp operations
``` 

- SSH commands
```swift
let response = try await connection.execute("echo Hello\n")
// Handle response
```

You keep track of the connection state, using the dedicated `stateUpdateHandler` property:
```swift
connection.stateUpdateHandle = { state in
    switch state {
    case .idle, .failed:
        // Handle disconnection
    case .ready:
        // Handle connection start
    }
}
```

As `SSHConnection` represents the overall SSH connection, if it ends, all the SSH operations or clients linked to it will end accordingly.

## Beta version

Consider the `0.1` version as a beta version. From patch to patch, the project API can change a lot. 

## License

`Swift SSH Client` is available under the MIT license. See the `LICENSE.txt` file for more info.
