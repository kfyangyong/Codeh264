//
//  ViewController.swift
//  Codeh264
//
//  Created by 阿永 on 2021/7/1.
//

import UIKit
import AVFoundation
import Photos
import VideoToolbox


class ViewController: UIViewController {
    var recodButton:UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        recodButton = UIButton(frame: CGRect(x: view.bounds.size.width - 160, y: view.bounds.size.height - 60, width: 150, height: 50))
        recodButton.backgroundColor = .gray
        recodButton.center.y = view.center.y
        recodButton.setTitle("视频编码H264", for: .normal)
        recodButton.addTarget(self, action: #selector(recordAction(btn:)), for: .touchUpInside)
        view.addSubview(recodButton)
    }
    
    private func getAllow() {
        
    }
    
    @objc func recordAction(btn:UIButton){
        let vc = VideoViewController()
        navigationController?.pushViewController(vc, animated: true)
    }

}

