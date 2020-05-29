import Algorithms // for Collection.trim
import SE0270_RangeSet

/// A String which is known to contain a valid URL.
///
public struct XURL {
    var string: String
}

extension XURL {

    public struct Components: Equatable {
        struct Authority: Equatable {
            var username: String?
            var password: String?
            var host: XURL.Host?
            var port: Int?
        }

        var scheme: String?
        var authority = Authority()
        var path: [String] = []
        var query: String?
        var fragment: String?
        var cannotBeABaseURL = false

        var isSpecial: Bool {
            scheme.flatMap { XURL.Parser.SpecialScheme(rawValue: $0) } != nil
        }

        var hasCredentials: Bool {
            authority.username != nil || authority.password != nil
        }
    }
}

extension XURL.Components: CustomDebugStringConvertible {

    public var debugDescription: String {
        return """
        Scheme:\t\(scheme ?? "<nil>")
        Authority:\t\(authority)
        Path:\t\(path)
        Query:\t\(query ?? "<nil>")
        Fragment:\t\(fragment ?? "<nil>")
        """
    }
}

/*
Note: Unicode requirements of URLs:

- Scheme must be ASCII (one alpha, followed by alphanumerics, +/-/. )
- Username must be ASCII
- Password must be ASCII
- Port must be ASCII digits
- Host must be empty, an IP address, opaque (an ASCII string), or a _domain_:
- Domains are ASCII, but non-ASCII domains can be encoded via Punycode
- Path is a list of ASCII strings
- Query and Fragment are both ASCII strings

*/
extension Character {
    private var asciiValue: UInt8? {
        self.isASCII ? self.utf8.first.unsafelyUnwrapped : nil
    }

    fileprivate var isC0OrSpace: Bool {
        self.asciiValue.map { 
            (0x00...0x20).contains($0)
            } ?? false
    }

    fileprivate var isASCIINewlineOrTab: Bool {
        self.asciiValue.map { 
            $0 == 0x09 // TAB 
                || $0 == 0x0A // LF
                || $0 == 0x0D // CR
            } ?? false
    }
}

extension StringProtocol {

    var isNormalisedWindowsDriveLetter: Bool {
        var it = makeIterator()
        guard let first = it.next(), ASCII.ranges.isAlpha(first) else { return false }
        guard let second = it.next(), second == ASCII.colon else { return false } 
        guard it.next() == nil else { return false }
        return true 
    }

    var isWindowsDriveLetter: Bool {
        isNormalisedWindowsDriveLetter || self.dropFirst().first == ASCII.verticalBar
    }

    func hasWindowsDriveLetterPrefix() -> Bool {
        var it = makeIterator()
        guard let first = it.next(), ASCII.ranges.isAlpha(first) else { return false }
        guard let second = it.next(), second == ASCII.colon || second == ASCII.verticalBar else { return false } 
        if let third = it.next() {
            guard third == ASCII.forwardSlash || third == ASCII.backslash ||
                third == ASCII.questionMark || third == ASCII.numberSign else {
                    return false
            }
        }
        return true 
    }

    /// Returns true if the next contents of `iterator` are either the ASCII period, %2e, or %2E.
    /// Otherwise, returns false.
    private func checkForDotOrCaseInsensitivePercentEncodedDot(in iterator: inout Iterator) -> Bool {
        guard let first = iterator.next() else { return false }
        if first == ASCII.period { return true }
        guard first == ASCII.percentSign, iterator.next() == ASCII.n2,
              let third = iterator.next(), third == ASCII.E || third == ASCII.e else { return false }
        return true
    }

    var isSingleDotPathSegment: Bool {
        var it = makeIterator()
        guard checkForDotOrCaseInsensitivePercentEncodedDot(in: &it) else { return false }
        guard it.next() == nil else { return false }
        return true
    }

    var isDoubleDotPathSegment: Bool {
        var it = makeIterator()
        guard checkForDotOrCaseInsensitivePercentEncodedDot(in: &it) else { return false }
        guard checkForDotOrCaseInsensitivePercentEncodedDot(in: &it) else { return false }
        guard it.next() == nil else { return false }
        return true
    }
}

func shortenURLPath(_ path: inout [String], isFileScheme: Bool) {
    guard path.isEmpty == false else { return }
    if isFileScheme, path.count == 1, path[0].isNormalisedWindowsDriveLetter { return }
    path.removeLast()
}



extension XURL {

