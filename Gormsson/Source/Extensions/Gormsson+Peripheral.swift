//
//  Gormsson+Peripheral.swift
//  Gormsson
//
//  Created by Loïc GRIFFIE on 12/04/2019.
//  Copyright © 2019 Loïc GRIFFIE. All rights reserved.
//

import CoreBluetooth
import Nevanlinna

extension Gormsson: CBPeripheralDelegate {
    /// Invoked when you discover the peripheral’s available services.
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }

        discoveringService = services.count
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    /// Invoked when you discover the characteristics of a specified service.
    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverCharacteristicsFor service: CBService,
                           error: Error?) {
        discoveringService -= 1
        if discoveringService <= 0 {
            isDiscovering = false
            pendingRequests.forEach { request in
                switch request.property {
                case .read:
                    read(request)
                case .notify:
                    notify(request)
                default:
                    break
                }
            }
        }
    }

    /// Invoked when you retrieve a specified characteristic’s value, or when the peripheral device notifies
    /// your app that the characteristic’s value has changed.
    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        let property = characteristic.isNotifying ? CBCharacteristicProperties.notify : .read
        request(for: peripheral, with: characteristic, property: property, error: error)
    }

    /// Invoked when the peripheral receives a request to start or stop providing notifications for
    /// a specified characteristic’s value.
    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateNotificationStateFor characteristic: CBCharacteristic,
                           error: Error?) {
        request(for: peripheral, with: characteristic, property: .notify, error: error)
    }

    /// Invoked when you write data to a characteristic’s value.
    public func peripheral(_ peripheral: CBPeripheral,
                           didWriteValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        request(for: peripheral, with: characteristic, property: .write, error: error)
    }

    // MARK: - Private functions

    private func request(for peripheral: CBPeripheral,
                         with characteristic: CBCharacteristic,
                         property: CBCharacteristicProperties,
                         error: Error?) {
        let filter: (GattRequest) -> Bool = { $0.characteristic.uuid == characteristic.uuid &&
            characteristic.properties.contains($0.property) && $0.property == property }

        guard property != .notify else {
            currentRequests.filter(filter).forEach { request in
                if let error = error {
                    request.result?(.failure(error))
                } else {
                    compute(request, for: characteristic)
                }
            }
            return
        }

        guard let request = currentRequests.first(where: filter) else { return }

        if property.contains(.read) || property.contains(.write) {
            currentRequests.removeAll(where: { $0 === request })
        }

        guard error == nil else {
            if let error = error {
                request.result?(.failure(error))
            }
            return
        }

        compute(request, for: characteristic)
    }

    private func compute(_ request: GattRequest, for characteristic: CBCharacteristic) {
        guard let data = characteristic.value else {
            request.result?(.success(Empty()))
            return
        }

        guard let value = request.characteristic.format.init(with: data.toOctets) else {
            request.result?(.failure(GormssonError.uncastableValue))
            return
        }

        request.result?(.success(value))
    }
}
