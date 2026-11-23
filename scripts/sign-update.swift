// Podpis aktualizací (ed25519). Použití:
//   swift scripts/sign-update.swift --gen            # vypíše nový pár klíčů (base64)
//   UPDATE_SIGNING_KEY=<base64> swift scripts/sign-update.swift --file X.zip   # vypíše podpis (base64)
import CryptoKit
import Foundation

let args = CommandLine.arguments
if args.contains("--gen") {
    let key = Curve25519.Signing.PrivateKey()
    print("private (do GitHub Secret UPDATE_SIGNING_KEY): \(key.rawRepresentation.base64EncodedString())")
    print("public  (MRUpdatePublicKey v project.yml):     \(key.publicKey.rawRepresentation.base64EncodedString())")
} else if let i = args.firstIndex(of: "--file"), i + 1 < args.count {
    guard let b64 = ProcessInfo.processInfo.environment["UPDATE_SIGNING_KEY"], let raw = Data(base64Encoded: b64),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw),
          let data = FileManager.default.contents(atPath: args[i + 1]) else {
        FileHandle.standardError.write(Data("chybí UPDATE_SIGNING_KEY nebo soubor\n".utf8))
        exit(1)
    }
    print(try key.signature(for: data).base64EncodedString())
} else {
    FileHandle.standardError.write(Data("použití: --gen | --file <soubor>\n".utf8))
    exit(2)
}
