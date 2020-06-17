import Algorithms // for Collection.trim
import SE0270_RangeSet

/// A String which is known to contain a valid URL.
///
public struct XURL {
    var string: String
}

extension XURL {
    
    public struct Components: Equatable, Hashable, Codable {
        private final class Storage: Equatable, Hashable, Codable {
            var scheme: String
            var username: String
            var password: String
            var host: XURL.Host?
            var port: UInt16?
            var path: [String]
            var query: String?
            var fragment: String?
            var cannotBeABaseURL = false
            // TODO:
            // URL also has an associated blob URL entry that is either null or a blob URL entry. It is initially null.
         
            init(scheme: String, username: String, password: String, host: XURL.Host?,
                 port: UInt16?, path: [String], query: String?, fragment: String?,
                 cannotBeABaseURL: Bool) {
                self.scheme = scheme; self.username = username; self.password = password; self.host = host
                self.port = port; self.path = path; self.query = query; self.fragment = fragment
                self.cannotBeABaseURL = cannotBeABaseURL
            }
            
            func copy() -> Self {
                return Self(
                    scheme: scheme, username: username, password: password, host: host,
                    port: port, path: path, query: query, fragment: fragment,
                    cannotBeABaseURL: cannotBeABaseURL
                )
            }
            
            static func == (lhs: Storage, rhs: Storage) -> Bool {
            	return
                lhs.scheme == rhs.scheme &&
                lhs.username == rhs.username &&
                lhs.password == rhs.password &&
                lhs.host == rhs.host &&
                lhs.port == rhs.port &&
                lhs.path == rhs.path &&
                lhs.query == rhs.query &&
                lhs.fragment == rhs.fragment &&
                lhs.cannotBeABaseURL == rhs.cannotBeABaseURL
            }
            
            func hash(into hasher: inout Hasher) {
                scheme.hash(into: &hasher)
                username.hash(into: &hasher)
                password.hash(into: &hasher)
                host.hash(into: &hasher)
                port.hash(into: &hasher)
                path.hash(into: &hasher)
                query.hash(into: &hasher)
                fragment.hash(into: &hasher)
                cannotBeABaseURL.hash(into: &hasher)
            }
        }
        
        private var _storage: Storage
        
        private mutating func ensureUnique() {
            if !isKnownUniquelyReferenced(&_storage) {
                _storage = _storage.copy()
            }
        }
        
        public init(scheme: String = "", username: String = "", password: String = "", host: XURL.Host? = nil,
                    port: UInt16? = nil, path: [String] = [], query: String? = nil, fragment: String? = nil,
                     cannotBeABaseURL: Bool = false) {
            self._storage = Storage(
                scheme: scheme, username: username, password: password, host: host,
                port: port, path: path, query: query, fragment: fragment,
                cannotBeABaseURL: cannotBeABaseURL
            )
        }
    }
}

extension XURL.Components {
        
    
    /// A URL’s scheme is an ASCII string that identifies the type of URL and can be used to dispatch a URL for further processing after parsing. It is initially the empty string.
    ///
    /// https://url.spec.whatwg.org/#url-representation as of 14.06.2020
    ///
    public var scheme: String {
        get { return _storage.scheme }
        set { ensureUnique(); _storage.scheme = newValue }
    }
    
    /// A URL’s username is an ASCII string identifying a username. It is initially the empty string.
    ///
    /// https://url.spec.whatwg.org/#url-representation as of 14.06.2020
    ///
    public var username: String {
       get { return _storage.username }
       set { ensureUnique(); _storage.username = newValue }
   }
  
    /// A URL’s password is an ASCII string identifying a password. It is initially the empty string.
    ///
    /// https://url.spec.whatwg.org/#url-representation as of 14.06.2020
    ///
    public var password: String {
       get { return _storage.password }
       set { ensureUnique(); _storage.password = newValue }
   }
            
    /// A URL’s host is null or a host. It is initially null.
    ///
    /// A host is a domain, an IPv4 address, an IPv6 address, an opaque host, or an empty host.
    /// Typically a host serves as a network address, but it is sometimes used as opaque identifier in URLs where a network address is not necessary.
    ///
    /// https://url.spec.whatwg.org/#url-representation as of 14.06.2020
    /// https://url.spec.whatwg.org/#host-representation as of 14.06.2020
    ///
    public var host: XURL.Host? {
       get { return _storage.host }
       set { ensureUnique(); _storage.host = newValue }
    }

    /// A URL’s port is either null or a 16-bit unsigned integer that identifies a networking port. It is initially null.
    ///
    /// https://url.spec.whatwg.org/#url-representation as of 14.06.2020
    ///
    public var port: UInt16? {
       get { return _storage.port }
       set { ensureUnique(); _storage.port = newValue }
    }

    /// A URL’s path is a list of zero or more ASCII strings, usually identifying a location in hierarchical form. It is initially empty.
    ///
    /// https://url.spec.whatwg.org/#url-representation as of 14.06.2020
    ///
    public var path: [String] {
        get { return _storage.path }
        _modify { ensureUnique(); yield &_storage.path }
        set { ensureUnique(); _storage.path = newValue }
    }
    
    /// A URL’s query is either null or an ASCII string. It is initially null.
    ///
    /// https://url.spec.whatwg.org/#url-representation as of 14.06.2020
    ///
    public var query: String? {
       get { return _storage.query }
       set { ensureUnique(); _storage.query = newValue }
    }
    
    /// A URL’s fragment is either null or an ASCII string that can be used for further processing on the resource the URL’s other components identify. It is initially null.
    ///
    /// https://url.spec.whatwg.org/#url-representation as of 14.06.2020
    ///
    public var fragment: String? {
       get { return _storage.fragment }
       set { ensureUnique(); _storage.fragment = newValue }
    }
    
