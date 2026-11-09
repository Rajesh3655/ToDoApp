import Flutter
import UIKit
import UserNotifications
import QuickLook
import CryptoKit
import Security

/// iOS uses OS-delivered local notifications. It does not emulate a ringing alarm.
@main
@objc class AppDelegate: FlutterAppDelegate, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
  private let center = UNUserNotificationCenter.current()
  private var nativeStore: NativeStore?
  private var secure = false
  private var privacyCover: UIView?
  private var previewURL: URL?
  private var previewResult: FlutterResult?
  private let prefix = "supare."
  private var operations: [() -> Void] = []
  private var operationInFlight = false

  /// Serialize capacity checks/replacement requests so concurrent Flutter saves cannot exceed the OS limit.
  private func enqueue(_ operation: @escaping (@escaping FlutterResult) -> Void, result: @escaping FlutterResult) {
    operations.append {
      operation { value in
        DispatchQueue.main.async {
          result(value)
          self.operationInFlight = false
          self.runNext()
        }
      }
    }
    runNext()
  }
  private func runNext() {
    guard !operationInFlight, !operations.isEmpty else { return }
    operationInFlight = true
    operations.removeFirst()()
  }

  override func application(_ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    center.delegate = self
    registerCategories()
    do {
      nativeStore = try NativeStore()
      try protectLocalFiles()
    } catch { NSLog("Supare secure native storage unavailable (contents withheld)") }
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "app.supare/native", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        self.handle(call, result: result)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func registerCategories() {
    let done = UNNotificationAction(identifier: "done", title: "Done", options: [.authenticationRequired])
    // iOS shows at most four custom actions. One text-input action supports all three intervals.
    let snooze = UNTextInputNotificationAction(identifier: "snooze", title: "Snooze (5, 10 or 15 min)", options: [],
      textInputButtonTitle: "Snooze", textInputPlaceholder: "5, 10 or 15")
    let stop = UNNotificationAction(identifier: "stop", title: "Stop", options: [])
    center.setNotificationCategories([
      UNNotificationCategory(identifier: "SUPARE_REMINDER", actions: [done, snooze, stop],
        intentIdentifiers: [], options: [.customDismissAction])
    ])
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "getCapabilities":
      center.getNotificationSettings { settings in
        DispatchQueue.main.async {
          result(["platform": "ios", "notifications": settings.authorizationStatus == .authorized,
                  "exactAlarms": false, "fullScreen": false, "alarmKit": false,
                  "alarmMode": "localNotificationFallback", "screenshotsBlocked": false,
                  "notificationLimit": 60,
                  "message": "iOS local notifications respect mute and Focus settings. Repeating ringtone and lock-screen alarm controls are unavailable in this build. Recurring notifications are scheduled for up to 8 occurrences; reopen Supare to refresh them."])
        }
      }
    case "requestAlarmPermissions":
      center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        DispatchQueue.main.async {
          if let error = error { result(self.flutterError("PERMISSION", error)) }
          else { result(granted) }
        }
      }
    case "scheduleTask":
      guard nativeStore != nil else { result(FlutterError(code: "LOCKED", message: "Unlock the device and reopen Supare before scheduling.", details: nil)); return }
      enqueue({ done in self.schedule(args, result: done) }, result: result)
    case "cancelTask":
      let id = (call.arguments as? String) ?? args["id"] as? String ?? ""
      guard !id.isEmpty else { result(FlutterError(code: "ARGUMENT", message: "Missing task ID", details: nil)); return }
      enqueue({ done in
        self.cancel(id) {
          do { try self.nativeStore?.removeTask(id); done(nil) }
          catch { done(self.flutterError("STORAGE", error)) }
        }
      }, result: result)
    case "setSecure":
      secure = (call.arguments as? Bool) ?? args["secure"] as? Bool ?? args["enabled"] as? Bool ?? false
      if !secure { privacyCover?.removeFromSuperview(); privacyCover = nil }
      result(nil)
    case "drainActions":
      do {
        guard let store = nativeStore else { throw NativeError.unavailable }
        result(store.drainActions())
      } catch { result(flutterError("STORAGE", error)) }
    case "ackActions":
      guard let eventIDs = args["eventIds"] as? [String] else { result(FlutterError(code: "ARGUMENT", message: "Missing native event IDs", details: nil)); return }
      do {
        guard let store = nativeStore else { throw NativeError.unavailable }
        try store.ackActions(eventIDs); result(nil)
      } catch { result(flutterError("STORAGE", error)) }
    case "previewFile":
      guard let path = args["path"] as? String else { result(FlutterError(code: "ARGUMENT", message: "Missing file path", details: nil)); return }
      let url = URL(fileURLWithPath: path).standardizedFileURL
      guard url.path.hasPrefix(NSHomeDirectory() + "/"), FileManager.default.fileExists(atPath: path),
            ["pdf", "jpg", "jpeg", "png", "heic", "heif", "webp"].contains(url.pathExtension.lowercased()) else {
        result(FlutterError(code: "FILE", message: "Unsupported local preview file", details: nil)); return
      }
      guard previewURL == nil else { result(FlutterError(code: "BUSY", message: "A document preview is already open", details: nil)); return }
      do {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var protectedURL = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try protectedURL.setResourceValues(values)
      } catch { result(flutterError("FILE", error)); return }
      previewURL = url
      previewResult = result
      let controller = QLPreviewController(); controller.dataSource = self; controller.delegate = self
      var presenter = window?.rootViewController
      while let next = presenter?.presentedViewController { presenter = next }
      guard let presenter = presenter else { previewURL = nil; previewResult = nil; result(FlutterError(code: "VIEW", message: "Preview is unavailable", details: nil)); return }
      presenter.present(controller, animated: true)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func schedule(_ task: [String: Any], result: @escaping FlutterResult) {
    guard let id = task["id"] as? String, !id.isEmpty,
          let title = task["title"] as? String, !title.isEmpty,
          let due = task["dueMillis"] as? NSNumber else {
      result(FlutterError(code: "ARGUMENT", message: "Invalid task ID, title or due time", details: nil)); return
    }
    let dueDate = Date(timeIntervalSince1970: due.doubleValue / 1000)
    let repeatRule = task["repeat"] as? String ?? "none"
    guard dueDate > Date() || ["daily", "weekly", "monthly", "custom"].contains(repeatRule) else {
      result(FlutterError(code: "PAST_DUE", message: "Choose a future reminder time", details: nil)); return
    }
    center.getNotificationSettings { settings in
      guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
        DispatchQueue.main.async { result(FlutterError(code: "PERMISSION", message: "Allow Supare notifications in iOS Settings to receive reminders.", details: nil)) }; return
      }
      self.center.getPendingNotificationRequests { pending in
        let previous = pending.filter { ($0.content.userInfo["supareID"] as? String) == id }
        let otherCount = pending.count - previous.count
        let dates = NativeSchedule.futureDates(due: dueDate, repeatRule: repeatRule,
          intervalDays: (task["intervalDays"] as? NSNumber)?.intValue ?? 1, after: Date(),
          anchorDay: (task["anchorDay"] as? NSNumber)?.intValue)
        guard otherCount + dates.count <= 60 else {
          DispatchQueue.main.async { result(FlutterError(code: "LIMIT", message: "iOS supports a limited number of pending reminders. Reduce recurring reminders and reopen Supare to refresh schedules.", details: nil)) }; return
        }
        // Prepare validated replacement; only remove this task's existing requests.
        self.center.removePendingNotificationRequests(withIdentifiers: previous.map { $0.identifier })
        let group = DispatchGroup()
        let lock = NSLock()
        var firstError: Error?
        var created: [String] = []
        for (index, date) in dates.enumerated() {
          let content = UNMutableNotificationContent()
          content.title = title
          content.body = task["body"] as? String ?? ""
          content.sound = .default
          content.categoryIdentifier = "SUPARE_REMINDER"
          content.threadIdentifier = id
          content.userInfo = ["supareID": id, "dueMillis": Int64(date.timeIntervalSince1970 * 1000)]
          if #available(iOS 15.0, *), task["mode"] as? String == "alarm" { content.interruptionLevel = .timeSensitive }
          let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
          let identifier = self.prefix + id + "." + String(index)
          created.append(identifier)
          let request = UNNotificationRequest(identifier: identifier, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
          group.enter()
          self.center.add(request) { error in
            lock.lock(); if firstError == nil { firstError = error }; lock.unlock(); group.leave()
          }
        }
        group.notify(queue: .main) {
          if let error = firstError {
            self.center.removePendingNotificationRequests(withIdentifiers: created)
            // Restore previous schedules on an OS delivery failure.
            for request in previous { self.center.add(request, withCompletionHandler: nil) }
            result(self.flutterError("SCHEDULE", error)); return
          }
          do { try self.nativeStore?.saveTask(task, id: id); result(nil) }
          catch {
            self.center.removePendingNotificationRequests(withIdentifiers: created)
            for request in previous { self.center.add(request, withCompletionHandler: nil) }
            result(self.flutterError("STORAGE", error))
          }
        }
      }
    }
  }

  private func cancel(_ id: String, completion: @escaping () -> Void) {
    center.getPendingNotificationRequests { requests in
      let ids = requests.filter { ($0.content.userInfo["supareID"] as? String) == id }.map { $0.identifier }
      self.center.removePendingNotificationRequests(withIdentifiers: ids)
      self.center.getDeliveredNotifications { delivered in
        self.center.removeDeliveredNotifications(withIdentifiers: delivered.filter {
          ($0.request.content.userInfo["supareID"] as? String) == id
        }.map { $0.request.identifier })
        DispatchQueue.main.async(execute: completion)
      }
    }
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
      willPresent notification: UNNotification,
      withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if #available(iOS 14.0, *) { completionHandler([.banner, .sound, .list]) }
    else { completionHandler([.alert, .sound]) }
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
      didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    guard let id = response.notification.request.content.userInfo["supareID"] as? String else {
      super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler); return
    }
    let action = response.actionIdentifier
    // Opening a reminder is not a dismissal or completion.
    if action == UNNotificationDefaultActionIdentifier { completionHandler(); return }
    let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
    var event: [String: Any] = ["id": id, "action": "stop", "atMillis": nowMillis,
      "dueMillis": response.notification.request.content.userInfo["dueMillis"] as? NSNumber ?? NSNumber(value: nowMillis),
      "eventId": response.notification.request.identifier + ":" + String(response.notification.date.timeIntervalSince1970)]
    if action == "done" { event["action"] = "done" }
    var minutes: Int?
    if action == "snooze" {
      let text = (response as? UNTextInputNotificationResponse)?.userText.trimmingCharacters(in: .whitespacesAndNewlines) ?? "5"
      let parsed = Int(text) ?? 5
      minutes = [5, 10, 15].contains(parsed) ? parsed : 5
    }
    if let minutes = minutes {
      event["action"] = "snooze"; event["minutes"] = minutes
      event["dueMillis"] = nowMillis + Int64(minutes * 60_000)
    }
    do {
      guard let store = nativeStore else { throw NativeError.unavailable }
      try store.appendAction(event)
      if action == "done" {
        // Keep future occurrences scheduled; Flutter reconciles completion when reopened.
        center.removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier])
        completionHandler()
      } else if let minutes = minutes {
        let content = response.notification.request.content.mutableCopy() as! UNMutableNotificationContent
        content.userInfo["dueMillis"] = event["dueMillis"]
        let request = UNNotificationRequest(identifier: prefix + id + ".snooze", content: content,
          trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(minutes * 60), repeats: false))
        center.add(request) { _ in completionHandler() }
      } else { completionHandler() }
    } catch { completionHandler() }
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    if secure, let window = window, privacyCover == nil {
      let cover = UIView(frame: window.bounds)
      cover.backgroundColor = UIColor(red: 0.05, green: 0.12, blue: 0.11, alpha: 1)
      cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      let label = UILabel(frame: cover.bounds); label.text = "Supare · Wallet locked"
      label.textColor = .white; label.textAlignment = .center
      label.autoresizingMask = [.flexibleWidth, .flexibleHeight]; cover.addSubview(label)
      window.addSubview(cover); privacyCover = cover
    }
    super.applicationWillResignActive(application)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    privacyCover?.removeFromSuperview(); privacyCover = nil
    super.applicationDidBecomeActive(application)
    // Extend the bounded recurrence horizon even when Flutter keeps an overdue occurrence pending.
    for task in nativeStore?.tasks() ?? [] {
      guard let rule = task["repeat"] as? String, rule != "none" else { continue }
      enqueue({ done in self.schedule(task, result: done) }, result: { _ in })
    }
  }

  private func protectLocalFiles() throws {
    for directory in [FileManager.SearchPathDirectory.documentDirectory, .applicationSupportDirectory] {
      let url = try FileManager.default.url(for: directory, in: .userDomainMask, appropriateFor: nil, create: true)
      var mutableURL = url
      var values = URLResourceValues(); values.isExcludedFromBackup = true
      try mutableURL.setResourceValues(values)
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
    }
    let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    for directory in [caches, URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)] {
      var protectedURL = directory
      var values = URLResourceValues(); values.isExcludedFromBackup = true
      try protectedURL.setResourceValues(values)
      // Imported and shared plaintext intermediates inherit complete device-lock protection.
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
    }
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }
  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { previewURL! as NSURL }
  func previewControllerDidDismiss(_ controller: QLPreviewController) {
    if let url = previewURL { try? FileManager.default.removeItem(at: url) }
    previewURL = nil
    previewResult?(nil); previewResult = nil
  }
  private func flutterError(_ code: String, _ error: Error) -> FlutterError {
    FlutterError(code: code, message: error.localizedDescription, details: nil)
  }
}

