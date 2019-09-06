/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation
import os.log

class SClass {
    
    internal var errorCode: SCardErrorCode = .noError
    internal var errorMessage = ""

    internal func setInternalError(code: SCardErrorCode, message: String) {
        self.errorCode = code
        self.errorMessage = message
    }
}

