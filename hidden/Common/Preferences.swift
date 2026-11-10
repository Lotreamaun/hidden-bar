//
//  Preferences.swift
//  Hidden Bar
//
//  Created by phucld on 12/18/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Foundation

enum Preferences {
    
    static var isAutoStart: Bool {
        get {
            return UserDefaults.standard.bool(forKey: UserDefaults.Key.isAutoStart)
        }
        
        set {
            // Apply first, then persist the outcome: on failure the stored value
            // stays at the previous state so the menu's checkmark shows reality
            // instead of the intent.
            let applied = Util.setUpAutoStart(isAutoStart: newValue)
            UserDefaults.standard.set(applied ? newValue : isAutoStart, forKey: UserDefaults.Key.isAutoStart)

            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }
    
    static var numberOfSecondForAutoHide: Double {
        get {
            UserDefaults.standard.double(forKey: UserDefaults.Key.numberOfSecondForAutoHide)
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.numberOfSecondForAutoHide)
            
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }
    
    static var isAutoHide: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.isAutoHide)
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.isAutoHide)
            
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }
    
    static var hoverToExpand: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.hoverToExpand)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.hoverToExpand)
        }
    }
}
