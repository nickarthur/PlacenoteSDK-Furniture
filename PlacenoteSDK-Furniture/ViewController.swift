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
    
    // All IB outlets connects to Main.storyboard
    @IBOutlet weak var sessionInfoView: UIView!     // view container for session status label
    @IBOutlet weak var sessionInfoLabel: UILabel!   // label to show session status
    @IBOutlet weak var sceneView: ARSCNView!        // main scene view
    @IBOutlet weak var addItemsPanel: UIView!       // view with item picker buttons
    

    // The data structure to store our models and positions
    private var modelTransforms: ModelLoc = ModelLoc() // Info stored using NSKeyedArchive
    private var modelNames: [String] = ["WoodChair/CHAHIN_WOODEN_CHAIR.scn",
                                        "Plant/PUSHILIN_plant.scn",
                                        "BlueLamp/model-triangulated.scn",
                                        "Gramophone/model-triangulated.scn"]
    
    // variables to hold models and saved mapID
    private var loadedModelNodes: [SCNNode] = []
    private var currMapID : String = "" //map id currently being used
  
    // to store mapID's in user defaults
    private var defaults: UserDefaults = UserDefaults.standard
    
    // Session status flags
    private var arkitActive: Bool = false
    private var placenoteSessionRunning = false
    private var localizedSession = false;
  
    // Placenote specific variables
    private var camManager: CameraManager? = nil       // to control the AR camera
    private var ptViz: FeaturePointVisualizer? = nil  // to visualize Placenote features
    private var renderedScene = false
  
    // class that displays the reticle (little red dot)
    private var reticle: ReticleAR = ReticleAR()
  
    private var originalSource: Any? = nil
    
  // MARK: - View Life Cycle
  /// - Tag: StartARSession
    
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
  
    // ARKit Session configuration
    let configuration = ARWorldTrackingConfiguration()
    configuration.planeDetection = [.horizontal, .vertical]
    sceneView.autoenablesDefaultLighting = true
    //self.sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
    sceneView.session.run(configuration)
    

    // sceneView delegate
    sceneView.session.delegate = self
  
    /*
     Prevent the screen from being dimmed after a while as users will likely
     have long periods of interaction without touching the screen or buttons.
    */
    UIApplication.shared.isIdleTimerDisabled = true
  
    // Show debug UI to view performance metrics (e.g. frames per second).
    sceneView.showsStatistics = true
    
    // setting up the Reticle
    reticle = ReticleAR(arview: sceneView)
    
    
    // Placenote configurations
    LibPlacenote.instance.multiDelegate += self
    
    ptViz = FeaturePointVisualizer(inputScene: sceneView.scene);
    ptViz?.enableFeaturePoints()
    
    if let camera: SCNNode = sceneView?.pointOfView {
      camManager = CameraManager(scene: sceneView.scene, cam: camera)
    }
    
    
    if (!loadMapAndModels()) {
        
        os_log("Starting Fresh Design Session")
        
        sessionInfoLabel.text = "Starting Fresh Design Session"
        sessionInfoView.isHidden = false
        sessionInfoView.backgroundColor = UIColor.white;
        
        while (!LibPlacenote.instance.initialized()) { //wait for it to initialize
            print("Waiting to initialize")
                usleep(100);
        }
        
        placenoteSessionRunning = true;
        LibPlacenote.instance.startSession()
    }
    else {
        // the session will resume within the LoadMapAndModels function
        os_log("Resuming Saved Session")
        //sessionInfoLabel.text = "Resuming Saved Design Session"
        //sessionInfoView.isHidden = false
        
        
    }
    
  }
	
    
    // Pause session on disappear
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

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
    //node.addChildNode(planeNode)
    
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

    plane.width = CGFloat(planeAnchor.extent.x)
    plane.height = CGFloat(planeAnchor.extent.z)
    
  }
 
 
    
