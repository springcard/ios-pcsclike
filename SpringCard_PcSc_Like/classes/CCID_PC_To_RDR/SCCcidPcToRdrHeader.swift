/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation
import CoreBluetooth
import os.log

/// nodoc:
internal class SCCcidPcToRdrHeader: SClass {
	
	private var rawContent: [Byte] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	
	private var command: SCard_CCID_PC_To_RDR
	private var slotNumber: Int
	private var sequenceNumber: Int
	private var payloadLength: UInt32
	private var commandParameters: [Byte]
	private var readerListSecure: SCardReaderListSecure?
    private var isSecureCommunication = false
	
	private let headerSize = 10

	init(command: SCard_CCID_PC_To_RDR, slotNumber: Int, sequenceNumber: Int, payloadLength: UInt32, commandParameters: [Byte], readerListSecure: SCardReaderListSecure?) {
		self.command = command
		self.slotNumber = slotNumber
		self.sequenceNumber = sequenceNumber
		self.payloadLength = payloadLength
		self.commandParameters = commandParameters
		self.readerListSecure = readerListSecure
        
        super.init()
        if (readerListSecure != nil) && ((readerListSecure?.isSecureCommunication)!) {
            self.isSecureCommunication = true
        }
		constructHeader()
	}
	
	private func constructHeader() {
		self.rawContent = [UInt8](repeating: 0x00, count: self.headerSize)
		rawContent[0] = self.command.rawValue
        setLengthBytes(secureCommunication: false)
		rawContent[5] = UInt8(self.slotNumber)
		rawContent[6] = UInt8(self.sequenceNumber)
		rawContent[7] = self.commandParameters[0]
		rawContent[8] = self.commandParameters[1]
		rawContent[9] = self.commandParameters[2]
	}
    
    private func setLengthBytes(secureCommunication: Bool) {
        let lengthAsBytes = SCUtilities.toByteArray(value: self.payloadLength, secureCommunication: secureCommunication)
        rawContent[1] = lengthAsBytes[0]
        rawContent[2] = lengthAsBytes[1]
        rawContent[3] = lengthAsBytes[2]
        rawContent[4] = lengthAsBytes[3]
    }
    
    // Used for secure communication where the length changed after encryption
    internal func setLength(_ length: UInt32, _ secureCommunication: Bool) {
        self.payloadLength = length
        setLengthBytes(secureCommunication: secureCommunication)
    }
	
	internal func getHeader() -> [Byte] {
		return self.rawContent
	}
}
