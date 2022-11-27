
import CCryptoBoringSSL
import Crypto
import Foundation
import NIO
import NIOSSH

enum AES128CTRTransportProtectionError: Error {
    case invalidKeySize
    case invalidEncryptedPacketLength
    case invalidDecryptedPlaintextLength
    case insufficientPadding, excessPadding
    case invalidMac
    case cryptographicError
    case invalidSignature
    case signingError
    case unsupported
    case commandOutputTooLarge
    case channelCreationFailed
}

final class AES128CTRTransportProtection: NIOSSHTransportProtection {
    static let macName: String? = "hmac-sha2-256"
    static let cipherBlockSize = 16
    static let cipherName = "aes128-ctr"

    static let keySizes = ExpectedKeySizes(
        ivSize: 16,
        encryptionKeySize: 16, // 128 bits
        macKeySize: 32 // hmac-sha2-256
    )

    let macBytes = 32 // hmac-sha2-256
    private var keys: NIOSSHSessionKeys
    private var decryptionContext: UnsafeMutablePointer<EVP_CIPHER_CTX>
    private var encryptionContext: UnsafeMutablePointer<EVP_CIPHER_CTX>

    init(initialKeys: NIOSSHSessionKeys) throws {
        guard
            initialKeys.outboundEncryptionKey.bitCount == Self.keySizes.encryptionKeySize * 8,
            initialKeys.inboundEncryptionKey.bitCount == Self.keySizes.encryptionKeySize * 8
        else {
            throw AES128CTRTransportProtectionError.invalidKeySize
        }

        keys = initialKeys

        encryptionContext = CCryptoBoringSSL_EVP_CIPHER_CTX_new()
        decryptionContext = CCryptoBoringSSL_EVP_CIPHER_CTX_new()

        let outboundEncryptionKey = initialKeys.outboundEncryptionKey.withUnsafeBytes { buffer -> [UInt8] in
            let outboundEncryptionKey = Array(buffer.bindMemory(to: UInt8.self))
            assert(outboundEncryptionKey.count == Self.keySizes.encryptionKeySize)
            return outboundEncryptionKey
        }

        let inboundEncryptionKey = initialKeys.inboundEncryptionKey.withUnsafeBytes { buffer -> [UInt8] in
            let inboundEncryptionKey = Array(buffer.bindMemory(to: UInt8.self))
            assert(inboundEncryptionKey.count == Self.keySizes.encryptionKeySize)
            return inboundEncryptionKey
        }

        guard CCryptoBoringSSL_EVP_CipherInit(
            encryptionContext,
            CCryptoBoringSSL_EVP_aes_128_ctr(),
            outboundEncryptionKey,
            initialKeys.initialOutboundIV,
            1
        ) == 1 else {
            throw AES128CTRTransportProtectionError.cryptographicError
        }

        guard CCryptoBoringSSL_EVP_CipherInit(
            decryptionContext,
            CCryptoBoringSSL_EVP_aes_128_ctr(),
            inboundEncryptionKey,
            initialKeys.initialInboundIV,
            0
        ) == 1 else {
            throw AES128CTRTransportProtectionError.cryptographicError
        }
    }

    var lengthEncrypted: Bool {
        true
    }

    func updateKeys(_ newKeys: NIOSSHSessionKeys) throws {
        guard
            newKeys.outboundEncryptionKey.bitCount == Self.keySizes.encryptionKeySize * 8,
            newKeys.inboundEncryptionKey.bitCount == Self.keySizes.encryptionKeySize * 8
        else {
            throw AES128CTRTransportProtectionError.invalidKeySize
        }

        keys = newKeys

        let outboundEncryptionKey = newKeys.outboundEncryptionKey.withUnsafeBytes { buffer -> [UInt8] in
            let outboundEncryptionKey = Array(buffer.bindMemory(to: UInt8.self))
            assert(outboundEncryptionKey.count == Self.keySizes.encryptionKeySize)
            return outboundEncryptionKey
        }

        let inboundEncryptionKey = newKeys.inboundEncryptionKey.withUnsafeBytes { buffer -> [UInt8] in
            let inboundEncryptionKey = Array(buffer.bindMemory(to: UInt8.self))
            assert(inboundEncryptionKey.count == Self.keySizes.encryptionKeySize)
            return inboundEncryptionKey
        }

        guard CCryptoBoringSSL_EVP_CipherInit(
            encryptionContext,
            CCryptoBoringSSL_EVP_aes_128_ctr(),
            outboundEncryptionKey,
            newKeys.initialOutboundIV,
            1
        ) == 1 else {
            throw AES128CTRTransportProtectionError.cryptographicError
        }

        guard CCryptoBoringSSL_EVP_CipherInit(
            decryptionContext,
            CCryptoBoringSSL_EVP_aes_128_ctr(),
            inboundEncryptionKey,
            newKeys.initialInboundIV,
            0
        ) == 1 else {
            throw AES128CTRTransportProtectionError.cryptographicError
        }
    }