enum NativeError: LocalizedError {
  case unavailable, corrupt
  var errorDescription: String? {
    switch self {
    case .unavailable: return "Device protected storage is unavailable; unlock the device and reopen Supare."
    case .corrupt: return "Native reminder storage failed integrity validation."
    }
  }
}

/// Bounded horizon because iOS permits at most 64 pending local notifications per app.
enum NativeSchedule {
  private static func occurrence(due: Date, component: Calendar.Component, offset: Int, anchorDay: Int?) -> Date? {
    let calendar = Calendar.current
    guard let target = calendar.date(byAdding: component, value: offset, to: due) else { return nil }
    guard component == .month, offset > 0, let day = anchorDay else { return target }
    guard let range = calendar.range(of: .day, in: .month, for: target) else { return nil }
    var parts = calendar.dateComponents([.year, .month, .hour, .minute, .second, .nanosecond], from: target)
    parts.day = min(max(1, day), range.count)
    return calendar.date(from: parts)
  }

  static func futureDates(due: Date, repeatRule: String, intervalDays: Int, after: Date, anchorDay: Int? = nil) -> [Date] {
    if due > after { return dates(due: due, repeatRule: repeatRule, intervalDays: intervalDays, anchorDay: anchorDay) }
    if repeatRule == "none" { return [] }
    let calendar = Calendar.current
    let component: Calendar.Component = repeatRule == "monthly" ? .month : .day
    let unit = repeatRule == "weekly" ? 7 : (repeatRule == "custom" ? max(1, min(intervalDays, 3650)) : 1)
    let difference = calendar.dateComponents([component], from: due, to: after).value(for: component) ?? 0
    var index = max(0, difference / unit)
    var output: [Date] = []
    while output.count < 8 {
      guard let next = occurrence(due: due, component: component, offset: index * unit,
        anchorDay: anchorDay ?? calendar.component(.day, from: due)) else { break }
      if next > after { output.append(next) }
      index += 1
    }
    return output
  }

