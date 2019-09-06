/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation

/// :nodoc:
internal enum SCard_CCID_PC_To_RDR: UInt8 {
	case PC_To_RDR_IccPowerOn = 0x62,
	PC_To_RDR_IccPowerOff = 0x63,
	PC_To_RDR_GetSlotStatus = 0x65,
	PC_To_RDR_Escape = 0x6B,
	PC_To_RDR_XfrBlock = 0x6F
}

/// :nodoc:
internal enum CCID_RDR_To_PC_Answer_Codes: UInt8 {
	case RDR_To_PC_DataBlock = 0x80,
	RDR_To_PC_SlotStatus = 0x81,
	RDR_To_PC_Escape = 0x83
}

/// :nodoc:
internal let getSlotsNameApdu: [UInt8] = [0x58, 0x21, 0x00]

/// :nodoc:
internal let shutdownCommand: [UInt8] = [0x58, 0xAF, 0xDE, 0xAD]


/// :nodoc:
internal let BUSY = "Library si busy"

/// :nodoc:
internal enum MachineState: Int {
	case noState,
	isReadingCommonCharacteristicsValues,
	isReadingSlotCount,
	isUnSubsribingToNotifications,
	isReadingSlotsName,
	isGettingReaderStatus,
    isDisconnecting,
	isDisconnected,
    poweringSlots,
	discoveredDeviceWithSuccess,
	discoverFailed,
	isInError,
    initiateMutualAuthentication,
    authenticationStep1
}

/// :nodoc:
internal enum LastCommand: Int {
	case noCommand = 0,
	getStatus,
	cardConnect,
	control,
	transmit,
    cardDisconnect,
    readingBatteryLevel
}

/// :nodoc:
internal enum SlotError: UInt8 {
	case CMD_ABORTED = 0xFF,
	ICC_MUTE = 0xFE,
	XFR_PARITY_ERROR = 0xFD,
	XFR_OVERRUN = 0xFC,
	HW_ERROR = 0xFB,
	BAD_ATR_TS = 0xF8,
	BAD_ATR_TCK = 0xF7,
	ICC_PROTOCOL_NOT_SUPPORTED = 0xF6,
	ICC_CLASS_NOT_SUPPORTED = 0xF5,
	PROCEDURE_BYTE_CONFLICT = 0xF4,
	DEACTIVATED_PROTOCOL = 0xF3,
	BUSY_WITH_AUTO_SEQUENCE = 0xF2,
	CMD_SLOT_BUSY = 0xE0,
	COMMAND_NOT_SUPPORTED = 0x00
}

/// :nodoc:
internal enum CcidResponseCommandStatus: UInt8 {
	case NO_ERROR = 0x00,
	COMMAND_FAILED = 0x01,
	TIME_EXTENSION_REQUESTED = 0x02,
	RFU = 0x03
}

/// :nodoc:
internal enum CcidResponseCardStatus: UInt8 {
	case CARD_PRESENT_AND_ACTIVE = 0x00,
	CARD_PRESENT_AND_INACTIVE = 0x01,
	NO_CARD_PRESENT = 0x02,
	RFU = 0x03
}

/// :nodoc:
internal enum SlotStatusNotification: Byte {
	case cardAbsent = 0b00,
	cardPresent = 0b01,
	cardRemoved = 0b10,
	cardInserted = 0b11
}

/// Key Index
public enum KeyIndex: UInt8 {
    case user = 0x00
    case admin = 0x01
    case none = 0x02
}

/// Communication mode
public enum CommMode: UInt8 {
    case plain = 0x00
    case MACed = 0x01
    case secure = 0x03
}

/// Authentication mode
public enum AuthenticationMode: UInt8 {
    case none = 0x00
    case Aes128 = 0x01
}

internal enum ProtocolOpcode: UInt8 {
    case success = 0x00
    case authenticate = 0x0A
    case following = 0xFF
}

internal enum SCARD: UInt8 {
    case s_success = 0x00
}

internal enum Ins: UInt8 {
    case authenticate = 0x0A
    case following = 0xFF
}

internal enum Class: UInt8 {
    case classProtocol = 0x00
}
