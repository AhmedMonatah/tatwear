import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let printerChannelName = "com.tatweer/honeywell_printer"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    let channel = FlutterMethodChannel(
      name: printerChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handlePrinterCall(call, result: result)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handlePrinterCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "listPrinters", "listAllBondedDevices":
      result(HoneywellPrinterBridge.availablePrinters())
    case "printPdf", "printTest":
      guard let arguments = call.arguments as? [String: Any],
            let address = arguments["address"] as? String,
            let printerId = arguments["printerId"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Printer address and profile are required.", details: nil))
        return
      }
      let testOnly = call.method == "printTest"
      let pdfData: Data
      if testOnly {
        pdfData = Data()
      } else if let typedData = arguments["pdfBytes"] as? FlutterStandardTypedData {
        pdfData = typedData.data
      } else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Invoice PDF is required.", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        var error: NSError?
        let response = HoneywellPrinterBridge.printPdf(
          pdfData,
          address: address,
          printerId: printerId,
          testOnly: testOnly,
          error: &error
        )
        DispatchQueue.main.async {
          if let error {
            result(FlutterError(
              code: "HONEYWELL_PRINT_FAILED",
              message: error.localizedDescription,
              details: error.description
            ))
          } else {
            result(response)
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
