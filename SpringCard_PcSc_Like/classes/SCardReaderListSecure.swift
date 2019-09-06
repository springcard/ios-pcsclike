/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation
import CoreBluetooth
import os.log
import CryptoSwift

internal class SCardReaderListSecure : SClass {
   
    internal var secureConnectionParameters: SecureConnectionParameters!
    internal var isSecureCommunication = false
    
    internal var debugSecureCommunication = true
    private let protocolCode: UInt8 = 0x00
    
    private var sessionEncKey: [UInt8] = []
    private var sessionMacKey: [UInt8] = []
    private var sessionSendIV: [UInt8] = []
    private var sessionRecvIV: [UInt8] = []
    
    private var rndA: [UInt8] = []
    private var rndB: [UInt8] = []
    
    private let versionMode: UInt8 = 0x01
    private let expectedLength = 17
    
    // *****************************************
    // * Pubic methods (accessible to the lib) *
    // *****************************************

    init(secureConnectionParameters: SecureConnectionParameters) {
        #if DEBUG
        os_log("SCardReaderListSecure:init()", log: OSLog.libLog, type: .info)
        #endif
        self.secureConnectionParameters = secureConnectionParameters
        self.debugSecureCommunication = secureConnectionParameters.debugSecureCommunication
            if secureConnectionParameters.commMode != .plain {
                self.isSecureCommunication = true
        }
    }

    // to be called to initiate secure communication according to parameters
    internal func getAuthenticationCommand() -> [UInt8]? {
        #if DEBUG
        os_log("SCardReaderListSecure:getAuthenticationCommand()", log: OSLog.libLog, type: .info)
        #endif
        switch self.secureConnectionParameters.authMode {
        case .none:
            return [UInt8]()
            
        case .Aes128:
            return getAuthenticationCommandForAes128(self.secureConnectionParameters.keyIndex.rawValue, self.secureConnectionParameters.keyValue)
        }
    }
    
    // To be called after sending the authenticate command
    internal func getAesAuthenticationResponseForStep1(responsePayload: [UInt8]) -> [UInt8]? {
        #if DEBUG
        os_log("SCardReaderListSecure:getAesAuthenticationResponseForStep1()", log: OSLog.libLog, type: .info)
        #endif
        switch self.secureConnectionParameters.authMode {
        case .none:
            return [UInt8]()
            
        case .Aes128:
        	return aesAuthenticationStep1(responseStep1: responsePayload, keySelect: self.secureConnectionParameters.keyIndex.rawValue, keyValue: self.secureConnectionParameters.keyValue)
        }
    }

    internal func getAesAuthenticationResponseForStep2(responsePayload: [UInt8]) -> Bool {
        #if DEBUG
        os_log("SCardReaderListSecure:getAesAuthenticationResponseForStep2()", log: OSLog.libLog, type: .info)
        #endif
        switch self.secureConnectionParameters.authMode {
        case .none:
            return true
            
        case .Aes128:
            return aesAuthenticationStep2(responseStep2: responsePayload, keySelect: self.secureConnectionParameters.keyIndex.rawValue, keyValue: self.secureConnectionParameters.keyValue)
        }
    }

