import Foundation
import Network

enum PrivateRouteProbe {
    struct Result: Sendable, Equatable {
        let ip: String
        let country: String
    }

    static func verifyUS(port: UInt16) async throws -> Result {
        var lastError: Error = PrivateRouteError.verificationFailed
        for attempt in 0..<12 {
            do {
                let result = try parse(await requestThroughProxy(port: port))
                guard result.country == "US" else {
                    throw PrivateRouteError.nonUSExit(result.country)
                }
                return result
            } catch let route as PrivateRouteError {
                throw route
            } catch let cancelled as CancellationError {
                throw cancelled
            } catch {
                lastError = PrivateRouteError.verificationFailed
                if attempt < 11 {
                    try await Task.sleep(for: .milliseconds(500))
                }
            }
        }
        throw lastError
    }

    static func parse(_ data: Data) throws -> Result {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PrivateRouteError.verificationFailed
        }
        guard
            let object = json as? [String: Any],
            object["success"] as? Bool == true,
            let ip = object["ip"] as? String, !ip.isEmpty,
            let country = object["country_code"] as? String, !country.isEmpty
        else {
            throw PrivateRouteError.verificationFailed
        }
        return Result(ip: ip, country: country)
    }

    private static func requestThroughProxy(port: UInt16) async throws -> Data {
        guard let proxyPort = NWEndpoint.Port(rawValue: port) else {
            throw PrivateRouteError.verificationFailed
        }
        var proxy = ProxyConfiguration(
            socksv5Proxy: .hostPort(host: .name("127.0.0.1", nil), port: proxyPort))
        proxy.allowFailover = false
        let configuration = URLSessionConfiguration.ephemeral
        configuration.proxyConfigurations = [proxy]
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        let url = URL(string: "https://ipwho.is/")!
        let (data, response) = try await URLSession(configuration: configuration).data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw PrivateRouteError.verificationFailed
        }
        return data
    }
}
