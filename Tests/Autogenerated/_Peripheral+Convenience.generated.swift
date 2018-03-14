import Foundation
import CoreBluetooth
@testable import RxBluetoothKit
import RxSwift

// swiftlint:disable line_length

extension _Peripheral {

    /// Function used to receive service with given identifier. It's taken from cache if it's available,
    /// or directly by `discoverServices` call
    /// - Parameter identifier: Unique identifier of _Service
    /// - Returns: `Single` which emits `next` event, when specified service has been found.
    func service(with identifier: ServiceIdentifier) -> Single<_Service> {
        return .deferred { [weak self] in
            guard let strongSelf = self else { throw _BluetoothError.destroyed }
            if let services = strongSelf.services,
                let service = services.first(where: { $0.uuid == identifier.uuid }) {
                return .just(service)
            } else {
                return strongSelf.discoverServices([identifier.uuid])
                    .map {
                        if let service = $0.first {
                            return service
                        }
                        throw RxError.noElements
                    }
            }
        }
    }

    /// Function used to receive characteristic with given identifier. If it's available it's taken from cache.
    /// Otherwise - directly by `discoverCharacteristics` call
    /// - Parameter identifier: Unique identifier of _Characteristic, that has information
    /// about service which characteristic belongs to.
    /// - Returns: `Single` which emits `next` event, when specified characteristic has been found.
    func characteristic(with identifier: CharacteristicIdentifier) -> Single<_Characteristic> {
        return .deferred { [weak self] in
            guard let strongSelf = self else { throw _BluetoothError.destroyed }
            return strongSelf.service(with: identifier.service)
                .flatMap { service -> Single<_Characteristic> in
                    if let characteristics = service.characteristics, let characteristic = characteristics.first(where: {
                        $0.uuid == identifier.uuid
                    }) {
                        return .just(characteristic)
                    }
                    return service.discoverCharacteristics([identifier.uuid])
                        .map {
                            if let characteristic = $0.first {
                                return characteristic
                            }
                            throw RxError.noElements
                        }
                }
        }
    }

    /// Function used to receive descriptor with given identifier. If it's available it's taken from cache.
    /// Otherwise - directly by `discoverDescriptor` call
    /// - Parameter identifier: Unique identifier of _Descriptor, that has information
    /// about characteristic which descriptor belongs to.
    /// - Returns: `Single` which emits `next` event, when specified descriptor has been found.
    func descriptor(with identifier: DescriptorIdentifier) -> Single<_Descriptor> {
        return .deferred { [weak self] in
            guard let strongSelf = self else { throw _BluetoothError.destroyed }
            return strongSelf.characteristic(with: identifier.characteristic)
                .flatMap { characteristic -> Single<_Descriptor> in
                    if let descriptors = characteristic.descriptors,
                        let descriptor = descriptors.first(where: { $0.uuid == identifier.uuid }) {
                        return .just(descriptor)
                    }
                    return characteristic.discoverDescriptors()
                        .map {
                            if let descriptor = $0.filter({ $0.uuid == identifier.uuid }).first {
                                return descriptor
                            }
                            throw RxError.noElements
                        }
                }
        }
    }

    /// Function that allow to observe writes that happened for characteristic.
    /// - Parameter identifier: Identifier of characteristic of which value writes should be observed.
    /// - Returns: Observable that emits `next` with `_Characteristic` instance every time when write has happened.
    /// It's **infinite** stream, so `.complete` is never called.
    func observeWrite(for identifier: CharacteristicIdentifier)
        -> Observable<_Characteristic> {
        return characteristic(with: identifier)
            .asObservable()
            .flatMap { [weak self] in
                self?.observeWrite(for: $0) ?? .error(_BluetoothError.destroyed)
            }
    }

    /// Function that triggers write of data to characteristic. Write is called after subscribtion to `Observable` is made.
    /// Behavior of this function strongly depends on [CBCharacteristicWriteType](https://developer.apple.com/documentation/corebluetooth/cbcharacteristicwritetype),
    /// so be sure to check this out before usage of the method.
    /// - parameter data: Data that'll be written  written to `_Characteristic` instance
    /// - parameter forCharacteristicWithIdentifier: unique identifier of characteristic, which also holds information about service characteristic belongs to.
    /// - parameter type: Type of write operation. Possible values: `.withResponse`, `.withoutResponse`
    /// - returns: Observable that emition depends on `CBCharacteristicWriteType` passed to the function call.
    /// Behavior is following:
    /// - `WithResponse` -  Observable emits `next` with `_Characteristic` instance write was confirmed without any errors.
    /// Immediately after that `complete` is called. If any problem has happened, errors are emitted.
    /// - `WithoutResponse` - Observable emits `next` with `_Characteristic` instance once write was called.
    /// Immediately after that `.complete` is called. Result of this call is not checked, so as a user you are not sure
    /// if everything completed successfully. Errors are not emitted
    func writeValue(_ data: Data, for identifier: CharacteristicIdentifier,
                           type: CBCharacteristicWriteType) -> Single<_Characteristic> {
        return characteristic(with: identifier)
            .flatMap { [weak self] in
                self?.writeValue(data, for: $0, type: type) ?? .error(_BluetoothError.destroyed)
            }
    }

