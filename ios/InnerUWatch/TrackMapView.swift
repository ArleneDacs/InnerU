import CoreLocation
import MapKit
import SwiftUI
import WatchKit

/// Records a GPS walk route on the watch. On stop, the track (distance,
/// duration, downsampled route) is sent to the phone, which saves it as
/// a walk session — queued if the phone is away.
final class WatchTrackRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isTracking = false
    @Published var route: [CLLocationCoordinate2D] = []
    @Published var distanceMeters: Double = 0
    @Published var startedAt: Date?
    @Published var authorizationDenied = false

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        route = []
        distanceMeters = 0
        lastLocation = nil
        startedAt = Date()
        isTracking = true
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        isTracking = false
        defer { startedAt = nil }
        guard let started = startedAt, route.count > 1 else { return }

        let elapsed = Int(Date().timeIntervalSince(started))
        let points = downsampled(route, maxCount: 100).map {
            ["latitude": $0.latitude, "longitude": $0.longitude]
        }
        WatchToPhoneSync.shared.sendCommand("trackCompleted", [
            "distanceMeters": distanceMeters,
            "elapsedSeconds": elapsed,
            "routePoints": points,
        ])
        WKInterfaceDevice.current().play(.success)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard isTracking else { return }
        for location in locations
        where location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 50 {
            if let last = lastLocation {
                let delta = location.distance(from: last)
                // Ignore jitter under 2 m so standing still doesn't add distance.
                guard delta >= 2 else { continue }
                distanceMeters += delta
            }
            route.append(location.coordinate)
            lastLocation = location
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationDenied = manager.authorizationStatus == .denied
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Transient GPS errors are expected outdoors; tracking continues.
    }

    private func downsampled(
        _ points: [CLLocationCoordinate2D],
        maxCount: Int
    ) -> [CLLocationCoordinate2D] {
        guard points.count > maxCount else { return points }
        let stride = Double(points.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { points[Int(Double($0) * stride)] }
    }
}

struct TrackMapView: View {
    @ObservedObject var recorder: WatchTrackRecorder

    var body: some View {
        VStack(spacing: 4) {
            Map {
                UserAnnotation()
                if recorder.route.count > 1 {
                    MapPolyline(coordinates: recorder.route)
                        .stroke(InnerUTheme.accent, lineWidth: 4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if recorder.authorizationDenied {
                Text("Allow location in Settings to track")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsedText(at: context.date))
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text(distanceText)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(InnerUTheme.accent)
            }
            .padding(.horizontal, 4)

            Button {
                recorder.isTracking ? recorder.stop() : recorder.start()
            } label: {
                Label(
                    recorder.isTracking ? "End Track" : "Start Track",
                    systemImage: recorder.isTracking ? "stop.fill" : "location.fill"
                )
            }
            .tint(recorder.isTracking ? .red : InnerUTheme.accent)
        }
        .containerBackground(InnerUTheme.background, for: .navigation)
        .navigationTitle("Track")
    }

    private func elapsedText(at now: Date) -> String {
        guard recorder.isTracking, let started = recorder.startedAt else {
            return "0:00"
        }
        let seconds = max(0, Int(now.timeIntervalSince(started)))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d",
                          seconds / 3600, (seconds / 60) % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var distanceText: String {
        let km = recorder.distanceMeters / 1000
        return String(format: km >= 10 ? "%.1f km" : "%.2f km", km)
    }
}
