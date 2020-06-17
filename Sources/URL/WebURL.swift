
public struct WebURL {
    private var components: XURL.Components
    
    public init?(_ url: String, base: String? = nil) {
        guard let components = XURL.Parser.parse(url, base: base) else {
            return nil
        }
        self.components = components
    }
    
    // For testing only.
    public init(components: XURL.Components) {
        self.components = components
    }
}

extension WebURL {
    
    private mutating func reparse<S: StringProtocol>(_ value: S, stateOverride: XURL.Parser.State) {
        guard let newComponents = XURL.Parser.modify(
            value, url: self.components, stateOverride: stateOverride, onValidationError: { _ in }
        ) else {
            return
        }
        self.components = newComponents
    }
    
    // TODO: href setter, origin, searchParams
    
    public var href: String {
        get { return components.serialised(excludeFragment: false) }
    }

    /// Known as `protocol` in JavaScript.
    public var scheme: String {
        get { return components.scheme + ":" }
        set { reparse(newValue + ":", stateOverride: .schemeStart) }
    }
    
    public var username: String {
        get { return components.username }
        set {
            guard components.cannotHaveCredentialsOrPort == false else { return }
            components.username = newValue.percentEscaped(where: url_escape_userInfo)
        }
    }
    
    public var password: String {
        get { return components.password }
        set {
            guard components.cannotHaveCredentialsOrPort == false else { return }
            components.password = newValue.percentEscaped(where: url_escape_userInfo)
        }
    }
    
    public var host: String {
        get {
            guard let host = components.host else { return "" }
            guard let port = components.port else { return host.description }
            return "\(host):\(port)"
        }
        set {
            guard components.cannotBeABaseURL == false else { return }
            reparse(newValue, stateOverride: .host)
        }
    }
    
    public var hostname: String {
        get { return components.host?.description ?? "" }
        set {
            guard components.cannotBeABaseURL == false else { return }
            reparse(newValue, stateOverride: .host)
        }
    }
    
    public var port: UInt16? {
        get { return components.port }
        set {
            guard components.cannotHaveCredentialsOrPort == false else { return }
            components.port = newValue
        }
    }
    
    public var pathname: String {
        get {
            if components.cannotBeABaseURL || components.path.isEmpty {
                return components.path.first ?? ""
            }
            return "/" + components.path.joined(separator: "/")
        }
        set {
            guard components.cannotBeABaseURL == false else { return }
            components.path.removeAll()
            reparse(newValue, stateOverride: .pathStart)
        }
    }
    
    public var search: String {
        get {
            guard let query = components.query, query.isEmpty == false else { return "" }
            return "?" + query
        }
        set {
            guard newValue.isEmpty == false else {
                components.query = nil
                // TODO: empty query object’s list
                return
            }
            let input: Substring
            if newValue.hasPrefix("?") {
                input = newValue.dropFirst()
            } else {
                input = newValue[...]
            }
            components.query = ""
            reparse(input, stateOverride: .query)
            // TODO: Set query object’s list to the result of parsing newString.
        }
    }
   
    /// Known as `hash` in JavaScript.
    public var fragment: String {
        get {
            guard let fragment = components.fragment, fragment.isEmpty == false else { return "" }
            return "#" + fragment
        }
        set {
            guard newValue.isEmpty == false else {
                components.fragment = nil
                return
            }
            let input: Substring
            if newValue.hasPrefix("#") {
                input = newValue.dropFirst()
            } else {
                input = newValue[...]
            }
            components.fragment = ""
            reparse(input, stateOverride: .fragment)
        }
    }
}
