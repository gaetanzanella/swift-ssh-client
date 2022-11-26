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

connection.start(withTimeout: 3.0) { result in
    switch result {
    case .success:
        // Handle connection
    case .failure:
        // Handle failure
    }
}
```
 
Once connected, you can start executing concrete SSH operations. 
As `SSH Client` means to be a high level interface, you do not directly interact with channels. 

Instead you use interfaces dedicated to your use case:

- SSH shell
```swift
connection.requestShell(withTimeout: 3.0) { result in
    switch result {
    case .success(let shell):
        // Start shell operations
    ...
    }
}
```

- SFTP client
```swift
connection.requestSFTPClient(withTimeout: 3.0) { result in
    switch result {
    case .success(let client):
        // Start sftp operations
    ...
    }
}
``` 

- SSH commands
```swift
let command = "echo Hello".data(using: .utf8)!
connection.execute(command) { result in
    switch result {
    case .success(let response):
        // Handle response
    case .failure:
        // Handle failure
    }
}
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

## License

`Swift SSH Client` is available under the MIT license. See the `LICENSE.txt` file for more info.
