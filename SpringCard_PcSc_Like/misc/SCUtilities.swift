/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation
import CoreBluetooth
import os.log
typealias Byte = UInt8

/// :nodoc:
extension Collection where Element == Byte {
	var data: Data {
		return Data(self)
	}
    
	var hexa: String {
		return map{ String(format: "%02X", $0) }.joined()
	}
    
    func hexa(length: Int) -> String {
        let result = String(map{ String(format: "%02X", $0) }.joined())
        let startIndex = result.index(result.startIndex, offsetBy: 0)
        let endIndex = result.index(result.startIndex, offsetBy: Int(length * 2))
        let range = startIndex ..< endIndex
        return String(result[range])
        
    }
}

/// :nodoc:
internal class SCUtilities {
	
	private static let cipherBitPosition = 7
	
	internal static func bytesToString(_ characteristic: CBCharacteristic) -> String {
		if characteristic.value != nil {
			let bytes = [Byte](characteristic.value!)
			if let string = String(bytes: bytes, encoding: .utf8) {
				return string
			} else {
				return ""
			}
		}
		return ""
	}
	
	internal static func getSlotNameFromBytes(_ bytes: [UInt8]) -> String? {
		if bytes.isEmpty {
			return nil
		}
		if bytes[0] != 0x00 {
			return nil
		}
		if let string = String(bytes: bytes[1...], encoding: .utf8) {
			return string
		} else {
			return nil
		}
	}
	
	internal static func byteToInt(_ characteristic: CBCharacteristic) -> Int {
		if characteristic.value != nil {
			let bytes = [Byte](characteristic.value!)
			if bytes.count > 0 {
				return Int(bytes[0])
			} else {
				return 0
			}
		}
		return 0
	}
	
	internal static func bytesToHex(_ characteristic: CBCharacteristic) -> String {
		if characteristic.value != nil {
			let bytes = [Byte](characteristic.value!)
			return bytes.hexa
		}
		return ""
	}
	
	internal static func getRawBytesFromCharacteristic(_ characteristic: CBCharacteristic) -> [UInt8]? {
		if characteristic.value != nil {
			return [Byte](characteristic.value!)
		}
		return nil
	}
	
	internal static func toByteArray(value: UInt32, secureCommunication: Bool) -> [Byte] {
		var byteArray: [Byte] = [0x00, 0x00, 0x00, 0x00]
		byteArray[0] = Byte(value & 0xFF)
		byteArray[1] = Byte(value >> 8 & 0xFF)
		byteArray[2] = Byte(value >> 16 & 0xFF)
		byteArray[3] = Byte(value >> 24)
		if secureCommunication {
			byteArray[3] = byteArray[3] | (1 << cipherBitPosition)
		} else {
			byteArray[3] &= ~(1 << cipherBitPosition)
		}
		return byteArray
	}
	
	internal static func fromByteArray(byteArray: [Byte], secureCommunication: Bool) -> UInt32 {
		var bytes = byteArray
		if secureCommunication {
			bytes[3] &= ~(1 << cipherBitPosition)
		}
		bytes = bytes.reversed()
		let data = Data(bytes)
		let value = UInt32(bigEndian: data.withUnsafeBytes { $0.pointee })
		return value
	}
	
}
