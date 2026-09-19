//
//  MicroZipReader.swift
//  VirtualEspressoMachine
//

import Foundation
import zlib

public final class MicroZipReader {
    public static func extractJSONFiles(from zipURL: URL) -> [String: Data] {
        guard let data = try? Data(contentsOf: zipURL) else { return [:] }
        var results: [String: Data] = [:]
        let count = data.count
        
        guard let eocdOffset = findEOCDOffset(in: data) else { return [:] }
        let totalEntries = Int(readUInt16(from: data, at: eocdOffset + 10))
        var cdOffset = Int(readUInt32(from: data, at: eocdOffset + 16))
        
        for _ in 0..<totalEntries {
            guard cdOffset + 46 <= count else { break }
            let sig = readUInt32(from: data, at: cdOffset)
            guard sig == 0x02014b50 else { break }
            
            let method = readUInt16(from: data, at: cdOffset + 10)
            let compSize = Int(readUInt32(from: data, at: cdOffset + 20))
            let uncompSize = Int(readUInt32(from: data, at: cdOffset + 24))
            let nameLen = Int(readUInt16(from: data, at: cdOffset + 28))
            let extraLen = Int(readUInt16(from: data, at: cdOffset + 30))
            let commentLen = Int(readUInt16(from: data, at: cdOffset + 32))
            let localHeaderOffset = Int(readUInt32(from: data, at: cdOffset + 42))
            
            let nameStart = cdOffset + 46
            if nameStart + nameLen <= count,
               let fileName = String(data: data.subdata(in: nameStart..<nameStart + nameLen), encoding: .utf8) {
                if fileName.lowercased().hasSuffix(".json") {
                    if let fileData = extractEntryData(
                        from: data,
                        localHeaderOffset: localHeaderOffset,
                        method: method,
                        compSize: compSize,
                        uncompSize: uncompSize
                    ) {
                        results[fileName] = fileData
                    }
                }
            }
            cdOffset += 46 + nameLen + extraLen + commentLen
        }
        return results
    }
    
    private static func extractEntryData(
        from data: Data,
        localHeaderOffset: Int,
        method: UInt16,
        compSize: Int,
        uncompSize: Int
    ) -> Data? {
        guard localHeaderOffset + 30 <= data.count else { return nil }
        let localSig = readUInt32(from: data, at: localHeaderOffset)
        guard localSig == 0x04034b50 else { return nil }
        
        let localNameLen = Int(readUInt16(from: data, at: localHeaderOffset + 26))
        let localExtraLen = Int(readUInt16(from: data, at: localHeaderOffset + 28))
        let dataStart = localHeaderOffset + 30 + localNameLen + localExtraLen
        
        guard dataStart + compSize <= data.count else { return nil }
        let compressedData = data.subdata(in: dataStart..<dataStart + compSize)
        
        if method == 0 {
            return compressedData
        } else if method == 8 {
            return decompressRawDeflate(compressedData, uncompressedSize: uncompSize)
        }
        return nil
    }
    
    private static func decompressRawDeflate(_ compressedData: Data, uncompressedSize: Int) -> Data? {
        guard uncompressedSize > 0 else { return Data() }
        var decompressedData = Data(count: uncompressedSize)
        var stream = z_stream()
        let initStatus = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { return nil }
        defer { inflateEnd(&stream) }
        
        let result = decompressedData.withUnsafeMutableBytes { destBuffer in
            compressedData.withUnsafeBytes { srcBuffer in
                guard let srcBase = srcBuffer.baseAddress, let destBase = destBuffer.baseAddress else {
                    return Z_DATA_ERROR
                }
                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: srcBase.assumingMemoryBound(to: Bytef.self))
                stream.avail_in = uInt(compressedData.count)
                stream.next_out = destBase.assumingMemoryBound(to: Bytef.self)
                stream.avail_out = uInt(uncompressedSize)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard result == Z_STREAM_END || result == Z_OK else { return nil }
        return decompressedData
    }
    
    private static func findEOCDOffset(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let minOffset = max(0, data.count - 65557)
        for offset in stride(from: data.count - 22, through: minOffset, by: -1) {
            if readUInt32(from: data, at: offset) == 0x06054b50 {
                return offset
            }
        }
        return nil
    }
    
    private static func readUInt16(from data: Data, at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
    
    private static func readUInt32(from data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }
}
