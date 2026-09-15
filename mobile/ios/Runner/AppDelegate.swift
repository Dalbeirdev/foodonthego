import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    /*
     The Google Maps SDK key, before any map view exists.

     The iOS Maps SDK requires this call before the first GMSMapView is created
     and offers no other way in — a --dart-define never reaches it. Until
     Restart Module 06 the call was missing entirely, so the moment anybody
     supplied a key the app would have turned its map on (MapsConfig reads the
     Dart define) and the SDK would have had nothing to authenticate with,
     which on iOS throws rather than degrading. That is the "iOS map is blank"
     outcome arriving on the day the credential did.

     Read from Info.plist rather than hard-coded, so the key is a build setting
     and never a literal in the repository. Empty here, because no key exists
     (MF-08): an empty or missing value is left unprovided rather than passed
     in, since providing an empty key is what makes the SDK throw.
     */
    let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String
    if let key, !key.trimmingCharacters(in: .whitespaces).isEmpty {
      GMSServices.provideAPIKey(key)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
