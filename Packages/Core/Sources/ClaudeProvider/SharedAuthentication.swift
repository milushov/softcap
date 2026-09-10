import ProviderKit

// Compatibility for clients that previously found the shared transport and
// OAuth primitives in ClaudeProvider. Their implementations live in ProviderKit.
public typealias HTTPClient = ProviderKit.HTTPClient
public typealias URLSessionHTTPClient = ProviderKit.URLSessionHTTPClient
public typealias FileDownloader = ProviderKit.FileDownloader
public typealias URLSessionFileDownloader = ProviderKit.URLSessionFileDownloader
public typealias PKCEPair = ProviderKit.PKCEPair
public typealias OAuthCallback = ProviderKit.OAuthCallback
public typealias RefreshedTokens = ProviderKit.RefreshedTokens
