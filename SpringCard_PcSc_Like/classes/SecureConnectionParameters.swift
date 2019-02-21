/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation

/// Parameters used to describe a secure connection
public struct SecureConnectionParameters {
    /// Authentication mode
    public var authMode: AuthenticationMode = .Aes128
    public var keyIndex: KeyIndex = .user
    public var keyValue: [UInt8] = []
    public var commMode: CommMode = .secure
    /// To be set to true to actviate debug mode
    public var debugSecureCommunication = true
    
    public init(authMode: AuthenticationMode, keyIndex: KeyIndex, keyValue: [UInt8], commMode: CommMode, debugSecureCommunication: Bool) {
        self.authMode = authMode
        self.keyIndex = keyIndex
        self.keyValue = keyValue
        self.commMode = commMode
        self.debugSecureCommunication = debugSecureCommunication
    }
}