    /// A URL also has an associated cannot-be-a-base-URL flag. It is initially unset.
    ///
    /// https://url.spec.whatwg.org/#url-representation as of 14.06.2020
    ///
    public var cannotBeABaseURL: Bool {
       get { return _storage.cannotBeABaseURL }
       set { ensureUnique(); _storage.cannotBeABaseURL = newValue }
    }
    
    // TODO:
    // URL also has an associated blob URL entry that is either null or a blob URL entry. It is initially null.
}

// Internal helpers.

extension XURL.Components {
    
    var isSpecial: Bool {
        XURL.Parser.SpecialScheme(rawValue: scheme) != nil
    }

    var hasCredentials: Bool {
        !username.isEmpty || !password.isEmpty
    }
    
    /// A URL cannot have a username/password/port if its host is null or the empty string, its cannot-be-a-base-URL flag is set, or its scheme is "file".
    ///
    /// https://url.spec.whatwg.org/#url-miscellaneous as seen on 14.06.2020
    ///
    var cannotHaveCredentialsOrPort: Bool {
        return host == nil || host == .empty || self.cannotBeABaseURL || scheme == XURL.Parser.SpecialScheme.file.rawValue
    }

    /// Copies the username, password, host and port fields from `other`.
    ///
    fileprivate mutating func copyAuthority(from other: Self) {
        self.username = other.username
        self.password = other.password
        self.host     = other.host
        self.port     = other.port
    }
    
    func serialised(excludeFragment: Bool = false) -> String {
        var result = ""
        result.append(self.scheme)
        result.append(":")
        
        if let host = self.host {
            result.append("//")
            if self.hasCredentials {
                result.append(self.username)
                if !self.password.isEmpty {
                    result.append(":")
                    result.append(self.password)
                }
                result.append("@")
            }
            result.append(host.description)
            if let port = self.port {
                result.append(":")
                result.append(String(port))
            }
        } else if self.scheme == XURL.Parser.SpecialScheme.file.rawValue {
            result.append("//")
        }
        
        if self.cannotBeABaseURL {
            if self.path.isEmpty == false {
                result.append(self.path[0])
            }
        } else {
            for pathComponent in self.path {
                result.append("/\(pathComponent)")
            }
        }
        
        if let query = self.query {
            result.append("?\(query)")
        }
        if let fragment = self.fragment, excludeFragment == false {
            result.append("#\(fragment)")
        }
        return result
    }
}

extension XURL.Components: CustomDebugStringConvertible {

