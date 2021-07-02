//
//  DQVideoEncoder.swift
//  Codeh264
//
//  Created by 阿永 on 2021/7/1.
//

import UIKit
import VideoToolbox

class DQVideoEncoder: NSObject {

    var frameId: Int64 = 0
    var hasSpaPps = false
    var width: Int32 = 480
    var height: Int32 = 640
    var bitRate: Int32 = 480 * 360 * 3 * 4
    var fps: Int32 = 10
    
    var encodeQueue = DispatchQueue(label: "encodeQueue")
    var callBackQueue = DispatchQueue(label: "callBackQueue")
    
    var encodeSession: VTCompressionSession!
    var encodeCallBack: VTCompressionOutputCallback?
    var videoEncodeCallback: ((Data)->())?
    func videoEncodeCallback(block: @escaping (Data)->()) {
        videoEncodeCallback = block
    }
    
    var videoEncodeCallbackSpsAndPps: ((Data,Data)->Void)?
    func videoEncodeCallbackSpsAndPps(block: @escaping ((Data,Data)->Void)) {
        videoEncodeCallbackSpsAndPps = block
    }
    
    init(width: Int32 = 480, height: Int32 = 640, bitRate: Int32? = nil, fps: Int32? = nil) {
        self.width = width
        self.height = height
        self.bitRate = bitRate != nil ? bitRate! : 480 * 640 * 3 * 4
        self.fps = fps != nil ? fps! : 10
        super.init()
        
    }
    
