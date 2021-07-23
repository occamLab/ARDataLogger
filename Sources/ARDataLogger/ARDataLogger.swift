import ARKit
import FirebaseAuth

protocol ARDataLoggerAdapter {
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor])
    func session(_ session: ARSession, didAdd anchors: [ARAnchor])
    func session(_ session: ARSession, didRemove anchors: [ARAnchor])
    func session(_ session: ARSession, didUpdate frame: ARFrame)
}


enum MeshLoggingBehavior {
    case none
    case all
    case updated
}

class ARDataLogger: ARDataLoggerAdapter {
    public static var shared = ARDataLogger()
    let uploadManager = UploadManager.shared
    var voiceFeedback: URL?
    var trialID: String?
    var poseLog: [(Double, simd_float4x4)] = []
    var trialLog: [(Double, Any)] = []
    var attributes: [String: Any] = [:]
    var configLog: [String: Bool]?
    var finalizedSet: Set<String> = []
    var lastBodyDetectionTime = Date()
    var baseTrialPath: String = ""
    var frameSequenceNumber: Int = 0
    var lastTimeStamp:Double = -1
    
    private init() {
    }
    
    
    func addAudioFeedback(audioFileURL: URL) {
        voiceFeedback = audioFileURL
    }
    
    func addFrame(frame: ARFrameDataLog) {
        print("Add frame called")
        // if we saw a body recently, we can't log the data
        if -lastBodyDetectionTime.timeIntervalSinceNow > 1.0 {
            frameSequenceNumber += 1
            DispatchQueue.global(qos: .background).async { [baseTrialPath = self.baseTrialPath, frameSequenceNumber = self.frameSequenceNumber] in
                self.uploadAFrame(baseTrialPath: baseTrialPath, frameSequenceNumber: frameSequenceNumber, frame: frame)
            }
        }
    }
    
    func logString(logMessage: String) {
        trialLog.append((lastTimeStamp, logMessage))
    }
    
    func logDictionary(logDictionary: [String : Any]) {
        guard JSONSerialization.isValidJSONObject(logDictionary) else {
            return
        }
        trialLog.append((lastTimeStamp, logDictionary))
    }
    
    func logPose(pose: simd_float4x4, at time: Double) {
        poseLog.append((time, pose))
    }
    
    private func uploadLog(trialLogToUse: [(Double, Any)], baseTrialPath: String) {
        guard let logJSON = try? JSONSerialization.data(withJSONObject: trialLogToUse.map({["timestamp": $0.0, "message": $0.1]}), options: .prettyPrinted) else {
            return
        }
        let logPath = "\(baseTrialPath)/log.json"
        UploadManager.shared.putData(logJSON, contentType: "application/json", fullPath: logPath)
    }
    
    private func uploadPoses(poseLogToUse: [(Double, simd_float4x4)], baseTrialPath: String) {
        guard let poseJSON = try? JSONSerialization.data(withJSONObject: poseLogToUse.map({["timestamp": $0.0, "pose": $0.1.asColumnMajorArray]}), options: .prettyPrinted) else {
            return
        }
        let posesPath = "\(baseTrialPath)/poses.json"
        UploadManager.shared.putData(poseJSON, contentType: "application/json", fullPath: posesPath)
        print("Uploading poses")
    }
    
    private func uploadConfig(configLogToUse: [String: Bool]?, attributesToUse: [String: Any], baseTrialPath: String) {
        guard let configLog = configLogToUse else {
            return
        }
        guard let configJSON = try? JSONSerialization.data(withJSONObject: configLog, options: .prettyPrinted) else {
            return
        }
        let configPath = "\(baseTrialPath)/config.json"
        UploadManager.shared.putData(configJSON, contentType: "application/json", fullPath: configPath)
        guard let attributeJSON = try? JSONSerialization.data(withJSONObject: attributesToUse, options: .prettyPrinted) else {
            return
        }
        let attributesPath = "\(baseTrialPath)/attributes.json"
        UploadManager.shared.putData(attributeJSON, contentType: "application/json", fullPath: attributesPath)
        print("Uploading configuration log")
    }
    
