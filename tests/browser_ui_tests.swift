import UIKit

@objc enum State: Int { case unknown, offline, online }
@objc enum PairState: Int { case unknown, unpaired, paired }
@objcMembers class TemporaryHost: NSObject {
    var state = State.online
    var pairState = PairState.paired
    var currentGame: String? = "0"
    var name = "PC"
    var mac: String? = nil
}
@objcMembers class TemporaryApp: NSObject {
    var id: String? = "1"
    var name: String? = "Desktop"
    var hidden = false
    var host: TemporaryHost?
}
class AppAssetManager {
    static var pathLookups = 0
    static var testPath = NSTemporaryDirectory() + "art.png"
    static func boxArtPath(for app: TemporaryApp) -> String? { pathLookups += 1; return testPath }
}
class ThemeManager {
    static var appPrimaryColor: UIColor { .blue }
    static var appPrimaryColorWithAlpha: UIColor { .blue }
    static var textColor: UIColor { .black }
    static var textColorGray: UIColor { .gray }
    static var lowProfileGray: UIColor { .gray }
    static var hostCardSeparatorColor: UIColor { .gray }
    static var textTintColorWithAlpha: UIColor { .blue }
    static var offlineHostIconBackgroundColor: UIColor { .gray }
    static var widgetBackgroundColor: UIColor { .white }
    static var hostViewBackgroundColor: UIColor { .white }
    static func userInterfaceStyle() -> UIUserInterfaceStyle { .light }
}
class LocalizationHelper {
    static func localizedString(forKey key: String) -> String { key }
}
extension UIView {
    var parentViewController: UIViewController? { nil }
}
@objc protocol ControllerNavigationHighlightTargetProviding: NSObjectProtocol {
    var controllerNavigationHighlightTargetView: UIView { get }
    func controllerNavigationHighlightDidClear()
}
extension UIViewController {
    var hasNoPresentedVC: Bool { true }
    var controllerNavigationSelectedIndexPath: IndexPath? { nil }
    func applyControllerNavigationHighlight(to cell: UICollectionViewCell, highlighted: Bool) {}
}
final class Probe: NSObject, AppCallback, AppViewUpdateLoopDelegate, HostCardActionDelegate {
    var appTicks = 0
    var hostTicks = 0
    var streaming = false
    func isInAppView() -> Bool { appTicks += 1; return !streaming }
    func isStreaming() -> Bool { hostTicks += 1; return streaming }
    func appClicked(_ app: TemporaryApp, view: UIView) {}
    func appLongClicked(_ app: TemporaryApp, view: UIView) {}
    func appButtonTapped(for host: TemporaryHost) {}
    func launchButtonTapped(for host: TemporaryHost) {}
    func wakeupButtonTapped(for host: TemporaryHost) {}
    func pairButtonTapped(for host: TemporaryHost) {}
    func hostCardLongPressed(_ host: TemporaryHost, view: UIView) {}
}
@main class TestDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var checks = 0
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { print("BROWSER_UI_TESTS_RESULT: FAIL \(message)"); fflush(stdout); exit(1) }
        checks += 1
    }
    func writeArt(_ size: CGSize, color: UIColor) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill(); context.fill(CGRect(origin: .zero, size: size))
        }
        try! image.pngData()!.write(to: URL(fileURLWithPath: AppAssetManager.testPath))
    }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window!.rootViewController = UIViewController()
        window!.makeKeyAndVisible()
        DispatchQueue.main.async { self.run() }
        return true
    }
    func timer(_ view: UIView) -> Timer {
        let property = Mirror(reflecting: view).children.first { $0.label == "refreshTimer" }!.value
        return Mirror(reflecting: property).children.first!.value as! Timer
    }
    func runHostGeometry() {
        let root = window!.rootViewController!
        var canvas = UIView(frame: CGRect(x: 0, y: 0, width: 600, height: 500))
        root.view.addSubview(canvas)
        let grid = HostCollectionViewController()
        grid.cellSize = CGSize(width: 160, height: HostCardView.unscaledHeight * 0.75)
        root.addChild(grid); canvas.addSubview(grid.view); grid.didMove(toParent: root)
        grid.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            grid.view.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 10),
            grid.view.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            grid.view.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
        ])
        func settle() {
            for _ in 0..<8 {
                canvas.setNeedsLayout(); canvas.layoutIfNeeded()
                grid.view.setNeedsLayout(); grid.view.layoutIfNeeded()
            }
        }
        func expectGeometry(_ description: String) {
            settle()
            let available = max(0, canvas.safeAreaLayoutGuide.layoutFrame.maxY - grid.view.frame.minY)
            let content = grid.collectionView.collectionViewLayout.collectionViewContentSize.height
            expect(abs(grid.view.bounds.height - min(available, content)) < 1,
                   "\(description): height=\(grid.view.bounds.height), available=\(available), content=\(content)")
            expect(!grid.view.hasAmbiguousLayout, "host grid has unambiguous geometry")
            let requiredBottom = canvas.constraints.contains { constraint in
                constraint.isActive && constraint.priority == .required && constraint.relation == .equal &&
                ((constraint.firstItem as? UIView === grid.view && constraint.firstAttribute == .bottom) ||
                 (constraint.secondItem as? UIView === grid.view && constraint.secondAttribute == .bottom))
            }
            expect(!requiredBottom, "host grid does not retain a conflicting bottom anchor")
        }
        let first = TemporaryHost(); grid.addHost(first)
        expectGeometry("one host sizes to its content")
        let firstHeight = grid.view.bounds.height
        for index in 0..<24 { let host = TemporaryHost(); host.name = "PC \(index)"; grid.addHost(host) }
        expectGeometry("many hosts clamp to the available viewport")
        expect(grid.collectionView.contentSize.height > grid.view.bounds.height, "overflowing hosts remain scrollable")
        while grid.items.count > 1 { grid.removeLastItem() }
        expectGeometry("removing hosts restores content height after overflow")
        expect(abs(grid.view.bounds.height - firstHeight) < 1, "shrinking grid returns to its original content size")
        canvas.frame.size.height = 180
        expectGeometry("smaller window clamps a one-host grid")
        canvas.frame.size.height = 600
        expectGeometry("larger window releases the old viewport limit")
        grid.removeLastItem(); expectGeometry("empty grid collapses to its content size")
        grid.willMove(toParent: nil); grid.view.removeFromSuperview(); grid.removeFromParent(); canvas.removeFromSuperview()
        let previousCanvas = canvas
        canvas = UIView(frame: CGRect(x: 0, y: 0, width: 600, height: 220)); root.view.addSubview(canvas)
        root.addChild(grid); canvas.addSubview(grid.view); grid.didMove(toParent: root)
        NSLayoutConstraint.activate([
            grid.view.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 10),
            grid.view.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            grid.view.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
        ])
        grid.addHost(first); expectGeometry("reparented grid uses the new container height")
        expect(!previousCanvas.constraints.contains { $0.isActive && ($0.firstItem as? UIView === grid.view || $0.secondItem as? UIView === grid.view) },
               "reparented grid releases every old-container constraint")
        grid.willMove(toParent: nil); grid.view.removeFromSuperview(); grid.removeFromParent(); canvas.removeFromSuperview()
    }
    func run() {
        runHostGeometry()
        let lookups = AppAssetManager.pathLookups
        let ratios = (0..<100).map { _ in UIAppView.preferredAspectRatio }
        expect(ratios.allSatisfy { $0 == 0.75 }, "repeated sizing uses the established iPhone aspect ratio")
        expect(AppAssetManager.pathLookups == lookups, "aspect-ratio queries never load artwork")
        let probe = Probe()
        let cache = NSCache<AnyObject, AnyObject>()
        let host = TemporaryHost()
        let app = TemporaryApp(); app.host = host
        let root = window!.rootViewController!.view!
        try? FileManager.default.removeItem(atPath: AppAssetManager.testPath)
        let missing = UIAppView(app: app, cache: cache, andCallback: probe)
        expect(abs(missing.bounds.width / missing.bounds.height - UIAppView.preferredAspectRatio) < 0.000001,
               "actual app bounds use the same geometry as the collection sizing API")
        missing.updateLoopDelegate = probe
        root.addSubview(missing)
        let oldLabel = missing.subviews.compactMap { $0 as? UILabel }.first!
        let baseCard = HostCardView(host: host)
        expect(baseCard.size.height == HostCardView.unscaledHeight, "baseline card size matches actual layout")
        baseCard.delegate = probe
        root.addSubview(baseCard)
        let firstAppTimer = self.timer(missing)
        let firstHostTimer = self.timer(baseCard)
        for _ in 0..<4 {
            missing.removeFromSuperview(); root.addSubview(missing)
            baseCard.removeFromSuperview(); root.addSubview(baseCard)
        }
        expect(!firstAppTimer.isValid && !firstHostTimer.isValid, "reattaching invalidates old timers")
        let appTicks = probe.appTicks
        let hostTicks = probe.hostTicks
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
            self.expect(probe.appTicks - appTicks == 2, "one app polling timer after reattach")
            self.expect(probe.hostTicks - hostTicks == 1, "one host polling timer after reattach")
            self.expect(missing.subviews.compactMap { $0 as? UILabel }.first === oldLabel, "fallback artwork does not rebuild label every tick")
            self.writeArt(CGSize(width: 192, height: 256), color: .red)
            missing.updateAppImage()
            let firstImage = missing.subviews.compactMap { $0 as? UIImageView }.first!.image!
            let second = UIAppView(app: app, cache: cache, andCallback: probe)
            self.expect(second.subviews.compactMap { $0 as? UIImageView }.first!.image === firstImage, "unchanged file shares cached UIImage")
            self.writeArt(CGSize(width: 220, height: 256), color: .blue)
            missing.updateAppImage()
            let imageView = missing.subviews.compactMap { $0 as? UIImageView }.first!
            self.expect(imageView.image!.size.width == 220, "replacement image invalidates cache")
            cache.removeAllObjects()
            let afterEviction = UIAppView(app: app, cache: cache, andCallback: probe)
            self.expect(afterEviction.subviews.compactMap { $0 as? UIImageView }.first!.image !== imageView.image, "evicted artwork reloads")
            host.currentGame = app.id
            missing.updateAppImage()
            self.expect(imageView.layer.opacity == 0.75, "running app dimmed")
            host.currentGame = "0"
            missing.updateAppImage()
            self.expect(imageView.layer.opacity == 1, "stopped app restores opacity")
            try! FileManager.default.removeItem(atPath: AppAssetManager.testPath)
            missing.updateAppImage()
            self.expect(imageView.image == nil && cache.object(forKey: app) == nil, "deletion removes stale artwork and cache")
            self.writeArt(CGSize(width: 130, height: 180), color: .white)
            missing.updateAppImage()
            self.expect(imageView.image == nil && cache.object(forKey: app) == nil, "GFE placeholder is not cached")
            let appTimer = self.timer(missing)
            let hostTimer = self.timer(baseCard)
            missing.removeFromSuperview(); baseCard.removeFromSuperview()
            self.expect(!appTimer.isValid && !hostTimer.isValid, "detaching stops both timers")
            print("BROWSER_UI_TESTS_RESULT: PASS \(self.checks) checks")
            fflush(stdout); exit(0)
        }
    }
}