    public var debugDescription: String {
        return """
        Scheme:\t\(scheme)
        Username:\t\(username)
        Password:\t\(password)
        Host:\t\(host?.description ?? "<nil>")
        Port:\t\(port?.description ?? "<nil>")
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

    /// A Windows drive letter is two code points, of which the first is an ASCII alpha and the second is either U+003A (:) or U+007C (|).
	///
    /// https://url.spec.whatwg.org/#url-miscellaneous as of 14.06.2020
    ///
    var isWindowsDriveLetter: Bool {
        var it = makeIterator()
        guard let first = it.next(), ASCII.ranges.isAlpha(first) else { return false }
        guard let second = it.next(), (second == ASCII.colon || second == ASCII.verticalBar) else { return false }
        guard it.next() == nil else { return false }
        return true
    }
    
    /// A normalized Windows drive letter is a Windows drive letter of which the second code point is U+003A (:).
    ///
    /// https://url.spec.whatwg.org/#url-miscellaneous as of 14.06.2020
    ///
    var isNormalisedWindowsDriveLetter: Bool {
        isWindowsDriveLetter && self.dropFirst().first == ASCII.colon
    }

	/// A string starts with a Windows drive letter if all of the following are true:
	///
    /// - its length is greater than or equal to 2
    /// - its first two code points are a Windows drive letter
    /// - its length is 2 or its third code point is U+002F (/), U+005C (\), U+003F (?), or U+0023 (#).
    ///
    /// https://url.spec.whatwg.org/#url-miscellaneous as of 14.06.2020
    ///
    func hasWindowsDriveLetterPrefix() -> Bool {
        var it = makeIterator()
        guard let first = it.next(), ASCII.ranges.isAlpha(first) else { return false }
        guard let second = it.next(), (second == ASCII.colon || second == ASCII.verticalBar) else { return false }
        guard let third = it.next() else { return true }
        switch third {
        case ASCII.forwardSlash, ASCII.backslash, ASCII.questionMark, ASCII.numberSign:
            return true
        default:
            return false
        }
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

public var __BREAKPOINT__: ()->Void = {}


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

        var defaultPort: UInt16? {
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
    
    public struct ValidationError: Equatable, CustomStringConvertible {
        private var code: UInt8

        // Named errors and their descriptions/examples taken from:
        // https://github.com/whatwg/url/pull/502 on 15.06.2020
        internal static var unexpectedC0ControlOrSpace:         Self { Self(code: 0) }
        internal static var unexpectedASCIITabOrNewline:        Self { Self(code: 1) }
        internal static var invalidSchemeStart:                 Self { Self(code: 2) }
        internal static var fileSchemeMissingFollowingSolidus:  Self { Self(code: 3) }
        internal static var invalidScheme:                      Self { Self(code: 4) }
        internal static var missingSchemeNonRelativeURL:        Self { Self(code: 5) }
        internal static var relativeURLMissingBeginningSolidus: Self { Self(code: 6) }
        internal static var unexpectedReverseSolidus:           Self { Self(code: 7) }
        internal static var missingSolidusBeforeAuthority:      Self { Self(code: 8) }
        internal static var unexpectedCommercialAt:             Self { Self(code: 9) }
        internal static var missingCredentials:                 Self { Self(code: 10) }
        internal static var unexpectedPortWithoutHost:          Self { Self(code: 11) }
        internal static var emptyHostSpecialScheme:             Self { Self(code: 12) }
        internal static var hostInvalid:                        Self { Self(code: 13) }
        internal static var portOutOfRange:                     Self { Self(code: 14) }
        internal static var portInvalid:                        Self { Self(code: 15) }
        internal static var unexpectedWindowsDriveLetter:       Self { Self(code: 16) }
        internal static var unexpectedWindowsDriveLetterHost:   Self { Self(code: 17) }
        internal static var unexpectedHostFileScheme:           Self { Self(code: 18) }
        internal static var unexpectedEmptyPath:                Self { Self(code: 19) }
        internal static var invalidURLCodePoint:                Self { Self(code: 20) }
        internal static var unescapedPercentSign:               Self { Self(code: 21) }
        // TODO: host-related errors. Map these to our existing host-parser errors.
        internal static var unclosedIPv6Address:                Self { Self(code: 22) }
        internal static var domainToASCIIFailure:               Self { Self(code: 23) }
        internal static var domainToASCIIEmptyDomainFailure:    Self { Self(code: 24) }
        internal static var hostForbiddenCodePoint:             Self { Self(code: 25) }
        // This one is not in the spec.
        internal static var _baseURLRequired:                   Self { Self(code: 99) }
        
        public var description: String {
            switch self {
            case .unexpectedC0ControlOrSpace:
                return #"""
                The input to the URL parser contains a leading or trailing C0 control or space.
                The URL parser subsequently strips any matching code points.
                
                Example: " https://example.org "
                """#
            case .unexpectedASCIITabOrNewline:
                return #"""
                The input to the URL parser contains ASCII tab or newlines.
                The URL parser subsequently strips any matching code points.
                
                Example: "ht
                tps://example.org"
                """#
            case .invalidSchemeStart:
                return #"""
                The first code point of a URL’s scheme is not an ASCII alpha.

                Example: "3ttps://example.org"
                """#
            case .fileSchemeMissingFollowingSolidus:
                return #"""
                The URL parser encounters a URL with a "file" scheme that is not followed by "//".

                Example: "file:c:/my-secret-folder"
                """#
            case .invalidScheme:
                return #"""
                The URL’s scheme contains an invalid code point.

                Example: "^_^://example.org" and "https//example.org"
                """#
            case .missingSchemeNonRelativeURL:
                return #"""
                The input is missing a scheme, because it does not begin with an ASCII alpha,
                and either no base URL was provided or the base URL cannot be used as a base URL
                because its cannot-be-a-base-URL flag is set.

                Example (Input’s scheme is missing and no base URL is given):
                (url, base) = ("💩", nil)
                
                Example (Input’s scheme is missing, but the base URL’s cannot-be-a-base-URL flag is set):
                (url, base) = ("💩", "mailto:user@example.org")
                """#
            case .relativeURLMissingBeginningSolidus:
                return #"""
                The input is a relative-URL String that does not begin with U+002F (/).

                Example: (url, base) = ("foo.html", "https://example.org/")
                """#
            case .unexpectedReverseSolidus:
                return #"""
                The URL has a special scheme and it uses U+005C (\) instead of U+002F (/).

                Example: "https://example.org\path\to\file"
                """#
            case .missingSolidusBeforeAuthority:
                return #"""
                The URL includes credentials that are not preceded by "//".

                Example: "https:user@example.org"
                """#
            case .unexpectedCommercialAt:
                return #"""
                The URL includes credentials, however this is considered invalid.

                Example: "https://user@example.org"
                """#
            case .missingCredentials:
                return #"""
                A U+0040 (@) is found between the URL’s scheme and host, but the URL does not include credentials.

                Example: "https://@example.org"
                """#
            case .unexpectedPortWithoutHost:
                return #"""
                The URL contains a port, but no host.

                Example: "https://:443"
                """#
            case .emptyHostSpecialScheme:
                return #"""
                The URL has a special scheme, but does not contain a host.

                Example: "https://#fragment"
                """#
            case .hostInvalid:
                // FIXME: Javascript example.
                return #"""
                The host portion of the URL is an empty string when it includes credentials or a port and the basic URL parser’s state is overridden.

                Example:
                  const url = new URL("https://example:9000");
                  url.hostname = "";
                """#
            case .portOutOfRange:
                return #"""
                The input’s port is too big.

                Example: "https://example.org:70000"
                """#
            case .portInvalid:
                return #"""
                The input’s port is invalid.

                Example: "https://example.org:7z"
                """#
            case .unexpectedWindowsDriveLetter:
                return #"""
                The input is a relative-URL string that starts with a Windows drive letter and the base URL’s scheme is "file".

                Example: (url, base) = ("/c:/path/to/file", "file:///c:/")
                """#
            case .unexpectedWindowsDriveLetterHost:
                return #"""
                The file URL’s host is a Windows drive letter.

                Example: "file://c:"
                """#
            case .unexpectedHostFileScheme:
                // FIXME: Javascript example.
                return #"""
                The URL’s scheme is changed to "file" and the existing URL has a host.

                Example:
                  const url = new URL("https://example.org");
                  url.protocol = "file";
                """#
            case .unexpectedEmptyPath:
                return #"""
                The URL’s scheme is "file" and it contains an empty path segment.

                Example: "file:///c:/path//to/file"
                """#
            case .invalidURLCodePoint:
                return #"""
                A code point is found that is not a URL code point or U+0025 (%), in the URL’s path, query, or fragment.

                Example: "https://example.org/>"
                """#
            case .unescapedPercentSign:
                return #"""
                A U+0025 (%) is found that is not followed by two ASCII hex digits, in the URL’s path, query, or fragment.

                Example: "https://example.org/%s"
                """#
            case ._baseURLRequired:
                return #"""
                A base URL is required.
                """#
            default:
                return "??"
            }
        }
    }
    
    // Parse, ignoring non-fatal validation errors.

    public static func parse<S>(_ input: S, base: String? = nil) -> XURL.Components? where S: StringProtocol {
        if let baseString = base, baseString.isEmpty == false {
            return parse(baseString[...], baseURL: nil).flatMap { parse(input[...], baseURL: $0) }
        }
        return parse(input[...], baseURL: nil)
    }

    public static func parse<S>(_ input: S, baseURL: XURL.Components?) -> XURL.Components? where S: StringProtocol {
        return _parse(input[...] as! Substring, base: baseURL, url: nil, stateOverride: nil, onValidationError: { _ in })
    }
    
    // Parse, reporting validation errors.
    
    public struct Result {
        public var components: XURL.Components?
        public var validationErrors: [ValidationError]
    }
    
    public static func parseAndReport<S>(_ input: S, base: String? = nil) -> (url: Result?, base: Result?) where S: StringProtocol {
        if let baseString = base, baseString.isEmpty == false {
            let baseResult = parseAndReport(baseString[...], baseURL: nil)
            return baseResult.components.map { (parseAndReport(input, baseURL: $0), baseResult) } ?? (nil, baseResult)
        }
        return (parseAndReport(input, baseURL: nil), nil)
    }
    
    public static func parseAndReport<S>(_ input: S, baseURL: XURL.Components?) -> Result where S: StringProtocol {
        var errors: [ValidationError] = []
        errors.reserveCapacity(8)
        let components = _parse(input[...] as! Substring, base: baseURL, url: nil, stateOverride: nil, onValidationError: { errors.append($0) })
        return Result(components: components, validationErrors: errors)
    }
    
    // Modification.
    
    internal static func modify<S>(_ input: S, url: XURL.Components?, stateOverride: State?, onValidationError: (ValidationError)->Void) -> XURL.Components? where S: StringProtocol {
        return _parse(input[...] as! Substring, base: nil, url: url, stateOverride: stateOverride, onValidationError: onValidationError)
    }

    // Parser algorithm.
    
    /// The "Basic URL Parser" algorithm described by:
    /// https://url.spec.whatwg.org/#url-parsing as of 14.06.2020
    ///
    /// - parameters:
    /// 	- input:				The String to parse (as a Substring).
    ///     - base:					The base-URL, in case `input` is a relative URL string
    ///     - url:					An existing parsed URL to modify
    ///     - stateOverride:		The starting state of the parser. Used when modifying a URL.
    ///     - onValidationError:	A callback for handling any validation errors that occur. Most of these are non-fatal.
    /// - returns:	The parsed URL components, or `nil` if the input failed to parse.
    ///
    private static func _parse(_ input: Substring, base: XURL.Components?,
             		            url: XURL.Components?, stateOverride: State?, onValidationError: (ValidationError)->Void) -> XURL.Components? {

        func validationFailure(_ msg: ValidationError) {
            onValidationError(msg)
        }
        var input = input[...]

        // 1. Trim leading/trailing C0 control characters and spaces.
        input = input.trim { $0.isC0OrSpace }
        
        // TODO: Add validation error.

        // 2. Remove all ASCII newlines and tabs. 
        let invalidRanges = input.subranges { $0.isASCIINewlineOrTab }
        if !invalidRanges.isEmpty { validationFailure(.unexpectedASCIITabOrNewline) }
        input.removeSubranges(invalidRanges)

        // 3. Begin state machine.
        var state = stateOverride ?? .schemeStart
        var url   = url ?? XURL.Components()

        var idx    = input.startIndex
        var buffer = ""
        var flag_at = false // @flag in spec.
        var flag_squareBracket = false // [] flag in spec.

        inputLoop: while true {
            stateMachine: switch state {
            // Within this switch statement:
            // - inputLoop runs the switch, then advances `idx`, if `idx != input.endIndex`.
            // - stateMachine switches on `state`. It *will* see `idx == endIndex`,
            //   which turns out to be important in some of the parsing logic.
            //
            // In plain English:
            // - `break stateMachine` means "we're done processing this character, exit the switch and let inputLoop advance to the character"
            // - `break inputLoop`    means "we're done processing 'input', return whatever we have (not a failure)".
            //                        typically comes up with `stateOverride`.
            // - `return nil`         means failure.
            // - `continue`           means "loop over inputLoop again, from the beginning (**without** first advancing the character)"
                
            // There are also notes about how non-ASCII characters are treated.
            // The idea is to eventually move to parsing input as an UnsafeBufferPointer<UInt8>, because iterating Strings is slooooow,
            // and almost all of this logic just checks for patterns of ASCII characters. Hopefully we can isolate any pieces that need
            // to be unicode-aware.

            case .schemeStart:
                // Erase 'endIndex' and non-ASCII characters to `ASCII.null`.
                // `c` is only used if it is known to be within an allowed ASCII range.
                let c: ASCII = (idx != input.endIndex) ? ASCII(input[idx]) ?? .null : .null
                switch c {
                case _ where ASCII.ranges.isAlpha(c):
                    buffer.append(Character(c).lowercased())
                    state = .scheme
                default:
                    guard stateOverride == nil else {
                        validationFailure(.invalidSchemeStart)
                        return nil
                    }
                    state = .noScheme
                    continue // Do not increment index.
                }
                 
            case .scheme:
                // Erase 'endIndex' and non-ASCII characters to `ASCII.null`.
                // `c` is only used if it is known to be within an allowed ASCII range.
                let c: ASCII = (idx != input.endIndex) ? ASCII(input[idx]) ?? .null : .null
                switch c {
                case _ where ASCII.ranges.isAlphaNumeric(c), .plus, .minus, .period:
                    buffer.append(Character(c).lowercased())
                    break stateMachine
                case .colon:
                    break // Handled below.
                default:
                    guard stateOverride == nil else {
                        validationFailure(.invalidScheme)
                        return nil
                    }
                    buffer = ""
                    state  = .noScheme
                    idx    = input.startIndex
                    continue // Do not increment index.
                }
                assert(c == .colon)
                let bufferSpecialScheme = SpecialScheme(rawValue: buffer)
                if stateOverride != nil {
                    let urlSpecialScheme = SpecialScheme(rawValue: url.scheme)
                    if (urlSpecialScheme == nil) != (bufferSpecialScheme == nil) { 
                        break inputLoop
                    }
                    if bufferSpecialScheme == .file && (url.hasCredentials || url.port != nil) {
                        break inputLoop
                    }
                    if urlSpecialScheme == .file && (url.host?.isEmpty ?? true) {
                        break inputLoop
                    }
                }
                url.scheme = buffer
                buffer = ""
                if stateOverride != nil {
                    if url.port == bufferSpecialScheme?.defaultPort {
                        url.port = nil
                    }
                    break inputLoop
                }
                switch bufferSpecialScheme {
                case .file:
                    state = .file
                    let nextIdx = input.index(after: idx)
                    if !input[nextIdx...].hasPrefix("//") { // FIXME: ASCII check.
                        validationFailure(.fileSchemeMissingFollowingSolidus)
                    }
                case .some(_):
                    if base?.scheme == url.scheme {
                        state = .specialRelativeOrAuthority
                    } else {
                        state = .specialAuthoritySlashes
                    }
                case .none:
                    let nextIdx = input.index(after: idx)
                    if nextIdx != input.endIndex, ASCII(input[nextIdx]) == .forwardSlash {
                        state = .pathOrAuthority
                        idx   = nextIdx
                    } else {
                        // TODO: Spec literally says "append an empty string to url’s path" -- but why?
                        url.cannotBeABaseURL = true
                        state = .cannotBeABaseURLPath
                    }
                }

            case .noScheme:
                // Erase 'endIndex' and non-ASCII characters to `ASCII.null`.
                // `c` is only checked against known ASCII values and never copied to the result.
                let c: ASCII = (idx != input.endIndex) ? ASCII(input[idx]) ?? .null : .null
                guard let base = base else {
                    validationFailure(.missingSchemeNonRelativeURL)
                    return nil
                }
                guard base.cannotBeABaseURL == false else {
                    guard c == ASCII.numberSign else {
                        validationFailure(.missingSchemeNonRelativeURL)
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
                    validationFailure(.relativeURLMissingBeginningSolidus)
                    state = .relative
                    continue // Do not increment index.    
                }
                state = .specialAuthorityIgnoreSlashes
                idx   = input.index(after: idx)

            case .pathOrAuthority:
                guard idx != input.endIndex, ASCII(input[idx]) == .forwardSlash else {
                    state = .path
                    continue // Do not increment index.
                }
                state = .authority

            case .relative:
                guard let base = base else {
                    // Note: The spec doesn't say what happens here if base is nil.
                    validationFailure(._baseURLRequired)
                    return nil
                }
                url.scheme = base.scheme
                guard idx != input.endIndex else {
                    url.copyAuthority(from: base)
                    url.path     = base.path
                    url.query    = base.query
                    break stateMachine
                }
                // Erase non-ASCII characters to `ASCII.null`.
                // `c` is only checked against known ASCII values and never copied to the result.
                let c: ASCII = ASCII(input[idx]) ?? .null
                switch c {
                case .backslash where url.isSpecial:
                    validationFailure(.unexpectedReverseSolidus)
                    state = .relativeSlash
                case .forwardSlash:
                    state = .relativeSlash
                case .questionMark:
                    url.copyAuthority(from: base)
                    url.path      = base.path
                    url.query     = ""
                    state         = .query
                case .numberSign:
                    url.copyAuthority(from: base)
                    url.path      = base.path
                    url.query     = base.query
                    url.fragment  = ""
                    state         = .fragment
                default:
                    url.copyAuthority(from: base)
                    url.path      = base.path
                    if url.path.isEmpty == false {
                    url.path.removeLast()
                    }
                    url.query     = nil
                    state         = .path
                    continue // Do not increment index.
                }

            case .relativeSlash:
                // Erase 'endIndex' and non-ASCII characters to `ASCII.null`.
                // `c` is only checked against known ASCII values and never copied to the result.
                let c: ASCII = (idx != input.endIndex) ? ASCII(input[idx]) ?? .null : .null
                let urlIsSpecial = url.isSpecial
                switch c {
                case .forwardSlash:
                    if urlIsSpecial {
                        state = .specialAuthorityIgnoreSlashes
                    } else {
                        state = .authority
                    }
                case .backslash where urlIsSpecial:
                    validationFailure(.unexpectedReverseSolidus)
                    state = .specialAuthorityIgnoreSlashes
                default:
                    // Note: The spec doesn't say what happens here if base is nil.
                    guard let base = base else {
                        validationFailure(._baseURLRequired)
                        return nil
                    }
                    url.copyAuthority(from: base)
                    state = .path
                    continue // Do not increment index.
                }

            case .specialAuthoritySlashes:
                state = .specialAuthorityIgnoreSlashes
                guard input[idx...].hasPrefix("//") else { // FIXME: ASCII check.
                    validationFailure(.missingSolidusBeforeAuthority)
                    continue // Do not increment index.
                }
                idx = input.index(after: idx)

            case .specialAuthorityIgnoreSlashes:
                // Erase 'endIndex' and non-ASCII characters to `ASCII.null`.
                // `c` is only checked against known ASCII values and never copied to the result.
                let c: ASCII = (idx != input.endIndex) ? ASCII(input[idx]) ?? .null : .null
                guard c == .forwardSlash || c == .backslash else {
                    state = .authority
                    continue // Do not increment index.
                }
                validationFailure(.missingSolidusBeforeAuthority)

            case .authority:
                // Erase 'endIndex' to `ASCII.forwardSlash`, as they are handled the same,
                // and `c` is not copied to the result in that case.
                // Note [unicode]: Do not erase non-ASCII characters. They are copied to `buffer`.
                let c: ASCII? = (idx != input.endIndex) ? ASCII(input[idx]) : ASCII.forwardSlash
                switch c {
                case .commercialAt?:
                    validationFailure(.unexpectedCommercialAt)
                    if flag_at {
                        buffer.insert(contentsOf: "%40", at: buffer.startIndex)
                    }
                    flag_at = true
                    // Parse username and password out of "buffer"
                    let passwordTokenIndex = buffer.firstIndex(where: { $0 == ASCII.colon })
                    let passwordStartIndex = passwordTokenIndex.flatMap { buffer.index(after: $0) }
                    let parsedUsername = buffer[..<(passwordTokenIndex ?? buffer.endIndex)]
                        .percentEscaped(where: url_escape_userInfo)
                    let parsedPassword = buffer[(passwordStartIndex ?? buffer.endIndex)...]
                        .percentEscaped(where: url_escape_userInfo)
                    url.username.append(parsedUsername)
                    url.password.append(parsedPassword)
                    buffer = ""
                case ASCII.forwardSlash?, ASCII.questionMark?, ASCII.numberSign?: // or endIndex.
                    fallthrough
                case ASCII.backslash? where url.isSpecial:
                    if flag_at, buffer.isEmpty {
                        validationFailure(.missingCredentials)
                        return nil
                    }
                    idx    = input.index(idx, offsetBy: -1 * buffer.count)
                    buffer = ""
                    state  = .host
                    continue // Do not increment index.
                default:
                    buffer.append(input[idx])
                }

            case .host:
                let urlSpecialScheme = SpecialScheme(rawValue: url.scheme)
                guard !(stateOverride != nil && urlSpecialScheme == .file) else {
                    state = .fileHost
                    continue // Do not increment index.
                }
                // Erase 'endIndex' to `ASCII.forwardSlash`, as they are handled the same,
                // and `c` is not copied to the result in that case.
                // Note [unicode]: Do not erase non-ASCII characters. They are copied to `buffer`.
                let c: ASCII? = (idx != input.endIndex) ? ASCII(input[idx]) : ASCII.forwardSlash
                switch c {
                case .colon? where flag_squareBracket == false:
                    guard buffer.isEmpty == false else {
                        validationFailure(.unexpectedPortWithoutHost)
                        return nil
                    }
                    guard let parsedHost = XURL.Host(buffer, isNotSpecial: urlSpecialScheme == nil) else {
                        return nil
                    }
                    url.host = parsedHost
                    buffer = ""
                    state  = .port
                    if stateOverride == .host { break inputLoop }
                case .forwardSlash?, .questionMark?, .numberSign?: // or endIndex.
                    fallthrough
                case .backslash? where urlSpecialScheme != nil:
                    if buffer.isEmpty {
                        if urlSpecialScheme != nil {
                            validationFailure(.emptyHostSpecialScheme)
                            return nil
                        } else if stateOverride != nil, (url.hasCredentials || url.port != nil) {
                            validationFailure(.hostInvalid)
                            break inputLoop
                        }
                    }
                    guard let parsedHost = XURL.Host(buffer, isNotSpecial: urlSpecialScheme == nil) else {
                        return nil
                    }
                    url.host = parsedHost
                    buffer = ""
                    state  = .pathStart
                    if stateOverride != nil { break inputLoop }
                    continue // Do not increment index.
                case .leftSquareBracket?:
                    flag_squareBracket = true
                    buffer.append(Character(ASCII.leftSquareBracket))
                case .rightSquareBracket?:
                    flag_squareBracket = false
                    buffer.append(Character(ASCII.rightSquareBracket))
                default:
                    buffer.append(input[idx])
                }

            case .port:
                // Erase 'endIndex' to `ASCII.forwardSlash` as it is handled the same and not copied to output.
                // Erase non-ASCII characters to `ASCII.null` as this state checks for specific ASCII characters/EOF.
                // `c` is only copied if it is known to be within an allowed ASCII range.
                let c: ASCII = (idx != input.endIndex) ? ASCII(input[idx]) ?? ASCII.null : ASCII.forwardSlash
                switch c {
                case _ where ASCII.ranges.digits.contains(c):
                    buffer.append(Character(c))
                case .forwardSlash, .questionMark, .numberSign: // or endIndex.
                    fallthrough
                case .backslash where url.isSpecial:
                    fallthrough
                case _ where stateOverride != nil:
                    if buffer.isEmpty == false {
                        guard let parsedInteger = UInt16(buffer) else {
                            validationFailure(.portOutOfRange)
                            return nil
                        }
                        url.port = (parsedInteger == SpecialScheme(rawValue: url.scheme)?.defaultPort) ? nil : parsedInteger
                        buffer   = ""
                    }
                    if stateOverride != nil { break inputLoop }
                    state = .pathStart
                    continue // Do not increment index.
                default:
                    validationFailure(.portInvalid)
                    return nil
                }

            case .file:
                url.scheme = SpecialScheme.file.rawValue
                if idx != input.endIndex, let c = ASCII(input[idx]), (c == .forwardSlash || c == .backslash) {
                    if c == .backslash {
                        validationFailure(.unexpectedReverseSolidus)
                    }
                    state = .fileSlash
                    break stateMachine
                }
                guard let base = base, base.scheme == SpecialScheme.file.rawValue else {
                    state = .path
                    continue // Do not increment index.
                }
                url.host  = base.host
                url.path  = base.path
                url.query = base.query
                guard idx != input.endIndex else {
                    break stateMachine
                }
                switch ASCII(input[idx]) {
                case .questionMark?:
                    url.query = ""
                    state     = .query
                case .numberSign?:
                    url.fragment = ""
                    state        = .fragment
                default:
                    url.query = nil
                    if input[idx...].hasWindowsDriveLetterPrefix() {
                        validationFailure(.unexpectedWindowsDriveLetter)
                        url.host = nil
                        url.path = []
                    } else {
                        shortenURLPath(&url.path, isFileScheme: true)
                    }
                    state = .path
                    continue // Do not increment index.
                }

            case .fileSlash:
                if idx != input.endIndex, let c = ASCII(input[idx]), (c == .forwardSlash || c == .backslash) {
                    if c == .backslash {
                        validationFailure(.unexpectedReverseSolidus)
                    }
                    state = .fileHost
                    break stateMachine
                }
                if let base = base, base.scheme == SpecialScheme.file.rawValue,
                    input[idx...].hasWindowsDriveLetterPrefix() == false {
                    if let basePathStart = base.path.first, basePathStart.isNormalisedWindowsDriveLetter {
                        url.path.append(basePathStart)
                    } else {
                        url.host = base.host
                    }
                }
                state = .path
                continue // Do not increment index.

            case .fileHost:
                // Erase 'endIndex' to `ASCII.forwardSlash` as it is handled the same and not copied to output.
                // Note [unicode]: Do not erase non-ASCII characters. They are copied to `buffer`.
                let c: ASCII? = (idx != input.endIndex) ? ASCII(input[idx]) : ASCII.forwardSlash
                switch c {
                case .forwardSlash?, .backslash?, .questionMark?, .numberSign?: // or endIndex.
                    if stateOverride == nil, buffer.isWindowsDriveLetter {
                        validationFailure(.unexpectedWindowsDriveLetterHost)
                        state = .path
                        // Note: buffer is intentionally not reset and used in the path-parsing state.
                    } else if buffer.isEmpty {
                        url.host = .empty
                        if stateOverride != nil { break inputLoop }
                        state = .pathStart
                    } else {
                        guard let parsedHost = XURL.Host(buffer, isNotSpecial: false) else { 
                            return nil
                        }
                        url.host = (parsedHost == .domain("localhost")) ? .empty : parsedHost
                        if stateOverride != nil { break inputLoop }
                        buffer = ""
                        state  = .pathStart
                    }
                    continue // Do not increment index.
                default:
                    buffer.append(input[idx])
                }

            case .pathStart:
                guard idx != input.endIndex else {
                    if url.isSpecial {
                        state = .path
                        continue // Do not increment index.
                    } else {
                        break stateMachine
                    }
                }
                // Erase non-ASCII characters to `ASCII.null` as this state checks for specific ASCII characters/EOF.
                // `c` is only checked against known ASCII values and never copied to the result.
                let c: ASCII = ASCII(input[idx]) ?? ASCII.null
                switch c {
                case _ where url.isSpecial:
                    if c == .backslash {
                        validationFailure(.unexpectedReverseSolidus)
                    }
                    state = .path
                    if (c == .forwardSlash || c == .backslash) == false {
                        continue // Do not increment index.
                    } else {
                        break stateMachine
                    }
                case .questionMark where stateOverride == nil:
                    url.query = ""
                    state = .query
                case .numberSign where stateOverride == nil:
                    url.fragment = ""
                    state = .fragment
                default:
                    state = .path
                    if c != .forwardSlash {
                        continue // Do not increment index.
                    }
                }

            case .path:
                let urlSpecialScheme = SpecialScheme(rawValue: url.scheme)
                
                let isPathComponentTerminator: Bool =
                    (idx == input.endIndex) ||
                    (input[idx] == ASCII.forwardSlash) ||
                    (input[idx] == ASCII.backslash && urlSpecialScheme != nil) ||
                    (stateOverride == nil && (input[idx] == ASCII.questionMark || input[idx] == ASCII.numberSign))
                
                guard isPathComponentTerminator else {
                    // TODO: Add a version of this which accepts a byte buffer and returns the codepoint's end-index.
                    if hasNonURLCodePoints(input[idx].utf8, allowPercentSign: true) {
                        validationFailure(.invalidURLCodePoint)
                    }
                    if ASCII(input[idx]) == .percentSign {
                        let nextTwo = input[idx...].dropFirst().prefix(2)
                        if nextTwo.count != 2 || !nextTwo.allSatisfy({ ASCII($0)?.isHexDigit ?? false }) {
                            validationFailure(.unescapedPercentSign)
                        }
                    }
                    buffer.append(input[idx].percentEscaped(where: url_escape_path))
                    break stateMachine
                }
                // From here, we know:
                // - idx == endIndex, or
                // - input[idx] is one of a specific set of allowed ASCII characters
                //     (forwardSlash, backslash, questionMark or numberSign), and
                // - if input[idx] is ASCII.backslash, it implies url.isSpecial.
                //
 				// To simplify bounds-checking in the following logic, we will encode
                // the state (idx == endIndex) by the ASCII.null character.
                let c: ASCII = (idx != input.endIndex) ? ASCII(input[idx])! : ASCII.null
                if c == .backslash {
                    validationFailure(.unexpectedReverseSolidus)
                }
                switch buffer {
                case _ where buffer.isDoubleDotPathSegment:
                    shortenURLPath(&url.path, isFileScheme: urlSpecialScheme == .file)
                    fallthrough
                case _ where buffer.isSingleDotPathSegment:
                    if !(c == .forwardSlash || c == .backslash) {
                        url.path.append("")
                    }
                default:
                    if urlSpecialScheme == .file, url.path.isEmpty, buffer.isWindowsDriveLetter {
                        if !(url.host == nil || url.host == .empty) {
                            validationFailure(.unexpectedHostFileScheme)
                            url.host = .empty
                        }
                        let secondChar = buffer.index(after: buffer.startIndex)
                        buffer.replaceSubrange(secondChar..<buffer.index(after: secondChar), with: String(Character(ASCII.colon)))
                    }
                    url.path.append(buffer)
                }
                buffer = ""
                if urlSpecialScheme == .file, (c == .null /* endIndex */ || c == .questionMark || c == .numberSign) {
                    while url.path.count > 1, url.path[0].isEmpty {
                        validationFailure(.unexpectedEmptyPath)
                        url.path.removeFirst()
                    }
                }
                switch c {
                case .questionMark:
                    url.query = ""
                    state     = .query
                case .numberSign:
                    url.fragment = ""
                    state        = .fragment
                default:
                    break
                }

            case .cannotBeABaseURLPath:
                guard idx != input.endIndex else {
                    break stateMachine
                }
                let c = ASCII(input[idx])
                switch c {
                case .questionMark?:
                    url.query = ""
                    state     = .query
                case .numberSign?:
                    url.fragment = ""
                    state        = .fragment
                default:
                    // TODO: Add a version of this which accepts a byte buffer and returns the codepoint's end-index.
                    if hasNonURLCodePoints(input[idx].utf8, allowPercentSign: true) {
                        validationFailure(.invalidURLCodePoint)
                    }
                    if ASCII(input[idx]) == .percentSign {
                        let nextTwo = input[idx...].dropFirst().prefix(2)
                        if nextTwo.count != 2 || !nextTwo.allSatisfy({ ASCII($0)?.isHexDigit ?? false }) {
                            validationFailure(.unescapedPercentSign)
                        }
                    }
                    let escapedChar = input[idx].percentEscaped(where: url_escape_c0)
                    if url.path.isEmpty {
                        url.path.append(escapedChar)
                    } else {
                        url.path[0].append(escapedChar)
                    }
                }

            case .query:
                // Note: we only accept the UTF8 encoding option.
                // This parser doesn't even have an argument to choose anything else.
                guard idx != input.endIndex else { 
                    break stateMachine
                }
                if stateOverride == nil, ASCII(input[idx]) == .numberSign {
                    url.fragment = ""
                    state        = .fragment
                    break stateMachine
                }
                // TODO: Add a version of this which accepts a byte buffer and returns the codepoint's end-index.
                if hasNonURLCodePoints(input[idx].utf8, allowPercentSign: true) {
                    validationFailure(.invalidURLCodePoint)
                }
                if ASCII(input[idx]) == .percentSign {
                    let nextTwo = input[idx...].dropFirst().prefix(2)
                    if nextTwo.count != 2 || !nextTwo.allSatisfy({ ASCII($0)?.isHexDigit ?? false }) {
                        validationFailure(.unescapedPercentSign)
                    }
                }
                let urlIsSpecial = url.isSpecial
                let escapedChar = input[idx].percentEscaped(where: { asciiChar in
                    switch asciiChar {
                    case .doubleQuotationMark, .numberSign, .lessThanSign, .greaterThanSign: fallthrough
                    case _ where asciiChar.codePoint < ASCII.exclamationMark.codePoint:      fallthrough
                    case _ where asciiChar.codePoint > ASCII.tilde.codePoint:                fallthrough
                    case .apostrophe where urlIsSpecial: return true
                    default: return false
                    }
                })
                if url.query == nil {
                    url.query = escapedChar
                } else {
                    url.query!.append(escapedChar)
                }

            case .fragment:
                guard idx != input.endIndex else {
                    break stateMachine
                }
                // TODO: Add a version of this which accepts a byte buffer and returns the codepoint's end-index.
                if hasNonURLCodePoints(input[idx].utf8, allowPercentSign: true) {
                    validationFailure(.invalidURLCodePoint)
                }
                if ASCII(input[idx]) == .percentSign {
                    let nextTwo = input[idx...].dropFirst().prefix(2)
                    if nextTwo.count != 2 || !nextTwo.allSatisfy({ ASCII($0)?.isHexDigit ?? false }) {
                        validationFailure(.unescapedPercentSign)
                    }
                }
                let escapedChar = input[idx].percentEscaped(where: url_escape_fragment)
                if url.fragment == nil {
                    url.fragment = escapedChar
                } else {
                    url.fragment!.append(escapedChar)
                }
            } // end of `stateMachine: switch state {`

            if idx == input.endIndex { break }
            idx = input.index(after: idx)
            
        } // end of `inputLoop: while true {`

        return url
    }
}
