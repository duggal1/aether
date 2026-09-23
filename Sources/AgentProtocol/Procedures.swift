import Foundation

public enum PageNavigate: AgentProcedure {
  public static let method: AgentMethod = .pageNavigate

  public struct Input: Codable, Sendable, Hashable {
    public let page: UInt64
    public let url: String
    public let settle: String?

    public init(page: UInt64, url: String, settle: String? = nil) {
      self.page = page
      self.url = url
      self.settle = settle
    }

    public func validate() throws {
      guard page > 0 else {
        throw AgentProcedureError(code: "badParameter", message: "page")
      }
      guard !url.isEmpty, URL(string: url) != nil else {
        throw AgentProcedureError(code: "badParameter", message: "url")
      }
    }
  }

  public struct Output: Codable, Sendable, Hashable {
    public let id: UInt64
    public let context: UInt64
    public let title: String
    public let loaded: Bool
    public let width: Double
    public let height: Double
    public let historyIndex: Int
    public let historyCount: Int
    public let canGoBack: Bool
    public let canGoForward: Bool
    public let url: String?

    public init(
      id: UInt64, context: UInt64, title: String, loaded: Bool, width: Double, height: Double,
      historyIndex: Int, historyCount: Int, canGoBack: Bool, canGoForward: Bool, url: String?
    ) {
      self.id = id
      self.context = context
      self.title = title
      self.loaded = loaded
      self.width = width
      self.height = height
      self.historyIndex = historyIndex
      self.historyCount = historyCount
      self.canGoBack = canGoBack
      self.canGoForward = canGoForward
      self.url = url
    }
  }
}

public enum ContextSetCookie: AgentProcedure {
  public static let method: AgentMethod = .contextSetCookie

  public struct Input: Codable, Sendable, Hashable {
    public let context: UInt64
    public let name: String
    public let value: String
    public let domain: String
    public let path: String?
    public let secure: Bool?
    public let httpOnly: Bool?
    public let sameSite: String?

    public init(
      context: UInt64, name: String, value: String, domain: String, path: String? = nil,
      secure: Bool? = nil, httpOnly: Bool? = nil, sameSite: String? = nil
    ) {
      self.context = context
      self.name = name
      self.value = value
      self.domain = domain
      self.path = path
      self.secure = secure
      self.httpOnly = httpOnly
      self.sameSite = sameSite
    }

    public func validate() throws {
      guard context > 0, !name.isEmpty, !domain.isEmpty else {
        throw AgentProcedureError(code: "badParameter", message: "name/value/domain")
      }
    }
  }

  public struct Output: Codable, Sendable, Hashable {
    public let ok: Bool

    public init(ok: Bool) {
      self.ok = ok
    }
  }
}

public enum ContextListCookies: AgentProcedure {
  public static let method: AgentMethod = .contextCookies

  public struct Input: Codable, Sendable, Hashable {
    public let context: UInt64

    public init(context: UInt64) {
      self.context = context
    }

    public func validate() throws {
      guard context > 0 else {
        throw AgentProcedureError(code: "badParameter", message: "context")
      }
    }
  }

  public struct Output: Codable, Sendable, Hashable {
    public struct Cookie: Codable, Sendable, Hashable {
      public let name: String
      public let value: String
      public let domain: String
      public let path: String
      public let secure: Bool
      public let httpOnly: Bool
      public let sameSite: String?

      public init(
        name: String, value: String, domain: String, path: String, secure: Bool,
        httpOnly: Bool, sameSite: String? = nil
      ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.secure = secure
        self.httpOnly = httpOnly
        self.sameSite = sameSite
      }
    }

    public let cookies: [Cookie]

    public init(cookies: [Cookie]) {
      self.cookies = cookies
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      cookies = try container.decode([Cookie].self)
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(cookies)
    }
  }
}