    internal func decryptCcidBuffer(_ ccidBuffer: [UInt8], payloadLength: inout UInt32) -> [UInt8]? {
        #if DEBUG
        os_log("SCardReaderListSecure:decryptCcidBuffer()", log: OSLog.libLog, type: .info)
        #endif
        if ccidBuffer.isEmpty || ccidBuffer.count < 18 {
            setInternalError(code: .secureCommunicationError, message: "Invalid ccid_buffer size")
            return nil
        }
        
        var ccid_buffer = ccidBuffer
        let received_cmac = BinUtils.copy(ccid_buffer, -8)
        ccid_buffer = BinUtils.copy(ccid_buffer, 0, -8) // remove CMAC
        
        /* Extract the data */
        var data = BinUtils.copy(ccid_buffer, 10); // remove header
        
        if (self.debugSecureCommunication) {
            os_log("   >     (crypted data) %s", log: OSLog.libLog, type: .debug, data.hexa)
        }
        
        /* Decipher the data */
        guard let _data = aesCbcDecrypt(sessionEncKey, sessionRecvIV, data) else {
            setInternalError(code: .secureCommunicationError, message: "aesCbcDecrypt returned nil")
            return nil
        }
        
        data = _data
        if (self.debugSecureCommunication) {
            os_log("   >     (padded data) %s", log: OSLog.libLog, type: .debug, data.hexa)
        }
        
        var data_len: Int = data.count
        while ((data_len > 0) && (data[data_len - 1] == 0x00)) {
            data_len -= 1
        }
        
        if ((data_len == 0) || (data[data_len - 1] != 0x80)) {
            setInternalError(code: .secureCommunicationError, message: "Padding is invalid (decryption failed/wrong session key?)")
            return nil
        }
        data_len -= 1
        data = BinUtils.copy(data, 0, data_len)
        
        if (self.debugSecureCommunication) {
            os_log("   >       (plain data) %s", log: OSLog.libLog, type: .debug, data.hexa)
        }
        
        /* Extract the header and re-create a valid buffer */
        ccid_buffer = BinUtils.copy(ccid_buffer, 0, 10)
        
        payloadLength = UInt32(data.count)
        PC_to_RDR_SetLength(&ccid_buffer, payloadLength, false)
        ccid_buffer = BinUtils.concat(ccid_buffer, data)
        
        /* Compute the CMAC */
        let computed_cmac:[UInt8] = computeCmac(sessionMacKey, sessionRecvIV, ccid_buffer)
        
        if (self.debugSecureCommunication) {
            os_log("   >{%s} -> CMAC={%s}", log: OSLog.libLog, type: .debug, ccid_buffer.hexa, computed_cmac.hexa(length: 8))
        }
        
        if (!BinUtils.equals(received_cmac, computed_cmac, 8)) {
            setInternalError(code: .secureCommunicationError, message: "CMAC is invalid (wrong session key?)")
            return nil
        }
        
        sessionRecvIV = computed_cmac
        return ccid_buffer
    }
    
    // ccidBuffer must contains the header
    internal func encryptCcidBuffer(_ ccidBuffer:[UInt8], payloadLength: inout UInt32) -> [UInt8]? {
        #if DEBUG
        os_log("SCardReaderListSecure:encryptCcidBuffer()", log: OSLog.libLog, type: .info)
        #endif
        var ccid_buffer = ccidBuffer
        
        /* Compute the CMAC of the plain buffer */
        let cmac: [UInt8] = computeCmac(sessionMacKey, sessionSendIV, ccid_buffer)
        
        if self.debugSecureCommunication {
            os_log("   <%s -> CMAC=%s", log: OSLog.libLog, type: .debug, ccid_buffer.hexa, cmac.hexa(length: 8))
        }
        
        /* Extract the data */
        var data: [UInt8] = BinUtils.copy(ccid_buffer, 10)
        
        if self.debugSecureCommunication {
            os_log("   <       (plain data) %s", log: OSLog.libLog, type: .debug, data.hexa)
        }
        
        /* Cipher the data */
        data = BinUtils.concat(data, 0x80)
        while ((data.count % 16) != 0) {
            data = BinUtils.concat(data, 0x00)
        }
        
        if self.debugSecureCommunication {
            os_log("   <      (padded data) %s", log: OSLog.libLog, type: .debug, data.hexa)
        }
        
        guard let _data = aesCbcEncrypt(sessionEncKey, sessionSendIV, data) else {
            setInternalError(code: .secureCommunicationError, message: "aesCbcEncrypt returned nil")
            return nil
        }
        
        data = _data
        if self.debugSecureCommunication {
            os_log("   <     (crypted data) %s", log: OSLog.libLog, type: .debug, data.hexa)
        }
        
        /* Re-create the buffer */
        ccid_buffer = BinUtils.copy(ccid_buffer, 0, 10)	// Get the original header
        ccid_buffer = BinUtils.concat(ccid_buffer, data)	// Append cyphered data
        ccid_buffer = BinUtils.concat(ccid_buffer, BinUtils.copy(cmac, 0, 8)) // Apppend CMAC
        
        /* Update the length */
        payloadLength = UInt32(data.count + 8)
        PC_to_RDR_SetLength(&ccid_buffer, payloadLength, true)
        sessionSendIV = cmac
        return ccid_buffer
    }
    
    
    // *******************
    // * private methods *
    // *******************
    
