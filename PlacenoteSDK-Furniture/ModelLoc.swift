//
//  ModelLoc.swift
//  PlacenoteSDK-Planes
//
//  Created by Prasenjit Mukherjee on 2018-02-02.
//  Copyright © 2018 Vertical AI. All rights reserved.
//

import Foundation
import ModelIO
import SceneKit.ModelIO

extension NSCoder {

  func data<T>(for array: [T]) -> Data {
    return array.withUnsafeBufferPointer { buffer in
      return Data(buffer: buffer)
    }
  }
  
  func array<T>(for data: Data) -> [T] {
    return data.withUnsafeBytes { (bytes: UnsafePointer<T>) -> [T] in
      let buffer = UnsafeBufferPointer(start: bytes, count: data.count / MemoryLayout<T>.stride)
      return Array(buffer)
    }
  }
  
  func encodePOD<T>(_ immutableArray: [T], forKey key: String) {
    encode(data(for: immutableArray), forKey: key)
  }
  
  func decodePOD<T>(forKey key: String) -> [T] {
    return array(for: decodeObject(forKey: key) as? Data ?? Data())
  }
}

class ModelLoc: NSObject, NSCoding {

  static let DocumentsDirectory = FileManager().urls(for: .documentDirectory, in: .userDomainMask).first!
  static let ArchiveURL = DocumentsDirectory.appendingPathComponent("modelTransforms")

  var transforms: [matrix_float4x4] = [] //the transforms of each model being stored
  var types: [UInt32] = [] // the model type being stored

  init(tfs: [matrix_float4x4], tps: [UInt32]) {
    transforms = tfs
    types = tps
  }
  
  override init() {
    super.init()
    transforms = []
    types = []
  }
  
  func add(transform: matrix_float4x4, type: UInt32) {
    transforms.append(transform)
    types.append(type)
  }
  
  func removeAll() {
    transforms.removeAll()
    types.removeAll()
  }
  
  func count() -> Int {
    return transforms.count
  }
  
  func encode(with aCoder: NSCoder) {
    aCoder.encodePOD(transforms, forKey: "transformMat")
    aCoder.encodePOD(types, forKey: "typeList")
  }
  
  required convenience init?(coder aDecoder: NSCoder) {
    let tfs : [matrix_float4x4] = aDecoder.decodePOD(forKey: "transformMat")
    let types: [UInt32] = aDecoder.decodePOD(forKey: "typeList")
    self.init(tfs: tfs, tps: types)
  }
}
