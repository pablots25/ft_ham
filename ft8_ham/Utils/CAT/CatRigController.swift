//
//  CatRigController.swift
//  ft_ham
//
//  Created by Pablo Turrion on 26/02/26.
//

import Foundation
import Network

final class CatRigController: CATControlProtocol {

    static let shared = CatRigController()

    private let queue = DispatchQueue(label: "CatRigController")
    private let logger = AppLogger(category: "CAT")

    private init() {}

    func setPTT(enabled: Bool, host: String, port: UInt16) async -> CatRigResponse {
        let command = "T \(enabled ? 1 : 0)"
        return await sendCommand(command, host: host, port: port)
    }

    func setFrequency(frequency: Int64, host: String, port: UInt16) async -> CatRigResponse {
        let command = "F \(frequency)"
        return await sendCommand(command, host: host, port: port)
    }

    func setFrequency(hz: Int64, host: String, port: UInt16) async -> CatRigResponse {
        await setFrequency(frequency: hz, host: host, port: port)
    }

    func getFrequency(host: String, port: UInt16) async -> CatRigResponse {
        return await sendCommand("f", host: host, port: port)
    }

    private func sendCommand(
        _ command: String,
        host: String,
        port: UInt16,
        timeout: TimeInterval = 10.0
    ) async -> CatRigResponse {
        guard port > 0 else {
            return CatRigResponse(success: false, response: "", errorMessage: CatRigError.invalidPort.localizedDescription)
        }

        let endpointHost = NWEndpoint.Host(host)
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            return CatRigResponse(success: false, response: "", errorMessage: CatRigError.invalidPort.localizedDescription)
        }

        let connection = NWConnection(host: endpointHost, port: endpointPort, using: .tcp)
        let requestID = UUID().uuidString.prefix(6)

        let response: Result<String, Error> = await withCheckedContinuation { continuation in
            var completed = false
            var receivedData = Data()

            let finish: (Result<String, Error>) -> Void = { result in
                guard !completed else { return }
                completed = true
                connection.cancel()
                continuation.resume(returning: result)
            }

            // Define receiveLoop as a function to allow recursion
            func receiveLoop() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                    if let error {
                        finish(.failure(CatRigError.receiveFailed(error.localizedDescription)))
                        return
                    }

                    if let data, !data.isEmpty {
                        receivedData.append(data)
                    }

                    let text = String(decoding: receivedData, as: UTF8.self)

                    // Check if we have a complete line (ends with \n)
                    if text.contains("\n") || isComplete {
                        finish(.success(text))
                        return
                    }

                    // Keep reading
                    receiveLoop()
                }
            }

            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let payload = "\(command)\n"
                    guard let data = payload.data(using: .utf8) else {
                        finish(.failure(CatRigError.sendFailed("encoding")))
                        return
                    }
                    self?.logger.debug("CAT(\(requestID)) -> \(command)")
                    connection.send(content: data, completion: .contentProcessed { error in
                        if let error {
                            finish(.failure(CatRigError.sendFailed(error.localizedDescription)))
                            return
                        }
                        // Start receiving after send completes
                        receiveLoop()
                    })
                case .failed(let error):
                    finish(.failure(CatRigError.connectionFailed(error.localizedDescription)))
                case .cancelled:
                    finish(.failure(CatRigError.connectionFailed("cancelled")))
                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                finish(.failure(CatRigError.timeout))
            }
        }

        switch response {
        case .success(let text):
            let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let success = isSuccessResponse(trimmed, forCommand: command)
            if success {
                logger.debug("CAT(\(requestID)) <- \(trimmed)")
            } else {
                logger.warning("CAT(\(requestID)) error response: \(trimmed)")
            }
            return CatRigResponse(success: success, response: trimmed, errorMessage: success ? nil : "Rig reported error")
        case .failure(let error):
            logger.warning("CAT(\(requestID)) failed: \(error.localizedDescription)")
            return CatRigResponse(success: false, response: "", errorMessage: error.localizedDescription)
        }
    }

    private func isSuccessResponse(_ response: String, forCommand command: String) -> Bool {
        // For SET commands (F = frequency, T = PTT), empty or RPRT 0 is success
        let isSetCommand = command.starts(with: "F") || command.starts(with: "T")
        
        if response.contains("RPRT") {
            return response.contains("RPRT 0")
        }
        
        if isSetCommand {
            // SET commands succeed with empty response or any non-error
            return !response.contains("RPRT") || response.contains("RPRT 0")
        }
        
        // GET commands must return non-empty
        return !response.isEmpty
    }
}
