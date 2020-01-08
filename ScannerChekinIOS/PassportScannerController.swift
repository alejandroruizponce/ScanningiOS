//
//  PassportScannerController.swift
//
//  Created by Edwin Vermeer on 9/7/15.
//  Copyright (c) 2015. All rights reserved.
//

import Foundation
import UIKit
import EVGPUImage2
import GPUImage //Still using this for the rotate
import UIImage_Resize
import AVFoundation
import TesseractOCR
import CoreMotion


// based to https://www.icao.int/publications/pages/publication.aspx?docnum=9303
@objc
public enum MRZType: Int {
    case auto
    case td1 // 3 lines - 30 chars per line
    case td2 // DNI FRANCES
    case td3 // 2 lines - 44 chars per line
}

@objc(PassportScannerController)
open class PassportScannerController: UIViewController, G8TesseractDelegate, AVCaptureMetadataOutputObjectsDelegate, UIGestureRecognizerDelegate {
    
    /// Set debug to true if you want to see what's happening
    @objc public var debug = false
    
    /// Set accuracy that is required for the scan. 1 = all checksums should be ok
    @objc public var accuracy: Float = 1
    
    /// If false then apply filters in post processing, otherwise instead of in camera preview
    @objc public var showPostProcessingFilters = false
    
    // The parsing to be applied
    @objc public var mrzType: MRZType = MRZType.auto
    
    @objc public var scannerDidCompleteWith:((MRZParser?) -> ())?
    
    /// When you create your own view, then make sure you have a GPUImageView that is linked to this
    @IBOutlet var renderView: RenderView!
    
    //@IBOutlet var renderView2: RenderView!
    /// For capturing the video and passing it on to the filters.
    var camera: Camera!
    
    // Quick reference to the used filter configurations
    var exposure: ExposureAdjustment!
    var highlightShadow: HighlightsAndShadows!
    var saturation: SaturationAdjustment!
    var contrast: ContrastAdjustment!
    var adaptiveThreshold: AdaptiveThreshold!
    var averageColor: AverageColorExtractor!
    
    var session: AVCaptureSession?
    var device: AVCaptureDevice?
    var input: AVCaptureDeviceInput?
    var output: AVCaptureMetadataOutput?
    var prevLayer: AVCaptureVideoPreviewLayer?
    
    var crop = Crop()
    let defaultExposure: Float = 1.5
    var adapt: Bool = false
    var expo: Bool = true
    var mode: Int = 1
    var filt: Int = 1
    var deb: Int = 0
    
    
    
    //Post processing filters
    private var averageColorFilter: GPUImageAverageColor!
    private var lastExposure: CGFloat = 1.5
    private let enableAdaptativeExposure = true
    
    let exposureFilter: GPUImageExposureFilter = GPUImageExposureFilter()
    let highlightShadowFilter: GPUImageHighlightShadowFilter = GPUImageHighlightShadowFilter()
    let saturationFilter: GPUImageSaturationFilter = GPUImageSaturationFilter()
    let contrastFilter: GPUImageContrastFilter = GPUImageContrastFilter()
    let adaptiveThresholdFilter: GPUImageAdaptiveThresholdFilter = GPUImageAdaptiveThresholdFilter()
    
    var pictureOutput = PictureOutput()
    
    /// The tesseract OCX engine
    var tesseract: G8Tesseract = G8Tesseract(language: "OcrB")!
    
    
    
