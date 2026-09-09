//
//  UIAppView.swift
//  Moonlight
//
//  Created by Diego Waxemberg on 10/22/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//
//  Created by True Zhuanjia on 2025.7.20.
//  Copyright 2025 True Zhuanjia @ Bilibili. All rights reserved.
//

import UIKit

private let refreshCycle: TimeInterval = 1.0

private final class CachedAppArtwork: NSObject {
    let image: UIImage
    let fileAttributes: NSDictionary

    init(image: UIImage, fileAttributes: NSDictionary) {
        self.image = image
        self.fileAttributes = fileAttributes
    }
}

@objc protocol AppViewUpdateLoopDelegate: AnyObject {
    func isInAppView() -> Bool
}

@objc protocol AppCallback: AnyObject {
    @objc(appClicked:view:)
    func appClicked(_ app: TemporaryApp, view: UIView)

    @objc(appLongClicked:view:)
    func appLongClicked(_ app: TemporaryApp, view: UIView)
}

@objcMembers
final class UIAppView: UIButton {
    weak var updateLoopDelegate: AppViewUpdateLoopDelegate?

    private static var noImage: UIImage?
    private static var preferredSize: CGSize {
        #if os(tvOS)
        return CGSize(width: 200, height: 265)
        #else
        return CGSize(width: 150, height: 200)
        #endif
    }

    // Collection layout needs only geometry, not a view with loaded artwork,
    // gesture recognizers and labels for every sizing query.
    @objc static var preferredAspectRatio: CGFloat {
        preferredSize.width / preferredSize.height
    }

    let app: TemporaryApp
    fileprivate weak var callback: AppCallback?
    private let artCache: NSCache<AnyObject, AnyObject>
    private var appLabel: UILabel?
    private var appOverlay: UIImageView?
    private var appImage: UIImageView
    private var contextMenuDelegate: AnyObject?
    private var refreshTimer: Timer?
    private var displayedCurrentApp = false

    @objc(initWithApp:cache:andCallback:)
    init(app: TemporaryApp, cache: NSCache<AnyObject, AnyObject>, andCallback callback: AppCallback) {
        self.app = app
        self.callback = callback
        self.artCache = cache

        if UIAppView.noImage == nil {
            UIAppView.noImage = UIImage(named: "NoAppImage")
        }

        let initialFrame = CGRect(origin: .zero, size: UIAppView.preferredSize)

        self.appImage = UIImageView(frame: initialFrame)

        super.init(frame: .zero)

        layer.cornerRadius = 16
        if #available(iOS 13.0, tvOS 13.0, *) {
            layer.cornerCurve = .continuous
        }
        clipsToBounds = true
        frame = initialFrame
        alpha = app.hidden ? 0.4 : 1.0

        appImage.image = UIAppView.noImage
        addSubview(appImage)

