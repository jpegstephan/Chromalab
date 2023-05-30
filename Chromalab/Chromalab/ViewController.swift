//
//  ViewController.swift
//  Chromalab
//
//  Created by STEPHAN on 5/28/23.
//

import AVFoundation
import UIKit
import Photos

class ViewController: UIViewController {

    // Capture Session
    var session: AVCaptureSession?
    // Photo Output
    let output = AVCapturePhotoOutput()
    // Video Preview
    let previewLayer = AVCaptureVideoPreviewLayer()
    // Shutter Button
    private let shutterButton: UIButton = {
        let button = UIButton(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        button.layer.cornerRadius = 50
        button.layer.borderWidth = 10
        button.layer.borderColor = UIColor.white.cgColor
        return button
    }()

    // Flash Mode
    private var flashMode: AVCaptureDevice.FlashMode = .on

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.layer.addSublayer(previewLayer)
        view.addSubview(shutterButton)
        checkCameraPermissions()

        shutterButton.addTarget(self, action: #selector(didTapTakePhoto(_:)), for: .touchUpInside)

    }
    


    // Frame

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    

        shutterButton.center = CGPoint(x: view.frame.size.width / 2, y: view.frame.size.height - 150)
    }
    
    

    private func checkCameraPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            // Request
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else {
                    return
                }
                DispatchQueue.main.async {
                    self?.setUpCamera()
                }
            }
        case .restricted:
            break
        case .denied:
            break
        case .authorized:
            setUpCamera()
        @unknown default:
            break
        }
    }

    // Input and Output

    private func setUpCamera() {
        let session = AVCaptureSession()
        if let device = AVCaptureDevice.default(for: .video) {
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                }
                if session.canAddOutput(output) {
                    session.addOutput(output)
                }
                
                // Set the video orientation
                            if let connection = output.connection(with: .video) {
                                if connection.isVideoOrientationSupported {
                                    connection.videoOrientation = .portrait
                                }
                            }

                previewLayer.videoGravity = .resizeAspectFill
                previewLayer.session = session

                DispatchQueue.global(qos: .userInitiated).async {
                    session.startRunning()
                }

                self.session = session

            } catch {
                print(error)
            }
        }
    }

    @objc private func didTapTakePhoto(_ sender: UIButton) {

        let settings = AVCapturePhotoSettings()

        // Set the maximum photo dimensions
        if let device = AVCaptureDevice.default(for: .video) {
            // Retrieve the active format of the video device
            let activeFormat = device.activeFormat
            _ = CMVideoFormatDescriptionGetDimensions(activeFormat.formatDescription)

            // Set maxPhotoDimensions based on the active format's dimensions
            settings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        }

        // Flash static on
        if let device = AVCaptureDevice.default(for: .video), device.hasFlash {
            settings.flashMode = flashMode
        }

        output.capturePhoto(with: settings, delegate: self)
    }

    // Flash mode button (deprecated)

    @IBAction func toggleFlashMode(_ sender: UIButton) {
        let alertController = UIAlertController(title: "Flash Mode", message: nil, preferredStyle: .actionSheet)

        let autoAction = UIAlertAction(title: "Auto", style: .default) { _ in
            self.flashMode = .auto
        }
        let onAction = UIAlertAction(title: "On", style: .default) { _ in
            self.flashMode = .on
        }
        let offAction = UIAlertAction(title: "Off", style: .default) { _ in
            self.flashMode = .off
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)

        alertController.addAction(autoAction)
        alertController.addAction(onAction)
        alertController.addAction(offAction)
        alertController.addAction(cancelAction)

        present(alertController, animated: true, completion: nil)
    }

}

extension ViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation() else {
            return
        }
        let image = UIImage(data: data)
        
        
        // Apply matrix effect (Kodak 2383) (cancel each vector multiplied exactly 1.25x for increased color processing)
        if let cgImage = image?.cgImage {
                    let ciImage = CIImage(cgImage: cgImage)
                    let filter = CIFilter(name: "CIColorMatrix")
                    filter?.setValue(ciImage, forKey: "inputImage")
                    
                    let rVector = CIVector(x: 0.96, y: 0.08, z: 0.05, w: 0.0) // Red channel
                    let gVector = CIVector(x: 0.081, y: 0.996, z: 0.037, w: 0.006) // Green channel
                    let bVector = CIVector(x: 0.124, y: 0.084, z: 0.884, w: 0.004) // Blue channel
                    let aVector = CIVector(x: 0.0, y: 0.0, z: 0.0, w: 1.0) // Alpha channel
                        let biasVector = CIVector(x: 0.0, y: 0.005, z: 0.006, w: 0.0) // Bias
            
            filter?.setValue(rVector, forKey: "inputRVector")
            filter?.setValue(gVector, forKey: "inputGVector")
            filter?.setValue(bVector, forKey: "inputBVector")
            filter?.setValue(aVector, forKey: "inputAVector")
            filter?.setValue(biasVector, forKey: "inputBiasVector")
            
            if let matrixOutputImage = filter?.outputImage {
                
                // halation / bloom effect
                if let bloomOutputImage = applyBloomEffect(to: matrixOutputImage) {
                    let context = CIContext()
                    if let cgImg = context.createCGImage(bloomOutputImage, from: bloomOutputImage.extent) {
                        let processedImage = UIImage(cgImage: cgImg)
                        
                        PHPhotoLibrary.requestAuthorization { [weak self] status in
                            if status == .authorized {
                                PHPhotoLibrary.shared().performChanges({
                                    PHAssetChangeRequest.creationRequestForAsset(from: processedImage)
                                }, completionHandler: { (success, error) in
                                    if success {
                                        DispatchQueue.main.async {
                                            let alertController = UIAlertController(title: "Saved!", message: "The photo has been saved to your library.", preferredStyle: .alert)
                                            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                                            self?.present(alertController, animated: true, completion: nil)
                                        }
                                    } else {
                                        print("Error saving photo: \(String(describing: error))")
                                    }
                                })
                            }
                        }
                    }
                }
            }
        }
    }
    
    
    
    func applyBloomEffect(to image: CIImage) -> CIImage? {
        let bloomFilter = CIFilter(name: "CIBloom")
        bloomFilter?.setValue(image, forKey: "inputImage")
        bloomFilter?.setValue(NSNumber(value: 0.5), forKey: "inputIntensity")
        bloomFilter?.setValue(NSNumber(value: 13), forKey: "inputRadius")
        
        // Apply bloom effect
        guard let bloomOutputImage = bloomFilter?.outputImage else { return nil }
        
        // Increase saturation and brightness of highlights
        let colorControlsFilter = CIFilter(name: "CIColorControls")
        colorControlsFilter?.setValue(bloomOutputImage, forKey: kCIInputImageKey)
        colorControlsFilter?.setValue(1.5, forKey: kCIInputSaturationKey) // Increase saturation
        colorControlsFilter?.setValue(-0.002, forKey: kCIInputBrightnessKey) // Increase brightness
        guard let tintedImage = colorControlsFilter?.outputImage else { return nil }
        
        return tintedImage
    }
}
