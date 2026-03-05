import SwiftUI

@main
struct WebRtcPhoneDialerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var sipService = SIPService()
    @StateObject private var callHistory = CallHistoryService()

    var body: some Scene {
        WindowGroup {
            DialerView()
                .environmentObject(sipService)
                .environmentObject(callHistory)
                .preferredColorScheme(.dark)
        }
    }
}
