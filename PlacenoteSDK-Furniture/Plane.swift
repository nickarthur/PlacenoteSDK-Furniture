//
//  PlaneAnchor.swift
//  PlacenoteSDK-Planes
//
//  Created by Prasenjit Mukherjee on 2018-01-29.
//  Copyright © 2018 Vertical AI. All rights reserved.
//

import Foundation
import UIKit
import ARKit
import os.log


class Plane: NSObject, NSCoding {
  
  var height : Float
  var width : Float 
  var center_x : Float
  var center_z : Float
  
  //Initializer
  init?(height: Float, width: Float, center_x: Float, center_z: Float) {
    self.center_x = center_x
    self.center_z = center_z
    self.height = height
    self.width = width
  }
  
  
  //MARK: NSCoding
  func encode(with aCoder: NSCoder) {
    aCoder.encode(center_x, forKey: "center_x")
    aCoder.encode(center_z, forKey: "center_z")
    aCoder.encode(height, forKey: "height")
    aCoder.encode(width, forKey: "width")
  }
  
  required convenience init?(coder aDecoder: NSCoder) {
    let center_x = aDecoder.decodeFloat(forKey: "center_x")
    let center_z = aDecoder.decodeFloat(forKey: "center_y")
    let height = aDecoder.decodeFloat(forKey: "height")
    let width = aDecoder.decodeFloat(forKey: "width")

    self.init(height: height, width: width, center_x: center_x, center_z: center_z)
  }
  
  
  
  
}
