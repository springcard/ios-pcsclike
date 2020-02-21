/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation
import CoreBluetooth
import os.log

extension OSLog {
    private static var subsystem = Bundle.main.bundleIdentifier!
    static let libLog = OSLog(subsystem: subsystem, category: "SC PC/SC OVER BLE LIB")
}

/**
 Main class, instanciate a reader list, manage slots, enable sending APDUs in transmit and control mode, etc
 
 - Version 1.0
 - Author: [SpringCard](https://www.springcard.com)
 - Copyright: [SpringCard](https://www.springcard.com)
 */
public class SCardReaderList: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    // Public properties related to the connected device *****
    /// Represent the vendor's name
    public var vendorName: String = ""
    /// Product's name
    public var productName: String = ""
    /// Device serial number, expressed in hex
    public var serialNumber: String = ""
    /// Device serial number of the BLE device
    public var serialNumberRaw: [UInt8]?
    /// Firmware's version
    public var firmwareVersion: String = ""
    /// Hardware version
    public var hardwareVersion: String = ""
    /// Software version
    public var softwareVersion: String = ""
    public var pnpId: String = ""
    /// Battery level in percentage
    public var batteryLevel: Int = 0
    /// Slots count (0 = device is not authentic)
    public var slotCount = 0
    /// Name of each slot, if names are equal to an empty string then there was an error
    public var slots: [String] = []
    /// Transmit Power Level
    public var powerLevel = 0;
    /// Battery Power State
    public var powerState = 0;
    /// Is the reader in low power mode?
    public var isInLowPowerMode = false;
    // ******************************************************
    
    // Slot status and error  ******************************
    private var _slotStatus: UInt8 = 0x00
    private var _slotError: UInt8 = 0x00
    
    /// Value of the last slot status (of the last exchange)
    public var slotStatus: UInt8 {
        return self._slotStatus
    }
    
    /// Value of the last slot error (of the last exchange)
    public var slotError: UInt8 {
        return self._slotError
    }
    // ******************************************************
    
    // "Meta" properties ************************************
    public static let libraryName = "PC/SC-Like BLE Library"
    public static let LibrarySpecial = ""
    public static let libraryDebug = true
    public static let libraryVersion = (Bundle.main.infoDictionary!["CFBundleShortVersionString"] as? String) ?? ""
    public static let libraryVersionMajor = libraryVersion.components(separatedBy: ".")[0]
    public static let libraryVersionMinor = libraryVersion.components(separatedBy: ".")[1]
    public static let LibraryVersionBuild = libraryVersion.components(separatedBy: ".")[2]
    
    public static var LibraryBuildDate: Date {
        var buildDate = Date()
        guard let infoPath = Bundle.main.path(forResource: "Info.plist", ofType: nil) else {
            return buildDate
        }
        
        do {
            let aFileAttributes = try FileManager.default.attributesOfItem(atPath: infoPath) as [FileAttributeKey:Any]
            buildDate = aFileAttributes[FileAttributeKey.creationDate] as! Date
        } catch {
            return buildDate
        }
        return buildDate
    }
    
    public static var LibrarycompileDate: Date {
        let bundleName = Bundle.main.infoDictionary!["CFBundleName"] as? String ?? "Info.plist"
        if let infoPath = Bundle.main.path(forResource: bundleName, ofType: nil),
            let infoAttr = try? FileManager.default.attributesOfItem(atPath: infoPath),
            let infoDate = infoAttr[FileAttributeKey.creationDate] as? Date
        { return infoDate }
        return Date()
    }
    // *****************************************************
    
    // Var used by public properties or methods **********
    private var isConnected = false
    private var isValid = false
    private var _lastError: Int = 0
    private var _lastErrorMessage = ""
    
    // Security related **************************
    private var isSecureCommunication = false
    private var secureConnectionParameters: SecureConnectionParameters?
    private var readerListSecure: SCardReaderListSecure?
    
    // BLE things *********************************
    private var centralManager: CBCentralManager!
    private var device: CBPeripheral!
    private var commonServices: [BleService] = []
    internal var deviceSpecificServices: [BleService] = []
    private var servicesCount = 0
    private var currentServiceIndex = 0
    private var deviceServices: [CBService] = []
    private var commoncharacteristicsList: [CBCharacteristic] = []
    private var batteryLevelCharacteristics: [CBCharacteristic] = []
    private var characteristicsSpecificsToDevice: [CBCharacteristic] = []
    
    private var CCID_Status_Characteristic: CBCharacteristic?
    private var CCID_PC_To_RDR_Characteristic: CBCharacteristic?
    private var CCID_RDR_To_PC_Characteristic: CBCharacteristic?
    
    private var CCID_Status_Characteristic_UUID: CBUUID?
    private var CCID_PC_To_RDR_Characteristic_UUID: CBUUID?
    private var CCID_RDR_To_PC_Characteristic_UUID: CBUUID?
    private var commonCharacteristicIndex = 0
    private let batteryLevelUuid = "180F"
    
    // Misc things *************************************
    private var delegate: SCardReaderListDelegate?
    private var readers:[SCardReader] = []
    
    private var sequenceNumber: Int = -1
    private var slotNameCounter = 0
    static var instance: SCardReaderList?	// self instance
    private let semaphore = NSCondition()
    private var isSemaphoreLocked = false
    
    // Vars related to current state
    private var afterDeviceWasDiscovered = false
    private var machineState: MachineState = .noState
    private var isWaitingAnswer = false
    private var lastCommand: LastCommand = .noCommand
    private var lastSlotNumberUsed: Int = 0
    private var isUsingSlotNumber: Int = -1
    private var isWakingUpSlotsAfterDiscover = false
    
    // Vars for write long *******************
    private let writeMaxLength = 512    // In bytes
    private var payloadToSend = [UInt8]()
    private var currentWriteIndex = 0
    
    // For waitintg answers *********************
    private var previousResponse: SCCcidRdrToPc?
    private var isWaitingAnswerToFinish = false
    
    // For status **********************************
    private var ccidStatus = SCCcidStatus()
    
    /// :nodoc:
    public init(device: CBPeripheral, centralManager: CBCentralManager, delegate: SCardReaderListDelegate, secureConnectionParameters: SecureConnectionParameters? = nil) {
        #if DEBUG
        os_log("SCardReaderList:init(device, centralManager, delegate)", log: OSLog.libLog, type: .info)
        #endif
        self.centralManager = centralManager
        super.init()
        self.delegate = delegate
        self.centralManager = centralManager
        self.centralManager.delegate = self
        self.device = device
        self.device.delegate = self
        self.isConnected = true
        self._lastErrorMessage = ""
        self._lastError = 0
        if secureConnectionParameters != nil {
            self.secureConnectionParameters = secureConnectionParameters
            if secureConnectionParameters?.commMode == .secure {
                self.isSecureCommunication = true
                self.readerListSecure = SCardReaderListSecure(secureConnectionParameters: self.secureConnectionParameters!)
            }
        }
        self.commonServices = CommonServices.getCommonServices()
        self.setSpecificDeviceServices()
    }
    
    /**
     Get a Reader objet from a slot's index
     
     - Parameter slot: index (0 based) of the slot from the `slots` property
     - Returns: a `Reader` object or nil if the index is out of bounds
     */
    public subscript(slot: Int) -> SCardReader? {
        return self.getReader(slot: slot)
    }
    
    /**
     Get a Reader objet from a slot's name
     
     - Parameter slot: name of the slot from the `slots` property
     - Returns: a `Reader` object or nil if the slot's name is unknown
     */
    public subscript(slot: String) -> SCardReader? {
        return self.getReader(slot: slot)
    }
    
    private func isDeviceValid() -> Bool {
        #if DEBUG
        os_log("SCardReaderList:isDeviceValid()", log: OSLog.libLog, type: .info)
        #endif
        if !DevicesServices.hasDeviceAllServices(expectedServices: self.deviceSpecificServices, readServices: self.deviceServices, errorMessage: &_lastErrorMessage) {
            self.generateError(code: SCardErrorCode.missingService, message: self._lastErrorMessage, trigger: true)
            return false
        }
        
        if self.CCID_Status_Characteristic == nil {
            _lastErrorMessage = "CCID Status characteristic was not found"
            self.generateError(code: SCardErrorCode.missingCharacteristic, message: self._lastErrorMessage, trigger: true)
            return false
        }
        if self.CCID_PC_To_RDR_Characteristic == nil {
            _lastErrorMessage = "CCID PC_To_RDR characteristic was not found"
            self.generateError(code: SCardErrorCode.missingCharacteristic, message: self._lastErrorMessage, trigger: true)
            return false
        }
        if self.CCID_RDR_To_PC_Characteristic == nil {
            _lastErrorMessage = "CCID CCID_RDR_To_PC characteristic was not found"
            self.generateError(code: SCardErrorCode.missingCharacteristic, message: self._lastErrorMessage, trigger: true)
            return false
        }
        return true
    }
    
    private func setLastError(code: Int, message: String) {
        self._lastError = code
        self._lastErrorMessage = message
    }
    
    // Launch services discovering
    private func launchServicesDiscovery() {
        #if DEBUG
        os_log("SCardReaderList:launchServicesDiscovery()", log: OSLog.libLog, type: .info)
        #endif
        self.device!.discoverServices(nil)
    }
    
    // set the private CBCharacteristics when they are read
    private func setCCIDCharacteristics(_ characteristic: CBCharacteristic) {
        #if DEBUG
        os_log("SCardReaderList:setCCIDCharacteristics()", log: OSLog.libLog, type: .info)
        #endif
        if characteristic.uuid == CCID_Status_Characteristic_UUID {
            self.CCID_Status_Characteristic = characteristic
        } else if characteristic.uuid == CCID_PC_To_RDR_Characteristic_UUID {
            self.CCID_PC_To_RDR_Characteristic = characteristic
        } else if characteristic.uuid == CCID_RDR_To_PC_Characteristic_UUID {
            self.CCID_RDR_To_PC_Characteristic = characteristic
        }
    }
    
    // Does the list of services find in the connected device match a list of service of a known device (Puck, D600, etc) ?
    private func searchInKnownServicesList(_ services: [BleService]) -> Bool {
        #if DEBUG
        os_log("SCardReaderList:searchInKnownServicesList()", log: OSLog.libLog, type: .info)
        #endif
        for service in services {
            for deviceService in self.deviceServices {
                if service.getServiceId().uuidString == deviceService.uuid.uuidString {
                    return true
                }
            }
        }
        return false
    }
    
    // Try do detect the device we are connected to
    private func detectDevice() {
        #if DEBUG
        os_log("SCardReaderList:detectDevice()", log: OSLog.libLog, type: .info)
        #endif
        if self.deviceServices.count == 0 {
            self.generateError(code: SCardErrorCode.missingService, message: "Impossible to find the device services", trigger: true)
            self.machineState = .isInError
            return
        }
        var deviceType: BleDeviceType = .Unknown
        if searchInKnownServicesList(DevicesServices.getServices(deviceType: .PUCK_Unbonded)) {
            #if DEBUG
            os_log("Device is detected as a Puck Unbonded", log: OSLog.libLog, type: .debug)
            #endif
            self.deviceSpecificServices = DevicesServices.getServices(deviceType: .PUCK_Unbonded)
            deviceType = .PUCK_Unbonded
        } else if searchInKnownServicesList(DevicesServices.getServices(deviceType: .PUCK_Bonded)) {
            #if DEBUG
            os_log("Device is detected as a Bonded", log: OSLog.libLog, type: .debug)
            #endif
            self.deviceSpecificServices = DevicesServices.getServices(deviceType: .PUCK_Bonded)
            deviceType = .PUCK_Bonded
        } else if searchInKnownServicesList(DevicesServices.getServices(deviceType: .D600)) {
            #if DEBUG
            os_log("Device is detected as a D600", log: OSLog.libLog, type: .debug)
            #endif
            self.deviceSpecificServices = DevicesServices.getServices(deviceType: .D600)
            deviceType = .D600
        }
        if deviceType == .Unknown {
            self.generateError(code: SCardErrorCode.missingService, message: "It was not possible to detect the device type", trigger: true)
            self.machineState = .isInError
            return
        }
        
        self.CCID_Status_Characteristic_UUID = DevicesServices.getCharacteristicIdFromName(services: self.deviceSpecificServices, searchedCharacteristicName: "CCID_Status")
        self.CCID_PC_To_RDR_Characteristic_UUID = DevicesServices.getCharacteristicIdFromName(services: self.deviceSpecificServices, searchedCharacteristicName: "CCID_PC_To_RDR")
        self.CCID_RDR_To_PC_Characteristic_UUID = DevicesServices.getCharacteristicIdFromName(services: self.deviceSpecificServices, searchedCharacteristicName: "CCID_RDR_To_PC")
    }
    
    // Launch reading of common Bluetooth characteristics (not the one specific to the SpringCard device)
    private func readCommonCharacteristics() {
        #if DEBUG
        os_log("SCardReaderList:readCommonCharacteristics()", log: OSLog.libLog, type: .info)
        #endif
        if self.commoncharacteristicsList.isEmpty {
            self.generateError(code: SCardErrorCode.missingCharacteristic, message: "Missing common characteristic(s)", trigger: true)
            return
        }
        if self.commonCharacteristicIndex >= self.commoncharacteristicsList.count {
            notifyToCharacteristics()
            self.getSlotsCount()
            return
        }
        self.machineState = .isReadingCommonCharacteristicsValues
        #if DEBUG
        os_log("Asking for reading chacacteristic ID:  %s", log: OSLog.libLog, type: .debug, self.commoncharacteristicsList[self.commonCharacteristicIndex].uuid.uuidString)
        #endif

        self.readCharacteristicValue(characteristic: self.commoncharacteristicsList[self.commonCharacteristicIndex])
    }
    
    // Subsribe to the notifications of all the characteristics that enable it
    private func notifyToCharacteristics() {
        #if DEBUG
        os_log("SCardReaderList:notifyToCharacteristics()", log: OSLog.libLog, type: .info)
        #endif
        self.commonCharacteristicIndex = 0
        for characteristic in self.characteristicsSpecificsToDevice {
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)  {
                #if DEBUG
                os_log("We are subsribing to characteristic: %s", log: OSLog.libLog, type: .debug, characteristic.uuid.uuidString)
                #endif
                self.device.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    // Ask for the reading of a specific characteristic value
    private func readCharacteristicValue(characteristic: CBCharacteristic) {
        #if DEBUG
        os_log("SCardReaderList:readCharacteristicValue(): %s", log: OSLog.libLog, type: .info, characteristic.uuid.uuidString)
        #endif
        self.device.readValue(for: characteristic)
    }
    
    // Read common Bluetooth characteristics and convert their values into properties
    private func createObjectProperties(_ characteristic: CBCharacteristic) {
        #if DEBUG
        os_log("SCardReaderList:createObjectProperties()", log: OSLog.libLog, type: .info)
        #endif
        switch(characteristic.uuid.uuidString.uppercased()) {
        case "2A29":
            self.vendorName = SCUtilities.bytesToString(characteristic)
        case "2A24":
            self.productName = SCUtilities.bytesToString(characteristic)
        case "2A25":
            self.serialNumber = SCUtilities.bytesToString(characteristic)
            self.serialNumberRaw = SCUtilities.getRawBytesFromCharacteristic(characteristic)
        case "2A26":
            self.firmwareVersion = SCUtilities.bytesToString(characteristic)
        case "2A27":
            self.hardwareVersion = SCUtilities.bytesToString(characteristic)
        case "2A19":
            self.batteryLevel = SCUtilities.byteToInt(characteristic)
        case "2A28":
            self.softwareVersion = SCUtilities.bytesToString(characteristic)
        case "2A50":
            self.pnpId = SCUtilities.bytesToHex(characteristic)
        case "2A07":
            self.powerLevel = SCUtilities.byteToInt(characteristic)
        case "2A1A":
            self.powerState = SCUtilities.byteToInt(characteristic)
        default:
            ()
            #if DEBUG
            os_log("unused common characteristic: %s", log: OSLog.libLog, type: .debug, characteristic.uuid.uuidString)
            #endif
        }
    }
    
    // Create the internal Readers objects that can be used later
    private func createReaders(_ ccidStatus: SCCcidStatus) {
        #if DEBUG
        os_log("SCardReaderList:createReaders()", log: OSLog.libLog, type: .info)
        #endif
        if self.slotCount == 0 {
            return
        }
        
        var slotIndex = 0
        for slot in self.slots {
            let reader = SCardReader(parent: self, slotName: slot, slotIndex: slotIndex)
            reader.setNewState(state: ccidStatus.slots[slotIndex])
            let channel = SCardChannel(parent: reader)
            reader.setNewChannel(channel)
            self.readers.append(reader)
            slotIndex += 1
        }
        debugSlotsStatus()
    }
    
    private func setSlotsCount(_ characteristic: CBCharacteristic) {
        #if DEBUG
        os_log("SCardReaderList:setSlotsCount()", log: OSLog.libLog, type: .info)
        #endif
        self.slotCount = 0
        
        let temporaryCcidStatus = SCCcidStatus(characteristic: characteristic)
        if !temporaryCcidStatus.isValid {
            self.generateError(code: temporaryCcidStatus.errorCode, message: temporaryCcidStatus.errorMessage, trigger: true)
            return
        }
        
        self.slotCount = temporaryCcidStatus.numberOfSlots
        #if DEBUG
        os_log("Slots count: %d", log: OSLog.libLog, type: .info, self.slotCount)
        #endif
        if self.slotCount == 0 {
            self.generateError(code: SCardErrorCode.dummyDevice, message: "Slot count is equal to 0", trigger: true)
            return
        }
        self.slots = Array(repeating: "", count: self.slotCount)
        createReaders(temporaryCcidStatus)
        refreshSlotsFromCcidStatus(characteristic: characteristic)
        machineState = .isReadingSlotsName
        getSlotsName()
    }
    
    // Returns the APDU [0x58, 0x21, 0x00], [0x58, 0x21, 0x01] necessary to read a slot's name
    private func getSlotNameApdu(_ slotNumber: Int) -> [UInt8] {
        #if DEBUG
        os_log("SCardReaderList:getSlotNameApdu()", log: OSLog.libLog, type: .info)
        #endif
        var bytes: [UInt8] = getSlotsNameApdu
        let index = bytes.count - 1
        bytes[index] = UInt8(slotNumber)
        return bytes
    }
    
    private func connectToSlot(_ slotIndex: Int) {
        #if DEBUG
        os_log("SCardReaderList:connectToSlot()", log: OSLog.libLog, type: .info)
        os_log("Slot Index: %d", log: OSLog.libLog, type: .debug, slotIndex)
        #endif
        self.lastCommand = .cardConnect
        self.CCID_PC_To_RDR(command: SCard_CCID_PC_To_RDR.PC_To_RDR_IccPowerOn, slotNumber: slotIndex, payload: nil)
    }
    
    private func initiateMutualAuthentication() {
        #if DEBUG
        os_log("SCardReaderList:initiateMutualAuthentication()", log: OSLog.libLog, type: .info)
        #endif
        self.machineState = .initiateMutualAuthentication
        self.isWaitingAnswer = true
        
        guard let authCommand = self.readerListSecure?.getAuthenticationCommand() else {
            self.generateError(code: SCardErrorCode.authenticationError, message: "Authentication was called but authenticate command returned nil", trigger: true)
            return
        }
        if authCommand.isEmpty {
            self.generateError(code: SCardErrorCode.authenticationError, message: "Authentication was called but authenticate command is empty", trigger: true)
            return
        }
        self.CCID_PC_To_RDR(command: SCard_CCID_PC_To_RDR.PC_To_RDR_Escape, slotNumber: 0, payload: authCommand)
    }
    
    private func powerOnSlotsWithCard() {
        #if DEBUG
        os_log("SCardReaderList:powerOnSlotsWithCard()", log: OSLog.libLog, type: .info)
        #endif
        if isUsingSlotNumber >= self.slotCount {
            #if DEBUG
            os_log("There's no more slots to power on", log: OSLog.libLog, type: .debug)
            #endif
            isUsingSlotNumber = 0
            //debugSlotsStatus()
            happyEnd()
            return
        }
        if self.readers[isUsingSlotNumber].cardPresent && !self.readers[isUsingSlotNumber].cardPowered  && !self.readers[isUsingSlotNumber].wasDisconnected() && !self.readers[isUsingSlotNumber].isSlotInError() {
            #if DEBUG
            os_log("Calling SCardConnect() on slot %d", log: OSLog.libLog, type: .debug, isUsingSlotNumber)
            #endif
            connectToSlot(isUsingSlotNumber)
        } else {
            isUsingSlotNumber += 1
            powerOnSlotsWithCard()
            return
        }
    }
    
    private func debugSlotsStatus() {
        #if DEBUG
        os_log("SCardReaderList:debugSlotsStatus()", log: OSLog.libLog, type: .info)
        for slotIndex in 0 ..< self.slotCount {
            os_log("Slot index, name:  %i, %s", log: OSLog.libLog, type: .debug, readers[slotIndex]._slotIndex, readers[slotIndex]._slotName)
            os_log("Card Present: %s", log: OSLog.libLog, type: .debug, String(readers[slotIndex].cardPresent))
            os_log("Card Powered: %s", log: OSLog.libLog, type: .debug, String(readers[slotIndex].cardPowered))
        }
        #endif
    }
    
    private func getUnpoweredSlotsCount() -> Int {
        #if DEBUG
        os_log("SCardReaderList:getUnpoweredSlotsCount()", log: OSLog.libLog, type: .info)
        #endif
        debugSlotsStatus()
        var count = 0
        for slotIndex in 0 ..< self.slotCount {
            if self.readers[slotIndex].cardPresent && !self.readers[slotIndex].cardPowered {
                count += 1
            }
        }
        #if DEBUG
        os_log("Unpowered slots count: %d", log: OSLog.libLog, type: .debug, count)
        #endif
        return count
    }
    
    private func getSlotsName() {
        #if DEBUG
        os_log("SCardReaderList:getSlotsName()", log: OSLog.libLog, type: .info)
        #endif
        if self.slotNameCounter >= self.slotCount {
            if self.isDeviceValid() {
                self.isValid = true
                self.afterDeviceWasDiscovered = true
                
                if self.isSecureCommunication {
                    initiateMutualAuthentication()
                } else {
                    machineState = .poweringSlots
                    isUsingSlotNumber = 0
                    if getUnpoweredSlotsCount() == 0 {
                        isUsingSlotNumber = self.slotCount + 1
                    }
                    powerOnSlotsWithCard()
                }
            } else {
                self.isValid = false
                machineState = .discoverFailed
                generateError(code: .dummyDevice, message: "Some required services and/or characteristics are missing", trigger: true)
            }
            return
        }
        self.control(command: getSlotNameApdu(slotNameCounter))
    }
    
    // Indicate that there is currently no operation
    private func noop() {
        #if DEBUG
        os_log("SCardReaderList:noop()", log: OSLog.libLog, type: .info)
        #endif
        lastCommand = .noCommand
        isWaitingAnswer = false
    }
    
    // When a Bluetooth error was raised
    private func generateErrorAfterReading(characteristic: CBCharacteristic, errorReceived: Error?) {
        #if DEBUG
        os_log("SCardReaderList:generateErrorAfterReadingCharacteristic()", log: OSLog.libLog, type: .info)
        #endif
        guard let error = errorReceived else {
            return
        }
        
        let errorDescription = error.localizedDescription
        let _error = self.generateError(code: error._code, message: errorDescription, trigger: false)
        
        if CommonServices.isCommonCharacteristic(commonServices: self.commonServices, characteristicId: characteristic.uuid) {
            if lastCommand != .readingBatteryLevel {
                self.delegate?.onReaderListDidCreate(readers: nil, error: _error)
                machineState  = .discoverFailed
                noop()
            } else {
                getBatteryLevelCharacteristicValue(nil, _error)
            }
            return
        }
        
        if characteristic.uuid == self.CCID_Status_Characteristic?.uuid {
            if self.machineState != .discoveredDeviceWithSuccess {
                self.delegate?.onReaderListDidCreate(readers: nil, error: _error)
            } else {
                delegate?.onReaderStatus(reader: nil, present: nil, powered: nil, error: _error)
            }
        } else if characteristic.uuid == CCID_RDR_To_PC_Characteristic?.uuid {
            if self.machineState == .isReadingSlotsName {
                noop()
                self.delegate?.onReaderListDidCreate(readers: nil, error: _error)
            } else if self.machineState == .poweringSlots {
                callOnCardDidConnectWithError(_error)
            } else if self.machineState == .initiateMutualAuthentication {
                self.delegate?.onReaderListDidCreate(readers: nil, error: _error)
            } else if self.machineState == .authenticationStep1 {
                self.delegate?.onReaderListDidCreate(readers: nil, error: _error)
            } else {
                switch lastCommand {
                case .control:
                    callOnControlDidResponseWithError(_error)
                case .cardConnect:
                    callOnCardDidConnectWithError(_error)
                case .noCommand, .getStatus:
                    ()
                case .transmit:
                    callOnCardDidTransmitWithError(_error)
                case .cardDisconnect:
                    callOnCardDidDisconnectWithError(_error)
                case .readingBatteryLevel:
                    getBatteryLevelCharacteristicValue(nil, _error)
                }
            }
        } else {
            delegate?.onReaderStatus(reader: nil, present: nil, powered: nil, error: _error)
        }
        noop()
        self.isValid = false
        machineState = .isInError
    }
    
    private func unlockSemaphore() {
        #if DEBUG
        os_log("unlockSemaphore(), machineState: %s", log: OSLog.libLog, type: .info, String(reflecting: self.machineState))
        #endif
        if self.machineState == .discoveredDeviceWithSuccess || self.machineState == .poweringSlots {
            #if DEBUG
            os_log("=== release semaphore ===", log: OSLog.libLog, type: .debug)
            #endif
            self.isSemaphoreLocked = false
            self.semaphore.signal()
            self.semaphore.unlock()
        }
    }
    
    private func lockSemaphore() {
        #if DEBUG
        os_log("=== lock semaphore ===", log: OSLog.libLog, type: .info)
        #endif
        self.semaphore.lock()
        self.isSemaphoreLocked = true
    }
    
    // When reading a Bluetooth characteristic has succeed
    private func afterReading(_ characteristic: CBCharacteristic) {
        #if DEBUG
        os_log("SCardReaderList:afterReading()", log: OSLog.libLog, type: .info)
        os_log("machineState = %s, lastCommand = %s", log: OSLog.libLog, type: .debug, String(reflecting: self.machineState), String(reflecting: self.lastCommand))
        #endif
        logDataReceivedFromCharacteristic(characteristic)
        if CommonServices.isCommonCharacteristic(commonServices: self.commonServices, characteristicId: characteristic.uuid) {
            #if DEBUG
            os_log("It's a common characteristic", log: OSLog.libLog, type: .debug)
            #endif
            if self.machineState != .discoveredDeviceWithSuccess { // We are still in the discover process
                // during device discovery, we save characteristics values and some other things
                if characteristic.service.uuid.uuidString.lowercased() == batteryLevelUuid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                    self.batteryLevelCharacteristics.append(characteristic)
                }
                createObjectProperties(characteristic)
                self.commonCharacteristicIndex += 1
                self.readCommonCharacteristics()
                return
            }
            if (self.lastCommand == .readingBatteryLevel) && (self.machineState == .discoveredDeviceWithSuccess) {
                getBatteryLevelCharacteristicValue(characteristic)
                return
            }
        }
        switch characteristic.uuid {
        case self.CCID_Status_Characteristic?.uuid:
            if self.machineState == .isReadingSlotCount {
                self.setSlotsCount(characteristic)
            } else if machineState == .discoveredDeviceWithSuccess {
                refreshSlotsFromCcidStatus(characteristic: characteristic)
            } else {
                if machineState != .discoveredDeviceWithSuccess && machineState != .poweringSlots {
                    refreshSlotsFromCcidStatus(characteristic: characteristic)
                    return
                }
                if machineState != .discoverFailed && machineState != .poweringSlots {
                    #if DEBUG
                    os_log("This case shall not happen, machineState: %s", log: OSLog.libLog, type: .error, String(self.machineState.rawValue))
                    #endif
                    self.generateError(code: .otherError, message: "This case shall not happen, machineState: " + String(self.machineState.rawValue), trigger: true)
                }
                return
            }
            
        case self.CCID_RDR_To_PC_Characteristic?.uuid:	// We got an answer
            if self.machineState == .isReadingSlotsName {
                if self.slotNameCounter < self.slots.count {
                    setSlotNameFrom(characteristic: characteristic)
                }
                self.slotNameCounter += 1
                getSlotsName()
            } else if machineState == .poweringSlots {
                callOnCardDidConnect(characteristic)
                isUsingSlotNumber += 1
                powerOnSlotsWithCard()
            } else if machineState == .initiateMutualAuthentication {
                authStep1(characteristic)
            } else if machineState == .authenticationStep1 {
                authStep2(characteristic)
            } else {
                if machineState != .discoveredDeviceWithSuccess {
                    return
                }
                switch lastCommand {
                case .cardConnect:
                    callOnCardDidConnect(characteristic)
                case .control:
                    callOnControlDidResponse(characteristic)
                case .transmit:
                    callOnCardDidTransmit(characteristic)
                case .cardDisconnect:
                    callOnCardDidDisconnect(characteristic)
                case .noCommand, .getStatus, .readingBatteryLevel:
                    break
                }
            }
            
        default:
            break
        }
    }
    
    // *****************************************************************************
    // * Second step of the authentication, the reader returned (may be) something *
    // *****************************************************************************
    private func authStep2WithError(_ error: NSError) {
        #if DEBUG
        os_log("SCardReaderList:authStep2WithError()", log: OSLog.libLog, type: .info)
        #endif
        noop()
        self.isUsingSlotNumber = -1
        triggerOnReaderListDidCreate(error)
    }
    
    private func authStep2(_ characteristic: CBCharacteristic) {
        #if DEBUG
        os_log("SCardReaderList:authStep2()", log: OSLog.libLog, type: .info)
        #endif
        noop()
        let response = SCCcidRdrToPc(characteristic: characteristic, readerListSecure: nil)
        if !response.isValid() {
            authStep2WithError(generateError(code: SCardErrorCode.authenticationError, message: "Response is invalid", trigger: false))
            return
        }
        
        if !areSequenceAndSlotValid(response) {
			self.close(keepBleActive: false)
            return
        }
        
        guard let payload = response.getAnswer() else {
            authStep2WithError(generateError(code: SCardErrorCode.authenticationError, message: "Payload is nil", trigger: false))
            return
        }
        
        if response.header.responseCode == .RDR_To_PC_Escape { // succeed
            guard let isAuthOk = self.readerListSecure?.getAesAuthenticationResponseForStep2(responsePayload: payload) else {
                generateError(code: .authenticationError, message: "Last step of authentication failed", trigger: true)
                return
            }
            if isAuthOk {
                machineState = .poweringSlots
                isUsingSlotNumber = 0
                if getUnpoweredSlotsCount() == 0 {
                    isUsingSlotNumber = self.slotCount + 1
                }
                powerOnSlotsWithCard()
            } else {
                machineState = .discoverFailed
                let error = generateError(code: SCardErrorCode.authenticationError, message: "Authentication failed at last step", trigger: false)
                self.delegate?.onReaderListDidCreate(readers: nil, error: error)
            }
        } else  { // fail
            authStep2WithError(generateError(code: .authenticationError, message: "Response code is not RDR_To_PC_DataBlock", trigger: false))
        }
    }
    
    private func happyEnd() {
        #if DEBUG
        os_log("SCardReaderList:happyEnd()", log: OSLog.libLog, type: .info)
        #endif
        machineState = .discoveredDeviceWithSuccess
        if !self.isWakingUpSlotsAfterDiscover {
            self.isWaitingAnswer = false
            self.delegate?.onReaderListDidCreate(readers: self, error: nil)
        } else {
            self.isWakingUpSlotsAfterDiscover = false
        }
    }
    
    private func areSequenceAndSlotValid(_ response: SCCcidRdrToPc) -> Bool {
        #if DEBUG
        os_log("SCardReaderList:areSequenceAndSlotValid()", log: OSLog.libLog, type: .info)
        #endif
        let responseSequence: UInt8 = (response.header.sequenceNumber ?? 0);
        let slotNumber: UInt8 = (response.header.slotNumber ?? 0)
        let isValid: Bool = (responseSequence != self.sequenceNumber || slotNumber != self.lastSlotNumberUsed) ? false : true
        if !isValid {
            os_log("Sequence and/or slot number are not valid: last sequence read: %d, awaited sequence: %d, last slot read: %d, awaited slot: %d", log: OSLog.libLog, type: .error, responseSequence, self.sequenceNumber, slotNumber, self.lastSlotNumberUsed)
        }
        return isValid
    }
    
    // ****************************************************************************
    // * First step of the authentication, the reader returned (may be) something *
    // ****************************************************************************
    private func authStep1WithError(_ error: NSError) {
        #if DEBUG
        os_log("SCardReaderList:authStep1WithError()", log: OSLog.libLog, type: .info)
        #endif
        noop()
        self.isUsingSlotNumber = -1
        self.triggerOnReaderListDidCreate(error)
    }
    
    private func authStep1(_ characteristic: CBCharacteristic) {
        #if DEBUG
        os_log("SCardReaderList:authStep1()", log: OSLog.libLog, type: .info)
        #endif
        noop()
        let response = SCCcidRdrToPc(characteristic: characteristic, readerListSecure: nil)
        if !response.isValid() {
            authStep1WithError(generateError(code: SCardErrorCode.authenticationError, message: "Response is invalid", trigger: false))
            return
        }
        
        if !areSequenceAndSlotValid(response) {
            self.close(keepBleActive: false)
            return
        }
        guard let payload = response.getAnswer() else {
            authStep1WithError(generateError(code: SCardErrorCode.authenticationError, message: "Payload is nil", trigger: false))
            return
        }
        
        if response.header.responseCode == .RDR_To_PC_Escape { // succeed
            self.machineState = .authenticationStep1
            guard let answserToSend = self.readerListSecure?.getAesAuthenticationResponseForStep1(responsePayload: payload) else {
                authStep1WithError(generateError(code: (readerListSecure?.errorCode)!, message: (readerListSecure?.errorMessage)!, trigger: false))
                return
            }
            #if DEBUG
            os_log("authentication went well, we are moving to step2", log: OSLog.libLog, type: .debug)
            #endif
            self.CCID_PC_To_RDR(command: .PC_To_RDR_Escape, slotNumber: 0, payload: answserToSend)
        } else  { // fail
            authStep1WithError(generateError(code: .authenticationError, message: "Response code is not RDR_To_PC_DataBlock", trigger: false))
        }
    }
    
    // *****************************************
    // * Used after a channel.cardDisconnect() *
    // *****************************************
    private func callOnCardDidDisconnectWithError(_ error: Error) {
        #if DEBUG
        os_log("SCardReaderList:callOnCardDidDisconnectWithError()", log: OSLog.libLog, type: .info)
        #endif
        noop()
        self.isUsingSlotNumber = -1
        self.delegate?.onCardDidDisconnect(channel: nil, error: error)
    }
    
    private func callOnCardDidDisconnect(_ characteristic: CBCharacteristic) {
        #if DEBUG
        os_log("SCardReaderList:callOnCardDidDisconnect(characteristic:)", log: OSLog.libLog, type: .info)
        #endif
        self.unlockSemaphore()
        
        let response = SCCcidRdrToPc(characteristic: characteristic, readerListSecure: (self.machineState == .discoveredDeviceWithSuccess || self.machineState == .poweringSlots) ? self.readerListSecure : nil)
        if !response.isValid() {
            callOnCardDidDisconnectWithError(generateError(code: response.errorCode, message: response.errorMessage, trigger: false))
            return
        }
        
        if !areSequenceAndSlotValid(response) {
            self.close(keepBleActive: false)
            return
        }
        
        let payload = response.getAnswer()
        if payload == nil {
            callOnCardDidDisconnectWithError(generateError(code: .otherError, message: "Response payload to SCardDisconnect() is nil", trigger: false))
            return
        }
        
        noop()
        if response.header.responseCode == .RDR_To_PC_SlotStatus { // succeed
            guard let slotNumber = response.header.slotNumber else {
                callOnCardDidConnectWithError(generateError(code: .otherError, message: "Slot number from answer is nil", trigger: false))
                return
            }
            let reader = self.readers[Int(slotNumber)]
            let channel = reader.channel
            channel?.reinitAtr()
            reader.setCardUnpowered()
            self.delegate?.onCardDidDisconnect(channel: channel, error: nil)
        } else if response.header.responseCode == .RDR_To_PC_SlotStatus { // fail
            callOnCardDidDisconnectWithError(generateError(code: .cardAbsent, message: "SCardDisconnect() was called but the answer is not RDR_To_PC_SlotStatus", trigger: false))
        }
    }
    
    // ***********************************
    // * Used after a channel.transmit() *
    // ***********************************
    private func callOnCardDidTransmitWithError(_ error: Error) {
        #if DEBUG
        os_log("SCardReaderList:callOnCardDidTransmitWithError()", log: OSLog.libLog, type: .info)
        #endif
        noop()
        unlockSemaphore()
        self.isUsingSlotNumber = -1
        self.delegate?.onTransmitDidResponse(channel: nil, response: nil, error: error)
    }
    
    private func callOnCardDidTransmit(_ characteristic: CBCharacteristic) {
        #if DEBUG
        os_log("SCardReaderList:callOnCardDidTransmit()", log: OSLog.libLog, type: .info)
        #endif
        var response = SCCcidRdrToPc(characteristic: characteristic, readerListSecure: (self.machineState == .discoveredDeviceWithSuccess || self.machineState == .poweringSlots) ? self.readerListSecure : nil)
        
        if response.isLongAnswer() && !isWaitingAnswerToFinish {
            self.isWaitingAnswerToFinish = true
            self.previousResponse = response
            return
        }
        
        if isWaitingAnswerToFinish {
            previousResponse?.addToPayload(characteristic)
            if (previousResponse?.isAnswerComplete())! {
                response = previousResponse!
                isWaitingAnswerToFinish = false
            } else {
                //self.unlockSemaphore()
                return
            }
        }
        
        if !response.isValid() {
            callOnCardDidTransmitWithError(generateError(code: response.errorCode, message: response.errorMessage, trigger: false))
            return
        }
        
        if !areSequenceAndSlotValid(response) {
            self.close(keepBleActive: false)
            return
        }
        
        let payload = response.getAnswer()
        if payload == nil {
            callOnCardDidTransmitWithError(generateError(code: .otherError, message: "Response payload to channel.transmit() is nil", trigger: false))
            return
        }
        
        guard let slotNumber = response.header.slotNumber else {
            callOnCardDidTransmitWithError(generateError(code: .otherError, message: "Slot number from answer is nil", trigger: false))
            return
        }
        let reader = self.readers[Int(slotNumber)]
        
        if response.header.responseCode == .RDR_To_PC_DataBlock { // succeed
            let slotStatus = response.header.slotStatus
            let slotError = response.header.slotError
            
            if (slotStatus == SCARD.s_success.rawValue && slotError == SCARD.s_success.rawValue)  {	// succeed
                noop()
                let channel = reader.channel
                self.unlockSemaphore()
                self.delegate?.onTransmitDidResponse(channel: channel, response: payload, error: nil)
                reader.setSlotNotInError()
                askToPowerOnSlotsWithCard()
            } else { // error
                self._slotStatus = slotStatus ?? 0x00
                self._slotError = slotError ?? 0x00
                let slotStatusAsString = (slotStatus != nil) ? String(format: "%02X", Int(slotStatus!)) : ""
                let slotErrorAsString =  (slotError != nil) ? String(format: "%02X", Int(slotError!)) : ""
                callOnCardDidTransmitWithError(generateError(code: .cardCommunicationError, message: "channel.transmit() was called but slot status and/or slot error are not equals to zero. Slot error: " + slotErrorAsString + ", slot status: " + slotStatusAsString, trigger: false))
                noop()
                askToPowerOnSlotsWithCard()
            }
        } else if response.header.responseCode == .RDR_To_PC_SlotStatus { // fail
            reader.setSlotInError()
            noop()
            callOnCardDidTransmitWithError(generateError(code: .cardAbsent, message: "channel.transmit() was called but the answer is RDR_To_PC_SlotStatus", trigger: false))
            askToPowerOnSlotsWithCard()
        }
    }
    
    // *************************************
    // * Used after a reader.cardConnect() *
    // *************************************
    private func callOnCardDidConnectWithError(_ error: Error) {
        #if DEBUG
        os_log("SCardReaderList:callOnCardDidConnectWithError()", log: OSLog.libLog, type: .info)
        #endif
        noop()
        self.unlockSemaphore()
        self.isUsingSlotNumber = -1
        if self.afterDeviceWasDiscovered { //} machineState != .poweringSlots
            self.delegate?.onCardDidConnect(channel: nil, error: error)
        }
    }
    
    private func callOnCardDidConnect(_ characteristic: CBCharacteristic) {
        #if DEBUG
        os_log("SCardReaderList:callOnCardDidConnect()", log: OSLog.libLog, type: .info)
        #endif
        let response = SCCcidRdrToPc(characteristic: characteristic, readerListSecure: (self.machineState == .discoveredDeviceWithSuccess || self.machineState == .poweringSlots) ? self.readerListSecure : nil)
        if !response.isValid() {
            callOnCardDidConnectWithError(generateError(code: response.errorCode, message: response.errorMessage, trigger: false))
            return
        }
        if !areSequenceAndSlotValid(response) {
            self.close(keepBleActive: false)
            return
        }
        let payload = response.getAnswer()
        if payload == nil {
            if machineState == .poweringSlots {
                isUsingSlotNumber = self.slotCount + 1
                self.machineState = .discoverFailed
            } else if machineState == .discoveredDeviceWithSuccess {
                self.unlockSemaphore()
            }
            noop()
            callOnCardDidConnectWithError(generateError(code: .otherError, message: "Response payload to SCardConnect() is nil", trigger: false))
            return
        }
        
        guard let slotNumber = response.header.slotNumber else {
            callOnCardDidConnectWithError(generateError(code: .otherError, message: "Slot number from answer is nil", trigger: false))
            return
        }
        let reader = self.readers[Int(slotNumber)]
        
        if response.header.responseCode == .RDR_To_PC_DataBlock { // succeed
            let slotStatus = response.header.slotStatus
            let slotError = response.header.slotError
            noop()
            
            if (slotStatus == SCARD.s_success.rawValue && slotError == SCARD.s_success.rawValue)  {	// succeed
                let channel = SCardChannel(parent: reader, atr: payload!)
                reader.setNewChannel(channel)
                reader.setCardPowered()
                reader.setConnected()
                self.unlockSemaphore()
                if machineState != .poweringSlots {
                    self.delegate?.onCardDidConnect(channel: channel, error: nil)
                }
                if self.isWakingUpSlotsAfterDiscover {
                    self.delegate?.onCardDidConnect(channel: channel, error: nil)
                }
            } else {
                self._slotStatus = slotStatus ?? 0x00
                self._slotError = slotError ?? 0x00
                let slotStatusAsString = (slotStatus != nil) ? String(format: "%02X", Int(slotStatus!)) : "Unknown slot status"
                let slotErrorAsString =  (slotError != nil) ? String(format: "%02X", Int(slotError!)) : "Unknown slot error"
                reader.setSlotInError()
                self.isUsingSlotNumber = self.slotCount + 1
                callOnCardDidConnectWithError(generateError(code: .cardCommunicationError, message: "SCardConnect() was called but slot status and/or slot error are not equals to zero. Slot error: " + slotErrorAsString + ", slot status: " + slotStatusAsString, trigger: false))
            }
        } else if response.header.responseCode == .RDR_To_PC_SlotStatus { // fail
            callOnCardDidConnectWithError(generateError(code: .cardAbsent, message: "SCardConnect() was called but the answer is RDR_To_PC_SlotStatus", trigger: false))
        }
    }
    
    // **********************************
    // * Used after a readers.control() *
    // **********************************
    private func callOnControlDidResponseWithError(_ error: Error) {
        #if DEBUG
        os_log("SCardReaderList:callOnControlDidResponseWithError()", log: OSLog.libLog, type: .info)
        #endif
        noop()
        self.delegate?.onControlDidResponse(readers: self, response: nil, error: error)
    }
    
    private func callOnControlDidResponse(_ characteristic: CBCharacteristic) {
        #if DEBUG
        os_log("SCardReaderList:callOnControlDidResponse()", log: OSLog.libLog, type: .info)
        #endif
        var response = SCCcidRdrToPc(characteristic: characteristic, readerListSecure: (self.machineState == .discoveredDeviceWithSuccess || self.machineState == .poweringSlots) ? self.readerListSecure : nil, isLongAnswer: self.isWaitingAnswerToFinish)
        
        if response.isLongAnswer() && !isWaitingAnswerToFinish {
            self.isWaitingAnswerToFinish = true
            self.previousResponse = response
            return
        }
        
        if isWaitingAnswerToFinish {
            previousResponse?.addToPayload(characteristic)
            if (previousResponse?.isAnswerComplete())! {
                response = previousResponse!
                isWaitingAnswerToFinish = false
            } else {
                self.unlockSemaphore()
                return
            }
        }
        
        self.unlockSemaphore()
        
        if !areSequenceAndSlotValid(response) {
            self.close(keepBleActive: false)
            return
        }
        
        if !response.isValid() {
            callOnControlDidResponseWithError(generateError(code: response.errorCode, message: response.errorMessage, trigger: false))
            return
        }
        
        let payload = response.getAnswer()
        if payload == nil {
            callOnControlDidResponseWithError(generateError(code: .otherError, message: "Response payload is nil", trigger: false))
            return
        }
        
        noop()
        self.delegate?.onControlDidResponse(readers: self, response: payload, error: nil)
        askToPowerOnSlotsWithCard()
    }
    
    private func setSlotNameFrom(characteristic: CBCharacteristic) {
        #if DEBUG
        os_log("SCardReaderList:setSlotNameFrom()", log: OSLog.libLog, type: .info)
        #endif
        let response = SCCcidRdrToPc(characteristic: characteristic, readerListSecure: (self.machineState == .discoveredDeviceWithSuccess || self.machineState == .poweringSlots) ? self.readerListSecure : nil)
        if !response.isValid() {
            generateError(code: response.errorCode, message: response.errorMessage, trigger: true)
            return
        }
        if response.header.responseCode != CCID_RDR_To_PC_Answer_Codes.RDR_To_PC_Escape {
            generateError(code: SCardErrorCode.invalidCharacteristicSetting, message: "Invalid response code when getting slots names", trigger: true)
            return
        }
        let name = SCUtilities.getSlotNameFromBytes(response.getAnswer()!)
        if name != nil {
            self.slots[slotNameCounter] = name!
            self.readers[slotNameCounter]._slotName = name!
        } else {
            generateError(code: SCardErrorCode.invalidCharacteristicSetting, message: "Invalid response code when getting slots names", trigger: true)
        }
    }
    
    private func unsubscribeCharacteristics() {
        #if DEBUG
        os_log("SCardReaderList:unsubscribeCharacteristics()", log: OSLog.libLog, type: .info)
        #endif
        if self.characteristicsSpecificsToDevice.isEmpty {
            #if DEBUG
            os_log("Nothing to unsubscribe", log: OSLog.libLog, type: .debug)
            #endif
            return
        }
        self.machineState = .isUnSubsribingToNotifications
        for characteristic in self.characteristicsSpecificsToDevice {
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)  {
                #if DEBUG
                os_log("Unsubscribe to characteristic %s", log: OSLog.libLog, type: .debug, characteristic.uuid.uuidString)
                #endif
                self.device!.setNotifyValue(false, for: characteristic)
            }
        }
    }
    
    private func silentSlotsAndChannels() {
        #if DEBUG
        os_log("SCardReaderList:silentSlotsAndChannels()", log: OSLog.libLog, type: .info)
        #endif
        for slotIndex in 0 ..< ccidStatus.numberOfSlots {
            self.readers[slotIndex].setCardUnpowered()
            self.readers[slotIndex].unpower()
        }
    }
    
    // Manage internal and external state when the reader is weaking up or when it is shutting down
    private func lowPowerModeChanged() {
        #if DEBUG
        os_log("SCardReaderList:lowPowerModeChanged()", log: OSLog.libLog, type: .info)
        #endif
        if self.machineState != .discoveredDeviceWithSuccess {
            return
        }
        var isInLowPowerMode = false;
        
        if !self.ccidStatus.isInLowPowerMode && self.isInLowPowerMode { // wake-up
            isInLowPowerMode = false
        } else if !self.isInLowPowerMode && self.ccidStatus.isInLowPowerMode { // Shut down
            isInLowPowerMode = true
            silentSlotsAndChannels()
        }
        self.isInLowPowerMode = self.ccidStatus.isInLowPowerMode
        self.delegate?.onReaderListState(readers: self, isInLowPowerMode: isInLowPowerMode)
    }
    
    private func refreshSlotsFromCcidStatus(characteristic: CBCharacteristic) {
        #if DEBUG
        os_log("SCardReaderList:refreshSlotsFromCcidStatus()", log: OSLog.libLog, type: .info)
        #endif
        self.ccidStatus = SCCcidStatus(characteristic: characteristic)
        if !ccidStatus.isValid {
            return;
        }
        
        // Case of the wakeup without card
        if self.ccidStatus.isInLowPowerMode && self.isInLowPowerMode {
            var hasNoCards = true
            for slotIndex in 0 ..< ccidStatus.numberOfSlots {
                if ccidStatus.slots[slotIndex].slotStatus != .cardAbsent {
                    hasNoCards = false
                }
            }
            if hasNoCards {
                self.ccidStatus.markAsWakeUped()
            }
        }
        
        if self.ccidStatus.isInLowPowerMode != self.isInLowPowerMode {
            lowPowerModeChanged()
        }
        if self.ccidStatus.isInLowPowerMode {
            return
        }
        
        var slotsToPowerOn = 0
        for slotIndex in 0 ..< ccidStatus.numberOfSlots {
            if ccidStatus.slots[slotIndex].slotStatus == .cardInserted || ccidStatus.slots[slotIndex].slotStatus == .cardRemoved {
                self.readers[slotIndex].setNewState(state: ccidStatus.slots[slotIndex])
                
                if ccidStatus.slots[slotIndex].slotStatus == .cardRemoved {
                    if machineState != .poweringSlots {
                        callOnCardDidDisconnect(slotIndex)
                    }
                }
                
                if machineState != .poweringSlots {
                    callOnReaderStatus(slotIndex)
                }
                if ccidStatus.slots[slotIndex].slotStatus == .cardInserted {
                    slotsToPowerOn += 1
                }
            }
        }
        if slotsToPowerOn > 0 {
            askToPowerOnSlotsWithCard()
        }
    }
    
    // Method to be called after any answer is received, to manage slots that need to be powered on and that was not powered on automatically because a command was running
    private func askToPowerOnSlotsWithCard() {
        #if DEBUG
        os_log("SCardReaderList:askToPowerOnSlotsWithCard()", log: OSLog.libLog, type: .info)
        #endif
        if !self.isWaitingAnswer && self.machineState == .discoveredDeviceWithSuccess {
            #if DEBUG
            os_log("We are launching automatic IccPowerOn", log: OSLog.libLog, type: .debug)
            #endif
            self.isWakingUpSlotsAfterDiscover = true
            machineState = .poweringSlots
            isUsingSlotNumber = 0
            powerOnSlotsWithCard()
        } else {
            ()
            #if DEBUG
            os_log("Nothing was done, coming back", log: OSLog.libLog, type: .debug)
            #endif
        }
    }
    
    private func callOnCardDidDisconnect(_ slotIndex: Int) {
        #if DEBUG
        os_log("SCardReaderList:callOnCardDidDisconnect(slotIndex:) %d", log: OSLog.libLog, type: .info, slotIndex)
        #endif
        if machineState != .discoveredDeviceWithSuccess {
            return
        }
        let channel = self.readers[slotIndex].channel
        self.delegate?.onCardDidDisconnect(channel: channel, error: nil)
    }
    
    private func callOnReaderStatus(_ slotIndex: Int) {
        #if DEBUG
        os_log("SCardReaderList:callOnReaderStatus()", log: OSLog.libLog, type: .info)
        #endif
        if machineState != .discoveredDeviceWithSuccess {
            return
        }
        let reader = self.readers[slotIndex]
        self.delegate?.onReaderStatus(reader: reader, present: reader.cardPresent, powered: reader.cardPowered, error: nil)
    }
    
    private func debugPcToRdrHeader(_ bytes : [UInt8]) {
        #if DEBUG
        if bytes.isEmpty || bytes.count < 10 {
            return
        }
        let payloadLengthBytes: [Byte] = [bytes[1], bytes[2], bytes[3], bytes[4]]
        let payloadLength = SCUtilities.fromByteArray(byteArray: payloadLengthBytes, secureCommunication: self.isSecureCommunication)
        
        os_log("%s", log: OSLog.libLog, type: .debug, "--------------------------")
        os_log("%s", log: OSLog.libLog, type: .debug, "Command        : 0x" + String(format: "%02X", bytes[0]))
        os_log("%s", log: OSLog.libLog, type: .debug, "Length         : " + String(payloadLength))
        os_log("%s", log: OSLog.libLog, type: .debug, "Slot number    : " + String(bytes[5]))
        os_log("%s", log: OSLog.libLog, type: .debug, "Sequence number: " + String(bytes[6]))
        if bytes.count > 10 {
            os_log("%s", log: OSLog.libLog, type: .debug, "Payload        : " + Array(bytes[10...]).hexa)
        }
        os_log("%s", log: OSLog.libLog, type: .debug, "--------------------------")
        #endif
    }
    
    private func logDataSent(_ bytes: [UInt8], characteristic: CBCharacteristic) {
        #if DEBUG
        os_log("SCardReaderList:logDataSent()", log: OSLog.libLog, type: .info)
        if bytes.isEmpty {
            os_log("There's no bytes sent", log: OSLog.libLog, type: .debug)
            return
        }
        os_log("Bytes sent: %s", log: OSLog.libLog, type: .debug, bytes.hexa)
        if characteristic.uuid.uuidString.count > 4 {
            debugPcToRdrHeader(bytes)
        }
        #endif
    }
    
    private func debugRdrToPcHeader(_ bytes : [UInt8]) {
        #if DEBUG
        if bytes.isEmpty || bytes.count < 10 {
            return
        }
        let payloadLengthBytes: [Byte] = [bytes[1], bytes[2], bytes[3], bytes[4]]
        let payloadLength = SCUtilities.fromByteArray(byteArray: payloadLengthBytes, secureCommunication: self.isSecureCommunication)
        os_log("%s", log: OSLog.libLog, type: .debug, "--------------------------")
        os_log("%s", log: OSLog.libLog, type: .debug, "Response code  : 0x" + String(format: "%02X", bytes[0]))
        os_log("%s", log: OSLog.libLog, type: .debug, "Length         : " + String(payloadLength))
        os_log("%s", log: OSLog.libLog, type: .debug, "Slot number    : " + String(bytes[5]))
        os_log("%s", log: OSLog.libLog, type: .debug, "Sequence number: " + String(bytes[6]))
        if bytes[7] != 0x00 {
            self._slotStatus = bytes[7]
            os_log("%s", log: OSLog.libLog, type: .debug, "Slot status    : " + String(format: "%02X", bytes[7]))
        }
        if bytes[8] != 0x00 {
            self._slotError = bytes[8]
            os_log("%s", log: OSLog.libLog, type: .debug, "Slot error     : " + String(format: "%02X", bytes[8]))
        }        
        if bytes.count > 10 {
            os_log("%s", log: OSLog.libLog, type: .debug, "Payload        : " + Array(bytes[10...]).hexa)
        }
        os_log("%s", log: OSLog.libLog, type: .debug, "--------------------------")
        #endif
    }
    
    private func logDataReceivedFromCharacteristic(_ characteristic: CBCharacteristic) {
        #if DEBUG
        os_log("SCardReaderList:logDataReceivedFromCharacteristic() from characteristic: %s", log: OSLog.libLog, type: .debug, characteristic.uuid.uuidString)
        guard let characteristicData = characteristic.value else {
            os_log("characteristic value is nil", log: OSLog.libLog, type: .debug)
            return
        }
        let bytes = [UInt8](characteristicData)
        if bytes.isEmpty {
            os_log("No bytes in characteristic", log: OSLog.libLog, type: .debug)
            return
        }
        os_log("%s", log: OSLog.libLog, type: .debug, String(repeating: "-", count: bytes.hexa.count + 16))
        os_log("Bytes received: %s", log: OSLog.libLog, type: .debug, bytes.hexa)
        os_log("%s", log: OSLog.libLog, type: .debug, String(repeating: "-", count: bytes.hexa.count + 16))
        if characteristic.uuid.uuidString.count > 4 {
            debugRdrToPcHeader(bytes)
        }
        #endif
    }
    
    // Data send from the lib to the reader
    private func CCID_PC_To_RDR(command: SCard_CCID_PC_To_RDR, slotNumber: Int, payload: [UInt8]?) {
        #if DEBUG
        os_log("SCardReaderList:CCID_PC_To_RDR()", log: OSLog.libLog, type: .info)
        os_log("Slot Number: %d", log: OSLog.libLog, type: .debug, slotNumber)
        #endif
        sequenceNumber += 1
        if sequenceNumber > 255 {
            sequenceNumber = 0
        }
        let command = SCCcidPcToRdr(command: command, slotNumber: slotNumber, sequenceNumber: Int(sequenceNumber), payload: payload, readerListSecure: (self.machineState == .discoveredDeviceWithSuccess || self.machineState == .poweringSlots) ? self.readerListSecure : nil)
        guard let sentData = command.getCommand() else {
            noop()
            #if DEBUG
            os_log("There's nothing to send", log: OSLog.libLog, type: .info)
            #endif
            return
        }
        self.currentWriteIndex = 0
        if sentData.isEmpty {
            noop()
            return
        }
        self.lastSlotNumberUsed = slotNumber
        self.payloadToSend = sentData
        if self.machineState == .discoveredDeviceWithSuccess || self.isWakingUpSlotsAfterDiscover {
            self.lockSemaphore()
        }
        writeToPcToRdrCharacteristic()
        // ICI
    }
    
    private func writeToPcToRdrCharacteristic() {
        #if DEBUG
        os_log("SCardReaderList:writeToPcToRdrCharacteristic()", log: OSLog.libLog, type: .info)
        #endif
        let startingIndex = self.currentWriteIndex
        if startingIndex >= payloadToSend.count {
            #if DEBUG
            os_log("payload was fully sent, nothing more to come, returning", log: OSLog.libLog, type: .debug)
            #endif
            return
        }
        var endingIndex = startingIndex + self.writeMaxLength
        if endingIndex > payloadToSend.count {
            endingIndex = payloadToSend.count
        }
        let bytesToSend = Array(payloadToSend[startingIndex ..< endingIndex])
        logDataSent(bytesToSend, characteristic: self.CCID_PC_To_RDR_Characteristic!)
        currentWriteIndex += writeMaxLength
        
        let data = Data(bytes: bytesToSend, count: bytesToSend.count)
        self.device.writeValue(data, for: self.CCID_PC_To_RDR_Characteristic!, type: CBCharacteristicWriteType.withResponse)
    }
    
    // Must be override in each child class
    internal func isBoundedDevice() -> Bool {
        #if DEBUG
        os_log("SCardReaderList:isBoundedDevice()", log: OSLog.libLog, type: .info)
        #endif
        return true;
    }
    
    private static func getAdvertisingServicesFromList(deviceServices: [String: (serviceDescription: String, isAdvertisingService: Bool, serviceCharacteristics: [String: String])], advertisingServices: inout [CBUUID]) {
        #if DEBUG
        os_log("SCardReaderList:getAdvertisingServicesFromList()", log: OSLog.libLog, type: .info)
        #endif
        for (serviceId, serviceDescription) in deviceServices {
            if serviceDescription.isAdvertisingService {
                advertisingServices.append(CBUUID(string: serviceId))
            }
        }
    }
    
    // Method used to set services specific to each device.
    // To be implemented in each child class
    internal func setSpecificDeviceServices() {
        #if DEBUG
        os_log("SCardReaderList:setSpecificDeviceServices()", log: OSLog.libLog, type: .info)
        #endif
    }
    
    private func getSlotsCount() {
        #if DEBUG
        os_log("SCardReaderList:getSlotsCount()", log: OSLog.libLog, type: .info)
        #endif
        if self.CCID_Status_Characteristic_UUID == nil {
            self.generateError(code: SCardErrorCode.missingCharacteristic, message: "The CCID_Status characteristic was not found", trigger: true)
            return
        }
        self.machineState = .isReadingSlotCount
        self.readCharacteristicValue(characteristic: self.CCID_Status_Characteristic!)
    }
    
    private func doGenerateError(code: Int, message: String, trigger: Bool) -> NSError {
        #if DEBUG
        os_log("SCardReaderList:doGenerateEror()", log: OSLog.libLog, type: .info)
        os_log("Debug of error generated, code: %d, Error message: %s", log: OSLog.libLog, type: .error, _lastError, message)
        #endif
        setLastError(code: code, message: message)
        let error = NSError(domain: Bundle.main.bundleIdentifier!, code: _lastError, userInfo: [NSLocalizedDescriptionKey : message])
        if trigger {
            self.triggerOnReaderListDidCreate(error)
        }
        return error
    }
    
    @discardableResult
    private func generateError(code: Int, message: String, trigger: Bool) -> NSError {
        return doGenerateError(code: code, message: message, trigger: trigger)
    }
    
    @discardableResult
    private func generateError(code: SCardErrorCode, message: String, trigger: Bool) -> NSError {
        return doGenerateError(code: code.rawValue, message: message, trigger: trigger)
    }
    
    private func triggerOnReaderListDidCreate(_ error: NSError) {
        self.delegate?.onReaderListDidCreate(readers: nil, error: error)
    }
    
    // Validates that a slot index is valid (not outside bounds)
    private func isSlotIndexValid(_ slotIndex: Int) -> Bool {
        return (slotIndex < 0 || slotIndex >= slotCount) ? false : true
    }
    
    private func canRequestCommandToDevice(_ takeSleeptModeIntoAccount: Bool = true) -> Bool {
        #if DEBUG
        os_log("SCardReaderList:canRequestCommandToDevice()", log: OSLog.libLog, type: .info)
        os_log("Debug of states, isConnected: %s, isValid: %s, isWaitingAnswer: %s, machineState: %s", log: OSLog.libLog, type: .debug, isConnected.description, isValid.description, isWaitingAnswer.description, String(reflecting: self.machineState))
        #endif
        
        if machineState == .isReadingSlotsName {
            return true
        }
        if self.isInLowPowerMode && takeSleeptModeIntoAccount {
            return false
        }
        if self.machineState != .discoveredDeviceWithSuccess {
            return false
        }
        return (!self.isConnected || !self.isValid || self.isWaitingAnswer) ? false : true
    }
    
    // ***********************************************************
    // ***********************************************************
    // * System callbacks related to the Bluetooth communication *
    // ***********************************************************
    // ***********************************************************
    
    // Services were discovered or they was an error
    /// :nodoc:
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        #if DEBUG
        os_log("SCardReaderList:didDiscoverServices()", log: OSLog.libLog, type: .info)
        #endif
        if error != nil {
            self.generateError(code: error!._code, message: error!.localizedDescription, trigger: true)
        } else {
            self.deviceServices = peripheral.services!
            self.servicesCount = (peripheral.services?.count)!
            self.currentServiceIndex = 0
            for service in peripheral.services! {
                #if DEBUG
                os_log("Service ID: %s, isPrimary: %s", log: OSLog.libLog, type: .debug, service.uuid.uuidString, service.isPrimary.description)
                os_log("Launching characteristics scan", log: OSLog.libLog, type: .debug)
                #endif
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    // Characteristics of a specific service are discovered (or there is an error)
    /// :nodoc:
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        #if DEBUG
        os_log("SCardReaderList:didDiscoverCharacteristicsFor()", log: OSLog.libLog, type: .info)
        os_log("Characteristics discovered for service %s", log: OSLog.libLog, type: .debug, service.uuid.uuidString)
        #endif
        
        if error != nil {
            self.generateError(code: error!._code, message: error!.localizedDescription, trigger: true)
        } else {
            if CommonServices.isCommonService(service.uuid) {
                #if DEBUG
                os_log("We are on a common service", log: OSLog.libLog, type: .debug)
                #endif
                for characteristic in service.characteristics! {
                    if CommonServices.isCommonCharacteristic(commonServices: self.commonServices, characteristicId: characteristic.uuid) {
                        #if DEBUG
                        os_log("Characteristic ID:  %s", log: OSLog.libLog, type: .debug, characteristic.uuid.uuidString)
                        #endif
                        self.commoncharacteristicsList.append(characteristic)
                    }
                }
            } else {
                #if DEBUG
                os_log("We are NOT on a common service", log: OSLog.libLog, type: .debug)
                #endif
                for characteristic in service.characteristics! {
                    setCCIDCharacteristics(characteristic)
                    #if DEBUG
                    os_log("Characteristic ID:  %s", log: OSLog.libLog, type: .debug, characteristic.uuid.uuidString)
                    #endif
                    self.characteristicsSpecificsToDevice.append(characteristic)
                }
            }
            self.currentServiceIndex += 1
            if self.currentServiceIndex >= self.servicesCount {
                self.searchDeviceSpecificCharacteristics()
                self.readCommonCharacteristics()
            }
        }
    }
    
    private func searchDeviceSpecificCharacteristics() {
        #if DEBUG
        os_log("SCardReaderList:searchDeviceSpecificCharacteristics()", log: OSLog.libLog, type: .info)
        #endif
        self.detectDevice()
        if self.characteristicsSpecificsToDevice.isEmpty {
            self.generateError(code: SCardErrorCode.missingCharacteristic, message: "Impossible to find the device characteristics", trigger: true)
            self.machineState = .isInError
            return
        }
        for characteristic in self.characteristicsSpecificsToDevice {
            if characteristic.uuid == CCID_Status_Characteristic_UUID {
                self.CCID_Status_Characteristic = characteristic
            } else if characteristic.uuid == CCID_PC_To_RDR_Characteristic_UUID {
                self.CCID_PC_To_RDR_Characteristic = characteristic
            } else if characteristic.uuid == CCID_RDR_To_PC_Characteristic_UUID {
                self.CCID_RDR_To_PC_Characteristic = characteristic
            }
        }
    }
    
    // When a characteristic value is read
    /// :nodoc:
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        #if DEBUG
        os_log("SCardReaderList:didUpdateValueFor()", log: OSLog.libLog, type: .info)
        #endif
        self._slotStatus = 0x00
        self._slotError = 0x00
        if error != nil {
            noop()
            if self.isSemaphoreLocked && self.machineState == .discoveredDeviceWithSuccess && characteristic.uuid == self.CCID_PC_To_RDR_Characteristic_UUID {
                self.unlockSemaphore()
            }
            generateErrorAfterReading(characteristic: characteristic, errorReceived: error)
            return
        }
        afterReading(characteristic)
    }
    
    // When a characteristic notifies
    /// :nodoc:
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        #if DEBUG
        os_log("SCardReaderList:didUpdateNotificationStateFor(): %s", log: OSLog.libLog, type: .info, characteristic.uuid.uuidString)
        #endif
        self._slotStatus = 0x00
        self._slotError = 0x00
        if error != nil {
            noop()
            if self.isSemaphoreLocked && self.machineState == .discoveredDeviceWithSuccess && characteristic.uuid == self.CCID_PC_To_RDR_Characteristic_UUID {
                self.unlockSemaphore()
            }
            generateErrorAfterReading(characteristic: characteristic, errorReceived: error)
            return
        }
        
        if characteristic.uuid == self.CCID_Status_Characteristic?.uuid {
            logDataReceivedFromCharacteristic(characteristic)
            if machineState == .discoveredDeviceWithSuccess {
                refreshSlotsFromCcidStatus(characteristic: characteristic)
            }
        }
    }
    
    // After writing on a characteristic
    /// :nodoc:
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        #if DEBUG
        os_log("SCardReaderList:didWriteValueFor() Characteristic ID: %s", log: OSLog.libLog, type: .info, characteristic.uuid.uuidString)
        #endif
        if error != nil {
            if self.isSemaphoreLocked && self.machineState == .discoveredDeviceWithSuccess && characteristic.uuid == self.CCID_PC_To_RDR_Characteristic_UUID {
                self.unlockSemaphore()
            }
            let _error = generateError(code: error!._code, message: error!.localizedDescription, trigger: false)
            switch lastCommand {
            case .control:
                callOnControlDidResponseWithError(_error)
            case .cardConnect:
                callOnCardDidConnectWithError(_error)
            case .transmit:
                callOnCardDidTransmitWithError(_error)
            case .cardDisconnect:
                callOnCardDidDisconnectWithError(_error)
            case .readingBatteryLevel:
                getBatteryLevelCharacteristicValue(nil, _error)
            case .noCommand, .getStatus:
                ()
                break
            }
            return
        }
        #if DEBUG
        os_log("Write succeed", log: OSLog.libLog, type: .debug)
        #endif
        writeToPcToRdrCharacteristic()
    }
    
    /// :nodoc:
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        #if DEBUG
        os_log("SCardReaderList:centralManagerDidUpdateState()", log: OSLog.libLog, type: .info)
        #endif
        ()
    }
    
    /// :nodoc:
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        #if DEBUG
        os_log("SCardReaderList:didDisconnectPeripheral()", log: OSLog.libLog, type: .info)
        #endif
        isConnected = false
        isValid = false
        var _error: Error?
        if error != nil {
            _error = self.generateError(code: error!._code, message: error!.localizedDescription, trigger: false)
        }
        
        if machineState != .isDisconnecting && machineState != .isUnSubsribingToNotifications {
            self.delegate?.onReaderListDidClose(readers: self, error: _error)
        }
        
        if self.isSemaphoreLocked {
            self.unlockSemaphore()
        }
        machineState = .isDisconnected
        noop()
    }
    
    
    // **************************************************************************************
    // **************************************************************************************
    // * Public callable methods (or methods publicly callable by other objects of the lib) *
    // **************************************************************************************
    // **************************************************************************************
    
    /**
     Send a direct command to the device
     
     - Parameter command: The command to send to the reader
     - Returns: Nothing, answer is available in the `onControlDidResponse()` callback
     */
    public func control(command: [UInt8]) {
        #if DEBUG
        os_log("SCardReaderList:control()", log: OSLog.libLog, type: .info)
        #endif
        if !canRequestCommandToDevice() {
            let error = generateError(code: .busy, message: "Another command is running or the reader is in low power mode", trigger: false)
            self.delegate?.onControlDidResponse(readers: self, response: nil, error: error)
            return
        }
        lastCommand = .control
        isWaitingAnswer = true
        self.CCID_PC_To_RDR(command: SCard_CCID_PC_To_RDR.PC_To_RDR_Escape, slotNumber: 0, payload: command)
    }
    
    /**
     Close connection with the product
     
     - Parameter keepBleActive: if true then the Bluetooth connection remains active, when false the Bluetooth connection is also closed
     */
    public func close(keepBleActive: Bool = false) {
        #if DEBUG
        os_log("SCardReaderList:close()", log: OSLog.libLog, type: .info)
        #endif
        noop()
        machineState = .isDisconnecting
        unsubscribeCharacteristics()
        if !keepBleActive {
            self.centralManager.cancelPeripheralConnection(self.device!)
        }
        self.delegate?.onReaderListDidClose(readers: self, error: nil)
    }
    
    private static func logLibraryVersion() {
        #if DEBUG
        os_log("LIBRARY INFORMATION", log: OSLog.libLog, type: .debug)
        os_log("libraryName: %s", log: OSLog.libLog, type: .debug, libraryName)
        os_log("LibrarySpecial: %s", log: OSLog.libLog, type: .debug, LibrarySpecial)
        os_log("libraryDebug: %s", log: OSLog.libLog, type: .debug, libraryDebug.description)
        os_log("libraryVersion: %s", log: OSLog.libLog, type: .debug, libraryVersion)
        os_log("libraryVersionMajor: %s", log: OSLog.libLog, type: .debug, libraryVersionMajor)
        os_log("libraryVersionMinor: %s", log: OSLog.libLog, type: .debug, libraryVersionMinor)
        os_log("LibraryVersionBuild: %s", log: OSLog.libLog, type: .debug, LibraryVersionBuild)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let compileDateFormated = dateFormatter.string(from: SCardReaderList.LibrarycompileDate)
        let buildDateFormated = dateFormatter.string(from: SCardReaderList.LibraryBuildDate)
        os_log("LibrarycompileDate: %s", log: OSLog.libLog, type: .debug, compileDateFormated)
        os_log("LibraryBuildDate: %s", log: OSLog.libLog, type: .debug, buildDateFormated)
        #endif
    }
    
    /**
     Request for the creation of a PC/SC product **over BLE**
     
     - Parameter peripheral: The peripheral the application is connected to
     - Parameter centralManager: The system Central Manager (must be a singleton)
     - Parameter delegate: "pointer" to the class that implements the callbacks (usually "self")
     - Parameter secureConnectionParameters: Object of type `SecureConnectionParameters` used to pass secure communication parameters (optional)
     - Returns: As the code is asynchronous, the onReaderListDidCreate() callback of the delegate will be called in case of success or failure (i.e you need to verify the error parameter)
     - SeeAlso: `getAllAdvertisingServices()`
     - Remark: The instanciation of the CBCentralManager, the scan of BLE peripherals and the connection to the device must be done by the library's client
     */
    public static func create(peripheral: CBPeripheral, centralManager: CBCentralManager, delegate: SCardReaderListDelegate, secureConnectionParameters: SecureConnectionParameters? = nil)  {
        #if DEBUG
        os_log("SCardReaderList:create()", log: OSLog.libLog, type: .info)
        #endif
        logLibraryVersion()
        self.instance = SCardReaderList(device: peripheral, centralManager: centralManager, delegate: delegate, secureConnectionParameters: secureConnectionParameters)
        self.instance!.launchServicesDiscovery()
    }
    
    /// Get the list of services UUID to filter scan
    ///
    /// - Returns: array of services UUIDs
    public static func getAllAdvertisingServices() -> [CBUUID] {
        #if DEBUG
        os_log("SCardReaderList:getAllAdvertisingServices()", log: OSLog.libLog, type: .info)
        #endif
        var advertisingServices: [CBUUID] = []
        SCardReaderList.getAdvertisingServicesFromList(deviceServices: DevicesServices.getD600Services(), advertisingServices: &advertisingServices)
        SCardReaderList.getAdvertisingServicesFromList(deviceServices: DevicesServices.getPuckUnbondedServices(), advertisingServices: &advertisingServices)
        SCardReaderList.getAdvertisingServicesFromList(deviceServices: DevicesServices.getPuckBondedServices(), advertisingServices: &advertisingServices)
        return advertisingServices;
    }
    
    /// Get the last error code
    ///
    /// - Returns: Int
    public func lastError() -> Int {
        return self._lastError
    }
    
    /// returns the last error message
    ///
    /// - Returns: a string describing the problem, can be a message from the system or a message specific to the SpringCard library
    public func lastErrorMessage() -> String {
        return self._lastErrorMessage
    }
    
    /// Returns the connection status
    ///
    /// - Returns: true if there is a connection to a BLE device
    public func connected() -> Bool {
        return self.isConnected
    }
    
    /// Is the connection valid?
    ///
    /// - Returns: Boolean
    public func valid() -> Bool {
        #if DEBUG
        os_log("SCardReaderList:valid()", log: OSLog.libLog, type: .info)
        #endif
        return self.isValid
    }
    
    /**
     Get a Reader objet from a slot's name
     
     - Parameter slot: name of the slot from the `slots` property
     - Returns: a `Reader` object or nil if the slot's name is unknown
     */
    public func getReader(slot: String) -> SCardReader? {
        #if DEBUG
        os_log("SCardReaderList:getReader()", log: OSLog.libLog, type: .info)
        os_log("slot: %s", log: OSLog.libLog, type: .debug, slot)
        #endif
        if machineState != .discoveredDeviceWithSuccess {
            return nil
        }
        if slot.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            return nil
        }
        for reader in self.readers {
            if reader._slotName.trimmingCharacters(in: .whitespacesAndNewlines) == slot.trimmingCharacters(in: .whitespacesAndNewlines) {
                return reader
            }
        }
        setLastError(code: SCardErrorCode.noSuchSlot.rawValue, message: "Invalid slot name")
        return nil
    }
    
    /**
     Get a Reader object from a slot's index
     
     - Parameter slot: index (0 based) of the slot from the `slots` property
     - Returns: a `Reader` object or nil if the index is out of bounds
     */
    public func getReader(slot: Int) -> SCardReader? {
        #if DEBUG
        os_log("SCardReaderList:getReader()", log: OSLog.libLog, type: .info)
        os_log("slot: %d", log: OSLog.libLog, type: .debug, slot)
        #endif
        if machineState != .discoveredDeviceWithSuccess {
            setLastError(code: SCardErrorCode.noSuchSlot.rawValue, message: "Invalid slot index")
            return nil
        }
        if (slot < 0 || slot >= self.slotCount) || self.slotCount == 0  {
            return nil
        }
        return self.readers[slot]
    }
    
    // Equivalent of ScardTransmit()
    internal func transmit(channel: SCardChannel, command: [UInt8]) {
        #if DEBUG
        os_log("SCardReaderList:transmit().", log: OSLog.libLog, type: .info)
        #endif
        if !canRequestCommandToDevice() {
            let error = generateError(code: .busy, message: "Another command is running or the reader is in low power mode", trigger: false)
            self.delegate?.onTransmitDidResponse(channel: channel, response: nil, error: error)
            return
        }
        
        let slotIndex = channel.getSlotIndex()
        
        if !channel.parent.cardPresent {
            let error = generateError(code: .cardRemoved, message: "Can't call transmit() because card was removed", trigger: false)
            self.delegate?.onTransmitDidResponse(channel: channel, response: nil, error: error)
            return
        }
        if !channel.parent.cardPowered || channel.isUnpowered {
            let error = generateError(code: .cardPoweredDown, message: "Can't call transmit() because card is powered down", trigger: false)
            self.delegate?.onTransmitDidResponse(channel: channel, response: nil, error: error)
            return
        }
        
        lastCommand = .transmit
        isWaitingAnswer = true
        isUsingSlotNumber = slotIndex
        self.CCID_PC_To_RDR(command: SCard_CCID_PC_To_RDR.PC_To_RDR_XfrBlock, slotNumber: slotIndex, payload: command)
    }
    
    // Equivalent of ScardDisconnect()
    internal func cardDisconnect(channel: SCardChannel) {
        #if DEBUG
        os_log("SCardReaderList:cardDisconnect()", log: OSLog.libLog, type: .info)
        #endif
        let slotIndex = channel.getSlotIndex()
        
        if lastCommand == .cardDisconnect {
            return
        }
        
        if !canRequestCommandToDevice() {
            let error = generateError(code: .busy, message: "Another command is running or the reader is in low power mode", trigger: false)
            self.delegate?.onCardDidDisconnect(channel: nil, error: error)
            return
        }
        
        if !isSlotIndexValid(slotIndex) {
            let error = generateError(code: .invalidParameter, message: "Slot number is out of bounds", trigger: false)
            self.delegate?.onCardDidDisconnect(channel: nil, error: error)
            return
        }
        
        if channel.isUnpowered {
            self.delegate?.onCardDidDisconnect(channel: channel, error: nil)
            return
        }
        
        lastCommand = .cardDisconnect
        isWaitingAnswer = true
        isUsingSlotNumber = slotIndex
        self.CCID_PC_To_RDR(command: SCard_CCID_PC_To_RDR.PC_To_RDR_IccPowerOff, slotNumber: slotIndex, payload: nil)
    }
    
    // Equivalent of the ScardConnect()
    internal func cardConnect(reader: SCardReader) {
        #if DEBUG
        os_log("SCardReaderList:cardConnect()", log: OSLog.libLog, type: .info)
        #endif
        let slotIndex = reader._slotIndex
        let cardPresent = reader.cardPresent
        
        #if DEBUG
        os_log("Slot index: %d, cardPresent: %s", log: OSLog.libLog, type: .debug, slotIndex, String(cardPresent))
        #endif
        
        if self.lastCommand == .cardConnect {
            #if DEBUG
            os_log("Nothing was done we are already connecting to the card", log: OSLog.libLog, type: .debug)
            #endif
            return
        }
        
        if !cardPresent {
            let error = generateError(code: .cardAbsent, message: "There's no card in the requested slot", trigger: false)
            self.delegate?.onCardDidConnect(channel: nil, error: error)
            return
        }
        if !isSlotIndexValid(slotIndex) {
            let error = generateError(code: .invalidParameter, message: "Slot number is out of bounds", trigger: false)
            self.delegate?.onCardDidConnect(channel: nil, error: error)
            return
        }
        
        if reader.cardPresent && reader.cardPowered {
            self.delegate?.onCardDidConnect(channel: reader.channel, error: nil)
            return
        }
        
        lastCommand = .cardConnect
        isWaitingAnswer = true
        isUsingSlotNumber = slotIndex
        self.connectToSlot(slotIndex)
    }
    
    internal func cardReconnect(channel: SCardChannel) {
        #if DEBUG
        os_log("SCardReaderList:cardReconnect()", log: OSLog.libLog, type: .info)
        #endif
        self.cardConnect(reader: channel.parent)
    }
    
    /**
     Wake-up the reader, if it is in low power mode.
     
     - SeeAlso: `onReaderListState()`
     */
    public func wakeUp() {
        #if DEBUG
        os_log("SCardReaderList:wakeUp()", log: OSLog.libLog, type: .info)
        #endif
        if !self.isInLowPowerMode {
            #if DEBUG
            os_log("Device is not in low power mode", log: OSLog.libLog, type: .debug)
            #endif
            return
        }
        if !canRequestCommandToDevice(false) {
            #if DEBUG
            os_log("It's actually not possible to request a command to the device", log: OSLog.libLog, type: .debug)
            #endif
            return
        }
        guard let CCID_Status_Characteristic = self.CCID_Status_Characteristic else {
            let error = self.generateError(code: SCardErrorCode.missingCharacteristic, message: "The CCID_Status characteristic is missing", trigger: false)
            self.delegate?.onReaderStatus(reader: nil, present: nil, powered: nil, error: error)
            return
        }
        self.device.setNotifyValue(true, for: CCID_Status_Characteristic)
    }
    
    /**
     Ask the device to enter full power-down mode
     
     - Remark: Not all hardware support a full power-down mode. For devices without such capabilities, this instruction is equivalent to a warm reset.
     */
    public func shutdown() {
        #if DEBUG
        os_log("SCardReaderList:shutdown()", log: OSLog.libLog, type: .info)
        #endif
        self.control(command: shutdownCommand)
    }
    
    private func callOnPowerInfo(_ powerState: Int?, _ batteryLevel: Int?, _ error: Error?) {
        #if DEBUG
        os_log("SCardReaderList:callOnPowerInfo()", log: OSLog.libLog, type: .info)
        #endif
        self.delegate?.onPowerInfo(powerState: powerState, batteryLevel: batteryLevel, error: error)
    }
    
    private func generateBatteryLevelError(_ error: Error) {
        #if DEBUG
        os_log("SCardReaderList:generateBatteryLevelError()", log: OSLog.libLog, type: .info)
        #endif
        noop()
        self.commonCharacteristicIndex = 0
        callOnPowerInfo(nil, nil, error)
    }
    
    private func getBatteryLevelCharacteristicValue(_ characteristic: CBCharacteristic? = nil, _ error: Error? = nil) {
        #if DEBUG
        os_log("SCardReaderList:getBatteryLevelCharacteristicValue()", log: OSLog.libLog, type: .info)
        #endif
        if error != nil {
            generateBatteryLevelError(error!)
            return
        }
        if characteristic != nil {
            guard let value = characteristic?.value else {
                let error = generateError(code: SCardErrorCode.invalidCharacteristicSetting, message: "Characteristic value is nil", trigger: false)
                generateBatteryLevelError(error)
                return
            }
            let bytes = [Byte](value)
            if (bytes.isEmpty) {
                let error = generateError(code: SCardErrorCode.invalidCharacteristicSetting, message: "Characteristic value is empty", trigger: false)
                generateBatteryLevelError(error)
                return
            }
            switch characteristic?.uuid {
            case CBUUID(string: "2A19"):
                self.batteryLevel = SCUtilities.byteToInt(characteristic!)
            case CBUUID(string: "2A1A"):
                self.powerState = SCUtilities.byteToInt(characteristic!)
            default:
                ()
            }
            commonCharacteristicIndex += 1
            if commonCharacteristicIndex >= self.batteryLevelCharacteristics.count {
                noop()
                commonCharacteristicIndex = 0
                callOnPowerInfo(self.powerState, self.batteryLevel, nil)
                return
            }
        }
        readCharacteristicValue(characteristic: batteryLevelCharacteristics[commonCharacteristicIndex])
    }
    
    /**
     Read device power state & battery level
     
     - Returns: Nothing, answer is available in the `onPowerInfo()` callback
     */
    public func getPowerInfo() {
        #if DEBUG
        os_log("SCardReaderList:getPowerInfo()", log: OSLog.libLog, type: .info)
        #endif
        if !canRequestCommandToDevice() {
            let error = generateError(code: .busy, message: "Another command is running or the reader is in low power mode", trigger: false)
            callOnPowerInfo(nil, nil, error)
            return
        }
        
        if self.batteryLevelCharacteristics.isEmpty {
            let error = generateError(code: .missingCharacteristic, message: "Battery level characteristics can't be found", trigger: false)
            callOnPowerInfo(nil, nil, error)
            return
        }
        
        lastCommand = .readingBatteryLevel
        self.isWaitingAnswer = true
        self.commonCharacteristicIndex = 0
        getBatteryLevelCharacteristicValue()
    }
}
