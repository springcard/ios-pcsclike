/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation
import CoreBluetooth
import os.log

// Represents a response (answer)
internal class SCCcidRdrToPc: SClass {
	internal var header: SCCcidRdRToPcHeader
	internal var payload: ScCcidRdrToPcPayload?

	private var _isValid = false
	internal var _isLongAnswer = false
	private var isLongAnswerFromCaller = false
    internal var awaitedPayloadLength: UInt32 = 0
    
    private var readerListSecure: SCardReaderListSecure?
    internal var isSecureCommunication = false
    
    init(characteristic: CBCharacteristic, readerListSecure: SCardReaderListSecure?, isLongAnswer: Bool = false) {
        self.header = SCCcidRdRToPcHeader(characteristic: characteristic, readerListSecure: readerListSecure, isLongAnswer: isLongAnswer)
        self.readerListSecure = readerListSecure
        self.isLongAnswerFromCaller = isLongAnswer
        super.init()
        
        if readerListSecure != nil && (readerListSecure?.isSecureCommunication)! {
            self.isSecureCommunication = true
        }

		if !header.isValid {
            if !self.isLongAnswerFromCaller {
                self.payload = nil
                setInternalError(code: header.errorCode, message: header.errorMessage)
                return
            }
		}
        
		guard let payloadLength = self.header.payloadLength else {
            setInternalError(code: .otherError, message: "Payload length is nil")
			return
		}

		self.awaitedPayloadLength = payloadLength
        self.payload = ScCcidRdrToPcPayload(characteristic: characteristic, startingIndex: header.payloadStartIndex, payloadLength: header.payloadLength!, readerListSecure: readerListSecure)
		
		if !payload!.isValid && !self.isLongAnswerFromCaller {
            setInternalError(code: payload!.errorCode, message: payload!.errorMessage)
			return
		}
		
		self._isLongAnswer = payload!.islongAnswer
		self._isValid = true
	}
	
	internal func isAnswerComplete() -> Bool {
		if self.payload?.payloadLength == self.awaitedPayloadLength {
			self._isLongAnswer = false
			return true
		}
		return false
	}
	
	internal func addToPayload(_ characteristic: CBCharacteristic) {
		self.payload?.addToPayload(characteristic)
	}
	
    internal func getAnswer() -> [Byte]? {
		if !self._isValid {
			return nil
		}
        
        var _payload:[UInt8] = []
        
        if self.isSecureCommunication {
            var ccidBuffer = header.getHeader()
            if self.payload != nil {
                guard let payloadData = self.payload?.getPayload() else {
                    setInternalError(code: .otherError, message: "Payload is nil")
                    return nil
                }
                ccidBuffer += payloadData
            }
            var payloadLength: UInt32 = 0
            guard let newCcidBuffer = self.readerListSecure?.decryptCcidBuffer(ccidBuffer, payloadLength: &payloadLength) else {
                _isValid = false
                setInternalError(code: self.readerListSecure?.errorCode ?? SCardErrorCode.secureCommunicationError, message: self.readerListSecure?.errorMessage ?? "It was not possible to decrypt receveid message")
                return nil
            }
            self.header.setLength(payloadLength)
            _payload = Array(newCcidBuffer.suffix(from: 10))
        } else {
            guard let __payload = self.payload?.getPayload() else {
                self.setInternalError(code: .otherError, message: "Payload is nil")
                return nil
            }
			_payload = __payload
        }
		return _payload
	}
	
	internal func isValid() -> Bool {
        if !self._isValid {
            return false
        }
		if self.payload == nil {
			return false
		}
		if !self.payload!.isValid {
			return false
		}
		return self._isValid
	}
	
	internal func isLongAnswer() -> Bool {
		return self._isLongAnswer
	}
}
