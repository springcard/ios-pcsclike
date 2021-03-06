/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation
import CoreBluetooth
import os.log

/// :nodoc:
public class SCardReaderList_D600_BLE: SCardReaderList {
	override func setSpecificDeviceServices() {
		self.deviceSpecificServices = DevicesServices.getServices(deviceType: .D600)		
	}
}
