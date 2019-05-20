/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation
import CoreBluetooth
import os.log

// Represents a response payload
internal class ScCcidRdrToPcPayload: SClass {
	private var isUsingSecureCommunication = false
	private var payload: [UInt8] = []
	internal var payloadLength: UInt32 = 0
	
	internal var isValid = false
	internal var islongAnswer = false
    private var readerListSecure: SCardReaderListSecure?

	init(characteristic: CBCharacteristic, startingIndex: Int, payloadLength: UInt32, readerListSecure: SCardReaderListSecure?) {
        super.init()
        
		self.readerListSecure = readerListSecure
        if readerListSecure != nil && (readerListSecure?.isSecureCommunication)! {
            self.isUsingSecureCommunication = true
        }

        if payloadLength == 0 {
            self.payloadLength = 0
            self.isValid = true
            self.payload = []
            return
        }
		guard let characteristicData = characteristic.value else {
			setInternalError(code: .invalidCharacteristicSetting, message: "CCID RDR_To_Pc characteristic bytes are empty")
			return
		}
		let bytes = [UInt8](characteristicData)
		if bytes.isEmpty {
			setInternalError(code: .invalidCharacteristicSetting, message: "CCID RDR_To_Pc characteristic is empty")
			return
		}
		var lastIndex = Int(UInt32(startingIndex) + payloadLength)
		let startIndex = Int(startingIndex)
		if startIndex >= bytes.count || startIndex < 0 {
			setInternalError(code: .invalidParameter, message: "Starting index to get the payload is out of bounds")
			return
		}
		if lastIndex < startIndex {
			setInternalError(code: .invalidParameter, message: "Ending index to get the payload is out of bounds")
			return
		}
		if lastIndex > bytes.count {
			lastIndex = bytes.count
			islongAnswer = true
        }
		self.payload = Array(bytes[startIndex ..< lastIndex])
		self.payloadLength = UInt32(payload.count)
		self.isValid = true
	}
	
	internal func addToPayload(_ characteristic: CBCharacteristic) {
		guard let characteristicData = characteristic.value else {
			setInternalError(code: .invalidCharacteristicSetting, message: "CCID RDR_To_Pc characteristic is empty")
			return
		}
		let bytes = [UInt8](characteristicData)
		if bytes.isEmpty {
			setInternalError(code: .invalidCharacteristicSetting, message: "CCID RDR_To_Pc characteristic is empty")
			return
		}
		if self.payload.isEmpty {
			self.payload = bytes
		} else {
			self.payload += bytes
		}		
		self.payloadLength = UInt32(payload.count)
	}
	
	internal func getPayload() -> [UInt8]? {
		if !self.isValid {
			return nil
		}
		return self.payload
	}
}