/*
     // Activate this to use polygonal planes from iOS 11.3
     
  func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        let anchorNode = SCNNode()
        anchorNode.name = "anchor"
        sceneView.scene.rootNode.addChildNode(anchorNode)
        return anchorNode
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        
        guard let planeAnchor = anchor as?  ARPlaneAnchor else { return }
        
        let planeGeometry = planeAnchor.geometry
        
        guard let device = MTLCreateSystemDefaultDevice() else {return}
        
        let plane = ARSCNPlaneGeometry(device: device)
        
        plane?.update(from: planeGeometry)
        
        node.geometry = plane
        node.geometry?.firstMaterial?.diffuse.contents = UIColor.blue
        node.geometry?.firstMaterial?.transparency = 0.20
    }
*/
    
    
    
  
  //MARK - IBActions
  
    @IBAction func addChair(_ sender: Any) {
        
        print("adding chair, index 0")
        
        let model = getModel(fileLoc: modelNames[0])
        let matrix = reticle.addModelAtReticle(node: model)
        
        loadedModelNodes.append(model)
        modelTransforms.add(transform: matrix_float4x4(matrix), type: UInt32(0))
    }
    
    @IBAction func addPlant(_ sender: Any) {
        
        print("adding Plant, index 1")
        
        let model = getModel(fileLoc: modelNames[1])
        let matrix = reticle.addModelAtReticle(node: model)
        
        loadedModelNodes.append(model)
        modelTransforms.add(transform: matrix_float4x4(matrix), type: UInt32(1))
    }
    
    @IBAction func addLamp(_ sender: Any) {
        
        print("adding Lamp, index 2")
        
        let model = getModel(fileLoc: modelNames[2])
        let matrix = reticle.addModelAtReticle(node: model)
        
        loadedModelNodes.append(model)
        modelTransforms.add(transform: matrix_float4x4(matrix), type: UInt32(2))
    }
    
    @IBAction func addGramophone(_ sender: Any) {
        
        //print("adding Gramophone, index 3")
        
        let model = getModel(fileLoc: modelNames[3])
        let matrix = reticle.addModelAtReticle(node: model)
        
        loadedModelNodes.append(model)
        modelTransforms.add(transform: matrix_float4x4(matrix), type: UInt32(3))
        
    }
    
    
    @IBAction func clearAll(_ sender: Any) {
        
        
        //  clear models from the scene
        modelTransforms.removeAll()
        clearModels()
        
        // Stop Placenote and delete the latest map
        placenoteSessionRunning = false
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
 
        
        
        //Start the mapping again
        os_log("starting new session")
        
        placenoteSessionRunning = true
        localizedSession = false;
        LibPlacenote.instance.startSession()
        
        // Set status on Label
        sessionInfoLabel.text = "Designing..."
        sessionInfoView.isHidden = false
        sessionInfoView.backgroundColor = UIColor.white;
    }
    
    
  @IBAction func buttonClick(_ sender: Any) {
    
    // save the session
    saveMapAndModels()
    
  }
  
  func saveMapAndModels() {
    
    // Save the models
    os_log("saving models")
    saveModels()
    
    // Save and upload the Placenote map
    
    LibPlacenote.instance.saveMap(
      savedCb: {(mapId: String?) -> Void in
        if (mapId != nil) {
          self.defaults.set(mapId, forKey: "MapID")

          self.placenoteSessionRunning = false
          LibPlacenote.instance.stopSession()
            
          self.sessionInfoLabel.text = "Saving..."
          self.sessionInfoView.isHidden = false
          self.sessionInfoView.backgroundColor = UIColor.yellow;
            
          let configuration = ARWorldTrackingConfiguration()
          configuration.planeDetection = []
          self.sceneView.session.run(configuration)
        } else {
          os_log("Failed to save map")
        }
    },
      uploadProgressCb: {(completed: Bool, faulted: Bool, percentage: Float) -> Void in
        
        // sessionInfo view set here:
        self.sessionInfoLabel.text = "Saving..."
        self.sessionInfoView.isHidden = false
        self.sessionInfoView.backgroundColor = UIColor.yellow;
        
        if (completed) {
            self.sessionInfoLabel.text = "Saved!"
            self.sessionInfoView.backgroundColor = UIColor.green;
        }
        
    })
  }
  
  private  func loadMapAndModels () -> Bool {
    
    guard let savedID = defaults.string(forKey: "MapID")
        else { return false }
    os_log ("Map Exists")
    
    currMapID = savedID
    
    modelTransforms = loadModels()!
    
    guard modelTransforms.count() > 0 else {return false}
    
    os_log ("saved models are loaded")
    print("first one: " + String(describing: modelTransforms.types.first))
    
    DispatchQueue.global(qos: .background).async (execute: {() -> Void in //
      while (!LibPlacenote.instance.initialized()) { //wait for it to initialize
        usleep(100);
      }
      LibPlacenote.instance.loadMap(mapId: self.currMapID, downloadProgressCb: {(completed: Bool, faulted: Bool, percentage: Float) -> Void in
        print("percentage:" + String(describing: percentage))
        if (completed) {
          os_log("Map load completed..localizing")
            
          self.placenoteSessionRunning = true;
          LibPlacenote.instance.startSession()
            
          self.sessionInfoLabel.text = "Resuming Shared Session"
          self.sessionInfoView.isHidden = false
          self.sessionInfoView.tintColor = UIColor.yellow;
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
    print (modelTransforms.count())
    
    
    for index in 0..<modelTransforms.count() {
        let modelType = modelTransforms.types[index]
        let model = getModel(fileLoc: modelNames[Int(modelType)])
        
        model.transform = SCNMatrix4(modelTransforms.transforms[index])
        sceneView.scene.rootNode.addChildNode(model)
        loadedModelNodes.append(model)
    }
    
//
//    for transform in modelTransforms.transforms {
//
//      print ("adding model")
//      let model = getModel(fileLoc: modelNames[0])
//      model.transform = SCNMatrix4(transform)
//      sceneView.scene.rootNode.addChildNode(model)
//      loadedModelNodes.append(model)
//      modelsAdded = modelsAdded + 1
//    }
    

  }
  
  func getModel (fileLoc: String) -> SCNNode {
    let fileNodes = SCNScene(named: "art.scnassets/" + fileLoc)
    let node = SCNNode()
    for child in (fileNodes?.rootNode.childNodes)! {
      node.addChildNode(child)
    }
    print ("created model from " + fileLoc)
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

    if (arkitActive && placenoteSessionRunning && !localizedSession) {
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
          //message = "Move the device around to detect horizontal surfaces."
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
    case .limited(.relocalizing):
        message = "Relocalizing AR session."
    }
    

    sessionInfoLabel.text = message
    sessionInfoView.isHidden = message.isEmpty
    sessionInfoView.backgroundColor = UIColor.white;
  }

  private func resetTracking() {
    let configuration = ARWorldTrackingConfiguration()

    configuration.planeDetection = [.horizontal, .vertical]

    sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
  }
  
  func onPose(_ outputPose: matrix_float4x4, _ arkitPose: matrix_float4x4) {
    
  }
  
  func onStatusChange(_ prevStatus: LibPlacenote.MappingStatus, _ currStatus: LibPlacenote.MappingStatus) {
    
    if prevStatus == LibPlacenote.MappingStatus.lost && currStatus == LibPlacenote.MappingStatus.running {
        
        if (renderedScene) {
            return
        }
        renderModels()
        renderedScene = true
        
        localizedSession = true;
        sessionInfoLabel.text = "Resuming Saved Design"
        sessionInfoView.isHidden = false
        sessionInfoView.backgroundColor = UIColor.green;
        
    }
  }
  
  
  
  
}
