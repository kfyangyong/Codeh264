//
//  VideoViewController.swift
//  Codeh264
//
//  Created by 阿永 on 2021/7/1.
//

import UIKit
import AVFoundation
import Photos
import VideoToolbox


class VideoViewController: UIViewController {

    var recodButton:UIButton!
    
    // 录屏
    var session: AVCaptureSession = AVCaptureSession()
    var queue = DispatchQueue(label: "queue")
    var input: AVCaptureDeviceInput?
    lazy var previewLayer = AVCaptureVideoPreviewLayer(session: session)
    
    //播放
    var recordOutput = AVCaptureMovieFileOutput()
    var captureView: UIView!
    let output = AVCaptureVideoDataOutput()

    var focusBox: UIView!
    var exposureBox: UIView!
    
    var encoder: DQVideoEncoder!
    var decoder: DQVideoDecode!
    var player: AAPLEAGLLayer?
    
    var fileHandle: FileHandle?
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white
        captureView = UIView(frame: CGRect(x: 5, y: 200, width: view.frame.size.width/2 - 10, height: 300))
        captureView.backgroundColor = .orange
        view.addSubview(captureView)
        previewLayer.frame = captureView.bounds

        player = AAPLEAGLLayer(frame: CGRect(x: view.frame.size.width/2 + 5, y: 200, width: view.frame.size.width/2 - 10, height: 300))
        view.layer.addSublayer(player!)
        
