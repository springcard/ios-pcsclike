/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */

// Contains all services (and characteristics) common to all devices
import Foundation
import CoreBluetooth
import os.log

/// :nodoc:
internal class CommonServices
{
	internal static func getCommonServices() -> [BleService] {
		var commonServices: [BleService] = []
		
		// Generic Access Profile
		commonServices.append(
			BleService(
				serviceId: "1800",
				serviceDescription: "org.bluetooth.service.generic_access",
				isAdvertisingService: false,
				serviceCharacteristics:	[
					"org.bluetooth.characteristic.gap.device_name": "2A00",
					"org.bluetooth.characteristic.gap.appearance": "2A01"
				]))
		
		// Service changed
		commonServices.append(
			BleService(
				serviceId: "1801",
				serviceDescription: "org.bluetooth.service.generic_attribute",
				isAdvertisingService: false,
				serviceCharacteristics:	[
					"org.bluetooth.characteristic.gatt.service_changed": "2A05"
				]))
		
		// Device Information
		commonServices.append(
			BleService(
				serviceId: "180A",
				serviceDescription: "org.bluetooth.service.device_information",
				isAdvertisingService: false,
				serviceCharacteristics:	[
					"org.bluetooth.characteristic.model_number_string"      : "2A24",
					"org.bluetooth.characteristic.serial_number_string"     : "2A25",
					"org.bluetooth.characteristic.firmware_revision_string" : "2A26",
					"org.bluetooth.characteristic.hardware_revision_string" : "2A27",
					"org.bluetooth.characteristic.software_revision_string" : "2A28",
					"org.bluetooth.characteristic.manufacturer_name_string" : "2A29",
					"org.bluetooth.characteristic.pnp_id"                   : "2A50"
				]))
		
		// Tx Power
		commonServices.append(
			BleService(
				serviceId: "1804",
				serviceDescription: "org.bluetooth.characteristic.tx_power",
				isAdvertisingService: false,
				serviceCharacteristics: [
					"org.bluetooth.characteristic.tx_power_level"      : "2A07"
				]))
		
		// Battery level
		commonServices.append(
			BleService(
				serviceId: "180F",
				serviceDescription: "org.bluetooth.service.battery",
				isAdvertisingService: false,
				serviceCharacteristics: [
					"org.bluetooth.characteristic.battery_level"      	: "2A19",
                    "org.bluetooth.characteristic.battery_power_state"	: "2A1A"
				]))
		return commonServices
	}
	
	internal static func isCommonService(_ serviceId: CBUUID) -> Bool {
		let commonServices = CommonServices.getCommonServices()
		for service in commonServices {
			if service.getServiceId() == serviceId {
				return true
			}
		}
		return false
	}
	
	internal static func isCommonCharacteristic(commonServices: [BleService], characteristicId: CBUUID) -> Bool {
		for service in commonServices {
			for characteristic in service.getCharacteristicsUuids() {
				if characteristic == characteristicId {
					return true
				}
			}
		}
		return false
	}
    
    internal static func getServiceCharacteristicsUuids(serviceUuid: CBUUID) -> [CBUUID] {
        let services = CommonServices.getCommonServices()
        for service in services {
            if service.getServiceId() == serviceUuid {
                return service.getCharacteristicsUuids()
            }
        }
        return []
    }
}
