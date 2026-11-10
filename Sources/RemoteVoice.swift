import Foundation
import Combine
import CoreBluetooth
import CoreAudio
import AudioToolbox
import AVFoundation

func voiceInputDecibels(_ samples: [Int16]) -> Double? {
 guard !samples.isEmpty else { return nil }
 let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
 let rms = sqrt(sum / Double(samples.count)) / 32768.0
 guard rms > 0 else { return nil }
 return 20 * log10(rms)
}
func voiceInputLevel(_ samples: [Int16]) -> Double {
 guard let decibels = voiceInputDecibels(samples) else { return 0 }
 return max(0, min(1, (decibels + 60) / 30))
}

final class RemoteVoice: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
 @Published private(set) var enabled = false
 @Published private(set) var status = "遥控器麦克风已关闭"
 @Published private(set) var serviceReady = false
 @Published private(set) var bleConnected = false
 @Published private(set) var receiving = false
 @Published private(set) var inputLevel = 0.0
 @Published private(set) var inputDecibels: Double?
 private let serviceID = CBUUID(string: ATVVProtocol.serviceUUID)
 private let commandID = CBUUID(string: ATVVProtocol.txUUID)
 private let audioID = CBUUID(string: ATVVProtocol.rxUUID)
 private let controlID = CBUUID(string: ATVVProtocol.controlUUID)
 private let decoder = ATVVProtocol()
 private let engine = AVAudioEngine()
 private let player = AVAudioPlayerNode()
 private var format: AVAudioFormat?
 private var central: CBCentralManager?
 private var remote: CBPeripheral?
 private var command: CBCharacteristic?
 private var ready = Set<CBUUID>()
 private var capabilitiesRequested = false
 private var active = false
 private var streamID: UInt8 = 0
 private var opened = false
 private var retry: Timer?
 private var generation = 0
 private var lastLevelUpdate = Date.distantPast
 private var levelTimer: Timer?

 func setEnabled(_ value: Bool) {
  guard value != enabled else { return }
  enabled = value
  if value {
   guard AudioDriverStatus.preferred() != nil else {
    enabled = false; status = "未找到 MiRemote 或兼容的虚拟音频驱动"; return
   }
   status = "正在启动蓝牙语音服务…"
   if let central { centralManagerDidUpdateState(central) }
   else { central = CBCentralManager(delegate: self, queue: .main) }
  } else {
   retry?.invalidate(); retry = nil
   closeMicrophone(); stopPlayback()
   if let remote { central?.cancelPeripheralConnection(remote) }
   remote = nil; command = nil; ready.removeAll(); capabilitiesRequested = false
   serviceReady = false; bleConnected = false
   status = "遥控器麦克风已关闭"
  }
 }
 func centralManagerDidUpdateState(_ central: CBCentralManager) {
  guard enabled else { return }
  guard central.state == .poweredOn else {
   serviceReady = false; bleConnected = false; stopPlayback(); status = "蓝牙未开启或未授权（状态 \(central.state.rawValue)）"; return
  }
  connectAvailable()
 }
 private func connectAvailable() {
  guard enabled, let central, central.state == .poweredOn, remote == nil else { return }
  let candidates = central.retrieveConnectedPeripherals(withServices: [serviceID]).filter { ($0.name ?? "").contains("小米蓝牙语音遥控器") }
  guard candidates.count == 1, let candidate = candidates.first else {
   status = candidates.isEmpty ? "等待连接小米遥控器…" : "检测到多只同名遥控器，请只连接一只"
   scheduleRetry(); return
  }
  retry?.invalidate(); retry = nil; remote = candidate; candidate.delegate = self
  status = "正在连接遥控器语音服务…"
  if candidate.state == .connected { bleConnected = true; candidate.discoverServices([serviceID]) }
  else { central.connect(candidate) }
 }
 private func scheduleRetry() {
  retry?.invalidate()
  retry = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in self?.connectAvailable() }
 }
 func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
  guard enabled, remote === peripheral else { return }
  bleConnected = true
  peripheral.discoverServices([serviceID])
 }
 func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) { disconnected(peripheral, error) }
 func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) { disconnected(peripheral, error) }
 private func disconnected(_ peripheral: CBPeripheral, _ error: Error?) {
  guard remote === peripheral else { return }
  stopPlayback(); remote = nil; command = nil; opened = false; serviceReady = false; bleConnected = false
  ready.removeAll(); capabilitiesRequested = false
  if enabled { status = "语音连接断开，正在重试"; scheduleRetry() }
 }
 func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
  guard enabled else { return }
  guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == serviceID }) else {
   fail("未找到语音服务", error); return
  }
  peripheral.discoverCharacteristics([commandID, audioID, controlID], for: service)
 }
 func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
  guard enabled else { return }
  if let error { fail("读取语音服务失败", error); return }
  for item in service.characteristics ?? [] {
   if item.uuid == commandID { command = item }
   if item.uuid == audioID || item.uuid == controlID { peripheral.setNotifyValue(true, for: item) }
  }
  if command == nil { fail("未找到语音控制通道", nil) }
 }
 func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor item: CBCharacteristic, error: Error?) {
  guard enabled else { return }
  guard error == nil, item.isNotifying else { fail("无法监听语音数据", error); return }
  ready.insert(item.uuid)
  guard ready.contains(audioID), ready.contains(controlID), !capabilitiesRequested, let command else { return }
  capabilitiesRequested = true
  peripheral.writeValue(decoder.getCapabilitiesCommand, for: command, type: .withoutResponse)
 }
 func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor item: CBCharacteristic, error: Error?) {
  guard enabled else { return }
  if let error { serviceReady = false; stopPlayback(); status = "接收语音失败：\(error.localizedDescription)"; return }
  guard let data = item.value else { return }
  if item.uuid == audioID {
   if active, let frame = decoder.decodeAudio(data) { updateInputLevel(frame.samples); play(frame.samples) }
  } else if item.uuid == controlID { handleControl(data, peripheral) }
 }
 private func handleControl(_ data: Data, _ peripheral: CBPeripheral) {
  switch decoder.parseControl(data) {
  case .capabilities(let capabilities):
   do {
    try decoder.acceptCapabilities(capabilities)
    guard let command, !opened else { return }
    peripheral.writeValue(try decoder.micOpenCommand(), for: command, type: .withoutResponse)
    opened = true; serviceReady = true; status = "语音服务已就绪 · 按住语音键说话"
   } catch { status = "语音服务不支持：\(error.localizedDescription)" }
  case .audioStart(let reason, let codec, let id):
   streamID = id
   guard reason == 3 else { return }
   do { try startPlayback(rate: Double(codec.sampleRate)); decoder.beginAudioStream(codec: codec); active = true; status = "等待遥控器音频数据…" }
   catch { serviceReady = false; stopPlayback(); status = "虚拟麦克风不可用：\(error.localizedDescription)" }
  case .audioStop(let reason):
   if reason == 2 { finishStream() }
  case .audioSync(let codec, let sequence, let predictor, let step):
   decoder.applyAudioSync(codec: codec, sequence: sequence, predictor: predictor, stepIndex: step)
  case .micOpenError(let code): opened = false; serviceReady = false; stopPlayback(); status = "遥控器拒绝开启麦克风（\(code)）"
  default: break
  }
 }
 private func fail(_ message: String, _ error: Error?) {
  serviceReady = false; stopPlayback()
  status = error.map { "\(message)：\($0.localizedDescription)" } ?? message
 }
 private func closeMicrophone() {
  if opened, let command, let remote, let close = try? decoder.micCloseCommand(streamID: streamID) {
   remote.writeValue(close, for: command, type: .withoutResponse)
  }
  opened = false
 }
 private func startPlayback(rate: Double) throws {
  generation += 1; active = false; player.stop(); engine.stop()
  if engine.attachedNodes.contains(player) { engine.detach(player) }
  guard let device = AudioDriverStatus.preferred()?.device else { throw voiceError("未找到可用的虚拟音频驱动") }
  guard let unit = engine.outputNode.audioUnit else { throw voiceError("音频输出不可用") }
  var value = device
  let result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &value, UInt32(MemoryLayout<AudioDeviceID>.size))
  guard result == noErr else { throw voiceError("选择虚拟麦克风失败（\(result)）") }
  guard let newFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { throw voiceError("不支持采样率") }
  format = newFormat
  if !engine.attachedNodes.contains(player) { engine.attach(player) }
  engine.connect(player, to: engine.mainMixerNode, format: newFormat)
  try engine.start(); player.play()
 }
 private func play(_ samples: [Int16]) {
  guard !samples.isEmpty, let format, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)), let channel = buffer.floatChannelData?[0] else { return }
  buffer.frameLength = AVAudioFrameCount(samples.count)
  for (index, sample) in samples.enumerated() { channel[index] = max(-1, min(1, Float(sample) * (4.0 / 32768))) }
  player.scheduleBuffer(buffer)
 }
 private func updateInputLevel(_ samples: [Int16]) {
  guard !samples.isEmpty else { return }
  let now = Date()
  if !receiving { receiving = true; status = "正在接收遥控器语音…" }
  if now.timeIntervalSince(lastLevelUpdate) >= 0.1 {
   inputDecibels = voiceInputDecibels(samples)
   inputLevel = voiceInputLevel(samples); lastLevelUpdate = now
  }
  if levelTimer == nil {
   levelTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
    guard let self, self.active, Date().timeIntervalSince(self.lastLevelUpdate) >= 0.5 else { return }
    self.inputLevel = 0; self.inputDecibels = nil; self.receiving = false; self.status = "等待遥控器音频数据…"
   }
  }
 }
 private func resetInputLevel() {
  levelTimer?.invalidate(); levelTimer = nil; lastLevelUpdate = .distantPast
  receiving = false; inputLevel = 0; inputDecibels = nil
 }
 private func finishStream() {
  guard active else { return }
  resetInputLevel()
  active = false; decoder.endAudioStream(); generation += 1
  let current = generation
  status = "语音服务已就绪 · 按住语音键说话"
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
   guard let self, !self.active, self.generation == current else { return }
   self.player.stop(); self.engine.stop()
  }
 }
 private func stopPlayback() {
  resetInputLevel()
  generation += 1; active = false; decoder.endAudioStream(); player.stop(); engine.stop()
  if engine.attachedNodes.contains(player) { engine.detach(player) }
  format = nil
 }
 private func voiceError(_ message: String) -> NSError {
  NSError(domain: "RemoteVoice", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
 }
}
