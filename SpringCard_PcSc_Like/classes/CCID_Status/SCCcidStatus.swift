/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation
import CoreBluetooth
import os.log

/// nodoc:
// Represents the value of the CCID_Status characteristic (as an object) and validate its content
internal class SCCcidStatus: SClass {
    
    // Equivalents of the CCID Status characteristic properties ****
    internal var responseReady: Bool = false
    internal var numberOfSlots = 0
    internal var slots: [SCCcidStatusSlotStatusNotification] = []
    internal var isInLowPowerMode = false
    // **************************************************************
    
    internal var isValid = true
    private let minimalBytesCount = 2
    private var rawContent: [Byte] = []
    
    override init() { }
    
    init(characteristic: CBCharacteristic) {
        super.init()
        guard let characteristicData = characteristic.value else {
            setInternalError(code: .invalidCharacteristicSetting, message: "CCID Status characteristic is empty")
            return
        }
        let bytes = [UInt8](characteristicData)
        if bytes.isEmpty {
            setInternalError(code: .invalidCharacteristicSetting, message: "CCID Status bytes are empty")
            return
        }
        self.rawContent = bytes
        validateContent()
    }
    
    private func validateContent() {
        if self.rawContent.isEmpty || self.rawContent.count < self.minimalBytesCount {
            setInternalError(code: .invalidCharacteristicSetting, message: "Raw content of CCID Status characterisitc is empty or too short")
            self.isValid  = false
        }
        if self.isValid {
            toObject()
        }
    }
    
    private func toObject() {
        self.responseReady = (self.rawContent[0] >> 8 == 1) ? true : false
        self.numberOfSlots = Int(self.rawContent[0] & 0b111)
        self.isInLowPowerMode = Int(self.rawContent[0] & 0b10000000) == 0x80 ? true : false;
        self.slots = []
        
        for slotIndex in 0 ..< self.numberOfSlots {
            let byteIndex = computeStatusByte(slotIndex)
            if byteIndex < 1 || byteIndex >= self.rawContent.count {
                self.setInternalError(code: .otherError, message: "Computed byte offset is out of boundd")
                return
            }
            let byte = self.rawContent[byteIndex]
            let bitsShift = computeBits(slotIndex: slotIndex, byteIndex: byteIndex)	// 0, 2, 4, 6
            let bits = (byte >> bitsShift) & 0b11
            let slot = SCCcidStatusSlotStatusNotification(slotNumber: slotIndex, bits: bits)
            self.slots.append(slot)
        }
    }
    
    private func computeStatusByte(_ slotIndex: Int) -> Int {
        let integer = floor((Double(slotIndex) / 4))
        return Int(integer + 1)
    }
    
    private func computeBits(slotIndex: Int, byteIndex: Int) -> Int {
        return ((slotIndex - (byteIndex * 4)) + 4) * 2	// 0 2 4 6
    }
    
    internal func markAsWakeUped() {
		self.isInLowPowerMode = false
    }
}
