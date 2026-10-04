//
//  CastDeviceScanner.swift
//  OpenCastSwift
//
//  Created by Miles Hollingsworth on 4/22/18
//  Copyright © 2018 Miles Hollingsworth. All rights reserved.
//

import Foundation

extension CastDevice {
    convenience init(service: NetService, info: [String: String]) {
        var ipAddress: String?

        // Prefer IPv4 when advertised: some receivers advertise unusable IPv6 routes.
        let addresses = service.addresses ?? []
        let address = addresses.first { data in
            data.withUnsafeBytes { pointer in
                guard let socket = pointer.bindMemory(to: sockaddr.self).baseAddress else { return false }
                return socket.pointee.sa_family == sa_family_t(AF_INET)
            }
        } ?? addresses.first
        if let address = address {
            ipAddress = address.withUnsafeBytes { pointer -> String? in
                guard let pointer = pointer.bindMemory(to: sockaddr.self).baseAddress else { return nil }

                var hostName = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                return getnameinfo(
                    pointer,
                    socklen_t(address.count),
                    &hostName,
                    socklen_t(NI_MAXHOST),
                    nil,
                    0,
                    NI_NUMERICHOST
                    ) == 0 ? String.init(cString: hostName) : nil
            }
        }

        self.init(id: info["id"] ?? "",
                  name: info["fn"] ?? service.name,
                  modelName: info["md"] ?? "Google Cast",
                  hostName: service.hostName ?? ipAddress ?? "",
                  ipAddress: ipAddress ?? "",
                  port: service.port,
                  capabilitiesMask: info["ca"].flatMap(Int.init) ?? 0 ,
                  status: info["rs"] ?? "",
                  iconPath: info["ic"] ?? "")
    }

}

public struct CastDiscoveryProgress {
    public let isScanning: Bool
    public let foundServices: Int
    public let resolvingServices: Int
    public let failedServices: Int
    public let discoveredDevices: Int

    public init(isScanning: Bool, foundServices: Int, resolvingServices: Int,
                failedServices: Int, discoveredDevices: Int) {
        self.isScanning = isScanning
        self.foundServices = foundServices
        self.resolvingServices = resolvingServices
        self.failedServices = failedServices
        self.discoveredDevices = discoveredDevices
    }
}

public final class CastDeviceScanner: NSObject {
    public weak var delegate: CastDeviceScannerDelegate?

    public static let deviceListDidChange = Notification.Name(rawValue: "DeviceScannerDeviceListDidChangeNotification")

    private var _discoveryError: ((String) -> Void)?

    private var browser: NetServiceBrowser?

    public private(set) var isScanning = false
    public var progressDidChange: ((CastDiscoveryProgress) -> Void)?
    private var resolvingServices = Set<NetService>()
    private var failedServices = Set<NetService>()

    fileprivate var services = [NetService]()

    public fileprivate(set) var devices = [CastDevice]() {
        didSet {
            NotificationCenter.default.post(name: CastDeviceScanner.deviceListDidChange, object: self)
            publishProgress()
        }
    }

    private func configureBrowser() -> NetServiceBrowser {
        let b = NetServiceBrowser()

        b.includesPeerToPeer = true
        b.delegate = self
        b.schedule(in: .main, forMode: .common)

        return b
    }

    public func startScanning() {
        guard !isScanning else { return }
        isScanning = true
        let browser = configureBrowser()
        self.browser = browser
        publishProgress()
        browser.searchForServices(ofType: "_googlecast._tcp", inDomain: "local")

        #if DEBUG
        NSLog("Started scanning")
        #endif
    }

    public func stopScanning() {
        browser?.delegate = nil
        browser?.stop()
        browser?.remove(from: .main, forMode: .common)
        browser = nil
        isScanning = false
        services.forEach { $0.stop(); $0.remove(from: .main, forMode: .common); $0.delegate = nil }
        resolvingServices.removeAll()
        publishProgress()

        #if DEBUG
        NSLog("Stopped scanning")
        #endif
    }

    public func reset() {
        stopScanning()
        services.forEach { $0.stop() }
        services.removeAll()
        failedServices.removeAll()
        devices.removeAll()
    }

    private func publishProgress() {
        progressDidChange?(CastDiscoveryProgress(isScanning: isScanning, foundServices: services.count,
            resolvingServices: resolvingServices.count, failedServices: failedServices.count,
            discoveredDevices: devices.count))
    }

