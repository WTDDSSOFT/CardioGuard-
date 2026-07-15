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
                        aiRiskCard
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
        .animation(AppTheme.Animation.backgroundTransition, value: viewModel.alertState)
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
                        .fill(AppTheme.Colors.liveMonitoring)
                        .frame(width: 7, height: 7)
                    Text("Live")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.Colors.liveMonitoring)
                }
            }
        }
        .foregroundStyle(viewModel.alertState.accentColor)
        .padding(.horizontal, AppTheme.Spacing.standard)
        .padding(.vertical, AppTheme.Spacing.compact)
        .background(viewModel.alertState.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.Radius.tag))
        .animation(AppTheme.Animation.stateChange, value: viewModel.alertState)
    }

    private var heartRateCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(AppTheme.Colors.heartRate)
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
                    .animation(AppTheme.Animation.metricUpdate, value: viewModel.currentMetrics?.BPM)
                Text("BPM")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            if let metrics = viewModel.currentMetrics {
                Text("Updated \(metrics.formattedTimestamp)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(AppTheme.Spacing.comfortable)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
    }

    private var bloodPressureCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(AppTheme.Colors.bloodPressure)
                Text("Blood Pressure")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.currentMetrics.map { "\($0.Systolic)" } ?? "--")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(AppTheme.Animation.metricUpdate, value: viewModel.currentMetrics?.Systolic)
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
                        .animation(AppTheme.Animation.metricUpdate, value: viewModel.currentMetrics?.Diastolic)
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
        .padding(AppTheme.Spacing.comfortable)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
    }

    /// Predictive on-device AI signal (see MLPipeline/). Only appears once
    /// the rolling reading window has filled and the model has produced a
    /// prediction - complements, and is visually distinct from, the instant
    /// clinical-threshold `alertBanner` above.
    @ViewBuilder
    private var aiRiskCard: some View {
        if let prediction = viewModel.aiRiskPrediction {
            HStack(spacing: 14) {
                Image(systemName: prediction.isElevated ? "brain.head.profile.fill" : "brain.head.profile")
                    .font(.title2)
                    .foregroundStyle(prediction.isElevated ? .orange : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Trend Analysis")
                        .font(.subheadline.weight(.semibold))
                    Text(prediction.isElevated
                         ? "Early warning: pattern resembles an approaching crisis"
                         : "No concerning trend detected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(prediction.riskScore * 100))%")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(prediction.isElevated ? AppTheme.Colors.warning : .secondary)
            }
            .padding(AppTheme.Spacing.snug)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card)
                    .strokeBorder(prediction.isElevated ? AppTheme.Colors.warning.opacity(0.5) : .clear, lineWidth: 1.5)
            )
            .animation(AppTheme.Animation.stateChange, value: prediction.isElevated)
        }
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
            .padding(.vertical, AppTheme.Spacing.snug)
            .background(
                viewModel.isMonitoring ? AppTheme.Colors.critical : AppTheme.Colors.liveMonitoring,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.actionButton)
            )
        }
        .animation(AppTheme.Animation.buttonToggle, value: viewModel.isMonitoring)
    }
}

// MARK: - HealthStatusAlert SwiftUI extensions
extension HealthStatusAlert {
    var accentColor: Color {
        switch self {
        case .normal: AppTheme.Colors.liveMonitoring
        case .hypertension, .tachycardia: AppTheme.Colors.critical
        case .hypotension: AppTheme.Colors.warning
        case .bradycardia: AppTheme.Colors.bradycardia
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
