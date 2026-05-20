//
//  DashBoardUIView.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 19/05/2026.
//

import SwiftUI

struct DashBoardUIView: View {
    @State private var viewModel = AppContainer.shared.makeDashboardViewModel()
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            ZStack {
                alertBackground
                ScrollView {
                    VStack(spacing: 24) {
                        alertBanner
                        heartRateCard
                        bloodPressureCard
                        monitorButton
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("CardioGuard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("Open Scanner")
                }
            }
            .sheet(isPresented: $showScanner) {
                ScannerUIView()
            }
        }
    }

    // MARK: - Subviews

    private var alertBackground: some View {
        LinearGradient(
            colors: [Color(.systemBackground), viewModel.alertState.accentColor.opacity(0.1)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: viewModel.alertState)
    }

    private var alertBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: viewModel.alertState.symbolName)
                .font(.subheadline.weight(.semibold))
            Text(viewModel.alertState.label)
                .font(.subheadline.weight(.semibold))
            Spacer()
            if viewModel.isMonitoring {
                HStack(spacing: 5) {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                    Text("Live")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
            }
        }
        .foregroundStyle(viewModel.alertState.accentColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(viewModel.alertState.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .animation(.easeInOut(duration: 0.4), value: viewModel.alertState)
    }

    private var heartRateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.bounce, value: viewModel.currentMetrics?.BPM)
                Text("Heart Rate")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(viewModel.currentMetrics.map { "\($0.BPM)" } ?? "--")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.3), value: viewModel.currentMetrics?.BPM)
                Text("BPM")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            if let metrics = viewModel.currentMetrics {
                Text("Updated \(metrics.TimeStamp)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var bloodPressureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.blue)
                Text("Blood Pressure")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.currentMetrics.map { "\($0.SystoliC)" } ?? "--")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.3), value: viewModel.currentMetrics?.SystoliC)
                    Text("Systolic")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(" / ")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.currentMetrics.map { "\($0.Diastolic)" } ?? "--")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.3), value: viewModel.currentMetrics?.Diastolic)
                    Text("Diastolic")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("mmHg")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var monitorButton: some View {
        Button {
            viewModel.toggleMonitoring()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: viewModel.isMonitoring ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                Text(viewModel.isMonitoring ? "Stop Monitoring" : "Start Monitoring")
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                viewModel.isMonitoring ? Color.red : Color.green,
                in: RoundedRectangle(cornerRadius: 18)
            )
        }
        .animation(.spring(response: 0.3), value: viewModel.isMonitoring)
    }
}

// MARK: - HealthStatusAlert SwiftUI extensions
extension HealthStatusAlert {
    var accentColor: Color {
        switch self {
        case .normal: .green
        case .hypertension, .tachycardia: .red
        case .hypotension: .orange
        case .bradycardia: .purple
        }
    }

    var symbolName: String {
        switch self {
        case .normal: "checkmark.circle.fill"
        case .hypertension: "exclamationmark.triangle.fill"
        case .hypotension: "arrow.down.heart.fill"
        case .bradycardia: "heart.slash.fill"
        case .tachycardia: "bolt.heart.fill"
        }
    }

    var label: String {
        switch self {
        case .normal: "Status Normal"
        case .hypertension: "Hypertension Alert"
        case .hypotension: "Hypotension Alert"
        case .bradycardia: "Bradycardia Detected"
        case .tachycardia: "Tachycardia Detected"
        }
    }
}

#Preview {
    DashBoardUIView()
}
