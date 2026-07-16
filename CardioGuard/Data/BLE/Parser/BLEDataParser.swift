//
//  BLEDataParser.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 19/05/2026.
//

import Foundation

enum BLEDataParserError: Error, Equatable {
    case invalidPacketLength
    case corruptedData
}

/// Physiologically-plausible bounds for each vital. Values outside this range
/// can't come from a live human reading - either the sensor glitched or the
/// packet is corrupted - so the parser rejects them at the decoding boundary
/// instead of letting nonsense values reach the clinical-threshold layer.
private enum PlausibleRange {
    static let bpm = 0...250
    static let systolic = 0...250
    static let diastolic = 0...200
}

struct BLEDataParser {
    func parse(payload: [UInt8]) throws -> CardioVascularMetrics {

        guard payload.count == 3 else {
            throw BLEDataParserError.invalidPacketLength
        }

        let bpm = Int(payload[0]) // BPM
        let slic = Int(payload[1]) // Systolic
        let dlic = Int(payload[2]) // Diastolic

        guard PlausibleRange.bpm.contains(bpm),
              PlausibleRange.systolic.contains(slic),
              PlausibleRange.diastolic.contains(dlic) else {
            throw BLEDataParserError.corruptedData
        }

        return CardioVascularMetrics(BPM: bpm, Systolic: slic, Diastolic: dlic)
    }
}
