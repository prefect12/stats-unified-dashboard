//
//  portal.swift
//  Battery
//
//  Created by Serhiy Mytrovtsiy on 16/03/2023
//  Using Swift 5.0
//  Running on macOS 13.2
//
//  Copyright © 2023 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class Portal: PortalWrapper {
    private let batteryView: BatteryView = BatteryView()
    
    private var levelField: NSTextField? = nil
    private var timeLabelField: NSTextField? = nil
    private var timeField: NSTextField? = nil
    private var statusField: NSTextField? = nil
    private var healthField: NSTextField? = nil

    private var timeFormat: String {
        Store.shared.string(key: "Battery_timeFormat", defaultValue: "short")
    }
    
    public override func load() {
        let chart = self.chartView()
        let details = self.detailsView()
        
        self.body.addArrangedSubview(chart)
        self.body.addArrangedSubview(details)
    }
    
    private func chartView() -> NSView {
        let view = NSStackView()
        view.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.addArrangedSubview(self.batteryView)
        return view
    }
    
    private func detailsView() -> NSView {
        let view = NSStackView()
        
        view.orientation = .vertical
        view.distribution = .fillEqually
        view.spacing = Constants.Popup.spacing*2
        
        self.levelField = portalRow(view, title: "\(localizedString("Level")):").1
        let time = portalRow(view, title: "\(localizedString("Time to discharge")):")
        self.timeLabelField = time.0
        self.timeField = time.1
        self.statusField = portalRow(view, title: "\(localizedString("Status")):").1
        self.healthField = portalRow(view, title: "\(localizedString("Health")):").1
        
        return view
    }
    
    public func loadCallback(_ value: Battery_Usage) {
        DispatchQueue.main.async(execute: {
            self.batteryView.setValue(abs(value.level), connected: !value.isBatteryPowered, charging: value.isCharging)
            
            self.levelField?.stringValue = "\(Int(abs(value.level) * 100))%"
            self.levelField?.toolTip = "\(value.currentCapacity) mAh"
            self.timeLabelField?.stringValue = "\(localizedString(value.isBatteryPowered ? "Time to discharge" : "Time to charge")):"
            self.timeField?.stringValue = self.timeValue(value)
            
            var status: String = localizedString("Charging")
            var color: NSColor = .systemGreen
            if value.isBatteryPowered {
                status = localizedString("On battery")
                color = value.level > 0.15 ? .textColor : .systemRed
            } else if !value.isCharging {
                if value.isCharged && value.level >= 1 {
                    status = localizedString("Plugged in")
                } else if value.optimizedChargingEngaged {
                    status = localizedString("On hold")
                    color = .systemGray
                }
            }
            self.statusField?.stringValue = status
            self.statusField?.textColor = color
            
            self.healthField?.stringValue = "\(value.health)%"
        })
    }

    private func timeValue(_ value: Battery_Usage) -> String {
        if value.isCharged {
            return localizedString("Fully charged")
        }
        if value.optimizedChargingEngaged {
            return localizedString("On hold")
        }

        let minutes = value.isBatteryPowered ? value.timeToEmpty : value.timeToCharge
        if minutes == -1 {
            return localizedString("Calculating")
        }
        if minutes <= 0 {
            return localizedString("Unknown")
        }
        return Double(minutes * 60).printSecondsToHoursMinutesSeconds(short: self.timeFormat == "short")
    }
}
