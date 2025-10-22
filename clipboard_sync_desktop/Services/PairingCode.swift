import Foundation

enum PairingCode {
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    static func generate(address: String, port: UInt16) -> String? {
        let parts = address.split(separator: ".")
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { UInt8($0) }
        guard octets.count == 4 else { return nil }

        var payload = octets
        payload.append(UInt8(port >> 8))
        payload.append(UInt8(port & 0xFF))
        let checksum = payload.reduce(0) { ($0 &+ UInt16($1)) & 0xFF }
        payload.append(UInt8(checksum))

        let encoded = base32EncodedString(payload)
        return stride(from: 0, to: encoded.count, by: 4)
            .map { index -> String in
                let end = encoded.index(encoded.startIndex, offsetBy: min(index + 4, encoded.count))
                let start = encoded.index(encoded.startIndex, offsetBy: index)
                return String(encoded[start..<end])
            }
            .joined(separator: "-")
    }

    static func parse(_ code: String) -> (address: String, port: UInt16)? {
        let cleaned = code.uppercased().filter { alphabet.contains($0) }
        guard !cleaned.isEmpty else { return nil }
        let bytes = base32DecodedBytes(cleaned)
        guard bytes.count >= 7 else { return nil }

        let ipBytes = Array(bytes[0..<4])
        let portBytes = Array(bytes[4..<6])
        let checksum = bytes[6]
        let expected = (ipBytes + portBytes).reduce(0) { ($0 &+ UInt16($1)) & 0xFF }
        guard checksum == expected else { return nil }

        let address = ipBytes.map(String.init).joined(separator: ".")
        let port = UInt16(portBytes[0]) << 8 | UInt16(portBytes[1])
        return (address, port)
    }

    private static func base32EncodedString(_ bytes: [UInt8]) -> String {
        var buffer = 0
        var bitsLeft = 0
        var output = ""

        for byte in bytes {
            buffer = (buffer << 8) | Int(byte)
            bitsLeft += 8
            while bitsLeft >= 5 {
                bitsLeft -= 5
                let index = (buffer >> bitsLeft) & 0x1F
                output.append(alphabet[index])
            }
        }

        if bitsLeft > 0 {
            let index = (buffer << (5 - bitsLeft)) & 0x1F
            output.append(alphabet[index])
        }

        return output
    }

    private static func base32DecodedBytes(_ string: String) -> [UInt8] {
        var buffer = 0
        var bitsLeft = 0
        var output: [UInt8] = []

        for character in string {
            guard let index = alphabet.firstIndex(of: character) else { continue }
            buffer = (buffer << 5) | index
            bitsLeft += 5

            if bitsLeft >= 8 {
                bitsLeft -= 8
                let byte = UInt8((buffer >> bitsLeft) & 0xFF)
                output.append(byte)
            }
        }

        return output
    }
}
