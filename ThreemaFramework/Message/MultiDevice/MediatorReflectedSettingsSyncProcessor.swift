//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2021-2022 Threema GmbH
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

import Foundation
import PromiseKit

class MediatorReflectedSettingsSyncProcessor {

    private let frameworkInjector: FrameworkInjectorProtocol

    required init(frameworkInjector: FrameworkInjectorProtocol) {
        self.frameworkInjector = frameworkInjector
    }

    func process(settingsSync: D2d_SettingsSync) -> Promise<Void> {
        let syncSettings = settingsSync.set.settings

        let settingsStore = SettingsStore(
            serverConnector: frameworkInjector.serverConnector,
            myIdentityStore: frameworkInjector.myIdentityStore,
            contactStore: frameworkInjector.contactStore,
            userSettings: frameworkInjector.userSettings,
            taskManager: nil
        )
        settingsStore.save(syncSettings: syncSettings)

        NotificationCenter.default.post(
            name: NSNotification.Name(rawValue: kNotificationIncomingSettingsSynchronization),
            object: nil
        )

        return Promise()
    }
}
