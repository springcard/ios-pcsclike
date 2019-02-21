/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation
import CoreBluetooth
import os.log

/**
Represents a slot

You can get this object with a call to `SCardReaderList.getReader()`

- Remark: This object implements the Equatable protocol
- Version 1.0
- Author: [SpringCard](https://www.springcard.com)
- Copyright: [SpringCard](https://www.springcard.com)
*/
public class SCardReader: Equatable {

	internal var _parent: SCardReaderList!
	internal var _channel: SCardChannel?
	internal var _slotIndex: Int = 0
	internal var _slotName: String = ""
	internal var _cardPowered: Bool = false
	internal var _cardPresent: Bool = false
    
    /**
     Contains the slot's index
     
     - Remark: read-only
     */
    public var index: Int {
        return self._slotIndex
    }
    
    /**
     Contains the slot's name
     
     - Remark: read-only
     */
    public var name: String {
        return self._slotName
    }

	/**
	Points to an `SCardReaderList` object
	
	- Remark: read-only
	*/
	public var parent: SCardReaderList! {
		return self._parent
	}
	
	internal var channel: SCardChannel? {
		return self._channel
	}

	/**
	Is card powered (by the application) ?
	
	- Remark: read-only
	*/
	public var cardPowered: Bool {
		return _cardPowered
	}
	
	/**
	Is a card present in the reader (slot) ?
	
	- Remark: read-only
	*/
	public var cardPresent: Bool {
		return _cardPresent
	}
	
	internal init(parent: SCardReaderList, slotName: String, slotIndex: Int) {
		//os_log("SCardReader:init()", log: OSLog.libLog, type: .info)
		self._parent = parent
		self._slotIndex = slotIndex
		self._slotName = slotName
	}
	
	/// :nodoc:
	public static func == (lhs: SCardReader, rhs: SCardReader) -> Bool {
		//os_log("SCardReader:==", log: OSLog.libLog, type: .info)
		return lhs._slotIndex == rhs._slotIndex
	}
	
	internal func setNewState(state: SCCcidStatusSlotStatusNotification) {
		os_log("SCardReader:setNewState()", log: OSLog.libLog, type: .info)
        os_log("Slot Index: %@, new state: %@", log: OSLog.libLog, type: .debug, String(self._slotIndex), String(state.slotStatus.rawValue))
		switch state.slotStatus {
			case .cardAbsent: // Card absent, no change since the last notification
				self._cardPresent = false
				self._cardPowered = false
			
			case .cardPresent:	// Card present, no change since last notification
				self._cardPresent = true

			case .cardRemoved:	// Card removed notification
				self._cardPresent = false
				self._cardPowered = false
				self._channel = nil

			case .cardInserted:	// Card inserted notification
				self._cardPresent = true
		}
	}

	/**
	Send a direct command to the device
	
	- Parameter command: The command to send to the reader
	- Returns: Nothing, answer is available in the `onControlDidResponse()` callback
	*/
	public func control(command: [UInt8]) {
		os_log("SCardReader:control()", log: OSLog.libLog, type: .info)
		parent?.control(command: command)
	}
	
	/**
	Connect to the card (power up + open a communication channel with the card)
	
	- Returns: Nothing, answer is available in the `onCardDidConnect()` callback
	*/
	public func cardConnect() {
		os_log("SCardReader:cardConnect()", log: OSLog.libLog, type: .info)
		os_log("Channel: %@", log: OSLog.libLog, type: .debug, self._slotName)
		parent?.cardConnect(reader: self)
	}
	
	internal func setNewChannel(_ channel: SCardChannel) {
		os_log("SCardReader:setNewChannel()", log: OSLog.libLog, type: .info)
		self._channel = channel
	}
	
	internal func setCardPowered() {
		os_log("SCardReader:setCardPowered()", log: OSLog.libLog, type: .info)
		self._cardPowered = true
	}
}
