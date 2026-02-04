//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreImage
import SignalServiceKit
import UIKit

public extension UIImage {

    @concurrent
    func withGaussianBlurAsync(radius: CGFloat, resizeToMaxPixelDimension: CGFloat) async throws -> UIImage {
        AssertNotOnMainThread()
        return UIImage(cgImage: try _cgImageWithGaussianBlur(radius: radius, resizeToMaxPixelDimension: resizeToMaxPixelDimension))
    }

    @concurrent
    func cgImageWithGaussianBlurAsync(radius: CGFloat, resizeToMaxPixelDimension: CGFloat) async throws -> CGImage {
        AssertNotOnMainThread()
        return try self._cgImageWithGaussianBlur(radius: radius, resizeToMaxPixelDimension: resizeToMaxPixelDimension)
    }

    private func _cgImageWithGaussianBlur(radius: CGFloat, resizeToMaxPixelDimension: CGFloat) throws -> CGImage {
        guard let resizedImage = self.resized(maxDimensionPixels: resizeToMaxPixelDimension) else {
            throw OWSAssertionError("Failed to downsize image for blur")
        }
        return try resizedImage._cgImageWithGaussianBlur(radius: radius)
    }

    func withGaussianBlur(radius: CGFloat, tintColor: UIColor? = nil) throws -> UIImage {
        UIImage(cgImage: try _cgImageWithGaussianBlur(radius: radius, tintColor: tintColor))
    }

    private func _cgImageWithGaussianBlur(radius: CGFloat, tintColor: UIColor? = nil) throws -> CGImage {
        guard let clampFilter = CIFilter(name: "CIAffineClamp") else {
            throw OWSAssertionError("Failed to create affine clamp filter")
        }

        guard
            let blurFilter = CIFilter(
                name: "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: radius],
            )
        else {
            throw OWSAssertionError("Failed to create blur filter")
        }
        guard let cgImage else {
            throw OWSAssertionError("Missing cgImage.")
        }

        // In order to get a nice edge-to-edge blur, we must apply a clamp filter and *then* the blur filter.
        let inputImage = CIImage(cgImage: cgImage)
        clampFilter.setDefaults()
        clampFilter.setValue(inputImage, forKey: kCIInputImageKey)

        guard let clampOutput = clampFilter.outputImage else {
            throw OWSAssertionError("Failed to clamp image")
        }

        blurFilter.setValue(clampOutput, forKey: kCIInputImageKey)

        guard let blurredOutput = blurFilter.value(forKey: kCIOutputImageKey) as? CIImage else {
            throw OWSAssertionError("Failed to blur clamped image")
        }

        var outputImage: CIImage = blurredOutput
        if let tintColor {
            guard
                let tintFilter = CIFilter(
                    name: "CIConstantColorGenerator",
                    parameters: [
                        kCIInputColorKey: CIColor(color: tintColor),
                    ],
                )
            else {
                throw OWSAssertionError("Could not create tintFilter.")
            }
            guard let tintImage = tintFilter.outputImage else {
                throw OWSAssertionError("Could not create tintImage.")
            }

            guard
                let tintOverlayFilter = CIFilter(
                    name: "CISourceOverCompositing",
                    parameters: [
                        kCIInputBackgroundImageKey: outputImage,
                        kCIInputImageKey: tintImage,
                    ],
                )
            else {
                throw OWSAssertionError("Could not create tintOverlayFilter.")
            }
            guard let tintOverlayImage = tintOverlayFilter.outputImage else {
                throw OWSAssertionError("Could not create tintOverlayImage.")
            }
            outputImage = tintOverlayImage
        }

        let context = CIContext(options: nil)
        guard let blurredImage = context.createCGImage(outputImage, from: inputImage.extent) else {
            throw OWSAssertionError("Failed to create CGImage from blurred output")
        }

        return blurredImage
    }
}