    private func PC_to_RDR_SetLength(_ buffer: inout [UInt8], _ dataLength: UInt32, _ secure: Bool) {
        #if DEBUG
        os_log("SCardReaderListSecure:PC_to_RDR_SetLength()", log: OSLog.libLog, type: .info)
        #endif
        buffer[1] = (UInt8)(dataLength & 0x0FF)
        buffer[2] = (UInt8)((dataLength >> 8) & 0x0FF)
        buffer[3] = (UInt8)((dataLength >> 16) & 0x0FF)
        buffer[4] = 0
        if (secure) {
            buffer[4] |= 0x80
        }
    }
    
    private func getRandom(_ length: Int) -> [UInt8] {
        #if DEBUG
        os_log("SCardReaderListSecure:getRandom()", log: OSLog.libLog, type: .info)
        #endif
        var result = [UInt8](repeating: 0x00, count: length)
        if self.debugSecureCommunication {
            for i in 0 ..< length {
                result[i] = (UInt8)(0xA0 | (i & 0x0F))
            }
        } else {
            _ = SecRandomCopyBytes(kSecRandomDefault, length, &result)
        }
        return result
    }
    
    private func computeCmac(_ key: [UInt8], _ iv: [UInt8]?, _ buffer: [UInt8]) -> [UInt8] {
        #if DEBUG
        os_log("SCardReaderListSecure:computeCmac()", log: OSLog.libLog, type: .info)
        #endif
        var cmac = [UInt8]()
        var actual_length = 0
        
        if (iv != nil && (iv?.count)! > 0) {
            cmac = iv!
        } else {
            cmac = [UInt8](repeating: 0x00, count: 16)
        }
        
        actual_length = buffer.count + 1
        while ((actual_length % 16) != 0) {
            actual_length += 1
        }
        
        for i in stride(from: 0, to: actual_length, by: 16) {
            var block = [UInt8](repeating: 0x00, count: 16)
        
            for j in 0 ..< 16 {
                if ((i + j) < buffer.count) {
                    block[j] = buffer[i + j]
                } else if ((i + j) == buffer.count) {
                    block[j] = 0x80
                } else {
                    block[j] = 0x00
                }
            }
            
            if self.debugSecureCommunication {
                os_log("        Block=%s, IV=%s", log: OSLog.libLog, type: .debug, block.hexa, cmac.hexa)
            }
            
            for j in 0 ..< 16 {
                block[j] ^= cmac[j]
            }

            guard let _cmac = aesEcbEncrypt(key, block) else {
                setInternalError(code: .secureCommunicationError, message: "aesEcbEncrypt returned a nil cmac")
                return [UInt8]()
            }
            
            cmac = _cmac
            if self.debugSecureCommunication {
                os_log("                -> %s", log: OSLog.libLog, type: .debug, cmac.hexa)
            }
        }
        return cmac
    }
    
