/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import UIKit
import SceneKit
import ARKit
import os.log
import PlacenoteSDK

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate, PNDelegate {

  
	// MARK: - IBOutlets
  @IBOutlet weak var sessionInfoView: UIView!
	@IBOutlet weak var sessionInfoLabel: UILabel!
	@IBOutlet weak var sceneView: ARSCNView!
  
  private var modelTransforms: ModelLoc = ModelLoc() //array of transforms to be stored using NSKeyedArchive
  private var modelsAdded: Int = 0 //number of models currently drawn to the scene (currently max:3)
  private var modelsDrawn: Bool = false //all models drawn (modelsAdded == 3)
  private var modelsLoaded: Bool = false //all models loaded into memory, but not necessarily drawn
  private var modelNames: [String] = ["Chair/model.obj", "Guitar/WashburnGuitar.obj","Light/model.obj"]
  private var loadedModelNodes: [SCNNode] = []
  
  private var currMapID : String = "" //map id currently being used
  
  private var localizing: Bool = false
  private var mapping: Bool = false
  private var arkitActive: Bool = false
  
  private var camManager: CameraManager? = nil
  private var defaults: UserDefaults = UserDefaults.standard
  
  private var reticle: ReticleAR = ReticleAR()
  @IBOutlet var saveLoadButton: UIButton!
  
  // MARK: - View Life Cycle
  /// - Tag: StartARSession
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
  
    guard ARWorldTrackingConfiguration.isSupported else {
        fatalError("""
            ARKit is not available on this device. For apps that require ARKit
            for core functionality, use the `arkit` key in the key in the
            `UIRequiredDeviceCapabilities` section of the Info.plist to prevent
            the app from installing. (If the app can't be installed, this error
            can't be triggered in a production scenario.)
            In apps where AR is an additive feature, use `isSupported` to
            determine whether to show UI for launching AR experiences.
        """) // For details, see https://developer.apple.com/documentation/arkit
    }
    
    let configuration = ARWorldTrackingConfiguration()

    reticle = ReticleAR(arview: sceneView)

    if (!loadMapAndModels()) {
      os_log ("No map or models found")
      saveLoadButton.setTitle("Add Model", for: .normal)
      modelsAdded = 0
      modelsDrawn = false
      modelsLoaded = false
      mapping = true
      LibPlacenote.instance.startSession()
      reticle.addPreviewModelToReticle(node: getModel(fileLoc: modelNames[modelsAdded]))
    }
    else {
      os_log("Map and models loaded")
      saveLoadButton.setTitle("Clear Models", for: .normal)
      modelsLoaded = true
      modelsDrawn  = false //it'll get drawn when we are localized
      modelsAdded = 0
      mapping = false //localization = true was set after map is loaded (see: Function loadMapAndModels)
    }
    
    /*
     Start the view's AR session with a configuration that uses the rear camera,
     device position and orientation tracking, and plane detection.
    */
    configuration.planeDetection = .horizontal
    sceneView.session.run(configuration)
    sceneView.autoenablesDefaultLighting = true

    // Set a delegate to track the number of plane anchors for providing UI feedback.
    sceneView.session.delegate = self
  
    /*
     Prevent the screen from being dimmed after a while as users will likely
     have long periods of interaction without touching the screen or buttons.
    */
    UIApplication.shared.isIdleTimerDisabled = true
  
    // Show debug UI to view performance metrics (e.g. frames per second).
    sceneView.showsStatistics = true
    
    LibPlacenote.instance.multiDelegate += self
    
    if let camera: SCNNode = sceneView?.pointOfView {
      camManager = CameraManager(scene: sceneView.scene, cam: camera)
    }
    
  }
	
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		
		// Pause the view's AR session.
		sceneView.session.pause()
	}
	
	// MARK: - ARSCNViewDelegate
  /// - Tag: PlaceARContent
  func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
    
    guard let planeAnchor = anchor as? ARPlaneAnchor else { //is it a plane?
      return
    }
    
    // Create a SceneKit plane to visualize the plane anchor using its position and extent.
    let plane = SCNPlane(width: CGFloat(planeAnchor.extent.x), height: CGFloat(planeAnchor.extent.z))
    let planeNode = SCNNode(geometry: plane)
    planeNode.simdPosition = float3(planeAnchor.center.x, 0, planeAnchor.center.z)
    planeNode.eulerAngles.x = -.pi / 2
    planeNode.opacity = 0.25
  
    reticle.addPlaneNode(planeNode: node, anchor: anchor)
    
    /*
     Add the plane visualization to the ARKit-managed node so that it tracks
     changes in the plane anchor as plane estimation continues.
     */
    node.addChildNode(planeNode)
  }

  
  /// - Tag: UpdateARContent
  func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
    // Update content only for plane anchors and nodes matching the setup created in `renderer(_:didAdd:for:)`.
    guard let planeAnchor = anchor as?  ARPlaneAnchor,
        let planeNode = node.childNodes.first,
        let plane = planeNode.geometry as? SCNPlane
        else { return }
    
    reticle.updatePlaneNode(planeNode: node, anchor: anchor)
    // Plane estimation may shift the center of a plane relative to its anchor's transform.
    planeNode.simdPosition = float3(planeAnchor.center.x, 0, planeAnchor.center.z)
  
    /*
     Plane estimation may extend the size of the plane, or combine previously detected
     planes into a larger one. In the latter case, `ARSCNView` automatically deletes the
     corresponding node for one plane, then calls this method to update the size of
     the remaining plane.
    */
    os_log ("updating anchors")
    plane.width = CGFloat(planeAnchor.extent.x)
    plane.height = CGFloat(planeAnchor.extent.z)
    
  }
  
  
  //MARK - IBActions
  
  @IBAction func buttonClick(_ sender: Any) {
    
    if(modelsLoaded) { //clear planes, clear out and delete map, start a new mapping session
      //Clear everything
      modelTransforms.removeAll()
      clearModels()
      modelsAdded = 0
      modelsDrawn = false
      modelsLoaded = false
      os_log("cleared models")

      //Allow models to be added again
      saveLoadButton.setTitle("Add Model", for: .normal)
      reticle.addPreviewModelToReticle(node: getModel(fileLoc: modelNames[modelsAdded]))
      
      //Stop the localized (or localizing) status, delete the map.
      LibPlacenote.instance.stopSession()
      LibPlacenote.instance.deleteMap(mapId: currMapID, deletedCb: {(deleted: Bool) -> Void in
        if (deleted) {
          print("Deleting: " + self.currMapID)
          self.defaults.removeObject(forKey: "MapID")
        }
        else {
          print ("Can't Delete: " + self.currMapID)
        }
      })
      localizing = false
      
      //Start mapping again
      os_log("starting new session")
      mapping = true
      LibPlacenote.instance.startSession()
    }
    else if (modelsAdded < 3) {
      //Add the current model, remove it from preview
      print("adding " + String(describing: modelsAdded) + "th Model")
      reticle.removePreviewModel()
      let model = getModel(fileLoc: modelNames[modelsAdded])
      let matrix = reticle.addModelAtReticle(node: model)
      loadedModelNodes.append(model)
      modelTransforms.add(transform: matrix_float4x4(matrix))
      modelsAdded = modelsAdded + 1
      
      if (modelsAdded >= 3) { //max number of models added, saveMap and Models
        saveLoadButton.setTitle("Clear Map", for: .normal)
        modelsDrawn = true
        saveMapAndModels()
      }
      else { //preview the next model
        reticle.addPreviewModelToReticle(node: getModel(fileLoc: modelNames[modelsAdded]))
      }
    }
    
  }
  
  func saveMapAndModels() {
    os_log("saving models")
    saveModels()
    
    LibPlacenote.instance.saveMap(
      savedCb: {(mapId: String?) -> Void in
        if (mapId != nil) {
          self.defaults.set(mapId, forKey: "MapID")
          self.mapping = false //we done mapping
          LibPlacenote.instance.stopSession()
          let configuration = ARWorldTrackingConfiguration()
          configuration.planeDetection = []
          self.sceneView.session.run(configuration)
        } else {
          os_log("Failed to save map")
        }
    },
      uploadProgressCb: {(completed: Bool, faulted: Bool, percentage: Float) -> Void in
        //nothing to do here, because we dont care if the map is uploaded or not
    })
  }
  
  private  func loadMapAndModels () -> Bool {
    guard let savedID = defaults.string(forKey: "MapID") else { return false }
    os_log ("Map Exists")
    currMapID = savedID
    modelTransforms = loadModels()!
    guard modelTransforms.count() > 0 else {return false}
    os_log ("saved models are loaded")
    print("first one: " + String(describing: modelTransforms.transforms.first))
    
    DispatchQueue.global(qos: .background).async (execute: {() -> Void in //
      while (!LibPlacenote.instance.initialized()) { //wait for it to initialize
        usleep(100);
      }
      LibPlacenote.instance.loadMap(mapId: self.currMapID, downloadProgressCb: {(completed: Bool, faulted: Bool, percentage: Float) -> Void in
        print("percentage:" + String(describing: percentage))
        if (completed) {
          os_log("Map load completed..localizing")
          self.localizing = true
          LibPlacenote.instance.startSession()
        }
      })
    })
    return true
  }
  
  private func saveModels() {
    let isSuccessfulSave = NSKeyedArchiver.archiveRootObject(modelTransforms, toFile: ModelLoc.ArchiveURL.path)
    if isSuccessfulSave {
      os_log("Models Saved", log: OSLog.default, type: .debug)
    } else {
      os_log("Can't save Models", log: OSLog.default, type: .error)
    }
  }
  
  enum FileError : Error {
    case NoFileError(String)
  }
  
  private func loadModels() -> ModelLoc?  {
    var models : ModelLoc = ModelLoc()
    do {
      guard let readmodels : ModelLoc = try NSKeyedUnarchiver.unarchiveObject(withFile: ModelLoc.ArchiveURL.path) as? ModelLoc else { throw FileError.NoFileError("Archive not found") }
      models = readmodels
    }
    catch {
      os_log ("can't open file")
    }
    return models
  }
  
  private func renderModels() {
    
    print ("adding models")
    for transform in modelTransforms.transforms {
      
      print ("adding model")
      let model = getModel(fileLoc: modelNames[modelsAdded])
      model.transform = SCNMatrix4(transform)
      sceneView.scene.rootNode.addChildNode(model)
      loadedModelNodes.append(model)
      modelsAdded = modelsAdded + 1
    }
    
    modelsDrawn = true
  }
  
  func getModel (fileLoc: String) -> SCNNode {
    let fileNodes = SCNScene(named: "art.scnassets/" + fileLoc)
    let node = SCNNode()
    for child in (fileNodes?.rootNode.childNodes)! {
      node.addChildNode(child)
    }
    print ("created model from" + fileLoc)
    return node
  }
  
  private func clearModels() {
    for node in loadedModelNodes {
      node.removeFromParentNode()
    }
    loadedModelNodes.removeAll()
  }
  
  

  // MARK: - ARSessionDelegate
  func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
    guard let frame = session.currentFrame else { return }
    updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
  }

  func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
    guard let frame = session.currentFrame else { return }
    updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
  }

  func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
    updateSessionInfoLabel(for: session.currentFrame!, trackingState: camera.trackingState)
  }
  
  
  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    if (arkitActive && (mapping || localizing)) {
      //os_log ("sending arframes!")
      let image: CVPixelBuffer = frame.capturedImage
      let pose: matrix_float4x4 = frame.camera.transform
      LibPlacenote.instance.setFrame(image: image, pose: pose)
    }
    reticle.updateReticle()
  }

    // MARK: - ARSessionObserver
	func sessionWasInterrupted(_ session: ARSession) {
		// Inform the user that the session has been interrupted, for example, by presenting an overlay.
		sessionInfoLabel.text = "Session was interrupted"
	}
	
	func sessionInterruptionEnded(_ session: ARSession) {
		// Reset tracking and/or remove existing anchors if consistent tracking is required.
		sessionInfoLabel.text = "Session interruption ended"
		resetTracking()
	}
    
    func session(_ session: ARSession, didFailWithError error: Error) {
      // Present an error message to the user.
      sessionInfoLabel.text = "Session failed: \(error.localizedDescription)"
      resetTracking()
  }

    // MARK: - Private methods

  private func updateSessionInfoLabel(for frame: ARFrame, trackingState: ARCamera.TrackingState) {
    // Update the UI to provide feedback on the state of the AR experience.
    var message: String = ""
    
    switch trackingState {
      case .normal where frame.anchors.isEmpty:
          // No planes detected; provide instructions for this app's AR interactions.
          message = "Move the device around to detect horizontal surfaces."
          arkitActive = true
      case .normal:
          // No feedback needed when tracking is normal and planes are visible.
          message = ""
          arkitActive = true
      case .notAvailable:
          message = "Tracking unavailable."
      
      case .limited(.excessiveMotion):
          message = "Tracking limited - Move the device more slowly."
      
      case .limited(.insufficientFeatures):
          message = "Tracking limited - Point the device at an area with visible surface detail, or improve lighting conditions."
      
      case .limited(.initializing):
          message = "Initializing AR session."
    }

    sessionInfoLabel.text = message
    sessionInfoView.isHidden = message.isEmpty
  }

  private func resetTracking() {
    let configuration = ARWorldTrackingConfiguration()
    configuration.planeDetection = .horizontal
    sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
  }
  
  func onPose(_ outputPose: matrix_float4x4, _ arkitPose: matrix_float4x4) {
    
  }
  
  func onStatusChange(_ prevStatus: LibPlacenote.MappingStatus, _ currStatus: LibPlacenote.MappingStatus) {
    if prevStatus != LibPlacenote.MappingStatus.running && currStatus == LibPlacenote.MappingStatus.running && !modelsDrawn {
      os_log("Found Old Map! Rendering Planes")
      clearModels() //clear some of the models if they are already drawn
      renderModels()
    }
  }
  
  
  
  
}
