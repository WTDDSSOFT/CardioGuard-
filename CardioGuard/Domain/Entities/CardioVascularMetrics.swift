//
//  CardiovascularMetrics.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 19/05/2026.
//
import Foundation

struct CardioVascularMetrics {
    var BPM: Int
    var SystoliC: Int
    var Diastolic: Int
    var Timestamp: Date?
    
    var Description: String {
        "\(BPM) BPM, \(SystoliC) /\(Diastolic) mmH"
    }
    
    var TimeStamp: String {
        Timestamp?.formatted(date: .abbreviated, time: .shortened) ?? "No timeStemp set"
    }

}