    private func aesCbcEncrypt(_ key: [UInt8], _ IV: [UInt8]?, _ buffer: [UInt8]) -> [UInt8]? {
        #if DEBUG
        os_log("SCardReaderListSecure:aesCbcEncrypt()", log: OSLog.libLog, type: .info)
        #endif
        let iv = (IV == nil) ? [UInt8](repeating: 0x00, count: 16) : IV
        do {
            let result = try AES(key: key, blockMode: CBC(iv: iv!), padding: .noPadding).encrypt(buffer)
            return result
        } catch {
            setInternalError(code: .secureCommunicationError, message: error.localizedDescription)
            return nil
        }
    }
    
    private func aesCbcDecrypt(_ key: [UInt8], _ IV: [UInt8]?, _ buffer: [UInt8]) -> [UInt8]? {
        #if DEBUG
        os_log("SCardReaderListSecure:aesCbcDecrypt()", log: OSLog.libLog, type: .info)
        #endif
        let iv = (IV == nil) ? [UInt8](repeating: 0x00, count: 16) : IV
        do {
            let result = try AES(key: key, blockMode: CBC(iv: iv!), padding: .noPadding).decrypt(buffer)
            return result
        } catch {
            setInternalError(code: .secureCommunicationError, message: error.localizedDescription)
            return nil
        }
    }
    
    private func aesEcbEncrypt(_ key: [UInt8], _ buffer: [UInt8]) -> [UInt8]? {
        #if DEBUG
        os_log("SCardReaderListSecure:aesEcbEncrypt()", log: OSLog.libLog, type: .info)
        #endif
        let iv = [UInt8](repeating: 0x00, count: 16)
        do {
            let result = try AES(key: key, blockMode: CBC(iv: iv), padding: .noPadding).encrypt(buffer)
            return Array(result.prefix(16))
        } catch {
            setInternalError(code: .secureCommunicationError, message: error.localizedDescription)
            return nil
        }
    }
    
    private func aesEcbDecrypt(_ key: [UInt8], _ buffer: [UInt8]) -> [UInt8]? {
        #if DEBUG
        os_log("SCardReaderListSecure:aesEcbDecrypt()", log: OSLog.libLog, type: .info)
        #endif
        let iv = [UInt8](repeating: 0x00, count: 16)
        do {
            let result = try AES(key: key, blockMode: CBC(iv: iv), padding: .noPadding).decrypt(buffer)
            return result
        } catch {
            setInternalError(code: .secureCommunicationError, message: error.localizedDescription)
            return nil
        }
    }
    
    internal func cleanupAuthentication() {
        #if DEBUG
        os_log("SCardReaderListSecure:cleanupAuthentication()", log: OSLog.libLog, type: .info)
        #endif
        sessionEncKey = []
        sessionMacKey = []
        sessionSendIV = []
        sessionRecvIV = []
        rndA = []
        rndB = []
    }

    private func getAuthenticationCommandForAes128(_ keySelect: UInt8, _ keyValue: [UInt8]) -> [UInt8]? {
        #if DEBUG
        os_log("SCardReaderListSecure:getAuthenticationCommandForAes128()", log: OSLog.libLog, type: .info)
        #endif
        
        cleanupAuthentication()
        #if DEBUG
        os_log("Running AES mutual authentication using key %02d", log: OSLog.libLog, type: .debug, keySelect)
        #endif
        
        /* Generate host nonce */
        self.rndA = self.getRandom(16)

        if self.debugSecureCommunication {
            os_log("key=%s", log: OSLog.libLog, type: .debug, keyValue.hexa)
            os_log("rndA=%s", log: OSLog.libLog, type: .debug, rndA.hexa)
        }
        
        /* Host->Device AUTHENTICATE command */
        /* --------------------------------- */
        
        var cmdAuthenticate = [UInt8](repeating: 0x00, count: 4)
        
        cmdAuthenticate[0] = self.protocolCode
        cmdAuthenticate[1] = ProtocolOpcode.authenticate.rawValue
        cmdAuthenticate[2] = self.versionMode /* Version & mode = AES128 */
        cmdAuthenticate[3] = keySelect
        
        if self.debugSecureCommunication {
            os_log("   <                    %s", log: OSLog.libLog, type: .debug, cmdAuthenticate.hexa)
        }
        
        return cmdAuthenticate
    }
    
