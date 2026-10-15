import UIKit
import FirebaseCore
import FirebaseMessaging
import AppTrackingTransparency
import UserNotifications
import AppsFlyerLib

final class AppDelegate: UIResponder, UIApplicationDelegate {

    private lazy var pedometer = Pedometer { payload in
        NotificationCenter.default.post(name: .strode, object: nil, userInfo: ["conversionData": payload])
    }

    private var spokes: [NSObjectProtocol] = []

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        wireSpokes(application)
        NotificationCenter.default.post(name: .assemble, object: nil)

        if let cold = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            read(cold)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(roused), name: UIApplication.didBecomeActiveNotification, object: nil)
        return true
    }

    private func wireSpokes(_ application: UIApplication) {
        let nc = NotificationCenter.default
        spokes.append(nc.addObserver(forName: .assemble, object: nil, queue: .main) { _ in
            FirebaseApp.configure()
        })
        spokes.append(nc.addObserver(forName: .assemble, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            let sdk = AppsFlyerLib.shared()
            sdk.appsFlyerDevKey = Tariff.relayKey
            sdk.appleAppID = Tariff.appCode
            sdk.delegate = self
            sdk.deepLinkDelegate = self
            sdk.isDebug = false
        })
        spokes.append(nc.addObserver(forName: .assemble, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Messaging.messaging().delegate = self
            UNUserNotificationCenter.current().delegate = self
            application.registerForRemoteNotifications()
        })
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    @objc private func roused() {
        guard #available(iOS 14, *) else { return AppsFlyerLib.shared().start() }
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
        ATTrackingManager.requestTrackingAuthorization { status in
            DispatchQueue.main.async {
                AppsFlyerLib.shared().start()
                UserDefaults.standard.set(status.rawValue, forKey: Dials.att)
            }
        }
    }

    private func read(_ payload: [AnyHashable: Any]) {
        clock(payload)

        var found: String?
        if let direct = payload["url"] as? String, direct.isEmpty == false {
            found = direct
        } else if let data = payload["data"] as? [AnyHashable: Any], let url = data["url"] as? String, url.isEmpty == false {
            found = url
        } else if let aps = payload["aps"] as? [AnyHashable: Any],
                  let data = aps["data"] as? [AnyHashable: Any],
                  let url = data["url"] as? String, url.isEmpty == false {
            found = url
        } else if let custom = payload["custom"] as? [AnyHashable: Any], let url = custom["url"] as? String, url.isEmpty == false {
            found = url
        }
        guard let link = found else { return }

        UserDefaults.standard.set(link, forKey: Dials.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NotificationCenter.default.post(name: .pinged, object: nil, userInfo: ["temp_url": link])
        }
    }

    private func clock(_ payload: [AnyHashable: Any]) {
        var raw: Any?
        if let data = payload["data"] as? [AnyHashable: Any], let value = data["message_id"] {
            raw = value
        } else if let value = payload["message_id"] {
            raw = value
        }
        guard let raw = raw else { return }
        let message = "\(raw)"
        guard message.isEmpty == false, message.count <= 128 else { return }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard message.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return }

        let af = AppsFlyerLib.shared().getAppsFlyerUID()
        guard af.isEmpty == false else { return }
        guard var comps = URLComponents(string: Tariff.interaction) else { return }
        comps.queryItems = [URLQueryItem(name: "message_id", value: message)]
        guard let url = comps.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["af_id": af])
        URLSession.shared.dataTask(with: request).resume()
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        messaging.token { token, error in
            guard error == nil, let token = token else { return }
            UserDefaults.standard.set(token, forKey: Dials.fcm)
            UserDefaults.standard.set(token, forKey: Dials.push)
            UserDefaults(suiteName: Tariff.suite)?.set(token, forKey: Dials.sharedFcm)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        read(notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        read(response.notification.request.content.userInfo)
        completionHandler()
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        read(userInfo)
        completionHandler(.newData)
    }
}

extension AppDelegate: AppsFlyerLibDelegate, DeepLinkDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        pedometer.gather(conversionInfo)
    }

    func onConversionDataFail(_ error: Error) {
    }

    func didResolveDeepLink(_ result: DeepLinkResult) {
        guard case .found = result.status, let deepLink = result.deepLink else { return }
        guard UserDefaults.standard.bool(forKey: Dials.primed) == false else { return }
        NotificationCenter.default.post(name: .veered, object: nil, userInfo: ["deeplinksData": deepLink.clickEvent])
        pedometer.annex(deepLink.clickEvent)
    }
}
