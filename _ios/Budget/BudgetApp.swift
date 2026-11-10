import SwiftUI

@main
struct BudgetApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea()
                .background(Color(red: 244/255, green: 246/255, blue: 251/255))
                .preferredColorScheme(.light)
        }
    }
}
