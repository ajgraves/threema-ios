//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2022-2024 Threema GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License, version 3,
// as published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import CocoaLumberjackSwift
import Intents
import SwiftUI
import ThreemaFramework

struct DeveloperSettingsView: View {
        
    // Multi-Device
    @State var allowSeveralDevices = UserSettings.shared().allowSeveralLinkedDevices
    @State private var showDebugDeviceJoin = false
    
    // Feature Flags
    @State var enableFSv12 = UserSettings.shared().enableFSv12ForTesting
    
    // Group Calls
    @State var groupCallsDebugMessages = UserSettings.shared().groupCallsDebugMessages
    
    var body: some View {
        List {
            Section("UI") {
                NavigationLink {
                    UIComponentsView()
                } label: {
                    Text("UI Components Debug View")
                }
                
                NavigationLink {
                    StyleKitView()
                } label: {
                    Text("StyleKit Debug View")
                }
                
                NavigationLink {
                    IDColorsView()
                } label: {
                    Text("ID Colors Debug View")
                }
                
                NavigationLink {
                    LaunchModalSettingsView()
                } label: {
                    Text("Launch Modals")
                }
            }
            
            Section("Multi-Device") {
                Toggle(isOn: $allowSeveralDevices) {
                    Text("Allow several linked devices")
                }
                .onChange(of: allowSeveralDevices) { newValue in
                    UserSettings.shared().allowSeveralLinkedDevices = newValue
                }
                
                Button("Show Debug Device Join") {
                    showDebugDeviceJoin = true
                }
                
                NavigationLink {
                    LinkedDevicesView()
                } label: {
                    Text("Linked Device (beta)")
                }
                
                NavigationLink {
                    MultiDeviceViewControllerRepresentable()
                } label: {
                    Text("Old Linking")
                }
            }
            
            Section("Feature Flags") {
                if ThreemaEnvironment.env() == .xcode {
                    Toggle(isOn: $enableFSv12) {
                        Text("Enable PFS 1.2")
                    }
                    .onChange(of: enableFSv12) { newValue in
                        UserSettings.shared().enableFSv12ForTesting = newValue
                        exit(1)
                    }
                    .disabled(UserSettings.shared().enableMultiDevice)
                }
            }
            
            Section("Group Calls") {
                Toggle(isOn: $groupCallsDebugMessages) {
                    Text("Send Debug Messages for Group Calls")
                }
                .onChange(of: groupCallsDebugMessages) { newValue in
                    UserSettings.shared().groupCallsDebugMessages = newValue
                }
            }
            
            Section {
                Button("Terminate All FS Session") {
                    let businessInjector = BusinessInjector()
                    let terminator = try! ForwardSecuritySessionTerminator(businessInjector: businessInjector)
                    
                    businessInjector.entityManager.performAndWait {
                        for contact in businessInjector.entityManager.entityFetcher
                            .allContacts() as? [ContactEntity] ?? [] {
                            try! terminator.terminateAllSessions(with: contact, cause: .reset)
                        }
                    }
                }
                Button("🚨 Delete All FS Sessions") {
                    let businessInjector = BusinessInjector()
                    let terminator = try! ForwardSecuritySessionTerminator(businessInjector: businessInjector)
                    
                    businessInjector.entityManager.performAndWait {
                        for contact in businessInjector.entityManager.entityFetcher
                            .allContacts() as? [ContactEntity] ?? [] {
                            try! terminator.deleteAllSessions(with: contact)
                        }
                    }
                }
                if ThreemaEnvironment.env() == .xcode {
                    Button("🚨 Delete Database, Settings & All Files") {
                        // DB & Files
                        FileUtility.removeItemsInAllDirectories()
                        AppGroup.resetUserDefaults()
                        DatabaseManager().eraseDB()
                        exit(0)
                    }
                }
            } header: {
                Text("🚨🚨🚨 FS State Deletion")
            }
            footer: {
                Text("This will delete data without any additional confirmation!")
                    .bold()
                    .foregroundColor(.red)
            }
        }
        .navigationBarTitle("Developer Settings", displayMode: .inline)
        .tint(UIColor.primary.color)
        .sheet(isPresented: $showDebugDeviceJoin) {
            DebugDeviceJoinView()
        }
    }
}

struct DevModeView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            DeveloperSettingsView()
        }
    }
}

// MARK: - ViewController Representables

private struct UIComponentsView: UIViewControllerRepresentable {
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) { }
    
    func makeUIViewController(context: Context) -> some UIViewController {
        let storyboard = UIStoryboard(name: "SettingsStoryboard", bundle: nil)
        let vc = storyboard.instantiateViewController(identifier: "ComponentsVC")
        return vc
    }
}

private struct StyleKitView: UIViewControllerRepresentable {
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) { }
    
    func makeUIViewController(context: Context) -> some UIViewController {
        let storyboard = UIStoryboard(name: "SettingsStoryboard", bundle: nil)
        let vc = storyboard.instantiateViewController(identifier: "StyleKitVC")
        return vc
    }
}

private struct IDColorsView: UIViewControllerRepresentable {
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) { }
    
    func makeUIViewController(context: Context) -> some UIViewController {
        let storyboard = UIStoryboard(name: "SettingsStoryboard", bundle: nil)
        let vc = storyboard.instantiateViewController(identifier: "IDColorsVC")
        return vc
    }
}
