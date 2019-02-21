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
    /// 0 = running on battery, 1 = external power supply present
    public var powerStatus = -1	// TODO
    // ******************************************************
    
    // "Meta" properties ************************************
    public static let libraryName = "PC/SC-Like over BLE Library"
    public static let LibrarySpecial = ""
    public static let libraryDebug = 1
    public static let libraryVersion = "MM.mm-bb-gXXXXX"
    public static let libraryVersionMajor = "MM"
    public static let libraryVersionMinor = "mm"
    public static let LibraryVersionBuild = "bb"
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
    private var commonCharacteristicsValues: [CBCharacteristic: Data] = [:]
    private var commoncharacteristicsList: [CBCharacteristic] = []
    private var characteristicsSpecificsToDevice: [CBCharacteristic] = []

    private var CCID_Status_Characteristic: CBCharacteristic?
    private var CCID_PC_To_RDR_Characteristic: CBCharacteristic?
    private var CCID_RDR_To_PC_Characteristic: CBCharacteristic?
    
    private var CCID_Status_Characteristic_UUID: CBUUID?
    private var CCID_PC_To_RDR_Characteristic_UUID: CBUUID?
    private var CCID_RDR_To_PC_Characteristic_UUID: CBUUID?
	private var commonCharacteristicIndex = 0
    
    // Misc things *************************************
    private var delegate: SCardReaderListDelegate?
    private var readers:[SCardReader] = []
    
    private var sequenceNumber = 0
    private var slotNameCounter = 0
    static var instance: SCardReaderList?	// self instance
    
    // Vars related to current state
    private var machineState: MachineState = .noState
    private var isWaitingAnswer = false
    private var lastCommand: LastCommand = .noCommand
    private var isUsingSlotNumber: Int = -1
    
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
        os_log("SCardReaderList:init(device, centralManager, delegate)", log: OSLog.libLog, type: .info)
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
        os_log("SCardReaderList:isDeviceValid()", log: OSLog.libLog, type: .info)
        if !DevicesServices.hasDeviceAllServices(expectedServices: self.deviceSpecificServices, readServices: self.deviceServices, errorMessage: &_lastErrorMessage) {
            _ = self.generateError(code: SCardErrorCode.missingService, message: self._lastErrorMessage, trigger: true)
            return false
        }
        
        if self.CCID_Status_Characteristic == nil {
            _lastErrorMessage = "CCID Status characteristic was not found"
            _ = self.generateError(code: SCardErrorCode.missingCharacteristic, message: self._lastErrorMessage, trigger: true)
            return false
        }
        if self.CCID_PC_To_RDR_Characteristic == nil {
            _lastErrorMessage = "CCID PC_To_RDR characteristic was not found"
            _ = self.generateError(code: SCardErrorCode.missingCharacteristic, message: self._lastErrorMessage, trigger: true)
            return false
        }
        if self.CCID_RDR_To_PC_Characteristic == nil {
            _lastErrorMessage = "CCID CCID_RDR_To_PC characteristic was not found"
            _ = self.generateError(code: SCardErrorCode.missingCharacteristic, message: self._lastErrorMessage, trigger: true)
            return false
        }
        return true
    }
    
    private func getCCIDCharacteristicsUUIDs() {
        os_log("SCardReaderList:getCCIDCharacteristicsUUIDs()", log: OSLog.libLog, type: .info)
        self.CCID_Status_Characteristic_UUID = DevicesServices.getCharacteristicIdFromName(services: self.deviceSpecificServices, searchedCharacteristicName: "CCID_Status")
        self.CCID_PC_To_RDR_Characteristic_UUID = DevicesServices.getCharacteristicIdFromName(services: self.deviceSpecificServices, searchedCharacteristicName: "CCID_PC_To_RDR")
        self.CCID_RDR_To_PC_Characteristic_UUID = DevicesServices.getCharacteristicIdFromName(services: self.deviceSpecificServices, searchedCharacteristicName: "CCID_RDR_To_PC")
    }
    
    private func setLastError(code: Int, message: String) {
        self._lastError = code
        self._lastErrorMessage = message
    }
    
    // Launch services discovering
    private func launchServicesDiscovery() {
        os_log("SCardReaderList:launchServicesDiscovery()", log: OSLog.libLog, type: .info)
        self.getCCIDCharacteristicsUUIDs()
        self.device!.discoverServices(nil)
    }
    
    // set the private CBCharacteristics when they are read
    private func setCCIDCharacteristics(_ characteristic: CBCharacteristic) {
        os_log("SCardReaderList:setCCIDCharacteristics()", log: OSLog.libLog, type: .info)
        if characteristic.uuid == CCID_Status_Characteristic_UUID {
            self.CCID_Status_Characteristic = characteristic
        } else if characteristic.uuid == CCID_PC_To_RDR_Characteristic_UUID {
            self.CCID_PC_To_RDR_Characteristic = characteristic
        } else if characteristic.uuid == CCID_RDR_To_PC_Characteristic_UUID {
            self.CCID_RDR_To_PC_Characteristic = characteristic
        }
    }
    
    private func readCommonCharacteristics() {
        os_log("SCardReaderList:readCommonCharacteristics()", log: OSLog.libLog, type: .info)
        if self.commoncharacteristicsList.isEmpty {
            _ = self.generateError(code: SCardErrorCode.missingCharacteristic, message: "Missing comon characteristic(s)", trigger: true)
            return
        }
        if self.commonCharacteristicIndex >= self.commoncharacteristicsList.count {
            self.getSlotsCount()
            return
        }
        self.machineState = .isReadingCommonCharacteristicsValues
        os_log("Asking for reading chacacteristic ID:  %@", log: OSLog.libLog, type: .debug, self.commoncharacteristicsList[self.commonCharacteristicIndex].uuid.uuidString)
        self.readCharacteristicValue(characteristic: self.commoncharacteristicsList[self.commonCharacteristicIndex])
    }
    
    private func notifyToCharacteristics() {
        os_log("SCardReaderList:notifyToCharacteristics()", log: OSLog.libLog, type: .info)
        self.commonCharacteristicIndex = 0
        for characteristic in self.characteristicsSpecificsToDevice {
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)  {
                os_log("We are subsribing to characteristic: %@", log: OSLog.libLog, type: .debug, characteristic.uuid.uuidString)
                self.device.setNotifyValue(true, for: characteristic)
            }
        }
        readCommonCharacteristics()
    }
    
    // Ask for the reading of a characteristic value
    private func readCharacteristicValue(characteristic: CBCharacteristic) {
        os_log("SCardReaderList:readCharacteristicValue(): %@", log: OSLog.libLog, type: .info, characteristic.uuid.uuidString)
        self.device.readValue(for: characteristic)
    }
    
    private func createObjectProperties(_ characteristic: CBCharacteristic) {
        os_log("SCardReaderList:createObjectProperties()", log: OSLog.libLog, type: .info)
        switch(characteristic.uuid.uuidString) {
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
        default:
            os_log("unused common characteristic: %@", log: OSLog.libLog, type: .debug, characteristic.uuid.uuidString)
        }
    }
    
    // Create the "internal" Readers objects that can be used later
    private func createReaders(_ ccidStatus: SCCcidStatus) {
        os_log("SCardReaderList:createReaders()", log: OSLog.libLog, type: .info)
        if self.slotCount == 0 {
            return
        }
        
        var slotIndex = 0
        for slot in self.slots {
            let reader = SCardReader(parent: self, slotName: slot, slotIndex: slotIndex)
            reader.setNewState(state: ccidStatus.slots[slotIndex])
            self.readers.append(reader)
            slotIndex += 1
        }
        debugSlotsStatus()
    }
    
    private func setSlotsCount(_ characteristic: CBCharacteristic) {
        os_log("SCardReaderList:setSlotsCount()", log: OSLog.libLog, type: .info)
        self.slotCount = 0
        
        let temporaryCcidStatus = SCCcidStatus(characteristic: characteristic)
        if !temporaryCcidStatus.isValid {
            _ = self.generateError(code: temporaryCcidStatus.errorCode, message: temporaryCcidStatus.errorMessage, trigger: true)
            return
        }
        
        self.slotCount = temporaryCcidStatus.numberOfSlots
        os_log("Slots count: %@", log: OSLog.libLog, type: .info, String(self.slotCount))
        if self.slotCount == 0 {
            _ = self.generateError(code: SCardErrorCode.dummyDevice, message: "Slot count is equal to 0", trigger: true)
            return
        }
        self.slots = Array(repeating: "", count: self.slotCount)
        createReaders(temporaryCcidStatus)
        refreshSlotsFromCcidStatus(characteristic: characteristic)
        machineState = .isReadingSlotsName
        getSlotsName()
    }
    
    // Returns [0x58, 0x21, 0x00], [0x58, 0x21, 0x01] etc
    private func getSlotNameApdu(_ slotNumber: Int) -> [UInt8] {
        os_log("SCardReaderList:getSlotNameApdu()", log: OSLog.libLog, type: .info)
        var bytes: [UInt8] = getSlotsNameApdu
        let index = bytes.count - 1
        bytes[index] = UInt8(slotNumber)
        return bytes
    }
    
    private func connectToSlot(_ slotIndex: Int) {
        os_log("SCardReaderList:connectToSlot()", log: OSLog.libLog, type: .info)
        os_log("Slot Index: %@", log: OSLog.libLog, type: .debug, String(slotIndex))
        self.lastCommand = .cardConnect
        self.CCID_PC_To_RDR(command: SCard_CCID_PC_To_RDR.PC_To_RDR_IccPowerOn, slotNumber: slotIndex, payload: nil)
    }
    
    private func initiateMutualAuthentication() {
        os_log("SCardReaderList:initiateMutualAuthentication()", log: OSLog.libLog, type: .info)
        sequenceNumber = 0
        self.machineState = .initiateMutualAuthentication
        self.isWaitingAnswer = true
        
        guard let authCommand = self.readerListSecure?.getAuthenticationCommand() else {
            _ = self.generateError(code: SCardErrorCode.authenticationError, message: "Authentication was called but authenticate command returned nil", trigger: true)
            return
        }
        if authCommand.isEmpty {
            _ = self.generateError(code: SCardErrorCode.authenticationError, message: "Authentication was called but authenticate command is empty", trigger: true)
            return
        }
        self.CCID_PC_To_RDR(command: SCard_CCID_PC_To_RDR.PC_To_RDR_Escape, slotNumber: 0, payload: authCommand)
    }
    
    private func powerOnSlotsWithCard() {
        os_log("SCardReaderList:powerOnSlotsWithCard()", log: OSLog.libLog, type: .info)
        if isUsingSlotNumber >= self.slotCount {
            isUsingSlotNumber = 0
            debugSlotsStatus()
            if self.isSecureCommunication == false {
                happyEnd()
            } else {
                initiateMutualAuthentication()
            }
            return
        }
        if self.readers[isUsingSlotNumber].cardPresent && !self.readers[isUsingSlotNumber].cardPowered {
            os_log("Calling SCardConnect() on slot %@", log: OSLog.libLog, type: .debug, String(isUsingSlotNumber))
            connectToSlot(isUsingSlotNumber)
        } else {
            isUsingSlotNumber += 1
            powerOnSlotsWithCard()
            return
        }
    }
    
    private func debugSlotsStatus() {
        os_log("SCardReaderList:debugSlotsStatus()", log: OSLog.libLog, type: .info)
        for slotIndex in 0 ..< self.slotCount {
            os_log("Slot index:  %i", log: OSLog.libLog, type: .debug, readers[slotIndex]._slotIndex)
            os_log("Card Present: %s", log: OSLog.libLog, type: .debug, String(readers[slotIndex].cardPresent))
            os_log("Card Powered: %@", log: OSLog.libLog, type: .debug, String(readers[slotIndex].cardPowered))
            os_log("Slot name: %s", log: OSLog.libLog, type: .debug, readers[slotIndex]._slotName)
        }
    }
    
    private func getUnpoweredSlotsCount() -> Int {
        os_log("SCardReaderList:getUnpoweredSlotsCount()", log: OSLog.libLog, type: .info)
        debugSlotsStatus()
        var count = 0
        for slotIndex in 0 ..< self.slotCount {
            if self.readers[slotIndex].cardPresent && !self.readers[slotIndex].cardPowered {
                count += 1
            }
        }
        return count
    }
    
    private func getSlotsName() {
        os_log("SCardReaderList:getSlotsName()", log: OSLog.libLog, type: .info)
        if self.slotNameCounter >= self.slotCount {
            if self.isDeviceValid() {
                self.isValid = true
                machineState = .poweringSlots
                isUsingSlotNumber = 0
                if getUnpoweredSlotsCount() == 0 {
                    isUsingSlotNumber = self.slotCount + 1
                }
                powerOnSlotsWithCard()
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
        os_log("SCardReaderList:noop()", log: OSLog.libLog, type: .info)
        lastCommand = .noCommand
        isWaitingAnswer = false
    }
    
    private func generateErrorAfterReading(characteristic: CBCharacteristic, errorReceived: Error?) {
        os_log("SCardReaderList:generateErrorAfterReadingCharacteristic()", log: OSLog.libLog, type: .info)
        guard let error = errorReceived else {
            return
        }
        let errorDescription = error.localizedDescription
        let _error = self.generateError(code: error._code, message: errorDescription, trigger: false)
        
        if CommonServices.isCommonCharacteristic(commonServices: self.commonServices, characteristicId: characteristic.uuid) {
            self.delegate?.onReaderListDidCreate(readers: nil, error: _error)
            machineState  = .discoverFailed
            noop()
            return
        }
        
        if characteristic.uuid == self.CCID_Status_Characteristic?.uuid {
            if self.machineState != .discoveredDeviceWithSuccess {
                self.delegate?.onReaderListDidCreate(readers: nil, error: error)
            } else {
                delegate?.onReaderStatus(reader: nil, present: nil, powered: nil, error: error)
            }
        } else if characteristic.uuid == CCID_RDR_To_PC_Characteristic?.uuid {
            if self.machineState == .isReadingSlotsName {
                self.delegate?.onReaderListDidCreate(readers: nil, error: error)
            } else if self.machineState == .poweringSlots {
                powerOnSlotsWithCard()
            } else if self.machineState == .initiateMutualAuthentication {
        		self.delegate?.onReaderListDidCreate(readers: nil, error: error)
            } else if self.machineState == .authenticationStep1 {
                self.delegate?.onReaderListDidCreate(readers: nil, error: error)
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
                }
            }
        } else {
            delegate?.onReaderStatus(reader: nil, present: nil, powered: nil, error: _error)
        }
        noop()
        machineState = .isInError
        self.isValid = false
    }
    
    private func afterReading(_ characteristic: CBCharacteristic) {
        os_log("SCardReaderList:afterReadingCharacteristic()", log: OSLog.libLog, type: .info)
        logDataReceivedFromCharacteristic(characteristic)
        if CommonServices.isCommonCharacteristic(commonServices: self.commonServices, characteristicId: characteristic.uuid) {
            os_log("isReadingCommonCharacteristicsValues", log: OSLog.libLog, type: .debug)
            self.commonCharacteristicsValues[characteristic] = characteristic.value
            createObjectProperties(characteristic)
            self.commonCharacteristicIndex += 1
            self.readCommonCharacteristics()
            return
        }
        switch characteristic.uuid {
        case self.CCID_Status_Characteristic?.uuid:
            if self.machineState == .isReadingSlotCount {
                self.setSlotsCount(characteristic)
            } else if machineState == .discoveredDeviceWithSuccess {
                refreshSlotsFromCcidStatus(characteristic: characteristic)
            } else {
                os_log("This case shall not happen, machineState: %@", log: OSLog.libLog, type: .error, String(self.machineState.rawValue))
                _ = self.generateError(code: .otherError, message: "This case shall not happen, machineState: " + String(self.machineState.rawValue), trigger: true)
                return
            }
            
        case self.CCID_RDR_To_PC_Characteristic?.uuid:	// We got an answer
            if self.machineState == .isReadingSlotsName {
                os_log("We are getting an answer from the request of slots name", log: OSLog.libLog, type: .debug)
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
                case .noCommand, .getStatus:
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
        os_log("SCardReaderList:authStep2WithError()", log: OSLog.libLog, type: .info)
        noop()
        self.isUsingSlotNumber = -1
        triggerError(error)
    }
    
    private func authStep2(_ characteristic: CBCharacteristic) {
        os_log("SCardReaderList:authStep2()", log: OSLog.libLog, type: .info)
        noop()
        let response = SCCcidRdrToPc(characteristic: characteristic, readerListSecure: nil)
        if !response.isValid() {
            authStep2WithError(generateError(code: SCardErrorCode.authenticationError, message: "Response is invalid", trigger: false))
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
                happyEnd()
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
        os_log("SCardReaderList:happyEnd()", log: OSLog.libLog, type: .info)
        machineState = .discoveredDeviceWithSuccess
        self.delegate?.onReaderListDidCreate(readers: self, error: nil)
    }
    
    // ****************************************************************************
    // * First step of the authentication, the reader returned (may be) something *
    // ****************************************************************************
    private func authStep1WithError(_ error: NSError) {
        os_log("SCardReaderList:authStep1WithError()", log: OSLog.libLog, type: .info)
        noop()
        self.isUsingSlotNumber = -1
        self.triggerError(error)
    }
    
    private func authStep1(_ characteristic: CBCharacteristic) {
        os_log("SCardReaderList:authStep1()", log: OSLog.libLog, type: .info)
        noop()
        let response = SCCcidRdrToPc(characteristic: characteristic, readerListSecure: nil)
        if !response.isValid() {
            authStep1WithError(generateError(code: SCardErrorCode.authenticationError, message: "Response is invalid", trigger: false))
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
            os_log("authentication went well, we are moving to step2", log: OSLog.libLog, type: .debug)
            self.CCID_PC_To_RDR(command: .PC_To_RDR_Escape, slotNumber: 0, payload: answserToSend)
        } else  { // fail
            authStep1WithError(generateError(code: .authenticationError, message: "Response code is not RDR_To_PC_DataBlock", trigger: false))
        }
    }
    
    // *****************************************
    // * Used after a channel.cardDisconnect() *
    // *****************************************
    private func callOnCardDidDisconnectWithError(_ error: Error) {
        os_log("SCardReaderList:callOnCardDidDisconnectWithError()", log: OSLog.libLog, type: .info)
        noop()
        let reader = self.readers[isUsingSlotNumber]
        let channel = reader.channel
        self.delegate?.onCardDidDisconnect(channel: channel, error: error)
        self.isUsingSlotNumber = -1
    }
    
    private func callOnCardDidDisconnect(_ characteristic: CBCharacteristic) {
        os_log("SCardReaderList:callOnCardDidDisconnect()", log: OSLog.libLog, type: .info)
        noop()
        let response = SCCcidRdrToPc(characteristic: characteristic, readerListSecure: self.machineState == .discoveredDeviceWithSuccess ? self.readerListSecure : nil)
        if !response.isValid() {
            callOnCardDidDisconnectWithError(generateError(code: response.errorCode, message: response.errorMessage, trigger: false))
            return
        }
        
        let payload = response.getAnswer()
        if payload == nil {
            callOnCardDidDisconnectWithError(generateError(code: .otherError, message: "Response payload to SCardDisconnect() is nil", trigger: false))
            return
        }
        
        if response.header.responseCode == .RDR_To_PC_SlotStatus { // succeed
            let reader = self.readers[isUsingSlotNumber]
            let channel = reader.channel
            channel?.reinitAtr()
            self.delegate?.onCardDidDisconnect(channel: channel, error: nil)
        } else if response.header.responseCode == .RDR_To_PC_SlotStatus { // fail
            callOnCardDidDisconnectWithError(generateError(code: .cardAbsent, message: "SCardDisconnect() was called but the answer is not RDR_To_PC_SlotStatus", trigger: false))
        }
    }
    
    // ***********************************
    // * Used after a channel.transmit() *
    // ***********************************
    private func callOnCardDidTransmitWithError(_ error: Error) {
        os_log("SCardReaderList:callOnCardDidTransmitWithError()", log: OSLog.libLog, type: .info)
        noop()
        let reader = self.readers[isUsingSlotNumber]
        let channel = reader.channel
        self.delegate?.onTransmitDidResponse(channel: channel, response: nil, error: error)
        self.isUsingSlotNumber = -1
    }
    
    private func callOnCardDidTransmit(_ characteristic: CBCharacteristic) {
        os_log("SCardReaderList:callOnCardDidTransmit()", log: OSLog.libLog, type: .info)
        var response = SCCcidRdrToPc(characteristic: characteristic, readerListSecure: self.machineState == .discoveredDeviceWithSuccess ? self.readerListSecure : nil)
        
        if isWaitingAnswerToFinish {
            previousResponse?.addToPayload(characteristic)
            if (previousResponse?.isAnswerComplete())! {
                response = previousResponse!
                isWaitingAnswerToFinish = false
            } else {
                return
            }
        }
        
        if !response.isValid() {
            callOnCardDidTransmitWithError(generateError(code: response.errorCode, message: response.errorMessage, trigger: false))
            return
        }
        
        let payload = response.getAnswer()
        if payload == nil {
            callOnCardDidTransmitWithError(generateError(code: .otherError, message: "Response payload to channel.transmit() is nil", trigger: false))
            return
        }
        
        if response.header.responseCode == .RDR_To_PC_DataBlock { // succeed
            if response.isLongAnswer() {
                self.isWaitingAnswerToFinish = true
                self.previousResponse = response
                return
            }
            let slotStatus = response.header.slotStatus
            let slotError = response.header.slotError
            
            if (slotStatus == SCARD.s_success.rawValue && slotError == SCARD.s_success.rawValue)  {	// succeed
                noop()
                let rapdu = response.getAnswer()
                let reader = self.readers[isUsingSlotNumber]
                let channel = reader.channel
                self.delegate?.onTransmitDidResponse(channel: channel, response: rapdu, error: nil)
            } else { // error
                let slotStatusAsString = (slotStatus != nil) ? String(Int(slotStatus!)) : ""
                let slotErrorAsString =  (slotError != nil) ? String(Int(slotError!)) : ""
                callOnCardDidTransmitWithError(generateError(code: .cardCommunicationError, message: "channel.transmit() was called but slot status and/or slot error are not equals to zero. Slot error: " + slotErrorAsString + ", slot status: " + slotStatusAsString, trigger: false))
            }
        } else if response.header.responseCode == .RDR_To_PC_SlotStatus { // fail
            callOnCardDidTransmitWithError(generateError(code: .cardAbsent, message: "channel.transmit() was called but the answer is RDR_To_PC_SlotStatus", trigger: false))
        }
    }
    
    // *************************************
    // * Used after a reader.cardConnect() *
    // *************************************
    private func callOnCardDidConnectWithError(_ error: Error) {
        os_log("SCardReaderList:callOnCardDidConnectWithError()", log: OSLog.libLog, type: .info)
        if machineState != .poweringSlots {
            self.delegate?.onCardDidConnect(channel: nil, error: error)
        }
        self.isUsingSlotNumber = -1
        noop()
    }
    
    private func callOnCardDidConnect(_ characteristic: CBCharacteristic) {
        os_log("SCardReaderList:callOnCardDidConnect()", log: OSLog.libLog, type: .info)
        noop()
        let response = SCCcidRdrToPc(characteristic: characteristic, readerListSecure: self.machineState == .discoveredDeviceWithSuccess ? self.readerListSecure : nil)
        if !response.isValid() {
            callOnCardDidConnectWithError(generateError(code: response.errorCode, message: response.errorMessage, trigger: false))
            return
        }
        
        let payload = response.getAnswer()
        if payload == nil {
            callOnCardDidConnectWithError(generateError(code: .otherError, message: "Response payload to SCardConnect() is nil", trigger: false))
            return
        }
        
        if response.header.responseCode == .RDR_To_PC_DataBlock { // succeed
            let slotStatus = response.header.slotStatus
            let slotError = response.header.slotError
            
            if (slotStatus == SCARD.s_success.rawValue && slotError == SCARD.s_success.rawValue)  {	// succeed
                let atr = response.getAnswer()
                if atr != nil {
                    let reader = self.readers[isUsingSlotNumber]
                    let channel = SCardChannel(parent: reader, atr: atr!)
                    reader.setNewChannel(channel)
                    reader.setCardPowered()
                    if machineState != .poweringSlots {
                        self.delegate?.onCardDidConnect(channel: channel, error: nil)
                    }
                } else {
                    callOnCardDidConnectWithError(generateError(code: .cardAbsent, message: "SCardConnect() was called but we did not received the card's ATR", trigger: false))
                }
            } else {
                let slotStatusAsString = (slotStatus != nil) ? String(Int(slotStatus!)) : ""
                let slotErrorAsString =  (slotError != nil) ? String(Int(slotError!)) : ""
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
        os_log("SCardReaderList:callOnControlDidResponseWithError()", log: OSLog.libLog, type: .info)
        noop()
        self.delegate?.onControlDidResponse(readers: self, response: nil, error: error)
    }
    
    private func callOnControlDidResponse(_ characteristic: CBCharacteristic) {
        os_log("SCardReaderList:callOnControlDidResponse()", log: OSLog.libLog, type: .info)
        var response = SCCcidRdrToPc(characteristic: characteristic, readerListSecure: self.machineState == .discoveredDeviceWithSuccess ? self.readerListSecure : nil)
        
        if isWaitingAnswerToFinish {
            previousResponse?.addToPayload(characteristic)
            if (previousResponse?.isAnswerComplete())! {
                response = previousResponse!
                isWaitingAnswerToFinish = false
            } else {
                return
            }
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
        if response.isLongAnswer() {
            self.isWaitingAnswerToFinish = true
            self.previousResponse = response
            return
        }
        self.delegate?.onControlDidResponse(readers: self, response: payload, error: nil)
        noop()
    }
    
    private func setSlotNameFrom(characteristic: CBCharacteristic) {
        os_log("SCardReaderList:setSlotNameFrom()", log: OSLog.libLog, type: .info)
        let response = SCCcidRdrToPc(characteristic: characteristic, readerListSecure: self.machineState == .discoveredDeviceWithSuccess ? self.readerListSecure : nil)
        if !response.isValid() {
            _ = generateError(code: response.errorCode, message: response.errorMessage, trigger: true)
            return
        }
        if response.header.responseCode != CCID_RDR_To_PC_Answer_Codes.RDR_To_PC_Escape {
            _ = generateError(code: SCardErrorCode.invalidCharacteristicSetting, message: "Invalid response code when getting slots names", trigger: true)
            return
        }
        let name = SCUtilities.getSlotNameFromBytes(response.getAnswer()!)
        if name != nil {
            self.slots[slotNameCounter] = name!
            self.readers[slotNameCounter]._slotName = name!
        } else {
            _ = generateError(code: SCardErrorCode.invalidCharacteristicSetting, message: "Invalid response code when getting slots names", trigger: true)
        }
    }
    
    private func unsubscribeCharacteristics() {
        os_log("SCardReaderList:unsubscribeCharacteristics()", log: OSLog.libLog, type: .info)
        if self.characteristicsSpecificsToDevice.isEmpty {
            os_log("Nothing to unsubscribe", log: OSLog.libLog, type: .debug)
            return
        }
        self.machineState = .isUnSubsribingToNotifications
        for characteristic in self.characteristicsSpecificsToDevice {
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)  {
                os_log("Unsubscribe to characteristic %@", log: OSLog.libLog, type: .debug, characteristic.uuid.uuidString)
                self.device!.setNotifyValue(false, for: characteristic)
            }
        }
    }
    
    private func refreshSlotsFromCcidStatus(characteristic: CBCharacteristic) {
        os_log("SCardReaderList:refreshSlotsFromCcidStatus()", log: OSLog.libLog, type: .info)
        self.ccidStatus = SCCcidStatus(characteristic: characteristic)
        if ccidStatus.isValid {
            for slotIndex in 0 ..< ccidStatus.numberOfSlots {
                if ccidStatus.slots[slotIndex].slotStatus == .cardInserted || ccidStatus.slots[slotIndex].slotStatus == .cardRemoved {
                    self.readers[slotIndex].setNewState(state: ccidStatus.slots[slotIndex])
                    
                    if ccidStatus.slots[slotIndex].slotStatus == .cardRemoved {
                        if machineState != .poweringSlots {
                            callOnCardDidDisconnect(slotIndex)
                        }
                    }
                    
                    if machineState != .poweringSlots {
                        if ccidStatus.slots[slotIndex].slotStatus == .cardInserted {
                            self.lastCommand = .cardConnect
                        }
                        callOnReaderStatus(slotIndex)
                    }
                    if ccidStatus.slots[slotIndex].slotStatus == .cardInserted {
                        connectToSlot(slotIndex)
                    }
                }
            }
        }
    }
    
    private func callOnCardDidDisconnect(_ slotIndex: Int) {
        os_log("SCardReaderList:callOnCardDidDisconnect()", log: OSLog.libLog, type: .info)
        if machineState != .discoveredDeviceWithSuccess {
            return
        }
        let channel = self.readers[slotIndex].channel
        self.delegate?.onCardDidDisconnect(channel: channel, error: nil)
    }
    
    private func callOnReaderStatus(_ slotIndex: Int) {
        os_log("SCardReaderList:callOnReaderStatus()", log: OSLog.libLog, type: .info)
        if machineState != .discoveredDeviceWithSuccess {
            return
        }
        let reader = self.readers[slotIndex]
        self.delegate?.onReaderStatus(reader: reader, present: reader.cardPresent, powered: reader.cardPowered, error: nil)
    }
    
    private func logDataSent(_ bytes: [UInt8]) {
        os_log("SCardReaderList:logDataSent()", log: OSLog.libLog, type: .info)
        if bytes.isEmpty {
            os_log("There's no bytes sent", log: OSLog.libLog, type: .debug)
        }
        os_log("Bytes sent: %@", log: OSLog.libLog, type: .debug, bytes.hexa)
    }
    
    private func logDataReceivedFromCharacteristic(_ characteristic: CBCharacteristic) {
        os_log("SCardReaderList:logDataReceivedFromCharacteristic() from characteristic: %@", log: OSLog.libLog, type: .debug, characteristic.uuid.uuidString)
        guard let characteristicData = characteristic.value else {
            os_log("characteristic value is nil", log: OSLog.libLog, type: .debug)
            return
        }
        let bytes = [UInt8](characteristicData)
        if bytes.isEmpty {
            os_log("No bytes in characteristic", log: OSLog.libLog, type: .debug)
            return
        }
        os_log("Bytes received: %@", log: OSLog.libLog, type: .debug, bytes.hexa)
    }
    
    private func CCID_PC_To_RDR(command: SCard_CCID_PC_To_RDR, slotNumber: Int, payload: [UInt8]?) {
        os_log("SCardReaderList:CCID_PC_To_RDR()", log: OSLog.libLog, type: .info)
        let command = SCCcidPcToRdr(command: command, slotNumber: slotNumber, sequenceNumber: sequenceNumber, payload: payload, readerListSecure: self.machineState == .discoveredDeviceWithSuccess ? self.readerListSecure : nil)
        guard let sentData = command.getCommand() else {
            os_log("There's nothing to send", log: OSLog.libLog, type: .info)
            return
        }
        self.currentWriteIndex = 0
        if sentData.isEmpty {
            return
        }
        self.payloadToSend = sentData
        writeToPcToRdrCharacteristic()
        sequenceNumber += 1
        if sequenceNumber >= 255 {
            sequenceNumber = 0
        }
    }
    
    private func writeToPcToRdrCharacteristic() {
        os_log("SCardReaderList:writeToPcToRdrCharacteristic()", log: OSLog.libLog, type: .info)
        let startingIndex = self.currentWriteIndex
        if startingIndex >= payloadToSend.count {
            os_log("payload was fully sent, nothing more to come, returning", log: OSLog.libLog, type: .debug)
            return
        }
        var endingIndex = startingIndex + self.writeMaxLength
        if endingIndex > payloadToSend.count {
            endingIndex = payloadToSend.count
        }
        let bytesToSend = Array(payloadToSend[startingIndex ..< endingIndex])
        logDataSent(bytesToSend)
        currentWriteIndex += writeMaxLength
        
        let data = Data(bytes: bytesToSend, count: bytesToSend.count)
        self.device.writeValue(data, for: self.CCID_PC_To_RDR_Characteristic!, type: CBCharacteristicWriteType.withResponse)
    }
    
    // Must be override in each child class
    internal func isBoundedDevice() -> Bool	{
        os_log("SCardReaderList:isBoundedDevice()", log: OSLog.libLog, type: .info)
        return true;
    }
    
    private static func getAdvertisingServicesFromList(deviceServices: [String: (serviceDescription: String, isAdvertisingService: Bool, serviceCharacteristics: [String: String])], advertisingServices: inout [CBUUID]) {
        os_log("SCardReaderList:getAdvertisingServicesFromList()", log: OSLog.libLog, type: .info)
        for (serviceId, serviceDescription) in deviceServices {
            if serviceDescription.isAdvertisingService {
                advertisingServices.append(CBUUID(string: serviceId))
            }
        }
    }
    
    private static func isInDeviceAdvertisingServices(deviceServices: [String: (serviceDescription: String, isAdvertisingService: Bool, serviceCharacteristics: [String: String])], deviceAdvertisedServices: [CBUUID]) -> Bool {
        os_log("SCardReaderList:isInDeviceAdvertisingServices()", log: OSLog.libLog, type: .info)
        var advertisingServices: [CBUUID] = []
        SCardReaderList.getAdvertisingServicesFromList(deviceServices: deviceServices, advertisingServices: &advertisingServices)
        for deviceAdvertisedService in deviceAdvertisedServices {
            if advertisingServices.contains(deviceAdvertisedService) {
                return true
            }
        }
        return false
    }
    
    // Method used to set services specific to each device.
    /// To be implemented in each child class
    internal func setSpecificDeviceServices() {
        os_log("SCardReaderList:setSpecificDeviceServices()", log: OSLog.libLog, type: .info)
    }
    
    private func getSlotsCount() {
        os_log("SCardReaderList:getSlotsCount()", log: OSLog.libLog, type: .info)
        if self.CCID_Status_Characteristic_UUID == nil {
            _ = self.generateError(code: SCardErrorCode.missingCharacteristic, message: "The CCID_Status characteristic was not found", trigger: true)
            return
        }
        self.machineState = .isReadingSlotCount
        self.readCharacteristicValue(characteristic: self.CCID_Status_Characteristic!)
    }
    
    private func doGenerateError(code: Int, message: String, trigger: Bool) -> NSError {
        os_log("SCardReaderList:doGenerateError()", log: OSLog.libLog, type: .info)
        setLastError(code: code, message: message)
        self.isValid = false
        os_log("Error code: %d, Error message: %s", log: OSLog.libLog, type: .error, _lastError, message)
        let error = NSError(domain: Bundle.main.bundleIdentifier!, code: _lastError, userInfo: [NSLocalizedDescriptionKey : message])
        if trigger {
            self.triggerError(error)
        }
        return error
    }
    
    private func generateError(code: Int, message: String, trigger: Bool = true) -> NSError {
        return doGenerateError(code: code, message: message, trigger: trigger)
    }
    
    @discardableResult
    private func generateError(code: SCardErrorCode, message: String, trigger: Bool = true) -> NSError {
        return doGenerateError(code: code.rawValue, message: message, trigger: trigger)
    }
    
    private func triggerError(_ error: NSError) {
        self.delegate?.onReaderListDidCreate(readers: nil, error: error)
    }
    
    private func isSlotIndexValid(_ slotIndex: Int) -> Bool {
        return (slotIndex < 0 || slotIndex >= slotCount) ? false : true
    }
    
    private func canRequestCommandToDevice() -> Bool {
        os_log("SCardReaderList:canRequestCommandToDevice()", log: OSLog.libLog, type: .info)
        
        if machineState == .isReadingSlotsName {
            return true
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
        os_log("SCardReaderList:didDiscoverServices()", log: OSLog.libLog, type: .info)
        if error != nil {
            _ = self.generateError(code: error!._code, message: error.debugDescription, trigger: true)
        } else {
            self.deviceServices = peripheral.services!
            self.servicesCount = (peripheral.services?.count)!
            self.currentServiceIndex = 0
            for service in peripheral.services! {
                os_log("Service ID: %@, isPrimary: %@", log: OSLog.libLog, type: .debug, service.uuid.uuidString, service.isPrimary.description)
                os_log("Launching characteristics scan", log: OSLog.libLog, type: .debug)
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    // Characteristics of a specific service are discovered (or there is an error)
    /// :nodoc:
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        os_log("SCardReaderList:didDiscoverCharacteristicsFor()", log: OSLog.libLog, type: .info)
        os_log("Characteristics discovered for service %@", log: OSLog.libLog, type: .debug, service.uuid.uuidString)
        
        if error != nil {
            _ = self.generateError(code: error!._code, message: error.debugDescription, trigger: true)
        } else {
            if CommonServices.isCommonService(service.uuid) {
                os_log("We are on a common service", log: OSLog.libLog, type: .debug)
                for characteristic in service.characteristics! {
                    if CommonServices.isCommonCharacteristic(commonServices: self.commonServices, characteristicId: characteristic.uuid) {
                        os_log("Characteristic ID:  %@", log: OSLog.libLog, type: .debug, characteristic.uuid.uuidString)
                        self.commoncharacteristicsList.append(characteristic)
                    }
                }
            } else {
                os_log("We are NOT on a common service", log: OSLog.libLog, type: .debug)
                for characteristic in service.characteristics! {
                    setCCIDCharacteristics(characteristic)
                    os_log("Characteristic ID:  %@", log: OSLog.libLog, type: .debug, characteristic.uuid.uuidString)
                    self.characteristicsSpecificsToDevice.append(characteristic)
                }
            }
            self.currentServiceIndex += 1
            if self.currentServiceIndex >= self.servicesCount {
                self.notifyToCharacteristics()
            }
        }
    }
    
    // When a characteristic value is read
    /// :nodoc:
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        os_log("SCardReaderList:didUpdateValueFor()", log: OSLog.libLog, type: .info)
        self.isWaitingAnswer = false
        if error != nil {
            generateErrorAfterReading(characteristic: characteristic, errorReceived: error)
            return
        }
        afterReading(characteristic)
    }
    
    // When a characteristic notifies
    /// :nodoc:
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        os_log("SCardReaderList:didUpdateNotificationStateFor(): %@", log: OSLog.libLog, type: .info, characteristic.uuid.uuidString)
        self.isWaitingAnswer = false
        if error != nil {
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
        os_log("SCardReaderList:didWriteValueFor()", log: OSLog.libLog, type: .info)
        os_log("Characteristic ID: %@", log: OSLog.libLog, type: .debug, characteristic.uuid.uuidString)
        if error != nil {
            let _error = generateError(code: error!._code, message: error.debugDescription)
            switch lastCommand {
            case .control:
                callOnControlDidResponseWithError(_error)
            case .cardConnect:
                callOnCardDidConnectWithError(_error)
            case .transmit:
                callOnCardDidTransmitWithError(_error)
            case .cardDisconnect:
                callOnCardDidDisconnectWithError(_error)
            case .noCommand, .getStatus:
                ()
                break
            }
            return
        }
        os_log("Write succeed", log: OSLog.libLog, type: .debug)
        writeToPcToRdrCharacteristic()
    }
    
    /// :nodoc:
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        os_log("SCardReaderList:centralManagerDidUpdateState()", log: OSLog.libLog, type: .info)
    }
    
    /// :nodoc:
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        os_log("SCardReaderList:didDisconnectPeripheral()", log: OSLog.libLog, type: .info)
        isConnected = false
        isValid = false
        noop()
        var _error: Error?
        if error != nil {
            _error = self.generateError(code: error!._code, message: error.debugDescription, trigger: false)
        }
        /*if machineState != .isDisconnecting {
         _error = generateError(code: .deviceNotConnected, message: "The reader sent a disconnection message", trigger: false)
         }*/
        machineState = .isDisconnected
        self.delegate?.onReaderListDidClose(readers: self, error: _error)
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
        os_log("SCardReaderList:control()", log: OSLog.libLog, type: .info)
        if !canRequestCommandToDevice() {
            let error = generateError(code: .busy, message: "Another command is running")
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
        os_log("SCardReaderList:close()", log: OSLog.libLog, type: .info)
        noop()
        machineState = .isDisconnecting
        unsubscribeCharacteristics()
        if !keepBleActive {
            self.centralManager.cancelPeripheralConnection(self.device!)
        }
        self.delegate?.onReaderListDidClose(readers: self, error: nil)
    }
    
    /**
     Request for the creation of a PC/SC product **over BLE**
     
     - Parameter peripheral: The peripheral the application is connected to
     - Parameter centralManager: The system Central Manager (must be a singleton)
     - Parameter advertisingServices: array of CBUUID found during devices scan. This parameter will help to instantiate the good objet
     - Parameter delegate: "pointer" to the class that implements the callbacks (usually "self")
     - Parameter secureConnectionParameters: Object of type `SecureConnectionParameters` used to pass secure communication parameters (optional)
     - Returns: As the code is asynchronous, the onReaderListDidCreate() callback of the delegate will be called in case of success or failure (i.e you need to verify the error parameter)
     - Remark: If this method is called with an unknow device, an error will be triggered. If you don't pass a `SecureConnectionParameters` object then the communication mode is considered to be in `clear`mode
     - SeeAlso: `getAllAdvertisingServices()`
     - Precondition: `advertisingServices` must point to the advertising services of a D600 or a Puck
     - Requires: All parameters are mandatory
     */
    public static func create(peripheral: CBPeripheral, centralManager: CBCentralManager, advertisingServices: [CBUUID], delegate: SCardReaderListDelegate, secureConnectionParameters: SecureConnectionParameters? = nil)  {
        os_log("SCardReaderList:create()", log: OSLog.libLog, type: .info)
        
        var detectedDeviceType: BleDeviceType = .Unknown
        if SCardReaderList.isInDeviceAdvertisingServices(deviceServices: DevicesServices.getD600Services(), deviceAdvertisedServices: advertisingServices) {
            self.instance = SCardReaderList_D600_BLE(device: peripheral, centralManager: centralManager, delegate: delegate, secureConnectionParameters: secureConnectionParameters) as SCardReaderList
            detectedDeviceType = .D600
        } else if SCardReaderList.isInDeviceAdvertisingServices(deviceServices: DevicesServices.getPuckUnbondedServices(), deviceAdvertisedServices: advertisingServices) {
            self.instance = SCardReaderList_PUCK_BLE_Unbonded(device: peripheral, centralManager: centralManager, delegate: delegate, secureConnectionParameters: secureConnectionParameters) as SCardReaderList
            detectedDeviceType = .PUCK_Unbonded
        } else if SCardReaderList.isInDeviceAdvertisingServices(deviceServices: DevicesServices.getPuckBondedServices(), deviceAdvertisedServices: advertisingServices) {
            self.instance = SCardReaderList_PUCK_BLE_Bonded(device: peripheral, centralManager: centralManager, delegate: delegate, secureConnectionParameters: secureConnectionParameters) as SCardReaderList
            detectedDeviceType = .PUCK_Bonded
        }
        
        if detectedDeviceType == .Unknown {
            let errorMessage = "Unknow device type"
            let errorCode = Int(SCardErrorCode.unsupportedPrimaryService.rawValue)
            os_log("Error code: %@, Message: %@", log: OSLog.libLog, type: .error, String(errorCode), errorMessage)
            let error = NSError(domain: Bundle.main.bundleIdentifier!, code: errorCode, userInfo: [NSLocalizedDescriptionKey : errorMessage])
            delegate.onReaderListDidCreate(readers: nil, error: error)
            return
        }
        self.instance!.launchServicesDiscovery()
    }
    
    /// Get the list of services UUID to filter scan
    ///
    /// - Returns: array of services UUIDs
    public static func getAllAdvertisingServices() -> [CBUUID] {
        os_log("SCardReaderList:getAllAdvertisingServices()", log: OSLog.libLog, type: .info)
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
        os_log("SCardReaderList:lastError()", log: OSLog.libLog, type: .info)
        return self._lastError
    }
    
    
    /// returns the last error message
    ///
    /// - Returns: a string describing the problem, can be a message from the system or a message specific to the SpringCard library
    public func lastErrorMessage() -> String {
        os_log("SCardReaderList:lastErrorMessage()", log: OSLog.libLog, type: .info)
        return self._lastErrorMessage
    }
    
    /// Returns the connection status
    ///
    /// - Returns: true if there is a connection to a BLE device
    public func connected() -> Bool {
        os_log("SCardReaderList:connected()", log: OSLog.libLog, type: .info)
        return self.isConnected
    }
    
    /// Is the connection valid?
    ///
    /// - Returns: Boolean
    public func valid() -> Bool {
        os_log("SCardReaderList:valid()", log: OSLog.libLog, type: .info)
        return self.isValid
    }
    
    /**
     Get a Reader objet from a slot's name
     
     - Parameter slot: name of the slot from the `slots` property
     - Returns: a `Reader` object or nil if the slot's name is unknown
     */
    public func getReader(slot: String) -> SCardReader? {
        os_log("SCardReaderList:getReader()", log: OSLog.libLog, type: .info)
        os_log("slot: %@", log: OSLog.libLog, type: .debug, slot)
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
     Get a Reader objet from a slot's index
     
     - Parameter slot: index (0 based) of the slot from the `slots` property
     - Returns: a `Reader` object or nil if the index is out of bounds
     */
    public func getReader(slot: Int) -> SCardReader? {
        os_log("SCardReaderList:getReader()", log: OSLog.libLog, type: .info)
        os_log("slot: %@", log: OSLog.libLog, type: .debug, String(slot))
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
        os_log("SCardReaderList:transmit()", log: OSLog.libLog, type: .info)
        if !canRequestCommandToDevice() {
            let error = generateError(code: .busy, message: "Another command is running")
            self.delegate?.onTransmitDidResponse(channel: channel, response: nil, error: error)
            return
        }
        
        let slotIndex = channel.getSlotIndex()
        
        if !channel.parent.cardPresent {
            let error = generateError(code: .cardRemoved, message: "Can't call transmit() because card was removed")
            self.delegate?.onTransmitDidResponse(channel: channel, response: nil, error: error)
            return
        }
        if !channel.parent.cardPowered {
            let error = generateError(code: .cardPoweredDown, message: "Can't call transmit() because card is powered down")
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
        os_log("SCardReaderList:cardDisconnect()", log: OSLog.libLog, type: .info)
        let slotIndex = channel.getSlotIndex()
        
        if lastCommand == .cardDisconnect {
            return
        }
        
        if !canRequestCommandToDevice() {
            let error = generateError(code: .busy, message: "Another command is running")
            self.delegate?.onCardDidConnect(channel: nil, error: error)
            return
        }
        
        if !isSlotIndexValid(slotIndex) {
            let error = generateError(code: .invalidParameter, message: "Slot number is out of bounds")
            self.delegate?.onCardDidConnect(channel: nil, error: error)
            return
        }
        
        lastCommand = .cardDisconnect
        isWaitingAnswer = true
        isUsingSlotNumber = slotIndex
        self.CCID_PC_To_RDR(command: SCard_CCID_PC_To_RDR.PC_To_RDR_IccPowerOff, slotNumber: slotIndex, payload: nil)
    }
    
    // Equivalent of the ScardConnect()
    internal func cardConnect(reader: SCardReader) {
        os_log("SCardReaderList:cardConnect()", log: OSLog.libLog, type: .info)
        let slotIndex = reader._slotIndex
        let cardPresent = reader.cardPresent
        
        os_log("Slot index: %@, cardPresent: %@", log: OSLog.libLog, type: .debug, String(slotIndex), String(cardPresent))
        
        if self.lastCommand == .cardConnect {
            os_log("NOTHING WAS DONE WE ARE ALREADY CONNECTING TO THE CARD", log: OSLog.libLog, type: .debug)
            return
        }
        
        if !cardPresent {
            let error = generateError(code: .cardAbsent, message: "There's no card in the requested slot")
            self.delegate?.onCardDidConnect(channel: nil, error: error)
            return
        }
        if !isSlotIndexValid(slotIndex) {
            let error = generateError(code: .invalidParameter, message: "Slot number is out of bounds")
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
        os_log("SCardReaderList:cardReconnect()", log: OSLog.libLog, type: .info)
        self.cardConnect(reader: channel.parent)
    }
    
}
