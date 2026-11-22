import Foundation

/// ULID (26 znaků Crockford base32: 48 bitů času v ms + 80 náhodných bitů).
public enum ULID {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static func make(date: Date = Date()) -> String {
        var rng = SystemRandomNumberGenerator()
        return make(ms: UInt64(max(0, date.timeIntervalSince1970 * 1000)), using: &rng)
    }

    static func make<R: RandomNumberGenerator>(ms: UInt64, using rng: inout R) -> String {
        var out = [Character]()
        out.reserveCapacity(26)
        for i in stride(from: 45, through: 0, by: -5) { // 10 znaků času
            out.append(alphabet[Int((ms >> UInt64(i)) & 0x1F)])
        }
        // 80 bitů náhody = 16 znaků po 5 bitech
        let hi = UInt64(rng.next() as UInt16), lo = rng.next() as UInt64
        for i in stride(from: 75, through: 0, by: -5) {
            let v: UInt64 = i >= 64 ? (hi >> UInt64(i - 64)) : (i > 59 ? ((hi << UInt64(64 - i)) | (lo >> UInt64(i))) : (lo >> UInt64(i)))
            out.append(alphabet[Int(v & 0x1F)])
        }
        return String(out)
    }
}
