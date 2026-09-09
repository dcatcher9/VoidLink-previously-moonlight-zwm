//
//  ThemeManager.swift
//  VoidLink
//
//  Created by True砖家 on 2026/3/6.
//  Copyright © 2026 True砖家 @ Bilibili. All rights reserved.
//


import UIKit

@objcMembers
class ThemeManager: NSObject {
    
    static let ThemeDidChangeNotification = "ThemeDidChangeNotification"
    
    private static var _privateUserInterfaceStyle: UIUserInterfaceStyle = .unspecified
    private static var _userInterfaceStyle: UIUserInterfaceStyle = .unspecified
    
    @objc class func setPublicUIStyle() -> UIColor {
        if #available(iOS 13.0, *) {
            let traitCollection = UIScreen.main.traitCollection
            if _privateUserInterfaceStyle == .unspecified {
                _userInterfaceStyle = traitCollection.userInterfaceStyle
            } else {
                _userInterfaceStyle = _privateUserInterfaceStyle
            }
        }
        return UIColor.clear
    }
    
    @objc class func userInterfaceStyle() -> UIUserInterfaceStyle {
        _ = setPublicUIStyle()
        return _userInterfaceStyle
    }

    @objc class func overrideUserInterfaceStyle() -> UIUserInterfaceStyle {
        return _privateUserInterfaceStyle
    }
    
    @objc class func setUserInterfaceStyle(_ style: UIUserInterfaceStyle) {
        let oldUserInterfaceStyle = _userInterfaceStyle
        _privateUserInterfaceStyle = style
        applyUserInterfaceStyleOverride(style)
        
        _ = setPublicUIStyle()

        if oldUserInterfaceStyle == _userInterfaceStyle {
            return
        }
        
        NotificationCenter.default.post(
            name: Notification.Name(ThemeDidChangeNotification),
            object: nil
        )
    }

    @objc class func systemUserInterfaceStyleDidChange(_ style: UIUserInterfaceStyle) {
        guard #available(iOS 13.0, *) else { return }

        if _privateUserInterfaceStyle != .unspecified {
            applyUserInterfaceStyleOverride(_privateUserInterfaceStyle)
            return
        }

        let oldUserInterfaceStyle = _userInterfaceStyle
        _userInterfaceStyle = style
        applyUserInterfaceStyleOverride(.unspecified)

        if oldUserInterfaceStyle == _userInterfaceStyle {
            return
        }

        NotificationCenter.default.post(
            name: Notification.Name(ThemeDidChangeNotification),
            object: nil
        )
    }

    @objc class func applyUserInterfaceStyleOverride(_ style: UIUserInterfaceStyle) {
        guard #available(iOS 13.0, *) else { return }

        let applyOverride = {
            let sceneWindows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }

            let allWindows = sceneWindows + UIApplication.shared.windows
            Set(allWindows).forEach { window in
                window.overrideUserInterfaceStyle = style
            }
        }

        if Thread.isMainThread {
            applyOverride()
        } else {
            DispatchQueue.main.async(execute: applyOverride)
        }
    }
    
    @objc static var menuBackgroundColor: UIColor {
        return SunlightUITheme.surfaceColor()
    }
    
    @objc static var hostViewBackgroundColor: UIColor {
        return SunlightUITheme.sunkenColor()
    }
    
    @objc static var offlineHostIconBackgroundColor: UIColor {
        return SunlightUITheme.surfaceColor()
    }
    
    @objc static var widgetBackgroundColor: UIColor {
        return SunlightUITheme.raisedColor()
    }
    
    @objc static var separatorColor: UIColor {
        return SunlightUITheme.borderColor()
    }
    
    @objc static var legacySepratorColor: UIColor {
        return SunlightUITheme.borderColor()
    }

    @objc static var hostCardSeparatorColor: UIColor {
        return SunlightUITheme.borderColor()
    }
    
    @objc static var textColor: UIColor {
        return SunlightUITheme.primaryTextColor()
    }
    
    @objc static var sectionLabelTextColor: UIColor {
        return SunlightUITheme.accentColor()
    }
    
    @objc static var appPrimaryColor: UIColor {
        return SunlightUITheme.accentColor()
    }
    
    @objc static var appSecondaryColor: UIColor {
        return SunlightUITheme.deepAccentColor()
    }
    
    @objc static var appPrimaryColorWithAlpha: UIColor {
        return appPrimaryColor.withAlphaComponent(0.20)
    }
    
    @objc static var textTintColorWithAlpha: UIColor {
        return appPrimaryColor.withAlphaComponent(0.20)
    }
    
    @objc static var textColorGray: UIColor {
        return SunlightUITheme.secondaryTextColor()
    }
    
    @objc static var lowProfileGray: UIColor {
        return SunlightUITheme.disabledTextColor()
    }
    
    @available(iOS 26.0, *)
    @objc static var liquidGlassSwitchOffTint: UIColor {
        return SunlightUITheme.raisedColor()
    }
    
    @objc static var liquidGlassSliderMaxTrackTint: UIColor {
        return SunlightUITheme.borderColor()
    }
}
