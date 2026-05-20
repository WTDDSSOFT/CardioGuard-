//
//  CardioMonitorServing.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 20/05/2026.
//
import Foundation

protocol CardioMonitorServing {
    var metricsStream: AsyncStream<CardioVascularMetrics> { get }
    func stopMonitoring()
    func startMonitoring()
}
