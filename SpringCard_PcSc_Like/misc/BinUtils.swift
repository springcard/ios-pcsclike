/*
 Copyright (c) 2018-2019 SpringCard - www.springcard.com
 All right reserved
 This software is covered by the SpringCard SDK License Agreement - see LICENSE.txt
 */
import Foundation
import os.log

internal class BinUtils {
    
    static func copy(_ array: [UInt8], _ offset: Int = 0, _ length: Int = 0) -> [UInt8] {
        var _offset = offset
        var _length = length
        let _array = array
        
        if _length == 0 {
            if _offset < 0 {
                _length = abs(_offset)
                _offset = array.count - _length
            } else if _offset > 0 {
                _length = array.count - _offset;
            }
        } else if _length < 0 {
            _length = abs(_length)
            _length = array.count - _length - offset
        }
        var r = [UInt8](repeating: 0x00, count: _length)
        r = Array(_array[_offset..<(_length + _offset)])
        return r
    }
    
    static func concat(_ arrayA: [UInt8], _ arrayB: [UInt8]) -> [UInt8] {
        return arrayA + arrayB
    }
    
    static func concat(_ array: [UInt8], _ byte: UInt8) -> [UInt8] {
        var newArray = array
        newArray.append(byte)
        return newArray
    }
    
    static func equals(_ arrayA: [UInt8]?, _ arrayB: [UInt8]?, _ length: Int) -> Bool {
        if (arrayA == nil) && (arrayB == nil) {
            return true
        }
        if (arrayA == nil) || (arrayB == nil) {
            return false
        }

        guard let _arrayA = arrayA else {
            return false
        }
        guard let _arrayB = arrayB else {
            return false
        }
        for i in 0 ..< length {
            if _arrayA.count < i {
                return false
            }
            if _arrayB.count < i {
                return false
            }
            if _arrayA[i] != _arrayB[i] {
                return false
            }
        }
        return true
    }
    
    static func equals(_ arrayA: [UInt8]?, _ arrayB: [UInt8]?) -> Bool {
        if (arrayA == nil) && (arrayB == nil) {
            return true
        }
        if (arrayA == nil) || (arrayB == nil) {
            return false
        }
        
        guard let _arrayA = arrayA else {
            return false
        }
        guard let _arrayB = arrayB else {
            return false
        }
        
        if _arrayA.count != _arrayB.count {
            return false
        }
        
        for i in 0 ..< _arrayA.count {
            if _arrayA[i] != _arrayB[i] {
                return false
            }
        }
        return true
    }
    
    static func copyTo(_ destination: inout [UInt8], _ destinationOffset: Int = 0, _ source: [UInt8], _ sourceOffset: Int, _ length: Int) {
        let lastIndex = (sourceOffset + length)
        
        if destinationOffset < 0 || source.isEmpty || sourceOffset < 0 || sourceOffset >= source.count || length < 0 {
            #if DEBUG
            os_log("BinUtils:copyTo(), problem with passed parameters", log: OSLog.libLog, type: .error)
            #endif
            return
        }
        
        if lastIndex > source.count {
            #if DEBUG
            os_log("BinUtils:copyTo(), sourceOffset + length is out of bounds", log: OSLog.libLog, type: .error)
            #endif
            return
        }
        
        let _source = Array(source[sourceOffset ..< lastIndex])
        let missingBytes = _source.count - (destination.count - destinationOffset)
        
        if missingBytes > 0 {
            for _ in 0 ..< missingBytes {
                destination.append(0x00)
            }
        }
        
        var cpt = 0
        let end = (destinationOffset + length)
        if end < destinationOffset {
            #if DEBUG
            os_log("BinUtils:copyTo(), end index is lower than start index", log: OSLog.libLog, type: .error)
            #endif
            return
        }
        for i in destinationOffset ..< end {
            destination[i] = _source[cpt]
            cpt += 1
        }
    }
    
    static func rotateLeftOneByte(_ buffer: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0x00, count: buffer.count)
        for i in 1 ..< buffer.count {
            result[i-1] = buffer[i]
        }
        result[buffer.count - 1] = buffer[0];
        return result
    }
    
    static func rotateRightOneByte(_ buffer: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0x00, count: buffer.count)
        for i in (1..<buffer.count).reversed() {
            result[i] = buffer[i - 1];
        }
        result[0] = buffer[buffer.count - 1];
        return result
    }
    
    static func XOR(_ arrayA: [UInt8], _ arrayB: [UInt8]) -> [UInt8] {
        let length1 = arrayA.count
        let length2 = arrayB.count
        
        var length = 0
        if (length1 == length2) {
            length = length1;
        } else if (length1 > length2) {
            length = length2;
        } else if (length2 > length1) {
            length = length1;
        }
        var result = [UInt8](repeating: 0x00, count: length)
        for i in 0 ..< length {
            var b1: UInt8 = 0x00
            var b2: UInt8 = 0x00
            if (i < length1) {
                b1 = arrayA[i]
            }
            
            if (i < length2) {
                b2 = arrayB[i];
            }
            result[i] = UInt8(b1 ^ b2);
        }
        return result
    }
}