    /// Function that allow to observe value updates for `_Characteristic` instance.
    /// - Parameter identifier: unique identifier of characteristic, which also holds information about service that characteristic belongs to.
    /// - Returns: Observable that emits `next` with `_Characteristic` instance every time when value has changed.
    /// It's **infinite** stream, so `.complete` is never called.
    func observeValueUpdate(for identifier: CharacteristicIdentifier) -> Observable<_Characteristic> {
        return characteristic(with: identifier)
            .asObservable()
            .flatMap { [weak self] in
                self?.observeValueUpdate(for: $0).asObservable() ?? .error(_BluetoothError.destroyed)
            }
    }

    /// Function that triggers read of current value of the `_Characteristic` instance.
    /// Read is called after subscription to `Observable` is made.
    /// - Parameter identifier: unique identifier of characteristic, which also holds information about service that characteristic belongs to.
    /// - Returns: Observable which emits `next` with given characteristic when value is ready to read. Immediately after that
    /// `.complete` is emitted.
    func readValue(for identifier: CharacteristicIdentifier) -> Single<_Characteristic> {
        return characteristic(with: identifier)
            .flatMap { [weak self] in
                self?.readValue(for: $0) ?? .error(_BluetoothError.destroyed)
            }
    }

    /// Setup characteristic notification in order to receive callbacks when given characteristic has been changed.
    /// Returned observable will emit `_Characteristic` on every notification change.
    /// It is possible to setup more observables for the same characteristic and the lifecycle of the notification will be shared among them.
    ///
    /// Notification is automaticaly unregistered once this observable is unsubscribed
    ///
    /// - parameter characteristic: `_Characteristic` for notification setup.
    /// - returns: `Observable` emitting `_Characteristic` when given characteristic has been changed.
    ///
    /// This is **infinite** stream of values.
    func observeValueUpdateAndSetNotification(for identifier: CharacteristicIdentifier)
        -> Observable<_Characteristic> {
        return characteristic(with: identifier)
            .asObservable()
            .flatMap { [weak self] in
                self?.observeValueUpdateAndSetNotification(for: $0) ?? .error(_BluetoothError.destroyed)
            }
    }

    /// Function that triggers descriptors discovery for characteristic
    /// - parameter identifier: unique identifier of descriptor, which also holds information about characteristic that descriptor belongs to.
    /// - Returns: `Single` that emits `next` with array of `_Descriptor` instances, once they're discovered.
    func discoverDescriptors(for identifier: CharacteristicIdentifier) ->
        Single<[_Descriptor]> {
        return characteristic(with: identifier)
            .flatMap { [weak self] in
                self?.discoverDescriptors(for: $0) ?? .error(_BluetoothError.destroyed)
            }
    }

    /// Function that allow to observe writes that happened for descriptor.
    /// - parameter identifier: unique identifier of descriptor, which also holds information about characteristic that descriptor belongs to.
    /// - Returns: Observable that emits `next` with `_Descriptor` instance every time when write has happened.
    /// It's **infinite** stream, so `.complete` is never called.
    func observeWrite(for identifier: DescriptorIdentifier) -> Observable<_Descriptor> {
        return descriptor(with: identifier)
            .asObservable()
            .flatMap { [weak self] in
                self?.observeWrite(for: $0) ?? .error(_BluetoothError.destroyed)
            }
    }

    /// Function that triggers write of data to descriptor. Write is called after subscribtion to `Observable` is made.
    /// - parameter data: `Data` that'll be written to `_Descriptor` instance
    /// - parameter identifier: unique identifier of descriptor, which also holds information about characteristic that descriptor belongs to.
    /// - returns: `Single` that emits `next` with `_Descriptor` instance, once value is written successfully.
    func writeValue(_ data: Data, for identifier: DescriptorIdentifier)
        -> Single<_Descriptor> {
        return descriptor(with: identifier)
            .flatMap { [weak self] in
                self?.writeValue(data, for: $0) ?? .error(_BluetoothError.destroyed)
            }
    }

    /// Function that allow to observe value updates for `_Descriptor` instance.
    /// - parameter identifier: unique identifier of descriptor, which also holds information about characteristic that descriptor belongs to.
    /// - Returns: Observable that emits `next` with `_Descriptor` instance every time when value has changed.
    /// It's **infinite** stream, so `.complete` is never called.
    func observeValueUpdate(for identifier: DescriptorIdentifier) -> Observable<_Descriptor> {
        return descriptor(with: identifier)
            .asObservable()
            .flatMap { [weak self] in
                self?.observeValueUpdate(for: $0) ?? .error(_BluetoothError.destroyed)
            }
    }

    /// Function that triggers read of current value of the `_Descriptor` instance.
    /// Read is called after subscription to `Observable` is made.
    /// - Parameter identifier: `_Descriptor` to read value from
    /// - Returns: Observable which emits `next` with given descriptor when value is ready to read. Immediately after that
    /// `.complete` is emitted.
    func readValue(for identifier: DescriptorIdentifier) -> Single<_Descriptor> {
        return descriptor(with: identifier)
            .flatMap { [weak self] in
                self?.readValue(for: $0) ?? .error(_BluetoothError.destroyed)
            }
    }
}
