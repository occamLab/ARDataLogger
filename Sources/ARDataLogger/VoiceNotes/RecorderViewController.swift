//
//  RecordViewController.swift
//  VoiceMemosClone
//
//  Created by Hassan El Desouky on 1/12/19.
//  Copyright © 2019 Hassan El Desouky. All rights reserved.
//

import UIKit
import AVFoundation
import Accelerate
import SwiftUI

public struct RecorderView: UIViewControllerRepresentable {
    public func makeUIViewController(context: Context) -> RecorderViewController {
        print("Recreating the view controller")
        return RecorderViewController()
    }
    
    public func updateUIViewController(_ uiViewController: RecorderViewController, context: Context) {
        
    }
}


public struct RecordFeedbackView: View {
    @Binding var showRecordFeedbackView: Bool

    public var body: some View {
        NavigationView {
            VStack {
                Text("If you want to record voice feedback regarding your experience recording and navigating the route, please use the button below to record your feedback on this trial.  When you are satisfied with your feedback, you can use the done button to return to the main screen of the app.")
                RecorderView()
            }
            .navigationBarTitle(Text("You've arrived!"), displayMode: .inline)
                .navigationBarItems(trailing: Button(action: {
                    print("Dismissing sheet view...")
                    self.showRecordFeedbackView = false
            }) {
                Text("Done").bold()
            })
        }.onDisappear() {
            ARLogger.shared.finalizeTrial()
        }.onAppear() {
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .screenChanged, argument: "You've arrived. Please use the pop-up window to provide your feedback on your experience.")
            }
        }.accessibility(addTraits: .isModal)
    }
}

extension Double {
    /// a double expressed as a time string of format MINUTES:SECONDS
    var toTimeString: String {
        let seconds: Int = Int(self.truncatingRemainder(dividingBy: 60.0))
        let minutes: Int = Int(self / 60.0)
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// The states for the audio recorder.
///
/// - recording: recording is ongoing
/// - stopped: recording has been stopped
/// - denied: the recording has been denied (e.g., appropriate permission was not granted)
enum RecorderState {
    /// recording is ongoing
    case recording
    /// recording has been stopped
    case stopped
    /// the recording has been denied (e.g., appropriate permission was not granted)
    case denied
}

/// The view controller for the audio recorder
public class RecorderViewController: UIViewController, SRCountdownTimerDelegate {
    
    //MARK:- Properties
    /// recorded audio
    var recordedAudioURL: URL?
    
    /// the handle view (TODO: not sure exactly what this is)
    var handleView = UIView()
    /// the countdown timer
    var srCountdownTimer = SRCountdownTimer()
    /// the button used to preview
    var playButton = UIButton()
    /// the button used for recording
    var recordButton = RecordButton()
    /// the view that displays the time
    var timeLabel = UILabel()
    /// the visualizer of the audio waveform
    var audioView = AudioVisualizerView()
    /// a handle to the `AVAudioEngine`
    let audioEngine = AVAudioEngine()
    private var renderTs: Double = 0
    private var recordingTs: Double = 0
    private var silenceTs: Double = 0
    private var audioFile: AVAudioFile?
    private var writeAudio = false
    private var doRecording: DispatchWorkItem?

    var voiceNoteToPlay: AVAudioPlayer?
    
    //MARK:- Outlets
    
    /// the view to use when fading the control in / out
    @IBOutlet weak var fadeView: UIView!
    
    //MARK:- Life Cycle
    
    /// Called when the view loads so various components can be setup.
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        setupHandleView()
        setupRecordingButton()
        setupTimeLabel()
        setupAudioView()
        setupSRCountdownView()
        
        title = NSLocalizedString("voiceNoteRecorderPop-UpHeader", comment: "The header of a pop-up window that allows user to record a voice note")
    }
    
    func setupSRCountdownView() {
        srCountdownTimer = SRCountdownTimer(frame: CGRect(x: 0,
                                                        y: 0,
                                                        width: 250,
                                                        height: 250))
        srCountdownTimer.labelFont = UIFont(name: "HelveticaNeue-Light", size: 100)
        srCountdownTimer.labelTextColor = UIColor.white
        srCountdownTimer.timerFinishingText = "End"
        srCountdownTimer.lineWidth = 10
        srCountdownTimer.lineColor = UIColor.white
        srCountdownTimer.delegate = self
        srCountdownTimer.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        srCountdownTimer.isHidden = true
        /// hide the timer as an accessibility element
        /// and announce through VoiceOver by posting appropriate notifications
        srCountdownTimer.accessibilityElementsHidden = true
        view.addSubview(srCountdownTimer)
        
        srCountdownTimer.translatesAutoresizingMaskIntoConstraints = false
        srCountdownTimer.widthAnchor.constraint(equalToConstant: 250).isActive = true
        srCountdownTimer.heightAnchor.constraint(equalToConstant: 250).isActive = true
        srCountdownTimer.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        srCountdownTimer.topAnchor.constraint(equalTo: view.topAnchor, constant: 10).isActive = true
    }
    
    /// Called when the view will appear.
    ///
    /// - Parameter animated: true if animated, false otherwise
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let notificationName = AVAudioSession.interruptionNotification
        NotificationCenter.default.addObserver(self, selector: #selector(handleRecording(_:)), name: notificationName, object: nil)
    }
    
    /// Called whent he view will disappear.
    ///
    /// - Parameter animated: true if animated, false otherwise
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }
    
