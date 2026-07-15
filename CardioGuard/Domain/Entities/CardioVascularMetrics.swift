//
//  CardiovascularMetrics.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 19/05/2026.
//
import Foundation

struct CardioVascularMetrics {
    var BPM: Int
    var Systolic: Int
    var Diastolic: Int
    var Timestamp: Date?
    
    var Description: String {
        "\(BPM) BPM, \(Systolic) /\(Diastolic) mmH"
    }
    
    var formattedTimestamp: String {
        Timestamp?.formatted(date: .abbreviated, time: .shortened) ?? "No timestamp set"
    }

}
