/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation

/**
List of the error codes generated by the library

- Version 1.0
- Author: [SpringCard](https://www.springcard.com)
- Copyright: [SpringCard](https://www.springcard.com)
*/
public enum SCardErrorCode: Int {
	case noError = 0x999,
	invalidParameter = 0x1000,
	missingCharacteristic = 0x1001,
	invalidCharacteristicSetting = 0x1002,
	missingService = 0x1003,
	busy = 0x1004,
	unsupportedPrimaryService = 0x1005,
	dummyDevice = 0x1006,
	otherError = 0x1007,
	cardAbsent = 0x1008,
	cardCommunicationError = 0x1009,
	cardPoweredDown = 0x1010,
	cardRemoved = 0x1011,
	authenticationError = 0x1012,
	secureCommunicationError = 0x1013,
	secureCommunicationAborted = 0x1014,
	noSuchSlot = 0x1015,
    deviceNotConnected = 0x1016
}
