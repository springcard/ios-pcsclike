/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation
import CoreBluetooth
import os.log

/// nodoc:
internal class ScCcidPcToRdrPayload: SClass {

	private var rawContent: [Byte]?
    private var readerListSecure: SCardReaderListSecure?
	
    init(payload: [Byte], readerListSecure: SCardReaderListSecure?) {
        super.init()
		self.rawContent = payload
		self.readerListSecure = readerListSecure
	}
	
	internal func getPayload() -> [Byte]? {
		return self.rawContent
	}
}
