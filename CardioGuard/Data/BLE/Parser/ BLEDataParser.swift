//
//   BLEDataParser.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 19/05/2026.
//

import Foundation

enum BLEDataParserError: Error {
    case invalidPacketLength
    case corruptedData
}


struct BLEDataParser {
    func parse(payload: [UInt8]) throws -> CardioVascularMetrics {
        
        guard payload.count == 3 else {
            throw BLEDataParserError.invalidPacketLength
        }
        
        let bpm = Int(payload[0]) // BPM
        let slic = Int(payload[1]) // SystoliC
        let dlic = Int(payload[2]) // Diastolic
        
        
        guard bpm >= 0, slic >= 0, dlic >= 0 else {
            throw BLEDataParserError.corruptedData
        }
        
        return CardioVascularMetrics(BPM: bpm, SystoliC: slic, Diastolic: dlic)
    }
}