    // It's up to the caller to verify that the response (code) is valid
    private func aesAuthenticationStep1(responseStep1: [UInt8], keySelect: UInt8, keyValue: [UInt8]) -> [UInt8]? {
        #if DEBUG
        os_log("SCardReaderListSecure:aesAuthenticationStep1()", log: OSLog.libLog, type: .info)
        #endif
        
        if self.debugSecureCommunication {
            os_log("   Response from reader:", log: OSLog.libLog, type: .debug)
            os_log("   >                    %s", log: OSLog.libLog, type: .debug, responseStep1.hexa)
        }
        
        /* Device->Host Authentication Step 1 */
        /* ---------------------------------- */
        
        if (responseStep1.isEmpty || responseStep1.count < 1) {
            setInternalError(code: .authenticationError, message: "Authentication failed at step 1 (response is too short)")
            return nil
        }
        
        // 1 au lieu de 0 ?
        if responseStep1[0] != ProtocolOpcode.following.rawValue {
            setInternalError(code: .authenticationError, message: "Authentication failed at step 1, the device has reported an error: " + String(responseStep1[0]))
            return nil
        }
        
        if (responseStep1.count != expectedLength) {
            setInternalError(code: .authenticationError, message: "Authentication failed at step 1 (response does not have the expected format)")
            return nil
        }
        
        var t = BinUtils.copy(responseStep1, 1, 16)
        guard let rndB = aesEcbDecrypt(keyValue, t) else {
            setInternalError(code: .authenticationError, message: "rndB is nil")
            return nil
        }
        self.rndB = rndB
        
        if self.debugSecureCommunication {
            os_log("rndB=%s", log: OSLog.libLog, type: .debug, rndB.hexa)
        }
        
        /* Host->Device Authentication Step 2 */
        /* ---------------------------------- */
        
        var cmdStep2 = [UInt8](repeating: 0x00, count: 34)
        
        cmdStep2[0] = protocolCode
        cmdStep2[1] = ProtocolOpcode.following.rawValue
        
        guard let _t = aesEcbEncrypt(keyValue, rndA) else {
            setInternalError(code: .secureCommunicationError, message: "aesEcbEncrypt returned nil for keyValue, rndA")
            return nil
        }
        
        t = _t
        BinUtils.copyTo(&cmdStep2, 2, t, 0, 16)
        t = BinUtils.rotateLeftOneByte(rndB)
        
        guard let _t2 = aesEcbEncrypt(keyValue, t) else {
            setInternalError(code: .secureCommunicationError, message: "aesEcbEncrypt returned nil for keyValue, t")
            return nil
        }
        
        t = _t2
        BinUtils.copyTo(&cmdStep2, 18, t, 0, 16)
        
        if self.debugSecureCommunication {
            os_log("   < Response sent to the reader:", log: OSLog.libLog, type: .debug)
            os_log("   <                    %s", log: OSLog.libLog, type: .debug, cmdStep2.hexa)
        }
        
        return cmdStep2
    }
    