  static func dates(due: Date, repeatRule: String, intervalDays: Int, anchorDay: Int? = nil) -> [Date] {
    if repeatRule == "none" { return [due] }
    var dates = [due]
    for index in 1..<8 {
      let component: Calendar.Component
      let multiple: Int
      switch repeatRule {
      case "daily": component = .day; multiple = 1
      case "weekly": component = .day; multiple = 7
      case "monthly": component = .month; multiple = 1
      case "custom": component = .day; multiple = max(1, min(intervalDays, 3650))
      default: return [due]
      }
      if let date = occurrence(due: due, component: component, offset: index * multiple,
        anchorDay: anchorDay ?? Calendar.current.component(.day, from: due)) { dates.append(date) }
    }
    return dates
  }
}

/// Only encrypted task snapshots and queued action IDs are persisted outside Flutter.
final class NativeStore {
  private let url: URL
  private let key: SymmetricKey
  private var root: [String: Any] = ["tasks": [String: Any](), "actions": [[String: Any]]()]
  private let lock = NSRecursiveLock()
  init() throws {
    let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true)
    url = directory.appendingPathComponent("supare-native-v1.bin")
    key = try NativeStore.loadKey()
    if FileManager.default.fileExists(atPath: url.path) {
      let data = try Data(contentsOf: url)
      let box = try AES.GCM.SealedBox(combined: data)
      let plain = try AES.GCM.open(box, using: key, authenticating: Data("supare.native.v1".utf8))
      guard let parsed = try JSONSerialization.jsonObject(with: plain) as? [String: Any] else { throw NativeError.corrupt }
      root = parsed
    }
  }
  private static func loadKey() throws -> SymmetricKey {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "app.supare.native", kSecAttrAccount as String: "aes256-v1"]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query.merging([kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne]) { _, new in new } as CFDictionary, &item)
    if status == errSecSuccess, let data = item as? Data, data.count == 32 { return SymmetricKey(data: data) }
    guard status == errSecItemNotFound else { throw NativeError.unavailable }
    var bytes = Data(count: 32)
    let randomStatus = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
    guard randomStatus == errSecSuccess else { throw NativeError.unavailable }
    let insertion = query.merging([kSecValueData as String: bytes,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]) { _, new in new }
    guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else { throw NativeError.unavailable }
    return SymmetricKey(data: bytes)
  }
  private func persist() throws {
    let plain = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    let box = try AES.GCM.seal(plain, using: key, authenticating: Data("supare.native.v1".utf8))
    guard let encrypted = box.combined else { throw NativeError.corrupt }
    try encrypted.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    var mutableURL = url
    var values = URLResourceValues(); values.isExcludedFromBackup = true
    try mutableURL.setResourceValues(values)
  }
  func tasks() -> [[String: Any]] {
    lock.lock(); defer { lock.unlock() }
    return (root["tasks"] as? [String: [String: Any]] ?? [:]).values.map { $0 }
  }
  func saveTask(_ task: [String: Any], id: String) throws {
    lock.lock(); defer { lock.unlock() }
    let previous = root
    var tasks = root["tasks"] as? [String: Any] ?? [:]; tasks[id] = task; root["tasks"] = tasks
    do { try persist() } catch { root = previous; throw error }
  }
  func removeTask(_ id: String) throws {
    lock.lock(); defer { lock.unlock() }
    let previous = root
    var tasks = root["tasks"] as? [String: Any] ?? [:]; tasks.removeValue(forKey: id); root["tasks"] = tasks
    do { try persist() } catch { root = previous; throw error }
  }
  func appendAction(_ action: [String: Any]) throws {
    lock.lock(); defer { lock.unlock() }
    let previous = root
    var actions = root["actions"] as? [[String: Any]] ?? []
    var handled = root["handled"] as? [String] ?? []
    if let eventID = action["eventId"] as? String {
      if handled.contains(eventID) { return }
      handled.append(eventID)
      root["handled"] = Array(handled.suffix(256))
    }
    actions.append(action); root["actions"] = actions
    do { try persist() } catch { root = previous; throw error }
  }
  func drainActions() -> [[String: Any]] {
    lock.lock(); defer { lock.unlock() }
    return root["actions"] as? [[String: Any]] ?? []
  }
  func ackActions(_ eventIDs: [String]) throws {
    lock.lock(); defer { lock.unlock() }
    let previous = root
    let acknowledged = Set(eventIDs)
    let actions = root["actions"] as? [[String: Any]] ?? []
    root["actions"] = actions.filter { event in
      guard let eventID = event["eventId"] as? String else { return true }
      return !acknowledged.contains(eventID)
    }
    do { try persist() } catch { root = previous; throw error }
  }
}
