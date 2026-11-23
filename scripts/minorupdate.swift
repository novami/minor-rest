#!/usr/bin/env swift
// MinorUpdate: shared Ed25519 signing for the Minor* apps (MinorIDE, MinorREST, MinorDLNA).
//
//   swift tools/minorupdate.swift keygen
//       Creates the key pair once. The private key goes to the login Keychain (service
//       "MinorUpdate", never to a file or a process argument); prints the public key (base64)
//       for MINORIDE_UPDATE_PUBLIC_KEY.
//   swift tools/minorupdate.swift sign <archive> <appID> <version> <https-url> [notes.md]
//       Prints appcast.json (the feed) for the archive. Upload it next to the archive as a release asset.
//
// The signed message is "minorupdate-v1\n<appID>\n<version>\n<sha256 hex>" (UpdateVerifier.signedMessage).
import CryptoKit
import Foundation
import Security

let service = "MinorUpdate", account = "ed25519-private-key"

func fail(_ message: String) -> Never {
	FileHandle.standardError.write(Data((message + "\n").utf8))
	exit(1)
}

func loadKey() -> Curve25519.Signing.PrivateKey? {
	let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
	                            kSecAttrAccount as String: account, kSecReturnData as String: true]
	var item: CFTypeRef?
	guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
	return try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "keygen":
	if let existing = loadKey() {
		print("Key already exists. Public key:\n" + existing.publicKey.rawRepresentation.base64EncodedString())
		exit(0)
	}
	let key = Curve25519.Signing.PrivateKey()
	let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
	                          kSecAttrAccount as String: account, kSecValueData as String: key.rawRepresentation,
	                          kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
	guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { fail("could not store the key in the Keychain") }
	print("Created. Public key:\n" + key.publicKey.rawRepresentation.base64EncodedString())
	print("Back up the private key (Keychain item \"\(service)\"): lost key = no more updates for installed apps.")
case "sign" where args.count >= 5:
	guard let key = loadKey() else { fail("no key; run keygen first") }
	guard let data = try? Data(contentsOf: URL(fileURLWithPath: args[1])) else { fail("cannot read \(args[1])") }
	let appID = args[2], version = args[3], url = args[4]
	guard url.hasPrefix("https://") else { fail("the URL must be https") }
	let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
	let message = Data("minorupdate-v1\n\(appID)\n\(version)\n\(hex)".utf8)
	guard let signature = try? key.signature(for: message) else { fail("signing failed") }
	var feed: [String: Any] = ["version": version, "url": url, "sha256": hex, "signature": signature.base64EncodedString()]
	if args.count > 5, let notes = try? String(contentsOfFile: args[5], encoding: .utf8) { feed["notes"] = notes }
	guard let json = try? JSONSerialization.data(withJSONObject: feed, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { fail("encoding failed") }
	print(String(decoding: json, as: UTF8.self))
default:
	fail("usage: minorupdate.swift keygen | sign <archive> <appID> <version> <https-url> [notes.md]")
}