    //MARK:- Setup Methods
    fileprivate func setupHandleView() {
        handleView.layer.cornerRadius = 2.5
        handleView.backgroundColor = UIColor(red: 208, green: 207, blue: 205, alpha: 255)
        view.addSubview(handleView)
        handleView.translatesAutoresizingMaskIntoConstraints = false
        handleView.widthAnchor.constraint(equalToConstant: 37.5).isActive = true
        handleView.heightAnchor.constraint(equalToConstant: 5).isActive = true
        handleView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        handleView.topAnchor.constraint(equalTo: view.topAnchor, constant: 10).isActive = true
        handleView.alpha = 0
    }
    
    fileprivate func setupRecordingButton() {
        recordButton.isRecording = false
        recordButton.addTarget(self, action: #selector(handleRecording(_:)), for: .touchUpInside)
        view.addSubview(recordButton)
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -32).isActive = true
        recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: -40).isActive = true
        recordButton.widthAnchor.constraint(equalToConstant: 65).isActive = true
        recordButton.heightAnchor.constraint(equalToConstant: 65 ).isActive = true
        
        playButton.setImage(UIImage(named: "startNavigation")!, for: .normal)
        print("setting preview handler", self)
        playButton.addTarget(self, action: #selector(handlePreview(_:)), for: .touchUpInside)
        view.addSubview(playButton)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        // TODO: put them in a hstack maybe?
        playButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -32).isActive = true
        playButton.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 40).isActive = true
        playButton.widthAnchor.constraint(equalToConstant: 65).isActive = true
        playButton.heightAnchor.constraint(equalToConstant: 65 ).isActive = true
        playButton.accessibilityLabel = "Preview voice feedback"
        playButton.isEnabled = false
    }
    
    fileprivate func setupTimeLabel() {
        view.addSubview(timeLabel)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        timeLabel.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -16).isActive = true
        timeLabel.text = "00.00"
        timeLabel.textColor = .gray
        timeLabel.alpha = 0
    }
    
    fileprivate func setupAudioView() {
        audioView.frame = CGRect(x: 0, y: 24, width: view.frame.width, height: 135)
        view.addSubview(audioView)
        //TODO: Add autolayout constraints
        audioView.alpha = 0
        audioView.isHidden = true
    }
    
    //MARK:- Actions
    
    /// Start recording in response to a user action.
    ///
    /// - Parameter sender: the button that initiated the recording
    @objc func handleRecording(_ sender: RecordButton) {
        var defaultFrame: CGRect = CGRect(x: 0, y: 24, width: view.frame.width, height: 135)
        if recordButton.isRecording {
            defaultFrame = self.view.frame
            audioView.isHidden = false
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .curveEaseOut, animations: {
                self.handleView.alpha = 1
                self.timeLabel.alpha = 1
                self.audioView.alpha = 1
                self.view.frame = CGRect(x: 0, y: self.view.frame.height, width: self.view.bounds.width, height: -300)
                self.view.layoutIfNeeded()
            }, completion: nil)
            self.checkPermissionAndRecord()
        } else {
            audioView.isHidden = true
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .curveEaseOut, animations: {
                self.handleView.alpha = 0
                self.timeLabel.alpha = 0
                self.audioView.alpha = 0
                self.view.frame = defaultFrame
                self.view.layoutIfNeeded()
            }, completion: nil)
            self.stopRecording()
        }
    }
    
    @objc func handlePreview(_ sender: UIButton) {
        if let recordedAudioURL = recordedAudioURL {
            let data = try! Data(contentsOf: recordedAudioURL)
            voiceNoteToPlay = try! AVAudioPlayer(data: data, fileTypeHint: AVFileType.caf.rawValue)
            voiceNoteToPlay?.prepareToPlay()
            voiceNoteToPlay?.volume = 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.voiceNoteToPlay?.play()
            }
        }
    }
    
    //MARK:- Update User Interface
    private func updateUI(_ recorderState: RecorderState) {
        switch recorderState {
        case .recording:
            UIApplication.shared.isIdleTimerDisabled = true
            self.audioView.isHidden = false
            self.timeLabel.isHidden = false
            break
        case .stopped:
            UIApplication.shared.isIdleTimerDisabled = false
            self.audioView.isHidden = true
            self.timeLabel.isHidden = true
            break
        case .denied:
            UIApplication.shared.isIdleTimerDisabled = false
            self.recordButton.isHidden = true
            self.audioView.isHidden = true
            self.timeLabel.isHidden = true
            break
        }
    }
    
    
    // MARK:- Recording
    private func startRecording() {
        // TODO: possibly notify the NavigationController that this is starting
        recordedAudioURL = nil
        print("resetting recordAudioURL")
        srCountdownTimer.isHidden = false
        srCountdownTimer.start(beginingValue: 3, interval: 1)
        view.layoutIfNeeded()
        writeAudio = false
        DispatchQueue.global(qos: .background).async {
            self.startAudioTap()
        }
        doRecording = DispatchWorkItem {
            self.srCountdownTimer.isHidden = true
            DispatchQueue.global(qos: .background).async {
                self.intiateAudioWrite()
            }
        }
    }
    
    func intiateAudioWrite() {
        recordingTs = NSDate().timeIntervalSince1970
        writeAudio = true
    }
    
    func startAudioTap() {
        self.recordingTs = NSDate().timeIntervalSince1970
        self.silenceTs = 0
        
        let sampleRate: Double
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .videoRecording)
            sampleRate = session.sampleRate
            try session.setActive(true)
        } catch let error as NSError {
            print(error.localizedDescription)
            return
        }
        
        let inputNode = self.audioEngine.inputNode
        guard let format = self.format(sampleRate) else {
            return
        }
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { (buffer, time) in
            let level: Float = -50
            let length: UInt32 = 1024
            buffer.frameLength = length
            let channels = UnsafeBufferPointer(start: buffer.floatChannelData, count: Int(buffer.format.channelCount))
            var value: Float = 0
            vDSP_meamgv(channels[0], 1, &value, vDSP_Length(length))
            var average: Float = ((value == 0) ? -100 : 20.0 * log10f(value))
            if average > 0 {
                average = 0
            } else if average < -100 {
                average = -100
            }
            let silent = average < level
            let ts = NSDate().timeIntervalSince1970
            if self.writeAudio && ts - self.renderTs > 0.1 {
                let floats = UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength))
                let frame = floats.map({ (f) -> Int in
                    return Int(f * Float(Int16.max))
                })
                DispatchQueue.main.async {
                    let seconds = (ts - self.recordingTs)
                    self.timeLabel.text = seconds.toTimeString
                    self.renderTs = ts
                    let len = self.audioView.waveforms.count
                    for i in 0 ..< len {
                        let idx = ((frame.count - 1) * i) / len
                        let f: Float = sqrt(1.5 * abs(Float(frame[idx])) / Float(Int16.max))
                        self.audioView.waveforms[i] = min(49, Int(f * 50))
                    }
                    self.audioView.active = !silent
                    self.audioView.setNeedsDisplay()
                }
            }

            if self.writeAudio {
                if self.audioFile == nil {
                    print("creating the audioFile and staring recording")
                    self.audioFile = self.createAudioRecordFile(sampleRate)
                }
                if let f = self.audioFile {
                    do {
                        try f.write(from: buffer)
                    } catch let error as NSError {
                        print(error.localizedDescription)
                    }
                }
            }
        }
        do {
            self.audioEngine.prepare()
            try self.audioEngine.start()
        } catch let error as NSError {
            print(error.localizedDescription)
            return
        }
        DispatchQueue.main.async {
            self.updateUI(.recording)
        }
    }
    
    /// Called when recording is stopped.
    private func stopRecording() {
        //if the view controller has a delegate
        if let audioFile = self.audioFile {
            //call the delegate's version of didFinishRecording
            recordedAudioURL = audioFile.url
            ARLogger.shared.addAudioFeedback(audioFileURL: audioFile.url)
            playButton.isEnabled = true
        }
        self.audioFile = nil
        self.audioEngine.inputNode.removeTap(onBus: 0)
        self.audioEngine.stop()
        self.updateUI(.stopped)
        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback)
        } catch let error {
            fatalError(error.localizedDescription)
        }
    }

    /// Make sure appropriate permissiosn to access the microphone have been granted.  If not, ask for them now.
    private func checkPermissionAndRecord() {
        let permission = AVAudioSession.sharedInstance().recordPermission
        switch permission {
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission({ (result) in
                DispatchQueue.main.async {
                    if result {
                        print("starting record")
                        self.startRecording()
                    }
                    else {
                        self.updateUI(.denied)
                    }
                }
            })
            break
        case .granted:
            self.startRecording()
            break
        case .denied:
            self.updateUI(.denied)
            break
        @unknown default:
            fatalError("Not sure what to do. This is unexpected.")
        }
    }
    
    /// Return whether or not the recorder is actively recording audio.
    ///
    /// - Returns: true if audio is being recorded and false otherwise
    private func isRecording() -> Bool {
        if self.audioEngine.isRunning {
            return true
        }
        return false
    }
    
    
    /// Return the audio recording  settings
    ///
    /// - Returns: the audio recording format / settings
    private func settings(_ sampleRate: Double)-> [String: Any] {
        return [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: true, AVSampleRateKey: Float64(sampleRate), AVNumberOfChannelsKey: 1]
    }
    
    /// Return the audio recording format
    ///
    /// - Returns: the audio recording format / settings
    private func format(_ sampleRate: Double) -> AVAudioFormat? {
        return AVAudioFormat(settings: settings(sampleRate))
    }
    
    
    // MARK:- Paths and files
    private func createAudioRecordPath() -> URL? {
        let format = DateFormatter()
        format.dateFormat="yyyy-MM-dd-HH-mm-ss-SSS"
        let currentFileName = "recording-\(format.string(from: Date()))" + ".wav"
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documentsDirectory.appendingPathComponent(currentFileName)
        return url
    }
    
    /// Create the audio file used for the recording.
    ///
    /// - Returns: the `AVAudioFile` object that can be used for recording
    private func createAudioRecordFile(_ sampleRate: Double) -> AVAudioFile? {
        guard let path = self.createAudioRecordPath() else {
            return nil
        }
        do {
            let file = try AVAudioFile(forWriting: path, settings: settings(sampleRate), commonFormat: .pcmFormatFloat32, interleaved: true)
            return file
        } catch let error as NSError {
            print(error.localizedDescription)
            return nil
        }
    }
    
    // MARK:- Handle interruption
    
    /// Called when the recording is interrupted
    ///
    /// - Parameter notification: the interrupting notification
    @objc func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        guard let key = userInfo[AVAudioSessionInterruptionTypeKey] as? NSNumber
            else { return }
        if key.intValue == 1 {
            DispatchQueue.main.async {
                if self.isRecording() {
                    self.stopRecording()
                }
            }
        }
    }
    
    /// Callback function for when `srCountdownTimer` updates.  This allows us to announce the new value via voice
    ///
    /// - Parameter newValue: the new value (in seconds) displayed on the countdown timer
    @objc public func timerDidUpdateCounterValue(sender: SRCountdownTimer, newValue: Int) {
        if newValue > 0 {
            UIAccessibility.post(notification: UIAccessibility.Notification.announcement, argument: String(newValue))
        }
    }
    
    @objc public func timerDidEnd(sender: SRCountdownTimer, elapsedTime: TimeInterval) {
        if let doRecording = doRecording {
            DispatchQueue.main.asyncAfter(deadline: .now(), execute: doRecording)
        }
    }
    
}
