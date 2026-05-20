//
//  ScannerUIView.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 19/05/2026.
//

import SwiftUI

struct ScannerUIView: View {
    @State private var viewModel = ScannerViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                scanningVisualization
                    .padding(.top, 16)
                
                statusLabel
                    .padding(.top, 20)
                    .padding(.horizontal, 32)
                
                if !viewModel.discoveredDevices.isEmpty {
                    deviceList
                        .padding(.top, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                Spacer()
                
                actionButton
                    .padding(.horizontal)
                    .padding(.bottom, 32)
            }
            .navigationTitle("BLE Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .animation(.spring(response: 0.4), value: viewModel.discoveredDevices.count)
        }
    }

    // MARK: - Subviews

    private var scanningVisualization: some View {
        ZStack {
            if viewModel.scanPhase == .scanning {
                PulseRingView(diameter: 110, opacity: 0.25, delay: 0.0)
                    .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                PulseRingView(diameter: 165, opacity: 0.17, delay: 0.35)
                    .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                PulseRingView(diameter: 220, opacity: 0.10, delay: 0.70)
                    .transition(.opacity.animation(.easeInOut(duration: 0.4)))
            }

            Circle()
                .fill(centerIconColor.opacity(0.12))
                .frame(width: 100, height: 100)
                .animation(.easeInOut(duration: 0.4), value: viewModel.scanPhase)

            Image(systemName: centerIconName)
                .font(.system(size: 42))
                .foregroundStyle(centerIconColor)
                .symbolEffect(.bounce, value: viewModel.scanPhase)
                .animation(.easeInOut(duration: 0.3), value: viewModel.scanPhase)
        }
        .frame(height: 250)
    }

    private var statusLabel: some View {
        VStack(spacing: 6) {
            Text(statusTitle)
                .font(.title3.weight(.semibold))
            Text(statusSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .animation(.easeInOut, value: viewModel.scanPhase)
    }

    private var deviceList: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Nearby Devices")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.discoveredDevices.count) found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ForEach(viewModel.discoveredDevices) { device in
                DeviceRowView(device: device) {
                    viewModel.connect(to: device)
                }
                .padding(.horizontal)
            }
        }
    }

    private var actionButton: some View {
        Group {
            switch viewModel.scanPhase {
            case .idle:
                Button { viewModel.startScan() } label: {
                    scanButtonLabel("Start Scan", icon: "antenna.radiowaves.left.and.right", color: .blue)
                }
            case .scanning:
                Button { viewModel.stopScan() } label: {
                    scanButtonLabel("Stop Scan", icon: "stop.circle", color: .gray)
                }
            case .connecting:
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Connecting...")
                        .font(.title3.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 16))
            case .connected:
                Button { dismiss() } label: {
                    scanButtonLabel("Done", icon: "checkmark.circle.fill", color: .green)
                }
            case .found:
                EmptyView()
            }
        }
        .animation(.spring(response: 0.3), value: viewModel.scanPhase)
    }

    // MARK: - Helpers

    private var centerIconName: String {
        switch viewModel.scanPhase {
        case .idle, .scanning: "antenna.radiowaves.left.and.right"
        case .found: "checkmark.circle.fill"
        case .connecting: "arrow.triangle.2.circlepath"
        case .connected: "heart.fill"
        }
    }

    private var centerIconColor: Color {
        switch viewModel.scanPhase {
        case .idle, .scanning: .blue
        case .found: .green
        case .connecting: .orange
        case .connected: .red
        }
    }

    private var statusTitle: String {
        switch viewModel.scanPhase {
        case .idle: "Ready to Scan"
        case .scanning: "Scanning..."
        case .found: "Devices Found"
        case .connecting: "Connecting..."
        case .connected: "Connected"
        }
    }

    private var statusSubtitle: String {
        switch viewModel.scanPhase {
        case .idle: "Tap Start to search for nearby cardiac monitors"
        case .scanning: "Looking for Bluetooth cardiac devices nearby"
        case .found: "Select a device below to connect"
        case .connecting: "Establishing a secure connection"
        case .connected: "Device connected and ready to monitor"
        }
    }

    private func scanButtonLabel(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(color, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Pulse Ring

private struct PulseRingView: View {
    let diameter: CGFloat
    let opacity: Double
    let delay: Double

    @State private var isAnimating = false

    var body: some View {
        Circle()
            .stroke(Color.blue.opacity(opacity), lineWidth: 1.5)
            .frame(width: diameter, height: diameter)
            .scaleEffect(isAnimating ? 1.12 : 0.92)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.4)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Device Row

private struct DeviceRowView: View {
    let device: DiscoveredDevice
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "heart.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.title2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body.weight(.semibold))
                Text(device.type)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                signalBars
                Text("\(device.rssi) dBm")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Button("Connect", action: onConnect)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.blue.opacity(0.12), in: Capsule())
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var signalBars: some View {
        let strength = device.rssi > -60 ? 3 : device.rssi > -75 ? 2 : 1
        let color: Color = strength == 3 ? .green : strength == 2 ? .orange : .red

        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < strength ? color : Color.gray.opacity(0.3))
                    .frame(width: 4, height: CGFloat(6 + i * 4))
            }
        }
    }
}

#Preview {
    ScannerUIView()
}
