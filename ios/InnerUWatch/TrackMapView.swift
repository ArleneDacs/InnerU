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
    @ObservedObject var connector: PhoneConnector
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)

    /// The phone's live walk, mirrored — shown when the watch itself
    /// isn't recording.
    private var phoneRoute: [CLLocationCoordinate2D] {
        guard !recorder.isTracking, connector.state.trackActive else { return [] }
        return connector.state.trackPoints.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
    }

    private var mirroringPhone: Bool {
        !recorder.isTracking && connector.state.trackActive
    }

    var body: some View {
        VStack(spacing: 4) {
            Map(position: $camera) {
                UserAnnotation()
                if recorder.route.count > 1 {
                    MapPolyline(coordinates: recorder.route)
                        .stroke(InnerUTheme.accent, lineWidth: 4)
                }
                if phoneRoute.count > 1 {
                    MapPolyline(coordinates: phoneRoute)
                        .stroke(InnerUTheme.accent, lineWidth: 4)
                    if let last = phoneRoute.last {
                        Annotation("", coordinate: last) {
                            Circle()
                                .fill(InnerUTheme.accent)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onChange(of: phoneRoute.count) { _, _ in
                frameOnPhoneRoute()
            }
            .onAppear {
                frameOnPhoneRoute()
            }

            if recorder.authorizationDenied {
                Text("Allow location in Settings to track")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if mirroringPhone {
                Label("Tracking on phone", systemImage: "iphone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsedText(at: context.date))
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                if mirroringPhone, connector.state.trackSteps > 0 {
                    Text("\(connector.state.trackSteps.formatted()) steps")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                }
                Text(distanceText)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(InnerUTheme.accent)
            }
            .padding(.horizontal, 4)

            if !mirroringPhone {
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
        }
        .containerBackground(InnerUTheme.background, for: .navigation)
        .navigationTitle("Track")
    }

    private func frameOnPhoneRoute() {
        let route = phoneRoute
        guard route.count > 1 else { return }
        let lats = route.map(\.latitude)
        let lngs = route.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.003),
            longitudeDelta: max((maxLng - minLng) * 1.4, 0.003)
        )
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func elapsedText(at now: Date) -> String {
        let started = mirroringPhone
            ? connector.state.trackStartedAt
            : (recorder.isTracking ? recorder.startedAt : nil)
        guard let started else { return "0:00" }
        let seconds = max(0, Int(now.timeIntervalSince(started)))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d",
                          seconds / 3600, (seconds / 60) % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var distanceText: String {
        let meters = mirroringPhone
            ? connector.state.trackDistanceM
            : recorder.distanceMeters
        let km = meters / 1000
        return String(format: km >= 10 ? "%.1f km" : "%.2f km", km)
    }
}