        #if !os(tvOS)
        if #available(iOS 13.0, *) {
            let delegate = UIAppViewContextMenuDelegate(appView: self)
            contextMenuDelegate = delegate
            let rightClickInteraction = UIContextMenuInteraction(delegate: delegate)
            addInteraction(rightClickInteraction)
        } else {
            let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(appLongClicked(_:)))
            addGestureRecognizer(longPressRecognizer)
        }
        #else
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(appLongClicked(_:)))
        addGestureRecognizer(longPressRecognizer)
        #endif

        addTarget(self, action: #selector(appClicked(_:)), for: .primaryActionTriggered)
        addTarget(self, action: #selector(buttonSelected(_:)), for: .touchDown)
        addTarget(self, action: #selector(buttonDeselected(_:)), for: [.touchUpInside, .touchCancel, .touchDragExit])

        #if os(tvOS)
        appImage.adjustsImageWhenAncestorFocused = true
        #else
        layer.shouldRasterize = false
        if #available(iOS 13.4, *) {
            isPointerInteractionEnabled = true
        }
        #endif

        updateAppImage()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        updateRefreshTimer()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateRefreshTimer()
    }

    private func updateRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard superview != nil, window != nil else { return }

        updateLoop()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshCycle, repeats: true) { [weak self] _ in
            self?.updateLoop()
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    @objc private func appClicked(_ view: UIView) {
        callback?.appClicked(app, view: view)
    }

    @objc private func appLongClicked(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            callback?.appLongClicked(app, view: self)
        }
    }

    private var isCurrentApp: Bool {
        app.id == app.host?.currentGame
    }

    private func loadAppArtwork() -> UIImage? {
        guard let path = AppAssetManager.boxArtPath(for: app) else { return nil }
        let cacheKey = "UIAppView.artwork:\(path)" as NSString
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) as NSDictionary else {
            artCache.removeObject(forKey: cacheKey)
            artCache.removeObject(forKey: app)
            return nil
        }

        // The legacy preloader caches by app alone and does not invalidate a replaced
        // file. Only reuse artwork whose on-disk version has also been recorded.
        if let cached = artCache.object(forKey: cacheKey) as? CachedAppArtwork,
           cached.fileAttributes.isEqual(attributes) {
            return cached.image
        }
        artCache.removeObject(forKey: cacheKey)
        artCache.removeObject(forKey: app)
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        let isGFE2BlankImage = image.size.width == 130.0 && image.size.height == 180.0
        let isGFE3BlankImage = image.size.width == 628.0 && image.size.height == 888.0
        guard !isGFE2BlankImage, !isGFE3BlankImage else { return nil }

        // Downloads currently write in place. Don't cache a version that changed
        // while UIImage was loading it; the asset callback will refresh the view.
        if let currentAttributes = try? FileManager.default.attributesOfItem(atPath: path) as NSDictionary,
           attributes.isEqual(currentAttributes) {
            artCache.setObject(CachedAppArtwork(image: image, fileAttributes: attributes), forKey: cacheKey)
            artCache.setObject(image, forKey: app)
        }
        return image
    }

    func updateAppImage() {
        appOverlay?.removeFromSuperview()
        appOverlay = nil
        appLabel?.removeFromSuperview()
        appLabel = nil

        let loadedAppImage = loadAppArtwork()
        let noAppImage = loadedAppImage == nil
        appImage.image = loadedAppImage ?? UIAppView.noImage
        displayedCurrentApp = isCurrentApp
        appImage.layer.opacity = isHighlighted ? 0.5 : (displayedCurrentApp ? 0.75 : 1.0)

        if isCurrentApp {
            if #available(iOS 13.0, tvOS 13.0, *) {
                let config = UIImage.SymbolConfiguration(pointSize: 23)
                let image = UIImage(systemName: "play.circle.fill", withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
                let playIcon = UIImageView(image: image)
                playIcon.tintColor = UIColor.black.withAlphaComponent(0.55)
                appOverlay = playIcon
            } else {
                let playIcon = UIImageView(image: UIImage(named: "play.circle.fill"))
                playIcon.tintColor = UIColor.black.withAlphaComponent(0.55)
                appOverlay = playIcon
            }
        } else if noAppImage {
            if #available(iOS 13.0, tvOS 13.0, *) {
                let config = UIImage.SymbolConfiguration(pointSize: 70)
                let image = UIImage(named: "icon-pc-app")?.withConfiguration(config).withRenderingMode(.alwaysTemplate)
                let appIcon = UIImageView(image: image)
                appIcon.tintColor = UIColor.black.withAlphaComponent(0.5)
                appOverlay = appIcon
            }
        }

        let label = UILabel()
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.textColor = UIColor.white
        label.text = app.name == "Steam Big Picture" ? "Steam" : app.name
        label.font = UIFont.systemFont(ofSize: 15)
        label.baselineAdjustment = .alignCenters
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 2
        appLabel = label

        positionSubviews()

        #if os(tvOS)
        appImage.overlayContentView.addSubview(label)
        if let appOverlay {
            appImage.overlayContentView.addSubview(appOverlay)
        }
        #else
        if let appOverlay {
            addSubview(appOverlay)
        }
        addSubview(label)
        #endif
    }

    @objc private func buttonSelected(_ sender: Any) {
        appImage.layer.opacity = 0.5
    }

    @objc private func buttonDeselected(_ sender: Any) {
        appImage.layer.opacity = isCurrentApp ? 0.75 : 1.0
    }

    private func positionSubviews() {
        let verticalPadding: CGFloat = 10
        let frameSize = appImage.frame.size

        appLabel?.frame = CGRect(x: 0, y: frameSize.height - 43, width: frameSize.width, height: 43)

        guard let appOverlay else { return }
        let overlaySize = isCurrentApp ? frameSize.width / 2.39 : frameSize.width / 2.0
        appOverlay.frame = CGRect(x: 0, y: 0, width: overlaySize, height: overlaySize)
        appOverlay.center = CGPoint(x: frameSize.width / 2.0, y: frameSize.height / 2.0 - 2.0 * verticalPadding)

    }

    @objc private func updateLoop() {
        guard superview != nil, updateLoopDelegate?.isInAppView() == true else {
            return
        }

        if displayedCurrentApp != isCurrentApp {
            updateAppImage()
        }

        superview?.layer.shadowOpacity = 0
        alpha = app.hidden ? 0.4 : 1.0

    }
}

@available(iOS 13.0, *)
private final class UIAppViewContextMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
    private weak var appView: UIAppView?

    init(appView: UIAppView) {
        self.appView = appView
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let appView else { return nil }
        appView.cancelTracking(with: nil)
        appView.callback?.appLongClicked(appView.app, view: appView)
        return nil
    }
}
