/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation
import CoreBluetooth
import os.log

// Represent a request (used to send/write data to the host)
/// nodoc:
internal class SCCcidPcToRdr: SClass {
    internal var header: SCCcidPcToRdrHeader!
    internal var payload: ScCcidPcToRdrPayload?
    
    internal var isValid = true
    internal var isSecureCommunication = false
    
    internal let commandParameters: [Byte] = [0x00, 0x00, 0x00]
    private var readerListSecure: SCardReaderListSecure?	// Security class
    
    init(command: SCard_CCID_PC_To_RDR, slotNumber: Int, sequenceNumber: Int, payload: [Byte]?, readerListSecure: SCardReaderListSecure?) {
        self.readerListSecure = readerListSecure
        super.init()
        
        var _payload = payload
        
        if readerListSecure != nil && (readerListSecure?.isSecureCommunication)! {
            self.isSecureCommunication = true
        }
        
        let payloadLength = (payload == nil) ? 0 : payload!.count
        self.header = SCCcidPcToRdrHeader.init(command: command, slotNumber: slotNumber, sequenceNumber: sequenceNumber, payloadLength: UInt32(payloadLength), commandParameters: commandParameters, readerListSecure: readerListSecure)
        
        if isSecureCommunication {
            var ccidBuffer = header.getHeader()
            if payload != nil {
                ccidBuffer += payload!
            }
            var payloadLength: UInt32 = 0
            guard let newCcidBuffer = self.readerListSecure?.encryptCcidBuffer(ccidBuffer, payloadLength: &payloadLength) else {
                isValid = false
                setInternalError(code: self.readerListSecure?.errorCode ?? SCardErrorCode.secureCommunicationError, message: self.readerListSecure?.errorMessage ?? "It was not possible to encrypt message to send")
                return
            }
            header.setLength(payloadLength, true)
            _payload = Array(newCcidBuffer.suffix(from: 10))
        }
        
        if _payload != nil {
            self.payload = ScCcidPcToRdrPayload.init(payload: _payload!, readerListSecure: readerListSecure)
        } else {
            self.payload = nil
        }
    }
    
    internal func getCommand() -> [Byte]? {
        var command: [Byte] = header.getHeader()
        if self.payload != nil {
            command += self.payload!.getPayload()!
        }
        return command
    }
}
