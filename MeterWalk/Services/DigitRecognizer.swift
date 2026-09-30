//
//  DigitRecognizer.swift
//  MeterWalk
//
//  Reads the number window of a meter with Vision, on the device. The meter's
//  digit layout decides where the decimal point goes, so a red fraction drum
//  is never mistaken for part of the whole number.
//

import UIKit
import Vision

enum DigitRecognizer {
    static func recognize(
        image: UIImage,
        digitsBefore: Int,
        digitsAfter: Int,
        completion: @escaping (RecognizedReading?) -> Void
    ) {
        guard let cg = image.normalizedUp().cgImage else {
            completion(nil)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0.08
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
            var result: RecognizedReading?
            do {
                try handler.perform([request])
                let observations = request.results ?? []
                result = parse(observations: observations, digitsBefore: digitsBefore, digitsAfter: digitsAfter)
            } catch {
                result = nil
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: Parsing

    private struct Piece {
        let text: String
        let confidence: Float
        let box: CGRect
    }

    static func parse(observations: [VNRecognizedTextObservation], digitsBefore: Int, digitsAfter: Int) -> RecognizedReading? {
        var pieces: [Piece] = []
        for observation in observations {
            for candidate in observation.topCandidates(3) {
                pieces.append(Piece(text: candidate.string, confidence: candidate.confidence, box: observation.boundingBox))
            }
        }
        guard !pieces.isEmpty else { return nil }

        // Also try each line joined left to right: the whole-number drum and
        // the red fraction drum often come back as separate pieces.
        let best = observations.compactMap { obs -> Piece? in
            guard let top = obs.topCandidates(1).first else { return nil }
            return Piece(text: top.string, confidence: top.confidence, box: obs.boundingBox)
        }
        for line in lines(best) where line.count > 1 {
            let joined = line.sorted { $0.box.minX < $1.box.minX }
            let text = joined.map(\.text).joined(separator: " ")
            let confidence = joined.map(\.confidence).min() ?? 0
            let box = joined.reduce(joined[0].box) { $0.union($1.box) }
            pieces.append(Piece(text: text, confidence: confidence, box: box))
        }

        var bestMatch: (reading: RecognizedReading, score: Double)?
        for piece in pieces {
            guard let (reading, exact) = DialTextParser.interpret(piece.text, digitsBefore: digitsBefore, digitsAfter: digitsAfter, confidence: piece.confidence) else { continue }
            // Taller text wins: the counter is the biggest number on the face.
            var score = Double(piece.box.height) * 10 + Double(piece.confidence)
            if exact { score += 5 }
            if bestMatch == nil || score > bestMatch!.score {
                bestMatch = (reading, score)
            }
        }
        return bestMatch?.reading
    }

    /// Groups observations whose boxes overlap vertically.
    private static func lines(_ pieces: [Piece]) -> [[Piece]] {
        var groups: [[Piece]] = []
        for piece in pieces.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let index = groups.firstIndex(where: { group in
                guard let first = group.first else { return false }
                let overlap = min(first.box.maxY, piece.box.maxY) - max(first.box.minY, piece.box.minY)
                return overlap > min(first.box.height, piece.box.height) * 0.5
            }) {
                groups[index].append(piece)
            } else {
                groups.append([piece])
            }
        }
        return groups
    }
}