    func decryptFirstBlock(_ source: inout ByteBuffer) throws {
        // For us, decrypting the first block is very easy: do nothing. The length bytes are already
        // unencrypted!
        guard source.readableBytes >= 16 else {
            throw AES128CTRTransportProtectionError.invalidKeySize
        }

        try source.readWithUnsafeMutableReadableBytes { source in
            let source = source.bindMemory(to: UInt8.self)
            let out = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.cipherBlockSize)
            defer { out.deallocate() }

            guard CCryptoBoringSSL_EVP_Cipher(
                decryptionContext,
                out,
                source.baseAddress!,
                Self.cipherBlockSize
            ) == 1 else {
                throw AES128CTRTransportProtectionError.cryptographicError
            }

            memcpy(source.baseAddress!, out, Self.cipherBlockSize)
            return 0
        }
    }

    func decryptAndVerifyRemainingPacket(_ source: inout ByteBuffer, sequenceNumber: UInt32) throws -> ByteBuffer {
        // The first 4 bytes are the length. The last 16 are the tag. Everything else is ciphertext. We expect
        // that the ciphertext is a clean multiple of the block size, and to be non-zero.
        guard
            var plaintext = source.readBytes(length: 16),
            let ciphertext = source.readBytes(length: source.readableBytes - macBytes),
            let macHash = source.readBytes(length: macBytes),
            ciphertext.count % Self.cipherBlockSize == 0
        else {
            // The only way this fails is if the payload doesn't match this encryption scheme.
            throw AES128CTRTransportProtectionError.invalidEncryptedPacketLength
        }

        if !ciphertext.isEmpty {
            // Ok, let's try to decrypt this data.
            plaintext += try ciphertext.withUnsafeBufferPointer { ciphertext -> [UInt8] in
                let ciphertextPointer = ciphertext.baseAddress!

                return try [UInt8](
                    unsafeUninitializedCapacity: ciphertext.count,
                    initializingWith: { plaintext, count in
                        let plaintextPointer = plaintext.baseAddress!

                        while count < ciphertext.count {
                            guard CCryptoBoringSSL_EVP_Cipher(
                                decryptionContext,
                                plaintextPointer + count,
                                ciphertextPointer + count,
                                Self.cipherBlockSize
                            ) == 1 else {
                                throw AES128CTRTransportProtectionError.cryptographicError
                            }

                            count += Self.cipherBlockSize
                        }
                    }
                )
            }

            // All good! A quick soundness check to verify that the length of the plaintext is ok.
            guard plaintext.count % Self.cipherBlockSize == 0 else {
                throw AES128CTRTransportProtectionError.invalidDecryptedPlaintextLength
            }
        }

        func test(sequenceNumber: UInt32) -> Bool {
            var hmac = Crypto.HMAC<Crypto.SHA256>(key: keys.inboundMACKey)
            withUnsafeBytes(of: sequenceNumber.bigEndian) { buffer in
                hmac.update(data: buffer)
            }
            hmac.update(data: plaintext)

            return hmac.finalize().withUnsafeBytes { buffer -> Bool in
                let buffer = Array(buffer.bindMemory(to: UInt8.self))
                return buffer == macHash
            }
        }

        if !test(sequenceNumber: sequenceNumber) {
            throw AES128CTRTransportProtectionError.invalidMac
        }

        plaintext.removeFirst(4)
        let paddingLength = Int(plaintext.removeFirst())

        guard paddingLength < plaintext.count else {
            throw AES128CTRTransportProtectionError.invalidDecryptedPlaintextLength
        }

        plaintext.removeLast(paddingLength)

        return ByteBuffer(bytes: plaintext)
    }

    func encryptPacket(_ destination: inout ByteBuffer, sequenceNumber: UInt32) throws {
        let packetLengthIndex = destination.readerIndex
        let encryptedBufferSize = destination.readableBytes
        let plaintext = destination.getBytes(
            at: packetLengthIndex,
            length: encryptedBufferSize
        )!
        assert(plaintext.count % Self.cipherBlockSize == 0)

        var hmac = Crypto.HMAC<Crypto.SHA256>(key: keys.outboundMACKey)
        withUnsafeBytes(of: sequenceNumber.bigEndian) { buffer in
            hmac.update(data: buffer)
        }
        hmac.update(data: plaintext)
        let macHash = hmac.finalize()

        let ciphertext = try plaintext.withUnsafeBufferPointer { plaintext -> [UInt8] in
            let plaintextPointer = plaintext.baseAddress!

            return try [UInt8](unsafeUninitializedCapacity: plaintext.count) { ciphertext, count in
                let ciphertextPointer = ciphertext.baseAddress!

                while count < encryptedBufferSize {
                    guard CCryptoBoringSSL_EVP_Cipher(
                        encryptionContext,
                        ciphertextPointer + count,
                        plaintextPointer + count,
                        Self.cipherBlockSize
                    ) == 1 else {
                        throw AES128CTRTransportProtectionError.cryptographicError
                    }

                    count += Self.cipherBlockSize
                }
            }
        }

        assert(ciphertext.count == plaintext.count)
        destination.setBytes(ciphertext, at: packetLengthIndex)
        destination.writeContiguousBytes(macHash)
    }

    deinit {
        CCryptoBoringSSL_EVP_CIPHER_CTX_free(encryptionContext)
        CCryptoBoringSSL_EVP_CIPHER_CTX_free(decryptionContext)
    }
}

private extension ByteBuffer {
    /// Prepends the given Data to this ByteBuffer.
    ///
    /// Will crash if there isn't space in the front of this buffer, so please ensure there is!
    mutating func prependBytes(_ bytes: [UInt8]) {
        moveReaderIndex(to: readerIndex - bytes.count)
        setContiguousBytes(bytes, at: readerIndex)
    }
}