    deinit {
        stopScanning()
    }

}

extension CastDeviceScanner: NetServiceBrowserDelegate {

    public func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        guard self.browser === browser else { return }
        isScanning = true
        publishProgress()
    }

    public var discoveryError: ((String) -> Void)? {
        get { _discoveryError }
        set { _discoveryError = newValue }
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        guard self.browser === browser else { return }
        isScanning = false
        _discoveryError?("Bonjour discovery failed (\(errorDict)). Check Local Network permission in System Settings.")
        publishProgress()
    }

    public func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        guard self.browser === browser else { return }
        isScanning = false
        publishProgress()
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard self.browser === browser else { return }
        if let old = removeService(service) {
            old.stop()
            old.remove(from: .main, forMode: .common)
            old.delegate = nil
        }

        service.delegate = self
        service.schedule(in: .main, forMode: .common)
        services.append(service)
        resolvingServices.insert(service)
        publishProgress()
        service.resolve(withTimeout: 5.0)

        #if DEBUG
        NSLog("Did find service: \(service) more: \(moreComing)")
        #endif
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        guard self.browser === browser else { return }
        guard let service = removeService(service) else { return }
        service.stop()
        service.remove(from: .main, forMode: .common)
        service.delegate = nil
        publishProgress()

        #if DEBUG
        NSLog("Did remove service: \(service)")
        #endif

        guard let deviceId = service.id,
            let index = devices.firstIndex(where: { $0.id == deviceId }) else {
                #if DEBUG
                NSLog("No device")
                #endif

                return
        }

        #if DEBUG
        NSLog("Removing device: \(devices[index])")
        #endif
        let device = devices.remove(at: index)
        delegate?.deviceDidGoOffline(device)
    }

    @discardableResult func removeService(_ service: NetService) -> NetService? {
        if let index = services.firstIndex(of: service) {
            let removed = services.remove(at: index)
            resolvingServices.remove(removed)
            failedServices.remove(removed)
            return removed
        }

        return nil
    }

    func addDevice(_ device: CastDevice) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            let existing = devices[index]

            guard existing.name != device.name || existing.hostName != device.hostName
                || existing.ipAddress != device.ipAddress || existing.port != device.port
                || existing.modelName != device.modelName || existing.capabilities != device.capabilities else { return }

            devices.remove(at: index)
            devices.insert(device, at: index)

            delegate?.deviceDidChange(device)
        } else {
            devices.append(device)
            delegate?.deviceDidComeOnline(device)
        }
    }
}

extension CastDeviceScanner: NetServiceDelegate {

    public func netServiceDidResolveAddress(_ sender: NetService) {
        guard isScanning, services.contains(where: { $0 === sender }) else { return }
        resolvingServices.remove(sender)
        defer { publishProgress() }
        guard let infoDict = sender.infoDict else {
            failedServices.insert(sender)
            #if DEBUG
            NSLog("No TXT record for \(sender), skipping")
            #endif
            return
        }

        #if DEBUG
        NSLog("Did resolve service: \(sender)")
        NSLog("\(infoDict)")
        #endif

        guard let id = infoDict["id"], !id.isEmpty, sender.port > 0, sender.port <= 65535 else {
            failedServices.insert(sender)
            #if DEBUG
            NSLog("No id for device \(sender), skipping")
            #endif
            return
        }

        addDevice(CastDevice(service: sender, info: infoDict))
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        guard isScanning, services.contains(where: { $0 === sender }) else { return }
        resolvingServices.remove(sender)
        failedServices.insert(sender)
        publishProgress()

        #if DEBUG
        NSLog("!! Failed to resolve service: \(sender) - \(errorDict) !!")
        #endif
    }
}

extension NetService {
    var infoDict: [String: String]? {
        guard let data = txtRecordData() else {
            return nil
        }

        var dict = [String: String]()
        NetService.dictionary(fromTXTRecord: data).forEach({ dict[$0.key] = String(data: $0.value, encoding: .utf8) })

        return dict
    }

    var id: String? {
        return infoDict?["id"]
    }
}

public protocol CastDeviceScannerDelegate: AnyObject {
    func deviceDidComeOnline(_ device: CastDevice)
    func deviceDidChange(_ device: CastDevice)
    func deviceDidGoOffline(_ device: CastDevice)
}