    // It's up to the caller to verify that the response (code) is valid
    private func aesAuthenticationStep2(responseStep2 rspStep3: [UInt8], keySelect: UInt8, keyValue: [UInt8]) -> Bool {
        #if DEBUG
        os_log("SCardReaderListSecure:aesAuthenticationStep2()", log: OSLog.libLog, type: .info)
        #endif
        
        if self.debugSecureCommunication {
            os_log("   >                    %s", log: OSLog.libLog, type: .debug, rspStep3.hexa)
        }
        
        /* Device->Host Authentication Step 3 */
        /* ---------------------------------- */
        
        if (rspStep3.isEmpty || rspStep3.count < 1) {
            setInternalError(code: .authenticationError, message: "Authentication failed at step 3")
            return false
        }
        
        if (rspStep3[0] != ProtocolOpcode.success.rawValue) {
            setInternalError(code: .authenticationError, message: "Authentication failed at step 3, the device has reported an error: " + String(rspStep3[0]))
            return false
        }
        
        if (rspStep3.count != expectedLength) {
            setInternalError(code: .authenticationError, message: "Authentication failed at step 3 (response does not have the expected format)")
            return false
        }
        
        var t = BinUtils.copy(rspStep3, 1, 16)
        guard let _t4 = aesEcbDecrypt(keyValue, t) else {
            setInternalError(code: .secureCommunicationError, message: "aesEcbDecrypt returned nil for keyValue, t")
            return false
        }
        
        t = _t4
        t = BinUtils.rotateRightOneByte(t)
        
        if (!BinUtils.equals(t, rndA)) {
            #if DEBUG
            os_log("%s!=%s", log: OSLog.libLog, type: .debug, t.hexa, rndA.hexa)
            #endif
            setInternalError(code: .authenticationError, message:  "Authentication failed at step 3 (device's cryptogram is invalid)")
            return false
        }
        
        /* Session keys and first init vector */
        /* ---------------------------------- */
        
        var sv1:[UInt8] = [UInt8](repeating: 0x00, count: 16)
        BinUtils.copyTo(&sv1, 0, rndA, 0, 4)
        BinUtils.copyTo(&sv1, 4, rndB, 0, 4)
        BinUtils.copyTo(&sv1, 8, rndA, 8, 4)
        BinUtils.copyTo(&sv1, 12, rndB, 8, 4)
        
        if self.debugSecureCommunication {
            os_log("SV1=%s", log: OSLog.libLog, type: .debug, sv1.hexa)
        }
        
        var sv2:[UInt8] = [UInt8](repeating: 0x00, count: 16)
        BinUtils.copyTo(&sv2, 0, rndA, 4, 4)
        BinUtils.copyTo(&sv2, 4, rndB, 4, 4)
        BinUtils.copyTo(&sv2, 8, rndA, 12, 4)
        BinUtils.copyTo(&sv2, 12, rndB, 12, 4)
        
        if self.debugSecureCommunication {
            os_log("SV2=%s", log: OSLog.libLog, type: .debug, sv2.hexa)
        }

        guard let _sessionEncKey = aesEcbEncrypt(keyValue, sv1) else {
            setInternalError(code: .secureCommunicationError, message: "aesEcbEncrypt returned nil for keyValue, sv1")
            return false
        }
        
        self.sessionEncKey = _sessionEncKey
        if self.debugSecureCommunication {
            os_log("Kenc=%s", log: OSLog.libLog, type: .debug, self.sessionEncKey.hexa)
        }
        
        guard let _sessionMacKey = aesEcbEncrypt(keyValue, sv2) else {
            setInternalError(code: .secureCommunicationError, message: "aesEcbEncrypt returned nil for keyValue, sv2")
            return false
        }
        self.sessionMacKey = _sessionMacKey
        
        if self.debugSecureCommunication {
            os_log("Kmac=%s", log: OSLog.libLog, type: .debug, self.sessionMacKey.hexa)
        }
        
        t = BinUtils.XOR(rndA, rndB)
        
        guard let _t5 = aesEcbEncrypt(self.sessionMacKey, t) else {
            setInternalError(code: .secureCommunicationError, message: "aesEcbEncrypt returned nil for sessionMacKey, t")
            return false
        }
        
        t = _t5
        
        if self.debugSecureCommunication {
            os_log("IV0=%s", log: OSLog.libLog, type: .debug, t.hexa)
        }
        
        self.sessionSendIV = t
        self.sessionRecvIV = t
        return true
    }

}
