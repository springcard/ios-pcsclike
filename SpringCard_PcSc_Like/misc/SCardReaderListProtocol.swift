/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation

/**
All the protocols to implement in the client app

- Version 1.0
- Author: [SpringCard](https://www.springcard.com)
- Copyright: [SpringCard](https://www.springcard.com)
*/
public protocol SCardReaderListDelegate {
	
	/// When the SCardReaderListe.create() methods finished its job, this method is called
	///
	/// - Parameters:
	///		- readers: in case of success an instance of an object of type `SCardReaderList`
	///   	- error: In case of problem this parameter is not nil and contains an error code and message
	/// - Remark: In the callback, the first thing to do is to validate that the error parameter is not nil
	func onReaderListDidCreate(readers: SCardReaderList?, error: Error?)
	
	/// When a deconnection from the current connected device is asked or when the device itself disconnect
	///
	/// - Parameters:
	/// 	- readers: Object of type `SCardReaderList`
	/// 	- error: In case of problem this parameter is not nil and contains an error code and message
	func onReaderListDidClose(readers: SCardReaderList?, error: Error?)
	
	/// When a response is received after a call to `SCardReaderList.control()`
	///
	/// - Parameters:
	///   - readers: Object of type `SCardReaderList`
	///   - response: a byte array if everything went well or nil in cas of problem.
	///   - error: In case of problem this parameter is not nil and contains an error code and message
	func onControlDidResponse(readers: SCardReaderList?, response: [UInt8]?, error: Error?)
	
	/// When a card is inserted into, or removed from an active reader
	///
	/// - Parameters:
	/// 	- reader: Object of type `SCardReader`
	///		- present: Is the card present?
	///		- powered: Is the card powered?
	/// 	- error: In case of problem this parameter is not nil and contains an error code and message
	func onReaderStatus(reader: SCardReader?, present: Bool?, powered: Bool?, error: Error?)
	
	/// When a R-APDU is received after a call to `SCardChannel.transmit()`
	///
	/// - Parameters:
	///   - channel: The channel that sent the C-APUD (object of type `SCardChannel`), can be nil in case of error
	///   - response: a byte array if everything went well or nil in case of problem
	///	  - error:  In case of problem this parameter is not nil and contains an error code and message
	func onTransmitDidResponse(channel: SCardChannel?, response: [UInt8]?, error: Error?)
	
	/// Used to give the result of a `SCardReader.cardConnect()`
	///
	/// - Parameters:
	///   - channel: Object of type `SCardChannel` or nil in case of problem
	///   - error: In case of problem this parameter is not nil and contains an error code and message
	func onCardDidConnect(channel: SCardChannel?, error: Error?)
	
	/// Callback used for giving the result of a channel.cardDisconnect()
	///
	/// - Parameters:
	///   - channel: Object of type `SCardChannel` or nil in case of problem
	///   - error: In case of problem this parameter is not nil and contains an error code and message
	func onCardDidDisconnect(channel: SCardChannel?, error: Error?)
    
    func onData(characteristicId: String, direction: String, data: [UInt8]?)
}
