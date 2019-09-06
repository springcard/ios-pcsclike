/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation
import CoreBluetooth
import os.log

/// nodoc:
// State of each slot
internal struct SCCcidStatusSlotStatusNotification {
	internal var slotNumber = 0
	internal var slotStatus: SlotStatusNotification = .cardAbsent
	internal var rawContent: UInt8 = UInt8(0x00)
	
	init(slotNumber: Int, bits: UInt8) {
		self.slotNumber = slotNumber
		self.rawContent = bits
		switch bits {
			case 0b00:
				slotStatus = .cardAbsent
			case 0b01:
				slotStatus = .cardPresent
			case 0b10:
				slotStatus = .cardRemoved
			case 0b11:
				slotStatus = .cardInserted
			default:
				slotStatus = .cardAbsent
		}
	}
}
