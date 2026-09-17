//
//  PSKReporterRetrieveClient.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//

import Foundation

/// Anything that can answer "who heard this callsign recently?".
protocol ReceptionReportFetching: Sendable {
    func fetch(senderCallsign: String, window: HeardMeWindow) async throws -> [ReceptionReport]
}

enum PSKReporterRetrieveError: Error, Equatable {
    case noCallsign
    case http(Int)
    case rateLimited
    case parse
}

/// Read-only client for the PSK Reporter retrieve API.
///
/// Sending reports is a premium feature (`PSKReporterReporter`); this only
/// asks the public query endpoint who heard *us*. PSK Reporter asks clients
/// not to poll more often than every 5 minutes; `HeardMeStore` enforces that.
final class PSKReporterRetrieveClient: ReceptionReportFetching {
    static let baseURL = URL(string: "https://retrieve.pskreporter.info/query")!
    /// Identifies the app to the PSK Reporter operators, as they request.
    static let appContact = "ftham@turrion.dev"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func makeURL(senderCallsign: String, window: HeardMeWindow) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "senderCallsign", value: senderCallsign.uppercased()),
            URLQueryItem(name: "flowStartSeconds", value: "-\(window.rawValue)"),
            URLQueryItem(name: "rronly", value: "1"),
            URLQueryItem(name: "appcontact", value: appContact),
        ]
        return components?.url
    }

    func fetch(senderCallsign: String, window: HeardMeWindow) async throws -> [ReceptionReport] {
        let call = senderCallsign.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !call.isEmpty, let url = Self.makeURL(senderCallsign: call, window: window) else {
            throw PSKReporterRetrieveError.noCallsign
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("FT Ham iOS (\(Self.appContact))", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200..<300: break
            case 429, 503: throw PSKReporterRetrieveError.rateLimited
            default: throw PSKReporterRetrieveError.http(http.statusCode)
            }
        }
        return try ReceptionReportXMLParser.parse(data)
    }
}

/// Parses the `<receptionReports>` document returned by the retrieve API.
final class ReceptionReportXMLParser: NSObject, XMLParserDelegate {
    private var reports: [ReceptionReport] = []
    private var failed = false

    static func parse(_ data: Data) throws -> [ReceptionReport] {
        let delegate = ReceptionReportXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), !delegate.failed else { throw PSKReporterRetrieveError.parse }
        return delegate.reports
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        guard elementName == "receptionReport" else { return }
        guard let receiver = attributes["receiverCallsign"]?.uppercased(), !receiver.isEmpty,
              let locator = attributes["receiverLocator"], isValidLocator(String(locator.prefix(4))),
              let sender = attributes["senderCallsign"]?.uppercased(),
              let start = attributes["flowStartSeconds"].flatMap(Double.init) else { return }

        reports.append(ReceptionReport(
            receiverCallsign: receiver,
            receiverLocator: locator.uppercased(),
            senderCallsign: sender,
            frequencyHz: attributes["frequency"].flatMap(Int64.init) ?? 0,
            snr: attributes["sNR"].flatMap(Int.init),
            mode: attributes["mode"] ?? "",
            flowStart: Date(timeIntervalSince1970: start)
        ))
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        failed = true
    }
}
