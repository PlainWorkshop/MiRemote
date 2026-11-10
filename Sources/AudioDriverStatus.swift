import Foundation
import CoreAudio

struct AudioDriverStatus {
 let name: String
 let device: AudioDeviceID

 static func find(named name: String) -> AudioDriverStatus? {
  var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
  var size: UInt32 = 0
  guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return nil }
  var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
  guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return nil }
  for id in ids {
   var property = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
   var label: Unmanaged<CFString>?
   var length = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
   guard AudioObjectGetPropertyData(id, &property, 0, nil, &length, &label) == noErr,
         let label, label.takeUnretainedValue() as String == name,
         (name != "MiRemote" || deviceUID(id) == "MiRemote_UID"),
         hasStreams(id, scope: kAudioDevicePropertyScopeInput), hasStreams(id, scope: kAudioDevicePropertyScopeOutput) else { continue }
   return AudioDriverStatus(name: name, device: id)
  }
  return nil
 }

 private static func deviceUID(_ device: AudioDeviceID) -> String? {
  var property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
  var value: Unmanaged<CFString>?
  var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
  guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr, let value else { return nil }
  return value.takeUnretainedValue() as String
 }

 private static func hasStreams(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
  var property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  var size: UInt32 = 0
  return AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size) == noErr && size >= MemoryLayout<AudioStreamID>.size
 }

 static func preferred() -> AudioDriverStatus? {
  find(named: "MiRemote") ?? find(named: "vRemoteDr 2ch")
 }
}
