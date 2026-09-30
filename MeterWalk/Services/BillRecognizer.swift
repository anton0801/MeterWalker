//
//  BillRecognizer.swift
//  MeterWalk
//
//  Pulls the amount and the period dates off a photo of a bill, on the
//  device. Everything it finds is only a suggestion: the bill form will not
//  save until the user has checked it.
//

import UIKit
import Vision

enum BillRecognizer {
    static func recognize(image: UIImage, completion: @escaping (RecognizedBill) -> Void) {
        guard let cg = image.normalizedUp().cgImage else {
            completion(RecognizedBill())
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
            var lines: [String] = []
            do {
                try handler.perform([request])
                lines = (request.results ?? [])
                    .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                    .compactMap { $0.topCandidates(1).first?.string }
            } catch {
                lines = []
            }
            let result = BillTextParser.parse(lines: lines)
            DispatchQueue.main.async { completion(result) }
        }
    }
}
