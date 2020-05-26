
extension XURL {
    public enum Host: Equatable {
        case domain(String)
        case ipv4Address(IPAddress.V4)
        case ipv6Address(IPAddress.V6)
        case opaque(String) // non-empty
        case empty
    }
}

extension XURL.Host {

    var isEmpty: Bool {
        switch self {
            case .domain(let str): return str.isEmpty
            case .opaque(let str): return str.isEmpty
            case .empty: return true
            default: return false
        }
    }

    init?(_ input: String, isNotSpecial: Bool = false) {
        func validationFailure(_ msg: String) {
            print("[URL.Host] Validation failure - \(msg).")
        } 
        guard input.isEmpty == false else { self = .empty; return }
        
        if input.first == ASCII.leftSquareBracket {
            guard input.last == ASCII.rightSquareBracket else {
                validationFailure("Invalid IPv6 Address - expected closing ']'")
                return nil        
            }
            guard let addr = IPAddress.V6(input.dropFirst().dropLast()) else {
                // The IPv6 parser emits its own validation failure messages.
                return nil
            }
            self = .ipv6Address(addr)
            return    
        }

        if isNotSpecial {
            // TODO.
            guard let opaque = Self.parseOpaqueHost(from: input[...]) else { return nil }
            self = .opaque(opaque)
            return
        }

        // TODO: domain-to-ascii

        if let addr = IPAddress.V4(input[...]) {
            self = .ipv4Address(addr)
            return
        }

        self = .domain(input)
    }

    static func parseOpaqueHost(from input: Substring) -> String? {
        // TODO
        return nil
    }
}

extension Character {
    fileprivate func isForbiddenHostCodepoint() -> Bool {
        switch self {
            case ASCII.null, .horizontalTab:
            return true
            default:
            return false
        }
    }
}