    private func uploadAFrame(baseTrialPath: String, frameSequenceNumber: Int, frame: ARFrameDataLog) {
        let imagePath = "\(baseTrialPath)/\(String(format:"%04d", frameSequenceNumber))/frame.jpg"
        UploadManager.shared.putData(frame.jpegData, contentType: "image/jpeg", fullPath: imagePath)
        guard let frameMetaData = frame.metaDataAsJSON() else {
            //NavigationController.shared.logString("Error: failed to get frame metadata")
            return
        }
        let metaDataPath = "\(baseTrialPath)/\(String(format:"%04d", frameSequenceNumber))/framemetadata.json"
        UploadManager.shared.putData(frameMetaData, contentType: "application/json", fullPath: metaDataPath)
        if let meshData = frame.meshesToProtoBuf() {
            let meshDataPath = "\(baseTrialPath)/\(String(format:"%04d", frameSequenceNumber))/meshes.pb"
            // TODO: gzipping gives a 30-40% reduction.  let compressedData: Data = try! meshData.gzipped()
            UploadManager.shared.putData(meshData, contentType: "application/x-protobuf", fullPath: meshDataPath)
        }
        print("Uploading a frame?")
    }
    
    func finalizeTrial() {
        guard let trialID = self.trialID else {
            return
        }
        guard !self.finalizedSet.contains(trialID) else {
            // can't finalize the trial more than once
            return
        }
        finalizedSet.insert(trialID)
        // TODO: we converted the upload interfaces to static to try to fix a bug where the app was crashing.  This might not be an issue anymore, so we should revisit whether we can change back to the old interfaces
        // Upload audio to Firebase
        if let voiceFeedback = voiceFeedback, let data = try? Data(contentsOf: voiceFeedback) {
            let audioFeedbackPath = "\(baseTrialPath)/voiceFeedback.wav"
            UploadManager.shared.putData(data, contentType: "audio/wav", fullPath: audioFeedbackPath)
        }
        print("tpath", baseTrialPath)
        uploadLog(trialLogToUse: trialLog, baseTrialPath: baseTrialPath)
        uploadPoses(poseLogToUse: poseLog, baseTrialPath: baseTrialPath)
        uploadConfig(configLogToUse: configLog, attributesToUse: attributes, baseTrialPath: baseTrialPath)
    }
    
    func startTrial() {
        resetInternalState()
        // Easier to navigate older vs newer data uploads
        trialID = "\(UUID())"
        logConfig()

        guard let user = Auth.auth().currentUser, let trialID = self.trialID else {
            print("User is not logged in")
            return
        }
        baseTrialPath = "\(user.uid)/\(trialID)"
        print("Starting trial", baseTrialPath)
    }
    
    func logConfig() {
        //configLog = CodesignConfiguration.shared.configAsDict()
    }
    
    func logAttribute(key: String, value: Any) {
        if JSONSerialization.isValidJSONObject([key: value]) {
            attributes[key] = value
        } else {
            //NavigationController.shared.logString("Unable to log \(key) as its value cannot be serialized to JSON")
        }
    }
    
    private func resetInternalState() {
        voiceFeedback = nil
        trialID = nil
        trialLog = []
        poseLog = []
        attributes = [:]
        configLog = nil
        frameSequenceNumber = 0
    }
    
    func processNewBodyDetectionStatus(bodyDetected: Bool) {
        if bodyDetected {
            lastBodyDetectionTime = Date()
        }
    }
    
    
    var meshNeedsUploading: [UUID: Bool] = [:]
    var meshRemovalFlag: [UUID: Bool] = [:]
    var meshesAreChanging: Bool = false
    
