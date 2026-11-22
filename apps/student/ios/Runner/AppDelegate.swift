import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let textToSpeech = SchoolTextToSpeech()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SchoolTextToSpeech") {
      textToSpeech.attach(to: registrar.messenger())
    }
  }
}

/// قراءة ردود المساعد بصوت عربي (القناة نفسها `dz.school.assistant/tts` كما في Android).
final class SchoolTextToSpeech: NSObject {
  private let synthesizer = AVSpeechSynthesizer()
  private var channel: FlutterMethodChannel?

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "dz.school.assistant/tts", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "speak":
        self.speak(call.arguments, result: result)
      case "stop":
        self.synthesizer.stopSpeaking(at: .immediate)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  private func speak(_ arguments: Any?, result: FlutterResult) {
    let text = ((arguments as? [String: Any])?["text"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if text.isEmpty || text.count > 6000 {
      result(FlutterError(code: "invalid_text", message: "نص القراءة الصوتية فارغ أو طويل جداً", details: nil))
      return
    }
    guard let voice = SchoolTextToSpeech.arabicVoice() else {
      result(FlutterError(code: "speech_unavailable", message: "لا يتوفر صوت عربي على هذا الجهاز", details: nil))
      return
    }
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    try? AVAudioSession.sharedInstance().setActive(true)
    synthesizer.stopSpeaking(at: .immediate)
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = voice
    synthesizer.speak(utterance)
    result(true)
  }

  private static func arabicVoice() -> AVSpeechSynthesisVoice? {
    for code in ["ar-DZ", "ar-001", "ar-SA"] {
      if let voice = AVSpeechSynthesisVoice(language: code) { return voice }
    }
    return AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("ar") }
  }
}
