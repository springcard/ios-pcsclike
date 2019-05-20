/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */

// Contains all the GATT Services specifics to each device
import Foundation
import CoreBluetooth
import os.log

/// :nodoc:
internal enum BleDeviceType {
	case Unknown, D600, PUCK_Unbonded, PUCK_Bonded
}

/// :nodoc:
internal class DevicesServices {
	internal static func getServices(deviceType: BleDeviceType) -> [BleService] {
		var deviceServices: [String: (serviceDescription: String, isAdvertisingService: Bool, serviceCharacteristics: [String: String])] = [:]
		var bleServices: [BleService] = []
		switch deviceType {
		case .D600:
			deviceServices = DevicesServices.getD600Services()
		case .PUCK_Bonded:
			deviceServices = DevicesServices.getPuckBondedServices()
		case .PUCK_Unbonded:
			deviceServices = DevicesServices.getPuckUnbondedServices()
		case .Unknown:
			deviceServices = [:]
		}
		
		for (serviceId, serviceDescription) in deviceServices {
			let bleService = BleService(serviceId: serviceId, serviceDescription: serviceDescription.serviceDescription, isAdvertisingService: serviceDescription.isAdvertisingService, serviceCharacteristics: serviceDescription.serviceCharacteristics)
			bleServices.append(bleService)
		}
		return bleServices
	}
	
	internal static func getD600Services() -> [String: (serviceDescription: String, isAdvertisingService: Bool, serviceCharacteristics: [String: String])] {
		return [
			"6CB501B7-96F6-4EEF-ACB1-D7535F153CF0":
				(
					serviceDescription: "Main service",
					isAdvertisingService: true,
					serviceCharacteristics: [
						"CCID_PC_To_RDR": "91ACE9FD-EDD6-40B1-BA77-050A78CF9BC0",
						"CCID_RDR_To_PC": "94EDE62E-0808-46F8-91EC-AC0272D67796",
						"CCID_Status": "7C334BC2-1812-4C7E-A81D-591F92933C37"
					])]
	}
	
	internal static func getPuckUnbondedServices() -> [String: (serviceDescription: String, isAdvertisingService: Bool, serviceCharacteristics: [String: String])] {
		return  [
			"F91C914F-367C-4108-AC3E-3D30CFDD0A1A":	// Service lu
				(
					serviceDescription: "Main service",
					isAdvertisingService: true,
					serviceCharacteristics:	[
						"CCID_PC_To_RDR": "281EBED4-86C4-4253-84F1-57FB9AB2F72C",
						"CCID_RDR_To_PC": "811DC7A6-A573-4E15-89CC-7EFACAE04E3C",
						"CCID_Status": "EAB75CAB-C7DC-4DB9-874C-4AD8EE0F180F"
			])]
	}
	
	internal static func getPuckBondedServices() -> [String: (serviceDescription: String, isAdvertisingService: Bool, serviceCharacteristics: [String: String])] {
		return [
			"7F20CDC5-A9FC-4C70-9292-3ACF9DE71F73":
				(
					serviceDescription: "Main service",
					isAdvertisingService: true,
					serviceCharacteristics:	[
						"CCID_PC_To_RDR": "CD5BCE75-65FC-4747-AB9A-FF82BFDFA7FB",
						"CCID_RDR_To_PC": "94EDE62E-0808-46F8-91EC-AC0272D67796",
						"CCID_Status": "DC2AA4CA-76A9-43F9-9FE5-127652837EF5"
				])]
	}
	
	internal static func getCharacteristicIdFromName(services: [BleService], searchedCharacteristicName: String) -> CBUUID {
		for service in services {
			for (descrition, uuid) in service.getCharacteristics() {
				if descrition.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == searchedCharacteristicName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
					return uuid
				}
			}
		}
		return CBUUID(string: "")
	}
	
	internal static func hasDeviceAllServices(expectedServices: [BleService], readServices:[CBService], errorMessage: inout String) -> Bool {
		errorMessage = ""

		if readServices.count < expectedServices.count  {
			errorMessage = "Expected services count is different from services read"
			return false
		}
		var servicesFound = 0
		for expectedService in expectedServices {
			for readService in readServices {
				if readService.uuid == expectedService.getServiceId() {
					servicesFound += 1
				}
			}
		}
		
		if servicesFound < expectedServices.count {
			errorMessage = "All required services were not found"
			return false
		} else {
			return true;
		}
	}
}
