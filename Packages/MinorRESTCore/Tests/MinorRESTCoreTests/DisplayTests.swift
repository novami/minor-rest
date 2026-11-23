import Foundation
import Testing
@testable import MinorRESTCore

@Test(arguments: [
    (Int64(999), "cs", "999 B"), (6400, "cs", "6,4 kB"), (6400, "en", "6.4 kB"), (12_345_678, "cs", "12,3 MB"),
])
func displayBytes(n: Int64, lang: String, expected: String) {
    #expect(DisplayFormat.bytes(n, locale: Locale(identifier: lang)) == expected)
}

@Test(arguments: [(133.4, "cs", "133 ms"), (999.4, "cs", "999 ms"), (1234, "cs", "1,23 s"), (1234, "en", "1.23 s")])
func displayDuration(ms: Double, lang: String, expected: String) {
    #expect(DisplayFormat.duration(ms: ms, locale: Locale(identifier: lang)) == expected)
}

@Test func markupXML() {
    let xml = #"<?xml version="1.0"?><a x="1>2"><b>text</b><c/><d><e></e></d><!-- k --></a>"#
    #expect(MarkupFormatter.format(xml, html: false) == """
    <?xml version="1.0"?>
    <a x="1>2">
      <b>text</b>
      <c/>
      <d>
        <e></e>
      </d>
      <!-- k -->
    </a>
    """)
}

@Test func markupHTML() {
    let html = "<!DOCTYPE html><HTML><body><p>a<br>b<p>c</body><script>if (a<b) x()</script></html>"
    #expect(MarkupFormatter.format(html, html: true) == """
    <!DOCTYPE html>
    <HTML>
      <body>
        <p>
          a
          <br>
          b
          <p>
            c
      </body>
      <script>if (a<b) x()</script>
    </html>
    """)
    // neuzavřená značka = zbytek jako text
    #expect(MarkupFormatter.format("<a><b", html: false) == "<a>\n  <b")
}

@Test func htmlPreviewCSP() {
    #expect(HTMLPreview.sandboxed("\n<!DOCTYPE html><p>x") == "\n<!DOCTYPE html>" + HTMLPreview.csp + "<p>x")
    #expect(HTMLPreview.sandboxed("<p>x") == HTMLPreview.csp + "<p>x")
}
