/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation
import CoreBluetooth
import os.log

/**
Represents a channel

You can get this object with a call to `reader.cardConnect()`

- Version 1.0
- Author: [SpringCard](https://www.springcard.com)
- Copyright: [SpringCard](https://www.springcard.com)
*/
public class SCardChannel: Equatable {

	internal var _atr = [UInt8]()
	internal var _parent: SCardReader!
    private var _isUnpowered = false
	
	/**
	Points to an `SCardReader` object
	
	- Remark: read-only
	*/
	public var parent: SCardReader {
		return self._parent
	}
    
    /// Was the channel unpowered after the reader went to sleep?
    public var isUnpowered: Bool {
        return self._isUnpowered
    }
	
	/**
	Card's ATR
	
	- Remark: read-only
	*/
	public var atr: [UInt8] {
		return self._atr
	}
	
	internal init(parent: SCardReader, atr: [UInt8]) {
        #if DEBUG
		os_log("SCardChannel:init() with ATR", log: OSLog.libLog, type: .info)
        #endif
		self._parent = parent
		self._atr = atr
	}
    
	internal init(parent: SCardReader) {
	#if DEBUG
	        os_log("SCardChannel:init() WITHOUT ATR", log: OSLog.libLog, type: .info)
        #endif
        self._parent = parent
    }
	
	internal func getSlotIndex() -> Int {
        #if DEBUG
		os_log("SCardChannel:getSlotIndex()", log: OSLog.libLog, type: .info)
        #endif
		return parent._slotIndex
	}
	
	public static func == (lhs: SCardChannel, rhs: SCardChannel) -> Bool {
        #if DEBUG
		os_log("SCardChannel:==", log: OSLog.libLog, type: .info)
        #endif
		return lhs._parent == rhs._parent
	}

	/**
	Transmit a C-APDU to the card, receive the R-APDU in response (in the callback)
	
	- Parameter command: The C-APDU to send to the card
	- Returns: Nothing, answer is available in the `onTransmitDidResponse()` callback
	*/
	public func transmit(command: [UInt8]) {
        #if DEBUG
		os_log("SCardChannel:transmit()", log: OSLog.libLog, type: .info)
        os_log("slot Index: %d", log: OSLog.libLog, type: .debug, self.parent._slotIndex)
        os_log("slot Name: %s", log: OSLog.libLog, type: .debug, self.parent._slotName)
        #endif
		_parent._parent.transmit(channel: self, command: command)
	}
	
	/**
	Disconnect from the card (close the communication channel + power down)
	
	- Returns: Nothing, answer is available in the `onCardDidDisconnect()` callback
	*/
	public func cardDisconnect() {
        #if DEBUG
		os_log("SCardChannel:cardDisconnect()", log: OSLog.libLog, type: .info)
        #endif
        _parent.setDeconnected()
		_parent._parent.cardDisconnect(channel: self)
	}

	internal func reinitAtr() {
		self._atr = [UInt8]()
	}
    
    internal func setUnpowered() {
        self.reinitAtr()
        self._isUnpowered = true
    }
	
	/**
	Connect to the card again (re-open an existing communication channel
	
	- Returns: Nothing, answer is available in the `onCardDidConnect()` callback
	*/
	public func cardReconnect() {
        #if DEBUG
		os_log("SCardChannel:cardReconnect()", log: OSLog.libLog, type: .info)
        #endif
		_parent._parent.cardReconnect(channel: self)
	}
}

