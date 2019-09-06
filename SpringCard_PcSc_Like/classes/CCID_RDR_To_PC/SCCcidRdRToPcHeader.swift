/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation
import CoreBluetooth
import os.log

/// :nodoc:
internal struct CcidResponsePositions {
	static let responseCode = 0
	static let payloadLength = 1
	static let slotNumber = 5
	static let sequenceNumber = 6
	static let slotStatus = 7
	static let slotError = 8
	static let RFU = 9
}

/// :nodoc:
// Represents a response header
internal class SCCcidRdRToPcHeader: SClass {
	private var rawContent: [UInt8] = []
	internal let headerLength = 10
    private var readerListSecure: SCardReaderListSecure?

	internal var isValid = false
    private var isSecureCommunication = false
    private var isLongAnswerFromCaller = false
	
	// Equivalents of the CCID_RDR_To_PC header ********************
	internal var responseCode: CCID_RDR_To_PC_Answer_Codes?
	internal var payloadLength: UInt32?
	internal var slotNumber: Byte?
	internal var sequenceNumber: Byte?
	internal var slotStatus: Byte?
	internal var slotError: Byte?
	internal var payloadStartIndex: Int = 0
	// *************************************************************

    init(characteristic: CBCharacteristic, readerListSecure: SCardReaderListSecure?, isLongAnswer: Bool = false) {
        super.init()
        self.isLongAnswerFromCaller = isLongAnswer
        self.readerListSecure = readerListSecure
        if readerListSecure != nil && (readerListSecure?.isSecureCommunication)! {
            self.isSecureCommunication = true
        }
		guard let characteristicData = characteristic.value else {
			self.setInternalError(code: .invalidCharacteristicSetting, message: "CCID RDR_To_Pc characteristic bytes are nil")
			return
		}
		let bytes = [UInt8](characteristicData)
		if bytes.isEmpty {
			setInternalError(code: .invalidCharacteristicSetting, message: "CCID RDR_To_Pc characteristic bytes are empty")
			return
		}
        if (bytes.count >= headerLength) {
        	self.rawContent = Array(bytes[..<headerLength])
        }
		validateContent()
	}
	
	private func isCommandValid() -> Bool {
		let value = rawContent[CcidResponsePositions.responseCode]
		let command = CCID_RDR_To_PC_Answer_Codes(rawValue: value)
		return command != nil ? true : false
	}

	private func validateContent() {
		if self.rawContent.isEmpty || self.rawContent.count < self.headerLength {
			setInternalError(code: .invalidCharacteristicSetting, message: "Raw content of CCID RDR_To_PC characterisitc is empty or too short")
			return
		}
		if !self.isLongAnswerFromCaller && !self.isCommandValid() {
			setInternalError(code: .invalidCharacteristicSetting, message: "Command response of CCID RDR_To_PC characterisitc is not valid")
			return
		}
		
		self.isValid  = true
		toObject()
	}

	private func getResponseCode() -> CCID_RDR_To_PC_Answer_Codes? {
		return self.isValid ? CCID_RDR_To_PC_Answer_Codes(rawValue: self.rawContent[CcidResponsePositions.responseCode]) : nil
	}

	private func toObject() {
		if !self.isValid {
			return
		}
		self.responseCode = self.getResponseCode()
		let payloadLengthBytes: [Byte] = [rawContent[1], rawContent[2], rawContent[3], rawContent[4]]
		payloadLength = SCUtilities.fromByteArray(byteArray: payloadLengthBytes, secureCommunication: self.isSecureCommunication)
        
		slotNumber = self.rawContent[CcidResponsePositions.slotNumber]
		sequenceNumber = self.rawContent[CcidResponsePositions.sequenceNumber]
		slotStatus = self.rawContent[CcidResponsePositions.slotStatus]
		slotError = self.rawContent[CcidResponsePositions.slotError]
		payloadStartIndex = self.headerLength
	}
    
    internal func getHeader() -> [Byte] {
        return self.rawContent
    }
    
    internal func setLength(_ length: UInt32) {
        payloadLength = length
    }
}