    func getMeshArrays(frame: ARFrame, meshLoggingBehavior: MeshLoggingBehavior)->[(String, [String: [[Float]]])]? {
        // TODO: could maybe speed this up using unsafe C operations and the like.  Probably this is not needed though
        var meshUpdateCount = 0
        // Boolean flag, when true, sessions do not collect data on added and updated meshes until flag is turned back off at end of function
        meshesAreChanging = true
        if meshLoggingBehavior == .none {
            return nil
        }
        var meshArrays: [(String,[String: [[Float]]])] = []
        for (key, value) in meshRemovalFlag {
            if value {
                meshArrays.append((key.uuidString, ["transform": [matrix_identity_float4x4.columns.0.asArray, matrix_identity_float4x4.columns.1.asArray, matrix_identity_float4x4.columns.2.asArray, matrix_identity_float4x4.columns.3.asArray], "vertices": [], "normals": []]))
                meshRemovalFlag[key] = false
            }
        }
        for mesh in frame.anchors.compactMap({$0 as? ARMeshAnchor }) {
            if meshLoggingBehavior == .all || meshNeedsUploading[mesh.identifier] == true {
                meshUpdateCount += 1
                meshNeedsUploading[mesh.identifier] = false
                var vertices: [[Float]] = []
                var normals: [[Float]] = []
                var vertexPointer = mesh.geometry.vertices.buffer.contents().advanced(by: mesh.geometry.vertices.offset)
                var normalsPointer = mesh.geometry.normals.buffer.contents().advanced(by: mesh.geometry.normals.offset)
                for _ in 0..<mesh.geometry.vertices.count {
                    let normal = normalsPointer.assumingMemoryBound(to: (Float, Float, Float).self).pointee
                    let vertex = vertexPointer.assumingMemoryBound(to: (Float, Float, Float).self).pointee
                    normals.append([normal.0, normal.1, normal.2])
                    vertices.append([vertex.0, vertex.1, vertex.2])
                    normalsPointer = normalsPointer.advanced(by: mesh.geometry.normals.stride)
                    vertexPointer = vertexPointer.advanced(by: mesh.geometry.vertices.stride)
                }
                
                meshArrays.append((mesh.identifier.uuidString, ["transform": [mesh.transform.columns.0.asArray, mesh.transform.columns.1.asArray, mesh.transform.columns.2.asArray, mesh.transform.columns.3.asArray], "vertices": vertices, "normals": normals]))
            }
        }
        print("updated \(meshUpdateCount)")
        meshesAreChanging = false
        return meshArrays
    }
    
    func toLogFrame(frame: ARFrame, type: String, trueNorthTransform: simd_float4x4?, meshLoggingBehavior: MeshLoggingBehavior)->ARFrameDataLog? {
        guard let uiImage = frame.capturedImage.toUIImage(), let jpegData = uiImage.jpegData(compressionQuality: 0.5) else {
            return nil
        }
        // Pointclouds for LiDAR phones
        var transformedCloud: [simd_float4] = []
        if let depthMap = frame.sceneDepth?.depthMap, let confMap = frame.sceneDepth?.confidenceMap {
            let pointCloud = saveSceneDepth(depthMapBuffer: depthMap, confMapBuffer: confMap)
            let xyz = pointCloud.getFastCloud(intrinsics: frame.camera.intrinsics, strideStep: 1, maxDepth: 1000, throwAwayPadding: 0, rgbWidth: CVPixelBufferGetWidth(frame.capturedImage), rgbHeight: CVPixelBufferGetHeight(frame.capturedImage))
            // Come back to this
            for p in xyz {
                transformedCloud.append(simd_float4(simd_normalize(p.0), simd_length(p.0)))
            }
        }
        
        let meshes = getMeshArrays(frame: frame, meshLoggingBehavior: meshLoggingBehavior)
        // Mesh length should not increase and remain around stable or fluttering within a certain range
        if let meshes = meshes {
            print("Mesh count: \(String(describing: meshes.count))")
        }
        
        return ARFrameDataLog(timestamp: frame.timestamp, jpegData: jpegData, depthData: transformedCloud, intrinsics: frame.camera.intrinsics, planes: frame.anchors.compactMap({$0 as? ARPlaneAnchor}), pose: frame.camera.transform, trueNorth: trueNorthTransform, meshes: meshes)
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        var allUpdatedMeshes: [UUID] = []
        for id in anchors.compactMap({$0 as? ARMeshAnchor}).map({$0.identifier}) {
            if !meshesAreChanging {
                meshNeedsUploading[id] = true
                allUpdatedMeshes.append(id)
            }
        }
        //print("number of meshes being updated \(allUpdatedMeshes.count) total meshes: \(session.currentFrame?.anchors.compactMap({$0 as? ARMeshAnchor}).count)")
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for id in anchors.compactMap({$0 as? ARMeshAnchor}).map({$0.identifier}) {
            if !meshesAreChanging {
                meshNeedsUploading[id] = true
                meshRemovalFlag[id] = false
            }
        }
    }
    
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for id in anchors.compactMap({$0 as? ARMeshAnchor}).map({$0.identifier}) {
            //print("WARNING: MESH DELETED \(id)")
            meshRemovalFlag[id] = true
        }
    }
    
    // - MARK: Running app session
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lastTimeStamp = frame.timestamp
    }
    
}
