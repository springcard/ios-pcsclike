/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation
import CoreBluetooth
import os.log

/// :nodoc:
public class SCardReaderList_PUCK_BLE_Unbonded: SCardReaderList {
	public override func isBoundedDevice() -> Bool {
		return false
	}

	public override func setSpecificDeviceServices() {
		self.deviceSpecificServices = DevicesServices.getServices(deviceType: .PUCK_Unbonded)
	}
}
