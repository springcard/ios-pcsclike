/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */

//
// Representation of a GATT Service with its characteristics
//  BleService.swift
//  SpringCard.PCSC.ZeroDriver
//
import Foundation
import CoreBluetooth

/// :nodoc:
internal class BleService: CustomStringConvertible
{
	private var serviceId: CBUUID?
	private var serviceDescription: String?
	private var isAdvertisingService = false;
	private var characterisitics: [String:CBUUID] = [:]
	
	// To get a printable version of the class
	internal var description: String {
		var characteristicsList: [String] = []
		for (_, uuid) in self.characterisitics {
			characteristicsList.append(uuid.uuidString)
		}
		return "BleService: " + (self.serviceId?.uuidString)! + ", Characteristics: " + characteristicsList.joined(separator: ", ")
	}
	
	internal func isAdvertising() -> Bool {
		return self.isAdvertisingService
	}

	internal init(serviceId id: String, serviceDescription description: String, isAdvertisingService: Bool, serviceCharacteristics: [String:String]) {
		self.serviceId = CBUUID(string: id)
		self.serviceDescription = description
		self.isAdvertisingService = isAdvertisingService
		for (characteristicDescription, characteristicId) in serviceCharacteristics {
			self.characterisitics[characteristicDescription] = CBUUID(string: characteristicId)
		}
	}
	
	internal func getServiceId() -> CBUUID {
		return self.serviceId!
	}
	
	internal func getCharacteristics() -> [String:CBUUID] {
		return self.characterisitics
	}
    
	internal func getCharacteristicsUuids() -> [CBUUID] {
		var characs:[CBUUID] = []
		for (_, ID) in self.characterisitics {
			characs.append(ID)
		}
		return characs
	}

	internal func getServiceIdAsString() -> String {
		if self.serviceId != nil {
			return self.serviceId!.uuidString
		} else {
			return ""
		}
	}
}
