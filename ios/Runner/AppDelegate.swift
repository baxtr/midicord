import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController

    // Set up method channel for native file sharing
    let shareChannel = FlutterMethodChannel(name: "com.midicord/share",
                                            binaryMessenger: controller.binaryMessenger)

    shareChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "shareFile" {
        guard let args = call.arguments as? [String: Any],
              let filePath = args["path"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Path required", details: nil))
          return
        }
        self?.shareFile(at: filePath, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Set up method channel for video export
    let videoChannel = FlutterMethodChannel(name: "com.midicord/video",
                                            binaryMessenger: controller.binaryMessenger)

    videoChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "createVideo" {
        guard let args = call.arguments as? [String: Any],
              let framesData = args["frames"] as? [FlutterStandardTypedData],
              let outputPath = args["outputPath"] as? String,
              let fps = args["fps"] as? Int,
              let width = args["width"] as? Int,
              let height = args["height"] as? Int else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
          return
        }

        let audioPath = args["audioPath"] as? String
        let frames = framesData.map { $0.data }

        DispatchQueue.global(qos: .userInitiated).async {
          self.createVideo(
            frames: frames,
            audioPath: audioPath,
            outputPath: outputPath,
            fps: fps,
            width: width,
            height: height
          ) { success, error in
            DispatchQueue.main.async {
              if success {
                result(true)
              } else {
                result(FlutterError(code: "VIDEO_ERROR", message: error ?? "Unknown error", details: nil))
              }
            }
          }
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func shareFile(at path: String, result: @escaping FlutterResult) {
    let fileURL = URL(fileURLWithPath: path)

    guard FileManager.default.fileExists(atPath: path) else {
      result(FlutterError(code: "FILE_NOT_FOUND", message: "File does not exist", details: nil))
      return
    }

    DispatchQueue.main.async {
      let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)

      if let popover = activityVC.popoverPresentationController {
        popover.sourceView = self.window?.rootViewController?.view
        popover.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
      }

      activityVC.completionWithItemsHandler = { activityType, completed, returnedItems, error in
        if let error = error {
          result(FlutterError(code: "SHARE_ERROR", message: error.localizedDescription, details: nil))
        } else {
          result(completed)
        }
      }

      self.window?.rootViewController?.present(activityVC, animated: true, completion: nil)
    }
  }

  // MARK: - Video Export

  private func createVideo(
    frames: [Data],
    audioPath: String?,
    outputPath: String,
    fps: Int,
    width: Int,
    height: Int,
    completion: @escaping (Bool, String?) -> Void
  ) {
    let outputURL = URL(fileURLWithPath: outputPath)

    try? FileManager.default.removeItem(at: outputURL)

    guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
      completion(false, "Failed to create video writer")
      return
    }

    let videoSettings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height
    ]

    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    videoInput.expectsMediaDataInRealTime = false

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: videoInput,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height
      ]
    )

    writer.add(videoInput)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
    var frameCount = 0

    for frameData in frames {
      guard let image = UIImage(data: frameData),
            let pixelBuffer = self.pixelBuffer(from: image, width: width, height: height) else {
        continue
      }

      while !videoInput.isReadyForMoreMediaData {
        Thread.sleep(forTimeInterval: 0.01)
      }

      let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameCount))
      adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
      frameCount += 1
    }

    videoInput.markAsFinished()

    writer.finishWriting {
      if writer.status == .completed {
        if let audioPath = audioPath, FileManager.default.fileExists(atPath: audioPath) {
          self.mergeVideoWithAudio(videoPath: outputPath, audioPath: audioPath, completion: completion)
        } else {
          completion(true, nil)
        }
      } else {
        completion(false, writer.error?.localizedDescription ?? "Unknown error")
      }
    }
  }

  private func pixelBuffer(from image: UIImage, width: Int, height: Int) -> CVPixelBuffer? {
    let attrs: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
    ]

    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32ARGB,
      attrs as CFDictionary,
      &pixelBuffer
    )

    guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
      return nil
    }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

    guard let context = CGContext(
      data: CVPixelBufferGetBaseAddress(buffer),
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
    ) else {
      return nil
    }

    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)

    UIGraphicsPushContext(context)
    image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
    UIGraphicsPopContext()

    return buffer
  }

  private func mergeVideoWithAudio(
    videoPath: String,
    audioPath: String,
    completion: @escaping (Bool, String?) -> Void
  ) {
    let videoURL = URL(fileURLWithPath: videoPath)
    let audioURL = URL(fileURLWithPath: audioPath)

    let mixComposition = AVMutableComposition()

    let videoAsset = AVAsset(url: videoURL)
    guard let videoTrack = videoAsset.tracks(withMediaType: .video).first,
          let compositionVideoTrack = mixComposition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
          ) else {
      completion(false, "Failed to create video track")
      return
    }

    do {
      try compositionVideoTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: videoAsset.duration),
        of: videoTrack,
        at: .zero
      )
    } catch {
      completion(false, "Failed to insert video: \(error.localizedDescription)")
      return
    }

    let audioAsset = AVAsset(url: audioURL)
    if let audioTrack = audioAsset.tracks(withMediaType: .audio).first,
       let compositionAudioTrack = mixComposition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
       ) {
      do {
        let audioDuration = min(audioAsset.duration, videoAsset.duration)
        try compositionAudioTrack.insertTimeRange(
          CMTimeRange(start: .zero, duration: audioDuration),
          of: audioTrack,
          at: .zero
        )
      } catch {
        print("Audio insert error: \(error)")
      }
    }

    let outputURL = URL(fileURLWithPath: videoPath.replacingOccurrences(of: ".mp4", with: "_final.mp4"))
    try? FileManager.default.removeItem(at: outputURL)

    guard let exporter = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality) else {
      completion(false, "Failed to create exporter")
      return
    }

    exporter.outputURL = outputURL
    exporter.outputFileType = .mp4

    exporter.exportAsynchronously {
      DispatchQueue.main.async {
        switch exporter.status {
        case .completed:
          try? FileManager.default.removeItem(at: videoURL)
          try? FileManager.default.moveItem(at: outputURL, to: videoURL)
          completion(true, nil)
        case .failed:
          completion(false, exporter.error?.localizedDescription ?? "Export failed")
        default:
          completion(false, "Export cancelled")
        }
      }
    }
  }
}