    /**
     Rotation is not needed.
     
     :returns: Returns .portrait
     
     
     */
    
    
    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        get { return .portrait }
    }
    /**
     Hide the status bar during scan
     
     :returns: true to indicate the statusbar should be hidden
     */
    override open var prefersStatusBarHidden: Bool {
        get { return true }
    }
    
    /**
     Initialize all graphic filters in the viewDidLoad
     */
    open override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
        
        /*
         let tapGR = UITapGestureRecognizer(target: self, action: #selector(PassportScannerController.myviewTapped(_:)))
         tapGR.delegate = self
         tapGR.numberOfTapsRequired = 2
         view.addGestureRecognizer(tapGR)
         renderView2.isHidden = true*/
        
        // Specify the crop region that will be used for the OCR
        crop.cropSizeInPixels = Size(width: 300, height: 1400)
        crop.locationOfCropInPixels = Position(250, 250, nil)
        crop.overriddenOutputRotation = .rotateClockwise
        
        if !showPostProcessingFilters {
            exposureFilter.exposure = CGFloat(self.defaultExposure)
            highlightShadowFilter.highlights = 0.8
            saturationFilter.saturation = 0.6
            contrastFilter.contrast = 2.0
            adaptiveThresholdFilter.blurRadiusInPixels = 8.0
        } else {
            // Filter settings
            exposure = ExposureAdjustment()
            exposure.exposure = 0.7 // -10 - 10
            
            highlightShadow = HighlightsAndShadows()
            highlightShadow.highlights  = 0.6 // 0 - 1
            
            saturation = SaturationAdjustment();
            saturation.saturation  = 0.6 // 0 - 2
            
            contrast = ContrastAdjustment();
            contrast.contrast = 2.0  // 0 - 4
            
            adaptiveThreshold = AdaptiveThreshold();
            adaptiveThreshold.blurRadiusInPixels = 8.0
            
            // Try to dynamically optimize the exposure based on the average color
            averageColor = AverageColorExtractor();
            averageColor.extractedColorCallback = { color in
                let lighting = color.blueComponent + color.greenComponent + color.redComponent
                let currentExposure = self.exposure.exposure
                
                // The stable color is between 2.75 and 2.85. Otherwise change the exposure
                if lighting < 2.75 {
                    self.exposure.exposure = currentExposure + (2.80 - lighting) * 2
                }
                
                if lighting > 2.85 {
                    self.exposure.exposure = currentExposure - (lighting - 2.80) * 2
                }
                
                if self.exposure.exposure > 2 {
                    self.exposure.exposure = self.defaultExposure
                }
                if self.exposure.exposure < -2 {
                    self.exposure.exposure = self.defaultExposure
                }
            }
            
            
        }
        
        
        
        // download trained data to tessdata folder for language from:
        // https://code.google.com/p/tesseract-ocr/downloads/list
        // ocr trained data is available in:    ;)
        // http://getandroidapp.org/applications/business/79952-nfc-passport-reader-2-0-8.html
        // optimisations created based on https://github.com/gali8/Tesseract-OCR-iOS/wiki/Tips-for-Improving-OCR-Results
        
        // tesseract OCR settings
        self.tesseract.setVariableValue("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ<", forKey: "tessedit_char_whitelist")
        self.tesseract.delegate = self
        self.tesseract.rect = CGRect(x: 0, y: 0, width: 900, height: 340)
        
        // see http://www.sk-spell.sk.cx/tesseract-ocr-en-variables
        self.tesseract.setVariableValue("1", forKey: "tessedit_serial_unlv")
        self.tesseract.setVariableValue("FALSE", forKey: "x_ht_quality_check")
        self.tesseract.setVariableValue("FALSE", forKey: "load_system_dawg")
        self.tesseract.setVariableValue("FALSE", forKey: "load_freq_dawg")
        self.tesseract.setVariableValue("FALSE", forKey: "load_unambig_dawg")
        self.tesseract.setVariableValue("FALSE", forKey: "load_punc_dawg")
        self.tesseract.setVariableValue("FALSE", forKey: "load_number_dawg")
        self.tesseract.setVariableValue("FALSE", forKey: "load_fixed_length_dawgs")
        self.tesseract.setVariableValue("FALSE", forKey: "load_bigram_dawg")
        self.tesseract.setVariableValue("FALSE", forKey: "wordrec_enable_assoc")
        
        
        
        
        
        
    }
    
    
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        
        
        do {
            // Initialize the camera
            camera = try Camera(sessionPreset: AVCaptureSession.Preset.high)
            camera.location = PhysicalCameraLocation.backFacing
            
            if !showPostProcessingFilters {
                // Apply only the cropping
                camera --> renderView
                camera --> crop
            } else {
                // Chain the filter to the render view
                camera --> exposure  --> highlightShadow  --> saturation --> contrast --> adaptiveThreshold --> renderView
                // Use the same chained filters and forward these to 2 other filters
                adaptiveThreshold --> crop --> averageColor
            }
        } catch {
            fatalError("Could not initialize rendering pipeline: \(error)")
        }
        
        
    }
    
    
    
    
    
    
    func evaluateExposure(image: UIImage){
        if !self.enableAdaptativeExposure || self.averageColorFilter != nil {
            return
        }
        
        DispatchQueue.global(qos: .background).async {
            self.averageColorFilter = GPUImageAverageColor()
            self.averageColorFilter.colorAverageProcessingFinishedBlock = {red, green, blue, alpha, time in
                let lighting = blue + green + red
                let currentExposure = self.lastExposure
                
                // The stable color is between 2.75 and 2.85. Otherwise change the exposure
                if lighting < 2.75 {
                    self.lastExposure = currentExposure + (2.80 - lighting) * 2
                }
                if lighting > 2.85 {
                    self.lastExposure = currentExposure - (lighting - 2.80) * 2
                }
                
                if self.lastExposure > 2 {
                    self.lastExposure = CGFloat(self.defaultExposure)
                }
                if self.lastExposure < -2 {
                    self.lastExposure = CGFloat(self.defaultExposure)
                }
                
                self.averageColorFilter = nil
            }
            self.averageColorFilter.image(byFilteringImage: image)
        }
    }
    
    open func preprocessedImage(sourceImage: UIImage!) -> UIImage! {
        // sourceImage is the same image you sent to Tesseract above.
        // Processing is already done in dynamic filters
        
        
        if showPostProcessingFilters { return sourceImage }
        var filterImage: UIImage = sourceImage
        if filt == 1 || filt == 3{
            print("MODO FILTRO 1")
            exposureFilter.exposure = self.lastExposure
            filterImage = exposureFilter.image(byFilteringImage: sourceImage)
            
            filterImage = highlightShadowFilter.image(byFilteringImage: filterImage)
            filterImage = saturationFilter.image(byFilteringImage: filterImage)
            filterImage = contrastFilter.image(byFilteringImage: filterImage)
            if(adapt == true) {
                print("Se ACTIVA el filtro TRESHOLD")
                filterImage = adaptiveThresholdFilter.image(byFilteringImage: filterImage)
            } else {
                print("Se DESACTIVA el filtro TRESHOLD")
            }
            self.evaluateExposure(image: filterImage)
        }
        else if filt == 2 || filt == 4 {
            print("MODO FILTRO 2")
            filterImage = binarize(inputImage: sourceImage)
            filterImage = noiseReduction(inputImage: filterImage)
        }
        
        self.filt = self.filt + 1
        
        
        
        return filterImage
    }
    
    
    @objc public func startScan() {
        self.view.backgroundColor = UIColor.black
        camera.startCapture()
        scanning()
    }
    
    private func scanning() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            //print("Start OCR")
            switch self.mode {
                //En horizontal
                
            case 1:
                self.crop.cropSizeInPixels = Size(width: 350, height: 1500)
                self.crop.locationOfCropInPixels = Position(150, 250, nil)
                break
            case 2:
                self.crop.cropSizeInPixels = Size(width: 350, height: 1500)
                self.crop.locationOfCropInPixels = Position(350, 250, nil)
                break
            case 3:
                self.crop.cropSizeInPixels = Size(width: 350, height: 1500)
                self.crop.locationOfCropInPixels = Position(550, 250, nil)
                break
            //En vertical
            case 4:
                self.crop.cropSizeInPixels = Size(width: 750, height: 600)
                self.crop.locationOfCropInPixels = Position(150, 250, nil)
                break
            case 5:
                self.crop.cropSizeInPixels = Size(width: 750, height: 600)
                self.crop.locationOfCropInPixels = Position(150, 650, nil)
                break
            case 6:
                self.crop.cropSizeInPixels = Size(width: 750, height: 600)
                self.crop.locationOfCropInPixels = Position(150, 1150, nil)
                break
            default:
                break
            }
            
            
            self.pictureOutput = PictureOutput()
            self.pictureOutput.encodedImageFormat = .jpeg
            self.pictureOutput.onlyCaptureNextFrame = true
            
            self.pictureOutput.imageAvailableCallback = { sourceImage in
                DispatchQueue.global().async() {
                    if self.processImage(sourceImage: sourceImage) { return }
                    // Not successful, start another scan
                    
                    if self.mode == 1 && self.filt == 5{
                        self.filt = 1
                        self.mode = 2
                    } else if self.mode == 2 && self.filt == 5 {
                        self.filt = 1
                        self.mode = 3
                    } else if self.mode == 3 && self.filt == 5 {
                        self.filt = 1
                        self.mode = 4
                    } else if self.mode == 4 && self.filt == 3 {
                        self.filt = 1
                        self.mode = 5
                    } else if self.mode == 5 && self.filt == 3 {
                        self.filt = 1
                        self.mode = 6
                    } else if self.mode == 6 && self.filt == 3 {
                        self.filt = 1
                        self.mode = 1
                    }
                    
                    
                    
                    self.scanning()
                }
            }
            self.crop --> self.pictureOutput
            
        }
    }
    
    @objc public func stopScan() {
        self.view.backgroundColor = UIColor.white
        camera.stopCapture()
        abortScan()
    }
    
    
    /**
     call this from your code to start a scan immediately or hook it to a button.
     
     :param: sender The sender of this event
     */
    @IBAction open func StartScan(sender: AnyObject) {
        self.startScan()
    }
    
    /**
     call this from your code to stop a scan or hook it to a button
     
     :param: sender the sender of this event
     */
    @IBAction open func StopScan(sender: AnyObject) {
        self.stopScan()
    }
    
    
    
    /**
     Processing the image
     
     - parameter sourceImage: The image that needs to be processed
     */
    open func processImage(sourceImage: UIImage) -> Bool {
        // resize image. Smaller images are faster to process. When letters are too big the scan quality also goes down.
        var multiplierW = 0.0
        var multiplierH = 0.0
        if self.mode != 4 && self.mode != 5 && self.mode != 6 {
            multiplierW = 0.9
            multiplierH = 0.9
        } else {
            multiplierW = 2.5
            multiplierH = 1
        }
        
        let croppedImage: UIImage = sourceImage.resizedImageToFit(in: CGSize(width: 300 * multiplierW, height: 1400 * multiplierH), scaleIfSmaller: true)
        
        var processedImage = preprocessedImage(sourceImage: croppedImage)
        
        
        if self.mode != 4 && self.mode != 5 && self.mode != 6 {
            if filt == 2 || filt == 3 {
                let selectedFilterLeft = GPUImageTransformFilter()
                selectedFilterLeft.setInputRotation(kGPUImageRotateLeft, at: 0)
                processedImage = selectedFilterLeft.image(byFilteringImage: processedImage)
            }
            else {
                let selectedFilterRight = GPUImageTransformFilter()
                selectedFilterRight.setInputRotation(kGPUImageRotateRight, at: 0)
                processedImage = selectedFilterRight.image(byFilteringImage: processedImage)
            }
        }
        
        // rotate image. tesseract needs the correct orientation.
        // let image: UIImage = croppedImage.rotate(by: -90)!
        // strange... this rotate will cause 1/2 the image to be skipped
        
        
        
        
        // Perform the OCR scan
        let resultRAW: String = self.doOCR(image: processedImage!)
        var lines = resultRAW.components(separatedBy: "\n")
        
        print("\(lines.count) LINEAS VALIDAS:")
        for i in 0...lines.count-1 {
            if lines[i].characters.contains("<"){
                print("Linea \(i): \(lines[i])")
                var words = lines[i].components(separatedBy: CharacterSet.whitespaces)
                lines[i] = ""
                for j in 0...words.count-1{
                    if words[j].characters.contains("<"){
                        print("NOS QUEDAMOS LA PALABRA: \(words[j])")
                        lines[i] = words[j]
                    }
                }
            } else {
                lines[i] = ""
            }
        }
        var result = ""
        for i in 0...lines.count-1 {
            if lines[i] != "" {
                result = result + lines[i] + "\n"
            }
        }
        
        print("TESSERACT LEE ESTO: \(lines[0])")
        
        // Create the MRZ object and validate if it's OK
        var mrz: MRZParser
        
        if mrzType == MRZType.auto {
            mrz = MRZTD1(scan: result, debug: self.debug)
            if  mrz.isValid() < self.accuracy {
                mrz = MRZTD2(scan: result, debug: self.debug)
                if  mrz.isValid() < self.accuracy {
                    mrz = MRZTD3(scan: result, debug: self.debug)
                }
            }
        } else if mrzType == MRZType.td1 {
            mrz = MRZTD1(scan: result, debug: self.debug)
        } else if mrzType == MRZType.td2 {
            mrz = MRZTD2(scan: result, debug: self.debug)
        } else {
            mrz = MRZTD3(scan: result, debug: self.debug)
        }
        
        if  mrz.isValid() < self.accuracy {
            print("Scan quality insufficient : \(mrz.isValid())")
            if adapt == true {
                adapt = false
            } else if adapt == false {
                adapt = true
            }
            
        } else {
            self.camera.stopCapture()
            DispatchQueue.main.async {
                self.successfulScan(mrz: mrz)
                
            }
            return true
        }
        return false
    }
    
    /**
     Perform the tesseract OCR on an image.
     
     - parameter image: The image to be scanned
     
     - returns: The OCR result
     */
    open func doOCR(image: UIImage) -> String {
        // Start OCR
        var result: String?
        
        self.tesseract.image = image
        
        print("- Start recognize")
        self.tesseract.recognize()
        result = self.tesseract.recognizedText
        //tesseract = nil
        
        print("Scan result : \(result ?? "")")
        return result ?? ""
    }
    
    /**
     Override this function in your own class for processing the result
     
     :param: mrz The MRZ result
     */
    
    func binarize(inputImage:UIImage) -> UIImage {
        let imageRef = inputImage.cgImage
        let context =  CIContext(options: nil)//[CIContext contextWithOptions:nil]; // 1
        let ciImage = CIImage(cgImage: imageRef!) //[CIImage imageWithCGImage:imageRef]; // 2
        let filter = CIFilter(name: "CIColorMonochrome", parameters: ["inputImage" : ciImage,"inputColor":CIColor.init(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),"inputIntensity":1])
        let ciExit = filter?.value(forKey: kCIOutputImageKey) as! CIImage
        
        let cgImg = context.createCGImage(ciExit, from: ciExit.extent)!
        
        return UIImage(cgImage: cgImg)
    }
    
    func noiseReduction(inputImage:UIImage) -> UIImage {
        let imageRef = inputImage.cgImage
        let context =  CIContext(options: nil)//[CIContext contextWithOptions:nil]; // 1
        let ciImage = CIImage(cgImage: imageRef!) //[CIImage imageWithCGImage:imageRef]; // 2
        let filter = CIFilter(name: "CINoiseReduction", parameters: ["inputImage" : ciImage,"inputNoiseLevel":0.04,"inputSharpness":0.40])
        let ciExit = filter?.value(forKey: kCIOutputImageKey) as! CIImage
        
        let cgImg = context.createCGImage(ciExit, from: ciExit.extent)!
        
        return UIImage(cgImage: cgImg)
    }
    
    open func successfulScan(mrz: MRZParser) {
        if(self.scannerDidCompleteWith != nil){
            self.scannerDidCompleteWith!(mrz)
        }else{
            assertionFailure("You should overwrite this function to handle the scan results")
        }
    }
    
    /**
     Override this function in your own class for processing a cancel
     */
    open func abortScan() {
        if(self.scannerDidCompleteWith != nil){
            self.scannerDidCompleteWith!(nil)
        }else{
            assertionFailure("You should overwrite this function to handle an abort")
        }
    }
}


// Wanted to use this rotation function. Tesseract does not like the result image.
// Went back to GpuImage for the rotation.
// Will try again later so that we can remove the old GpuImage dependency
@available(iOS 10.0, *)
extension UIImage {
    func rotate(by degrees: Double) -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }
        
        let transform = CGAffineTransform(rotationAngle: CGFloat(degrees * .pi / 180.0))
        var rect = CGRect(origin: .zero, size: self.size).applying(transform)
        rect.origin = .zero
        
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        
        return renderer.image { renderContext in
            renderContext.cgContext.translateBy(x: rect.midX, y: rect.midY)
            renderContext.cgContext.rotate(by: CGFloat(degrees * .pi / 180.0))
            renderContext.cgContext.scaleBy(x: 1.0, y: -1.0)
            
            let drawRect = CGRect(origin: CGPoint(x: -self.size.width/2, y: -self.size.height/2), size: self.size)
            renderContext.cgContext.draw(cgImage, in: drawRect)
        }
    }
}

extension String {
    var lines: [String] {
        return self.components(separatedBy: "\n")
    }
}