    func setCallBack() {
        //编码完成回调
        encodeCallBack = { (outputCallbackRefCon, sourceFrameRefCon, status, flag, sampleBuffer)  in
            //outputCallbackRefCon?.bindMemory(to: DQVideoEncoder.self, capacity: 1)
//            let encodepointer = outputCallbackRefCon?.assumingMemoryBound(to: DQVideoEncoder.self)
//            let encodepointer1 = outputCallbackRefCon?.bindMemory(to: DQVideoEncoder.self, capacity: 1)
//            let encoder1 = encodepointer1?.pointee
            
            let encoder: DQVideoEncoder = unsafeBitCast(outputCallbackRefCon, to: DQVideoEncoder.self)
            guard sampleBuffer != nil else {
                return
            }
            
            /// 0. 原始字节数据 8字节
            let buffer: [UInt8] = [0x00, 0x00, 0x00, 0x01]
            /// 1. [UInt8] -> UnsafeBufferPointer<UInt8>
            let unsafeBufferPointer = buffer.withUnsafeBufferPointer {$0}
            /// 2.. UnsafeBufferPointer<UInt8> -> UnsafePointer<UInt8>
            let  unsafePointer = unsafeBufferPointer.baseAddress
            guard let startCode = unsafePointer else {return}
            let attachArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer!, createIfNecessary: false)
            var strkey = unsafeBitCast(kCMSampleAttachmentKey_NotSync, to: UnsafeRawPointer.self)
            let cfDic = unsafeBitCast(CFArrayGetValueAtIndex(attachArray, 0), to: CFDictionary.self)
            let keyFrame = !CFDictionaryContainsKey(cfDic, strkey)
            //  获取sps pps
            if keyFrame && !encoder.hasSpaPps {
                if let description = CMSampleBufferGetFormatDescription(sampleBuffer!) {
                    var spsSize: Int = 0, spsCount: Int = 0, spsHeaderLength: Int32 = 0
                    var ppsSize: Int = 0, ppsCount: Int = 0, ppsHeaderLength: Int32 = 0
                    var spsDataPointer : UnsafePointer<UInt8>? = UnsafePointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 0))
                    var ppsDataPointer : UnsafePointer<UInt8>? = UnsafePointer<UInt8>(bitPattern: 0)
                    
                    let spsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, parameterSetIndex: 0, parameterSetPointerOut: &spsDataPointer, parameterSetSizeOut: &spsSize, parameterSetCountOut: &spsCount, nalUnitHeaderLengthOut: &spsHeaderLength)
                    if spsStatus != 0 {
                        print("sps失败")
                    }
                    let ppsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, parameterSetIndex: 1, parameterSetPointerOut: &ppsDataPointer, parameterSetSizeOut: &ppsSize, parameterSetCountOut: &ppsCount, nalUnitHeaderLengthOut: &ppsHeaderLength)
                    if ppsStatus != 0 {
                        print("pps失败")
                    }
                    
                    if let spsData = spsDataPointer, let ppsData = ppsDataPointer {
                        var spsDataValue = Data(capacity: 4 + spsSize)
                        spsDataValue.append(buffer, count: 4)
                        spsDataValue.append(spsData, count: spsSize)

                        
                        var ppsDataValue = Data(capacity: 4 + ppsSize)
                        ppsDataValue.append(startCode, count: 4)
                        ppsDataValue.append(ppsData, count: ppsSize)
                        encoder.callBackQueue.async {
                            encoder.videoEncodeCallbackSpsAndPps!(spsDataValue, ppsDataValue)
                            
                        }

                    }
                    
                    let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer!)
                    var dataPointer: UnsafeMutablePointer<Int8>? = nil
                    var totalLength = 0
                    let blockState = CMBlockBufferGetDataPointer(dataBuffer!, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
                    if blockState != 0 {
                        print("获取data失败\(blockState)")
                    }
                    
                    var offset: UInt32 = 0
                    let lengthInfoSize = 4
                    while offset < totalLength - lengthInfoSize {
                        var naluDataLenth: UInt32 = 0
                        memcpy(&naluDataLenth, dataPointer! + UnsafeMutablePointer<Int8>.Stride(offset), lengthInfoSize)
                        //大端转系统端
                        naluDataLenth = CFSwapInt32BigToHost(naluDataLenth)
                        //获取到编码好的视频数据
                        var data = Data(capacity: Int(naluDataLenth) + lengthInfoSize)
                        data.append(buffer, count: 4)
                        let naluUnsafePoint = unsafeBitCast(dataPointer, to: UnsafePointer<UInt8>.self)
                        data.append(naluUnsafePoint + UnsafePointer<UInt8>.Stride(offset + UInt32(lengthInfoSize)), count: Int(naluDataLenth))
                        encoder.callBackQueue.async {
                            encoder.videoEncodeCallback?(data)
                        }
                        offset += naluDataLenth + UInt32(lengthInfoSize)
                    }
                }
            }
            

        }
    }
    
    func initVideoToolBox() {
        
        let state = VTCompressionSessionCreate(allocator: kCFAllocatorDefault, width: width, height: height, codecType: kCMVideoCodecType_H264, encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: encodeCallBack, refcon: unsafeBitCast(self, to: UnsafeMutablePointer.self), compressionSessionOut: &self.encodeSession)
        
        if state != 0 {
            print("creat failed")
            return
        }
        //设置实时编码输出
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        //编码方式
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        //设置是否产生B帧
        
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        //关键帧间隔
        var frameInterval = 10
        let number = CFNumberCreate(kCFAllocatorDefault, CFNumberType.intType, &frameInterval)
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: number)
        
        //期望帧率
        let fpscf = CFNumberCreate(kCFAllocatorDefault, CFNumberType.intType, &fps)
        VTSessionSetProperty(encodeQueue, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fpscf)
        
        //设置码率平均值  大，清晰，文件大
        // 码率 = width * height * 3 * 4
        let bitrateAverage = CFNumberCreate(kCFAllocatorDefault, CFNumberType.intType, &bitRate)
        VTSessionSetProperty(encodeQueue, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrateAverage)
        let bitRatesLimit: CFArray = [bitRate * 2, 1] as CFArray
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_DataRateLimits, value: bitRatesLimit)
        
    }
    
    
    //开始编码
    func encodeVideo(sampleBuffer: CMSampleBuffer) {
        if self.encodeSession == nil {
            initVideoToolBox()
        }
        
        encodeQueue.async {
            let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            let time = CMTime(value: self.frameId, timescale: 1000)
            let state = VTCompressionSessionEncodeFrame(self.encodeSession, imageBuffer: imageBuffer!, presentationTimeStamp: time, duration: .invalid, frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: nil)
            if state != 0 {
                print("encode false")
            }
            
         }
    }
    
    
    deinit {
        if encodeSession != nil {
            VTCompressionSessionCompleteFrames(encodeSession, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(encodeSession)
            encodeSession = nil
        }
    }
}
