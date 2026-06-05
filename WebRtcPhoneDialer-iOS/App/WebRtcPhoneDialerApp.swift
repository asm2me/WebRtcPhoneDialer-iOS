import SwiftUI

@main
struct WebRtcPhoneDialerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var sipService = SIPService()
    @StateObject private var callHistory = CallHistoryService()
    @StateObject private var updateService = UpdateService()

    var body: some Scene {
        WindowGroup {
            DialerView()
                .environmentObject(sipService)
                .environmentObject(callHistory)
                .environmentObject(updateService)
                .preferredColorScheme(.dark)
                .task { await updateService.checkOnLaunch() }
        }
    }
}