    /// This parser is pretty-much a direct transcription of the WHATWG spec in to Swift.
    /// See: https://url.spec.whatwg.org/#url-parsing
    ///
    public struct Parser {}
}

extension XURL.Parser {

    enum SpecialScheme: String {
        case ftp = "ftp"
        case file = "file"
        case http = "http"
        case https = "https"
        case ws = "ws"
        case wss = "wss"

        var defaultPort: Int? {
            switch self {
            case .ftp:   return 21
            case .file:  return nil
            case .http:  return 80
            case .https: return 443
            case .ws:    return 80
            case .wss:   return 443
            }
        }
    }

    enum State {
        case schemeStart
        case scheme
        case noScheme
        case specialRelativeOrAuthority
        case pathOrAuthority
        case relative
        case relativeSlash
        case specialAuthoritySlashes
        case specialAuthorityIgnoreSlashes
        case authority
        case host
        case port
        case file
        case fileSlash
        case fileHost
        case pathStart
        case path
        case cannotBeABaseURLPath
        case query
        case fragment
    }

    public static func parse(_ input: String) -> XURL.Components? {
        parse(input, base: nil, url: nil, stateOverride: nil)
    }

    static func parse(_ input: String, base: XURL.Components?, url: XURL.Components?, stateOverride: State?) -> XURL.Components? {
        guard !input.isEmpty else { return nil }

        func validationFailure(_ msg: String) {
            print("Validation failure - \(msg).")
        }

        var input = input[...]

        // 1. Trim leading/trailing C0 control characters and spaces.
        input = input.trim { $0.isC0OrSpace }

        // 2. Remove all ASCII newlines and tabs. 
        let invalidRanges = input.subranges { $0.isASCIINewlineOrTab }
        if !invalidRanges.isEmpty { validationFailure("Input contains newline or tab characters") }
        input.removeSubranges(invalidRanges)

        // 3. Begin state machine.
        var state = stateOverride ?? .schemeStart
        var url   = url ?? XURL.Components()

        var idx    = input.startIndex
        var buffer = ""
        var flag_at = false // @flag in spec.
        var flag_squareBracket = false // [] flag in spec.

        func __UNIMPLEMENTED() {
            print("Unhandled state - \(state)\nInput: \(input)\nRemaining: \(input[idx...])\nParsed: \(url)\n")
        }

        inputLoop: while true {
            stateMachine: switch state {

            case .schemeStart:
                // TODO: Handle endIndex/EOF.
                let c = input[idx]
                guard ASCII.ranges.isAlpha(c) else {
                    guard stateOverride == nil else {
                        validationFailure("Scheme starts with invalid character")
                        return nil
                    }
                    state = .noScheme
                    continue // Do not increment index.
                }
                buffer.append(c.lowercased())
                state = .scheme 

            case .scheme:
                // TODO: Handle endIndex/EOF.
                let c = input[idx]
                let isAllowedNonAlphaNumeric = c.asciiValue.map { 
                    $0 == ASCII.plus || $0 == ASCII.minus || $0 == ASCII.period 
                    } ?? false

                guard !(ASCII.ranges.isAlphaNumeric(c) || isAllowedNonAlphaNumeric) else {
                    buffer.append(c.lowercased())
                    break stateMachine
                }
                guard c == ASCII.colon else {
                    guard stateOverride == nil else {
                        print("Validation failure - invalid scheme")
                        return nil
                    }
                    buffer = ""
                    state  = .noScheme
                    idx    = input.startIndex
                    continue // Do not increment index.
                }
                let bufferSpecialScheme = SpecialScheme(rawValue: buffer)
                if stateOverride != nil {
                    let urlSpecialScheme = url.scheme.flatMap { SpecialScheme(rawValue: $0) }
                    if (urlSpecialScheme == nil) != (bufferSpecialScheme == nil) { 
                        break inputLoop
                    }
                    if bufferSpecialScheme == .file && (url.hasCredentials || url.authority.port != nil) {
                        break inputLoop
                    }
                    if urlSpecialScheme == .file && (url.authority.host?.isEmpty ?? true) {
                        break inputLoop
                    }
                }

                url.scheme = buffer
                buffer = ""

                if stateOverride != nil {
                    if url.authority.port == bufferSpecialScheme?.defaultPort { url.authority.port = nil }
                    break inputLoop
                }
                switch bufferSpecialScheme {
                case .file:
                    state = .file
                    if !input[idx...].hasPrefix("//") { // FIXME: ASCII check.
                        print("Validation error - file URL should start with file://")
                    }
                case .some(_):
                    if base?.scheme == url.scheme {
                        state = .specialRelativeOrAuthority
                    } else {
                        state = .specialAuthoritySlashes
                    }
                case .none:
                    let nextIdx = input.index(after: idx)
                    if nextIdx != input.endIndex, input[nextIdx] == ASCII.forwardSlash {
                        state = .pathOrAuthority
                        idx   = nextIdx
                    } else {
                        // TODO: Spec says to append an empty string to url's path -- why?
                        url.cannotBeABaseURL = true
                        state = .cannotBeABaseURLPath
                    }
                }

            case .noScheme:
                // TODO: Handle endIndex/EOF.
                let c = input[idx]
                guard let base = base else {
                    validationFailure("input does not have a scheme, but no base given")
                    return nil
                }
                guard base.cannotBeABaseURL == false else {
                    guard c == ASCII.numberSign else {
                        validationFailure("base cannot be a base URL, and input is not a fragment")
                        return nil
                    }
                    url.scheme = base.scheme
                    url.path   = base.path
                    url.query  = base.query
                    url.fragment = ""
                    state = .fragment
                    break stateMachine
                }
                if base.scheme == SpecialScheme.file.rawValue {
                    state = .file
                } else {
                    state = .relative
                }
                continue // Do not increment index.

            case .specialRelativeOrAuthority:
                guard input[idx...].hasPrefix("//") else { // FIXME: ASCII check.
                    validationFailure("Expected // delimiter between scheme and authority")
                    state = .relative
                    continue // Do not increment index.    
                }
                state = .specialAuthorityIgnoreSlashes
                idx   = input.index(after: idx)

            case .pathOrAuthority:
                guard idx != input.endIndex, input[idx] == ASCII.forwardSlash else {
                    state = .path
                    continue // Do not increment index.
                }
                state = .authority

            case .relative:
                guard let base = base else {
                    // FIXME: I think this is correct. The spec doesn't say what happens if base is nil.
                    validationFailure("input is a relative URL; a base URL is required")
                    return nil
                }
                url.scheme = base.scheme
                guard idx != input.endIndex else {
                    url.authority = base.authority
                    url.path      = base.path
                    url.query     = base.query
                    break stateMachine
                }
                switch input[idx] {
                case ASCII.backslash where url.isSpecial:
                    validationFailure("Unexpected backslash in relative URL")
                    fallthrough
                case ASCII.forwardSlash:
                    state = .relativeSlash
                case ASCII.questionMark:
                    url.authority = base.authority
                    url.path      = base.path
                    url.query     = ""
                    state         = .query
                case ASCII.numberSign:
                    url.authority = base.authority
                    url.path      = base.path
                    url.query     = base.query
                    url.fragment  = ""
                    state         = .fragment
                default:
                    url.authority = base.authority
                    url.path      = base.path
                    url.path.removeLast()
                    state         = .path
                    continue // Do not increment index.
                }

            case .relativeSlash:
                // Treat endIndex like any non-slash character.
                let c = (idx == input.endIndex) ? Character(ASCII.a) : input[idx]
                let urlIsSpecial = url.isSpecial
                switch c {
                case ASCII.backslash where urlIsSpecial:
                    validationFailure("Unexpected relative backslash")
                    fallthrough
                case ASCII.forwardSlash:
                    if urlIsSpecial {
                        state = .specialAuthorityIgnoreSlashes
                    } else {
                        state = .authority
                    }
                default:
                    guard let base = base else {
                        validationFailure("Expected base URL for relative slash state")
                        return nil
                    }
                    url.authority = base.authority
                    state = .path
                    continue // Do not increment index.
                }

            case .specialAuthoritySlashes:
                state = .specialAuthorityIgnoreSlashes
                guard input[idx...].hasPrefix("//") else { // FIXME: ASCII check.
                    validationFailure("Expected // delimiter between scheme and authority")
                    continue // Do not increment index.
                }
                idx = input.index(after: idx)

            case .specialAuthorityIgnoreSlashes:
                // Treat endIndex like any non-slash character.
                let c = (idx == input.endIndex) ? Character(ASCII.a) : input[idx]
                guard c == ASCII.forwardSlash || c == ASCII.backslash else {
                    state = .authority
                    continue // Do not increment index.
                }
                validationFailure("Too many slashes between scheme and authority - will be ignored")

            case .authority:
                // Treat endIndex like a "/" as they are handled the same. 
                let c = (idx == input.endIndex) ? Character(ASCII.forwardSlash) : input[idx]
                switch c {
                case ASCII.commercialAt:
                    validationFailure("It is unwise to include credentials in URLs")
                    if flag_at {
                        buffer.insert(contentsOf: "%40", at: buffer.startIndex)
                    }
                    flag_at = true
                    // Parse username and password out of "buffer"
                    let passwordTokenIndex = buffer.firstIndex(where: { $0 == ASCII.colon })
                    let passwordStartIndex = passwordTokenIndex.flatMap { buffer.index(after: $0) }
                    let parsedUsername = buffer[..<(passwordTokenIndex ?? buffer.endIndex)].percentEscaped(where: url_escape_userInfo)
                    let parsedPassword = buffer[(passwordStartIndex ?? buffer.endIndex)...].percentEscaped(where: url_escape_userInfo)
                    url.authority.username = parsedUsername
                    url.authority.password = parsedPassword
                    if url.authority.username?.isEmpty == true { url.authority.username = nil }
                    if url.authority.password?.isEmpty == true { url.authority.password = nil }
                    buffer = ""
                case ASCII.forwardSlash, ASCII.questionMark, ASCII.numberSign: // or endIndex.
                    fallthrough
                case ASCII.backslash where url.isSpecial:
                    if flag_at, buffer.isEmpty {
                        validationFailure("Expected host after @")
                        return nil
                    }
                    idx    = input.index(idx, offsetBy: -1 * buffer.count)
                    buffer = ""
                    state  = .host
                    continue // Do not increment index.
                default:
                    buffer.append(c)
                }

            case .host:
                let urlSchemeIfSpecial = url.scheme.flatMap { SpecialScheme(rawValue: $0) }
                guard !(stateOverride != nil && urlSchemeIfSpecial == .file) else {
                    state = .fileHost
                    continue // Do not increment index.
                }
                // Treat endIndex like a "/" as they are handled the same. 
                let c = (idx == input.endIndex) ? Character(ASCII.forwardSlash) : input[idx]
                switch c {
                case ASCII.colon where flag_squareBracket == false:
                    guard buffer.isEmpty == false else {
                        validationFailure("Expected host before :")
                        return nil
                    }
                    guard let parsedHost = XURL.Host(buffer, isNotSpecial: urlSchemeIfSpecial == nil) else {
                        validationFailure("Failed to parse host")
                        return nil 
                    }
                    url.authority.host = parsedHost
                    buffer = ""
                    state  = .port
                    guard stateOverride != .host else { break inputLoop }
                case ASCII.forwardSlash, ASCII.questionMark, ASCII.numberSign: // and endIndex.
                    fallthrough
                case ASCII.backslash where urlSchemeIfSpecial != nil:
                    if buffer.isEmpty {
                        if urlSchemeIfSpecial != nil {
                            validationFailure("Expected host")
                            return nil
                        } else if stateOverride != nil, 
                            url.authority.username != nil || url.authority.password != nil, url.authority.port != nil {
                            validationFailure("Failed to set empty host - given components include other details")
                            return nil
                        }
                    }
                    guard let parsedHost = XURL.Host(buffer, isNotSpecial: urlSchemeIfSpecial == nil) else {
                        validationFailure("Failed to parse host")
                        return nil
                    }
                    url.authority.host = parsedHost
                    buffer = ""
                    state  = .pathStart
                    guard stateOverride == nil else { break inputLoop }
                    continue // Do not increment index.
                case ASCII.leftSquareBracket:
                    flag_squareBracket = true
                    buffer.append(c)
                case ASCII.rightSquareBracket:
                    flag_squareBracket = false
                    buffer.append(c)
                default:
                    buffer.append(c)
                }

            case .port:
                // Treat endIndex like a "/" as they are handled the same. 
                let c = (idx == input.endIndex) ? Character(ASCII.forwardSlash) : input[idx]
                switch c {
                case _ where ASCII.ranges.digits.contains(c):
                    buffer.append(c)
                case ASCII.forwardSlash, ASCII.questionMark, ASCII.numberSign: // and endIndex.
                    fallthrough
                case ASCII.backslash where url.isSpecial:
                    fallthrough
                case _ where stateOverride != nil:
                    guard !buffer.isEmpty, let parsedInteger = Int(buffer), parsedInteger < UInt16.max else {
                        validationFailure("Invalid value for port: \(buffer)")
                        return nil
                    }
                    if parsedInteger == url.scheme.flatMap({ SpecialScheme(rawValue: $0) })?.defaultPort {
                        url.authority.port = nil
                    } else {
                        url.authority.port = parsedInteger
                    }
                    buffer = ""
                    state  = .pathStart
                    guard stateOverride == nil else { break inputLoop }
                    continue // Do not increment index.
                default:
                    validationFailure("Invalid character in port: \(c)")
                    return nil
                }

            case .file:
                url.scheme = SpecialScheme.file.rawValue
                if idx != input.endIndex, (input[idx] == ASCII.forwardSlash || input[idx] == ASCII.backslash) {
                    if input[idx] == ASCII.backslash {
                        validationFailure("Unexpected backslash in file URL")
                    }
                    state = .fileSlash
                    break
                }
                if let base = base, base.scheme == SpecialScheme.file.rawValue {
                    guard idx != input.endIndex else {
                        url.authority.host = base.authority.host
                        url.path  = base.path
                        url.query = base.query
                        break
                    }
                    let c = input[idx]
                    switch c {
                    case ASCII.questionMark:
                        url.authority.host = base.authority.host
                        url.path  = base.path
                        url.query = ""
                        state     = .query

                    case ASCII.numberSign:
                        url.authority.host = base.authority.host
                        url.path     = base.path
                        url.query    = base.query
                        url.fragment = ""
                        state        = .fragment

                    default:
                        guard input[idx...].hasWindowsDriveLetterPrefix() == false else {
                            validationFailure("Unexpected windows drive letter")
                            state = .path
                            continue // Do not increment index.
                        }
                        url.authority.host = base.authority.host
                        url.path = base.path
                        shortenURLPath(&url.path, isFileScheme: true)
                    }
                } else {
                    state = .path
                    continue // Do not increment index.
                }

            case .fileSlash:
                if idx != input.endIndex {
                    let c = input[idx]
                    if c == ASCII.forwardSlash {
                        state = .fileHost
                        break stateMachine
                    } else if c == ASCII.backslash {
                        validationFailure("Unexpected backslash before file host")
                        state = .fileHost
                        break stateMachine
                    }
                }
                if let base = base, base.scheme == SpecialScheme.file.rawValue,
                    input[idx...].hasWindowsDriveLetterPrefix() == false {
                    if let basePathStart = base.path.first, basePathStart.isNormalisedWindowsDriveLetter {
                        url.path.append(basePathStart)
                    } else {
                        url.authority.host = base.authority.host
                    }
                }
                state = .path
                continue // Do not increment index.

            case .fileHost:
                let c = (idx == input.endIndex) ? Character(ASCII.forwardSlash) : input[idx]
                switch c {
                case ASCII.forwardSlash, ASCII.backslash, ASCII.questionMark, ASCII.numberSign: // or endIndex.
                    if stateOverride == nil, buffer.isWindowsDriveLetter {
                        validationFailure("Unexpected windows drive letter in file host")
                        state = .path
                        // Note: buffer is intentionally not reset and used in the path-parsing state.
                    } else if buffer.isEmpty {
                        url.authority.host = .empty
                        guard stateOverride == nil else { break inputLoop }
                        state = .pathStart
                    } else {
                        guard let parsedHost = XURL.Host(buffer, isNotSpecial: false) else { 
                            validationFailure("Failed to parse host")
                            return nil
                        }
                        url.authority.host = (parsedHost == .domain("localhost")) ? .empty : parsedHost
                        guard stateOverride == nil else { break inputLoop }
                        buffer = ""
                        state = .pathStart
                    }
                    continue // Do not increment index.
                default:
                    buffer.append(c)
                }

            case .pathStart:
                guard idx != input.endIndex else { 
                    state = .path
                    continue // Do not increment index.
                }
                let c = input[idx]
                if url.isSpecial {
                    if c == ASCII.backslash { validationFailure("Unexpected backslash at start of path") }
                    state = .path
                    if c != ASCII.forwardSlash, c != ASCII.backslash { 
                        continue // Do not increment index.
                    } 
                } else if stateOverride == nil, c == ASCII.questionMark {
                    url.query = ""
                    state = .query
                } else if stateOverride == nil, c == ASCII.numberSign {
                    url.fragment = ""
                    state = .fragment
                } else {
                    state = .path
                    guard c == ASCII.forwardSlash else { 
                        continue // Do not increment index.
                    }
                }

            case .path:
                let c: Character
                if idx == input.endIndex {
                    // FIXME: Double-check this. We need to send "endIndex" through this state machine,
                    // but it may not be correct to just treat it like a slash.
                    c = Character(ASCII.forwardSlash)
                } else {
                    c = input[idx]
                }
                let urlScheme = url.scheme.flatMap { SpecialScheme(rawValue: $0) }

                let c_isPathSeparator = (
                    c == ASCII.forwardSlash || (urlScheme != nil && c == ASCII.backslash)
                )

                if c_isPathSeparator ||
                    (stateOverride == nil && (c == ASCII.questionMark || c == ASCII.numberSign)) {

                    if urlScheme != nil, c == ASCII.backslash { validationFailure("Unexpected backslash in path") }

                    if buffer.isDoubleDotPathSegment {
                        shortenURLPath(&url.path, isFileScheme: urlScheme == .file)
                        if c_isPathSeparator {
                            // FIXME: Why does the spec want us to append empty path segments?
                            // url.path.append("")
                        }
                    } else if buffer.isSingleDotPathSegment {
                        if c_isPathSeparator {
                            // FIXME: Why does the spec want us to append empty path segments?
                            // url.path.append("")
                        }
                    } else {
                        // Note: This is a (platform-independent) Windows drive letter quirk.
                        if urlScheme == .file, url.path.isEmpty, buffer.isWindowsDriveLetter {
                            if url.authority.host?.isEmpty == false {
                                validationFailure("Host should be empty if path contains a windows drive letter")
                                url.authority.host = .empty
                            }
                            let secondChar = buffer.index(after: buffer.startIndex)
                            buffer.replaceSubrange(secondChar..<buffer.index(after: secondChar), with: String(Character(ASCII.colon)))
                        }
                        url.path.append(buffer)
                    }
                    buffer = ""
                    if urlScheme == .file && (c == ASCII.questionMark || c == ASCII.numberSign) { // FIXME: or endIndex.
                        if let firstNonEmptySegment = url.path.firstIndex(where: { $0.isEmpty == false }) {
                            if firstNonEmptySegment != url.path.startIndex { validationFailure("Unexpected empty segments at start of path") }
                            url.path.removeSubrange(url.path.startIndex..<firstNonEmptySegment)
                        } else {
                            validationFailure("Unexpected empty segments at start of path")
                            url.path.removeSubrange(url.path.index(after: url.path.startIndex)..<url.path.endIndex)
                        }
                    }
                    if c == ASCII.questionMark {
                        url.query = ""
                        state     = .query
                    } else if c == ASCII.numberSign {
                        url.fragment = ""
                        state        = .fragment
                    }
                } else {
                    // TODO: Validation failure if c is not a "URL code point" or "%"
                    if c == ASCII.percentSign {
                        let nextTwo = input[idx...].prefix(2)
                        if nextTwo.count != 2 || !nextTwo.allSatisfy({ (ASCII.A ... ASCII.F).contains($0) }) {
                            validationFailure("Invalid % in URL")
                        }
                    }
                    buffer.append(c.percentEscaped(where: url_escape_path))
                }

            case .cannotBeABaseURLPath:
                guard idx != input.endIndex else {
                    break // ???
                }
                let c = input[idx]
                switch c {
                case ASCII.questionMark:
                    url.query = ""
                    state     = .query
                case ASCII.numberSign:
                    url.fragment = ""
                    state        = .fragment
                default:
                    // TODO: validate and percent-encode using control options.
                    if url.path.isEmpty {
                        url.path.append(String(c))
                    } else {
                        url.path[0].append(c)
                    }
                }

            case .query:
                guard idx != input.endIndex else { 
                    break // ???
                }
                let c = input[idx]
                if stateOverride == nil, c == ASCII.numberSign {
                    url.fragment = ""
                    state        = .fragment
                    break
                }
                // TODO: Yeah... this stuff.
                if url.query != nil {
                    url.query!.append(c)
                } else {
                    url.query = String(c)
                }


            case .fragment:
                guard idx != input.endIndex else { break }
                let c = input[idx]
                if c == ASCII.null { validationFailure("Unexpected null code point in fragment") }
                // TODO: validate characters, percent-encode using fragment options.
                if var frag = url.fragment { 
                    frag.append(c)
                } else {
                    url.fragment = String(c)
                }
            }

            if idx == input.endIndex { break }
            idx = input.index(after: idx)
        }


        print("final state: \(state)")
        return url
    }
}