        recodButton = UIButton(frame: CGRect(x: view.bounds.size.width - 160, y: view.bounds.size.height - 60, width: 150, height: 50))
        recodButton.backgroundColor = .gray
        recodButton.center.x = view.center.x
        recodButton.setTitle("start record", for: .normal)
        recodButton.addTarget(self, action: #selector(recordAction(btn:)), for: .touchUpInside)
        view.addSubview(recodButton)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapAction(tap:)))
        view.addGestureRecognizer(tap)
        tap.numberOfTapsRequired = 1
        let tap1 = UITapGestureRecognizer(target: self, action: #selector(doubleTap(tap:)))
        tap1.numberOfTapsRequired = 2
        view.addGestureRecognizer(tap1)
        
        focusBox = boxView(color: UIColor(red: 0.102, green:0.636, blue:1.000, alpha:1.000))
        focusBox.isHidden = true
        exposureBox = boxView(color: UIColor(red: 1, green: 0.421, blue: 0.054, alpha: 1.0))
        exposureBox.isHidden = true
        self.view.addSubview(focusBox)
        self.view.addSubview(exposureBox)
        isAllow()
        startCapture()
    }
    
    func isAllow() {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if authStatus == .restricted || authStatus == .denied {
            print("应用相机权限受限,请在设置中启用")
        }
    }
    
    @objc func recordAction(btn:UIButton){
        btn.isSelected = !btn.isSelected
        if !session.isRunning{
            session.startRunning()
        }
        if btn.isSelected {
            
            btn.setTitle("stop record", for: .normal)
            
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output){
                session.addOutput(output)
            }
            output.alwaysDiscardsLateVideoFrames = false
            //这里设置格式为BGRA，而不用YUV的颜色空间，避免使用Shader转换
            //注意:这里必须和后面CVMetalTextureCacheCreateTextureFromImage 保存图像像素存储格式保持一致.否则视频会出现异常现象.
            output.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey)  :NSNumber(value: kCVPixelFormatType_32BGRA) ]
            guard let connection: AVCaptureConnection = output.connection(with: .video) else {
                return
            }
            
            connection.videoOrientation = .portrait
            
            if fileHandle == nil{
                //生成的文件地址
                guard let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else { return  }
                let filePath =  "\(path)/video.h264"
                try? FileManager.default.removeItem(atPath: filePath)
                if FileManager.default.createFile(atPath: filePath, contents: nil, attributes: nil){
                    print("创建264文件成功")
                }else{
                    print("创建264文件失败")
                }
                fileHandle = FileHandle(forWritingAtPath: filePath)
            }
            
        }else{
            session.removeOutput(output)
            btn.setTitle("start record", for: .normal)
        }
    }
    
    @objc func tapAction(tap:UITapGestureRecognizer){
        let point = tap.location(in: view)
        setFocus(point: point)
        boxAnimation(boxView: focusBox, point: point)
    }
    
    @objc func doubleTap(tap:UITapGestureRecognizer){
        let point = tap.location(in: view)
        setExposure(point: point)
        boxAnimation(boxView: exposureBox, point: point)
    }
    
    func startCapture() {
        guard let device = getCamera(postion: .back) else {
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }
        
        self.input = input
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        previewLayer.isHidden = false
        previewLayer.videoGravity = .resizeAspect
        session.startRunning()
        
        //编码
        encoder = DQVideoEncoder(width: 480, height: 640)
        encoder.videoEncodeCallback {[weak self] data in
            self?.decoder.decode(data: data)
            //存入文件...
        }
        encoder.videoEncodeCallbackSpsAndPps { [weak self] sps, pps in
            self?.decoder.decode(data: sps)
            self?.decoder.decode(data: pps)
            //存入文件...
        }
        
        //解码
        decoder = DQVideoDecode(width: 480, height: 640)
        decoder.setVideoDecodeCallBack { [weak self] image in
            self?.player?.pixelBuffer = image
        }
        
    }
    
    func writeTofile(data: Data){
        if #available(iOS 13.4, *) {
            try? self.fileHandle?.seekToEnd()
        } else {
            // Fallback on earlier versions
        }
        self.fileHandle?.write(data)
    }
    
    //获取相机设备
    func getCamera(postion: AVCaptureDevice.Position) -> AVCaptureDevice? {
        var devices = [AVCaptureDevice]()
        let discoverSession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera], mediaType: .video, position: .unspecified)
        devices = discoverSession.devices
        for device in devices {
            if device.position == postion {
                return device
            }
        }
        return nil
    }
    //设置横竖屏问题
     func setupVideoPreviewLayerOrientation() {
         
         if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
             if #available(iOS 13.0, *) {
                 if let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation{
                     switch orientation {
                     case .portrait:
                         connection.videoOrientation = .portrait
                     case .landscapeLeft:
                         connection.videoOrientation = .landscapeLeft
                     case .landscapeRight:
                         connection.videoOrientation = .landscapeRight
                     case .portraitUpsideDown:
                         connection.videoOrientation = .portraitUpsideDown
                     default:
                         connection.videoOrientation = .portrait
                     }
                 }
             }else{
                 switch UIApplication.shared.statusBarOrientation {
                 case .portrait:
                     connection.videoOrientation = .portrait
                 case .landscapeRight:
                     connection.videoOrientation = .landscapeRight
                 case .landscapeLeft:
                     connection.videoOrientation = .landscapeLeft
                 case .portraitUpsideDown:
                     connection.videoOrientation = .portraitUpsideDown
                 default:
                     connection.videoOrientation = .portrait
                 }
             }
         }
     }
    
    //MARK: -切换摄像头
    func swapFrontAndBackCameras() {
        if let input = input {
            
            var newDevice: AVCaptureDevice?
            
            if input.device.position == .front {
                newDevice = getCamera(postion: AVCaptureDevice.Position.back)
            } else {
                newDevice = getCamera(postion: AVCaptureDevice.Position.front)
            }
            
            if let new = newDevice {
                do{
                    let newInput = try AVCaptureDeviceInput(device: new)
                    
                    session.beginConfiguration()
                    
                    session.removeInput(input)
                    session.addInput(newInput)
                    self.input = newInput
                    
                    session.commitConfiguration()
                }
                catch let error as NSError {
                    print("AVCaptureDeviceInput(): \(error)")
                }
            }
        }
    }
    
    //MARK: -闪光灯
    func setFlash(mode : AVCaptureDevice.FlashMode){
        //设备是否支持闪光灯
        guard let device = self.input?.device,device.hasFlash else {
            return
        }
        //        When using AVCapturePhotoOutput, AVCaptureDevice's flashMode property is ignored. You specify flashMode on a per photo basis by setting the AVCapturePhotoSettings.flashMode property.
        if device.isFlashModeSupported(mode){
            do {
                try device.lockForConfiguration()
                device.flashMode = mode
                device.unlockForConfiguration()
            } catch let error {
                print(error.localizedDescription)
            }
        }
        
    }
    
    //MARK: - 手电筒
    func setTorch(mode:AVCaptureDevice.TorchMode) {
        //设备是否有手电筒
        guard let device = self.input?.device,device.hasTorch else {
            return
        }
        if device.isTorchModeSupported(mode){
            do {
                try device.lockForConfiguration()
                device.torchMode = mode
                device.unlockForConfiguration()
            } catch let error {
                print(error.localizedDescription)
            }
        }
    }
    
    //MARK: - 聚焦
    func setFocus(point:CGPoint? = nil ) {
        guard let device = input?.device else {
            return
        }
        if let po = point {
            // 触摸屏幕的坐标点需要转换成0-1，设置聚焦点
            let cameraPoint = CGPoint(x: po.x/previewLayer.bounds.size.width, y: po.y/previewLayer.bounds.size.height)
            if device.isFocusModeSupported(.continuousAutoFocus), device.isFocusPointOfInterestSupported {
                do {
                    try device.lockForConfiguration()
                    device.focusPointOfInterest = cameraPoint
                    device.unlockForConfiguration()
                } catch let err {
                    print(err)
                }
            }
        } else {
            let mode = AVCaptureDevice.FocusMode.autoFocus
            if device.isFocusModeSupported(mode) {
                do {
                    try device.lockForConfiguration()
                    device.focusMode = mode
                    device.unlockForConfiguration()
                } catch let err {
                    print(err)
                }
            }
        }
    }

    //MARK: - 曝光
    func setExposure(point:CGPoint? = nil) {
        guard let device = self.input?.device else {
            return
        }
        if let po = point {
            let cameraPoint = CGPoint(x: po.x/previewLayer.bounds.size.width, y: po.y/previewLayer.bounds.size.height)
            if device.isExposureModeSupported(.continuousAutoExposure) && device.isExposurePointOfInterestSupported {
                do {
                    try device.lockForConfiguration()
                    device.exposurePointOfInterest = cameraPoint
                    device.exposureMode = .continuousAutoExposure
                    
                } catch let error {
                    print(error.localizedDescription)
                }
            }
            
        }else{
            if device.isExposureModeSupported(.autoExpose) {
                do {
                    try device.lockForConfiguration()
                    device.exposureMode = .autoExpose
                    device.unlockForConfiguration()
                } catch let error {
                    print(error.localizedDescription)
                }
            }
        }
    }
    
    func boxAnimation(boxView:UIView,point:CGPoint) {
        boxView.center = point
        boxView.isHidden = false
        UIView.animate(withDuration: 0.15,delay: 0, options: .curveEaseInOut, animations: {
            
            boxView.layer.transform = CATransform3DMakeScale(0.5, 0.5, 1.0)
        }) { (complet) in
            let time = DispatchTime.now() + Double(Int64(1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
            DispatchQueue.main.asyncAfter(deadline: time) {
                
                boxView.isHidden = true
                boxView.layer.transform = CATransform3DIdentity
            }
        }
    }
    
    func boxView(color:UIColor) -> UIView{
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        view.backgroundColor = .clear
        view.layer.borderWidth = 5
        view.layer.borderColor = color.cgColor
        return view
    }
    
    
}

extension VideoViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        encoder.encodeVideo(sampleBuffer: sampleBuffer)
    }
}

extension VideoViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        
    }
    
    
}

