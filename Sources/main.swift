import AppKit
import SwiftUI
import IOKit.hid
import ApplicationServices
import Carbon

struct ButtonSpec: Identifiable { let id:String; let title:String; let icon:String }
let buttons:[ButtonSpec] = [
 .init(id:"power",title:"电源",icon:"power"), .init(id:"voice",title:"语音",icon:"mic"),
 .init(id:"up",title:"方向上",icon:"arrow.up"), .init(id:"down",title:"方向下",icon:"arrow.down"),
 .init(id:"left",title:"方向左",icon:"arrow.left"), .init(id:"right",title:"方向右",icon:"arrow.right"),
 .init(id:"select",title:"确认",icon:"circle.inset.filled"), .init(id:"home",title:"主页",icon:"house"),
 .init(id:"back",title:"返回",icon:"chevron.left"), .init(id:"menu",title:"菜单",icon:"line.3.horizontal"),
 .init(id:"volumeUp",title:"音量加",icon:"plus"), .init(id:"volumeDown",title:"音量减",icon:"minus")]
struct MappingOption: Identifiable {
 let id:String; let code:CGKeyCode?; var flags:CGEventFlags = []; var media:Int32? = nil
}
let choices:[MappingOption] = [
 .init(id:"不映射",code:nil), .init(id:"方向上",code:126), .init(id:"方向下",code:125), .init(id:"方向左",code:123), .init(id:"方向右",code:124),
 .init(id:"Command ⌘",code:55), .init(id:"Option ⌥",code:58), .init(id:"Control ⌃",code:59), .init(id:"Shift ⇧",code:56),
 .init(id:"回车",code:36), .init(id:"Esc",code:53), .init(id:"删除",code:51), .init(id:"Tab",code:48), .init(id:"空格",code:49),
 .init(id:"Home",code:115), .init(id:"End",code:119), .init(id:"Page Up",code:116), .init(id:"Page Down",code:121),
 .init(id:"系统音量 +",code:nil,media:0), .init(id:"系统音量 −",code:nil,media:1), .init(id:"系统静音",code:nil,media:7), .init(id:"播放/暂停",code:nil,media:16),
 .init(id:"显示桌面",code:103,flags:.maskSecondaryFn), .init(id:"Spotlight (⌘Space)",code:49,flags:.maskCommand),
 .init(id:"复制 (⌘C)",code:8,flags:.maskCommand), .init(id:"粘贴 (⌘V)",code:9,flags:.maskCommand), .init(id:"撤销 (⌘Z)",code:6,flags:.maskCommand), .init(id:"关闭窗口 (⌘W)",code:13,flags:.maskCommand),
 .init(id:"锁屏",code:12,flags:CGEventFlags(rawValue:CGEventFlags.maskControl.rawValue | CGEventFlags.maskCommand.rawValue | 0x12)),
 .init(id:"睡眠",code:nil), .init(id:"切换应用",code:nil), .init(id:"自定义…",code:nil)]
let defaultButtonMappings:[String:String] = [
 "power":"关闭窗口 (⌘W)", "voice":"Option ⌥",
 "up":"方向上", "down":"方向下", "left":"方向左", "right":"方向右",
 "select":"回车", "home":"复制 (⌘C)", "back":"撤销 (⌘Z)",
 "menu":"粘贴 (⌘V)", "volumeUp":"系统音量 +", "volumeDown":"系统音量 −"
]
func resolvedButtonMappings(_ saved:[String:String]?) -> [String:String] {
 var result=defaultButtonMappings
 if let saved { result.merge(saved) { _, userValue in userValue } }
 return result
}
struct Shortcut:Codable { let code:UInt16; let flags:UInt64; let label:String }
struct HeldKey { let code:CGKeyCode; let flags:CGEventFlags; var isModifier:Bool = false }
func modifierFlags(_ code:CGKeyCode)->CGEventFlags? {
 switch code {
 case 55: return CGEventFlags(rawValue:CGEventFlags.maskCommand.rawValue | 0x08)
 case 58: return CGEventFlags(rawValue:CGEventFlags.maskAlternate.rawValue | 0x20)
 case 59: return CGEventFlags(rawValue:CGEventFlags.maskControl.rawValue | 0x01)
 case 56: return CGEventFlags(rawValue:CGEventFlags.maskShift.rawValue | 0x02)
 default: return nil
 }
}
func combinedModifiers(_ held:[String:HeldKey])->CGEventFlags { held.values.reduce(CGEventFlags()) { current, item in item.isModifier ? current.union(modifierFlags(item.code) ?? []) : current } }
final class RemoteModel:ObservableObject {
 @Published var accessibilityGranted=false; @Published var inputAccess=2; @Published var postEventGranted=false; @Published var automationStatus="待检测"; @Published var showPermissions=false
 private var permissionTimer:Timer?
 @Published var connected=false; @Published var learning:String?; @Published var message="正在查找小米遥控器…"; @Published var codes:[String:String]; @Published var mappings:[String:String]; @Published var mappingEnabled=false
 let filter=DeviceFilter(); var testingBypassFilter=false; var eventSink:((CGEvent)->Void)?; var isTrusted:()->Bool = {AXIsProcessTrusted()}
 var mediaSink:((Int32)->Void)?; private var mediaRepeatTimers:[String:DispatchSourceTimer]=[:]; private var keyRepeatTimers:[String:DispatchSourceTimer]=[:]
 var manager:IOHIDManager!; var sent:[String:HeldKey]=[:]; var custom:[String:Shortcut]=[:]; var captureMonitor:Any?; @Published var recordingShortcut:String?; var physical=Set<String>(); var lastSeen=""; var preventUntil=Date.distantPast
 init() {
  let defaults=UserDefaults.standard
  var saved = defaults.dictionary(forKey:"buttonCodes") as? [String:String] ?? [:]
  let verified = ["voice":"7:62", "power":"7:102", "up":"7:82", "down":"7:81", "left":"7:80", "right":"7:79", "select":"7:40", "home":"7:74", "back":"7:241", "menu":"7:101", "volumeUp":"7:128", "volumeDown":"7:129"]
  for (id, code) in verified where saved[id] == nil && !saved.values.contains(code) { saved[id] = code }
  codes=saved
  defaults.set(saved, forKey:"buttonCodes")
  mappings=resolvedButtonMappings(defaults.dictionary(forKey:"buttonMappings") as? [String:String])
  if let data=defaults.data(forKey:"customShortcuts"), let stored=try? JSONDecoder().decode([String:Shortcut].self,from:data) { custom=stored }
  mappingEnabled=defaults.bool(forKey:"mappingEnabled")
 }
 func refreshPermissions() {
  let previous = accessibilityGranted
  let previousInput = inputAccess
  accessibilityGranted=AXIsProcessTrusted()
  inputAccess=Int(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue)
  postEventGranted=CGPreflightPostEventAccess()
  if mappingEnabled && ((previous && !accessibilityGranted) || (previousInput == 0 && inputAccess != 0) || !postEventGranted) {
   releaseAll();do {try filter.remove()} catch {message="权限变化，恢复原始按键失败：\(error.localizedDescription)"}
   mappingEnabled=false;UserDefaults.standard.set(false,forKey:"mappingEnabled")
  }
  if previousInput != inputAccess, manager != nil {
   releaseAll()
   IOHIDManagerClose(manager,0)
   let result=IOHIDManagerOpen(manager,0)
   if result != 0 { message="输入监控状态已变化，重新打开监听失败（\(result)）；请重启应用" }
  }
  let target=NSAppleEventDescriptor(bundleIdentifier:"com.apple.systemevents")
  let result=AEDeterminePermissionToAutomateTarget(target.aeDesc,AEEventClass(kCoreEventClass),AEEventID(kAEGetData),false)
  switch result {case 0: automationStatus="已授权";case -1743: automationStatus="未授权";case -1744: automationStatus="尚未请求";default: automationStatus="待检测"}
 }
 func openPrivacy(_ pane:String) {if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?\(pane)"){NSWorkspace.shared.open(url)}}
 func requestAccessibility(){let options=[kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary;_ = AXIsProcessTrustedWithOptions(options);openPrivacy("Privacy_Accessibility");refreshPermissions()}
 func requestInputMonitoring(){_ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent);openPrivacy("Privacy_ListenEvent");refreshPermissions()}
 func requestPostEvents(){_ = CGRequestPostEventAccess();openPrivacy("Privacy_Accessibility");refreshPermissions()}
 func requestAutomation(){
  var errors:NSDictionary?
  guard let script=NSAppleScript(source:"tell application \"System Events\" to get name") else {automationStatus="无法检测";return}
  _ = script.executeAndReturnError(&errors)
  if let errors {let number=(errors[NSAppleScript.errorNumber] as? NSNumber)?.intValue;if number == -1743 {automationStatus="未授权";openPrivacy("Privacy_Automation")} else {automationStatus="无法检测";message="自动化检查失败：\(errors[NSAppleScript.errorMessage] ?? "未知错误")"}} else {automationStatus="已授权"}
  refreshPermissions()
 }
 func start() {
  refreshPermissions()
  permissionTimer=Timer.scheduledTimer(withTimeInterval:2,repeats:true){[weak self] _ in self?.refreshPermissions()}
  manager=IOHIDManagerCreate(kCFAllocatorDefault,0)
  IOHIDManagerSetDeviceMatching(manager,[kIOHIDVendorIDKey:0x2717,kIOHIDProductIDKey:0x32b8] as CFDictionary)
  let ctx=Unmanaged.passUnretained(self).toOpaque()
  IOHIDManagerRegisterDeviceMatchingCallback(manager,{ctx,result,_,_ in guard let ctx,result==0 else{return};let m=Unmanaged<RemoteModel>.fromOpaque(ctx).takeUnretainedValue();m.connected=true
   if m.mappingEnabled {do {guard m.accessibilityGranted && m.inputAccess == 0 && m.postEventGranted else {throw DeviceFilter.FilterError.command("缺少输入监控或辅助功能权限")};try m.filter.install(manager:m.manager,codes:m.codes);m.message="映射已启用 · 原始按键已拦截"} catch {m.mappingEnabled=false;UserDefaults.standard.set(false,forKey:"mappingEnabled");m.message="拦截失败：\(error.localizedDescription)"}}
   else {m.message="遥控器已连接，可以识别按键"}},ctx)
  IOHIDManagerRegisterDeviceRemovalCallback(manager,{ctx,_,_,_ in guard let ctx else{return};let m=Unmanaged<RemoteModel>.fromOpaque(ctx).takeUnretainedValue();m.releaseAll();m.filter.deviceDisconnected();m.connected=false;m.learning=nil;m.message="遥控器已断开"},ctx)
  IOHIDManagerRegisterInputValueCallback(manager,{ctx,result,_,value in guard let ctx,result==0 else{return};let e=IOHIDValueGetElement(value);let page=IOHIDElementGetUsagePage(e),usage=IOHIDElementGetUsage(e);guard usage != 0 && usage != 1 && usage != UInt32.max else{return};let m=Unmanaged<RemoteModel>.fromOpaque(ctx).takeUnretainedValue();m.event(page:page,usage:usage,down:IOHIDValueGetIntegerValue(value) != 0)},ctx)
  IOHIDManagerScheduleWithRunLoop(manager,CFRunLoopGetMain(),CFRunLoopMode.defaultMode.rawValue)
  let r=IOHIDManagerOpen(manager,0); if r != 0 {message="无法监听遥控器（\(r)）"}
 }
 func event(page:UInt32,usage:UInt32,down:Bool) {
  let key="\(page):\(usage)"
  if down {
   guard !physical.contains(key) else{return};physical.insert(key)
   if let id=learning {
    guard Date() >= preventUntil else{return}
    if let existing=codes.first(where:{$0.value==key && $0.key != id}) { message="该信号已属于「\(buttons.first{$0.id==existing.key}?.title ?? existing.key)」，未覆盖"; learning=nil; return }
    codes[id]=key; UserDefaults.standard.set(codes,forKey:"buttonCodes");learning=nil;message="已识别「\(buttons.first{$0.id==id}?.title ?? id)」";return
   }
   guard mappingEnabled, (filter.installed || testingBypassFilter), isTrusted(), let id=codes.first(where:{$0.value==key})?.key, let name=mappings[id], let option=choices.first(where:{$0.id==name}) else {return}
   if let media=option.media { emitMedia(media); if media == 0 || media == 1 {startMediaRepeat(key,media)} }
   else if name == "睡眠" {
    var errors:NSDictionary?
    if let script=NSAppleScript(source:"tell application \"System Events\" to sleep") { _ = script.executeAndReturnError(&errors); if errors != nil {message="无法执行睡眠，请检查自动化权限";refreshPermissions();return} }
   }
   else if name == "切换应用" { switchApplication() }
   else {
    let saved = name == "自定义…" ? custom[id] : nil
    let code = saved.map { CGKeyCode($0.code) } ?? option.code
    let flags = saved.map { CGEventFlags(rawValue:$0.flags) } ?? option.flags
    guard let code else {message="请先录制自定义快捷键";return}
    let isModifier = saved == nil && modifierFlags(code) != nil
    if isModifier {
     let wasHeld=sent.values.contains { $0.isModifier && $0.code == code }
     sent[key]=HeldKey(code:code,flags:[],isModifier:true)
     if !wasHeld {postModifier(code,combinedModifiers(sent))}
    } else {
     post(code,flags.union(combinedModifiers(sent)),true);sent[key]=HeldKey(code:code,flags:flags)
     let oneShot = ["显示桌面", "Spotlight (⌘Space)", "复制 (⌘C)", "粘贴 (⌘V)", "撤销 (⌘Z)", "关闭窗口 (⌘W)", "锁屏"]
     if !oneShot.contains(name) && flags.intersection([.maskCommand,.maskControl,.maskAlternate]).isEmpty {startKeyRepeat(key)}
    }
   }
   message="\(buttons.first{$0.id==id}?.title ?? id) → \(name) 按住中"
  } else {
   physical.remove(key)
   stopMediaRepeat(key)
   stopKeyRepeat(key)
   if let held=sent.removeValue(forKey:key) {
    if held.isModifier { if !sent.values.contains(where:{$0.isModifier && $0.code == held.code}) {postModifier(held.code,combinedModifiers(sent))} }
    else {post(held.code,held.flags.union(combinedModifiers(sent)),false)}
    message="已释放按键"
   }
  }
 }
 func post(_ code:CGKeyCode,_ flags:CGEventFlags,_ down:Bool,repeatKey:Bool = false) { guard let event=CGEvent(keyboardEventSource:CGEventSource(stateID:.hidSystemState),virtualKey:code,keyDown:down) else{return};event.flags=flags;if repeatKey {event.setIntegerValueField(.keyboardEventAutorepeat,value:1)};if let eventSink {eventSink(event)} else {event.post(tap:.cghidEventTap)} }
 func postModifier(_ code:CGKeyCode,_ flags:CGEventFlags) {guard let event=CGEvent(keyboardEventSource:CGEventSource(stateID:.hidSystemState),virtualKey:code,keyDown:true) else{return};event.type = .flagsChanged;event.flags=flags;if let eventSink {eventSink(event)} else {event.post(tap:.cghidEventTap)}}
 func startKeyRepeat(_ key:String) {
  stopKeyRepeat(key)
  let timer=DispatchSource.makeTimerSource(queue:.main)
  timer.schedule(deadline:.now()+0.45,repeating:0.08,leeway:.milliseconds(10))
  timer.setEventHandler { [weak self] in
   guard let self,self.physical.contains(key),self.mappingEnabled,(self.filter.installed || self.testingBypassFilter),self.isTrusted(),let held=self.sent[key],!held.isModifier else {self?.stopKeyRepeat(key);return}
   self.post(held.code,held.flags.union(combinedModifiers(self.sent)),true,repeatKey:true)
  }
  keyRepeatTimers[key]=timer;timer.resume()
 }
 func stopKeyRepeat(_ key:String) {if let timer=keyRepeatTimers.removeValue(forKey:key) {timer.setEventHandler{};timer.cancel()}}
 func emitMedia(_ key:Int32) {if let mediaSink {mediaSink(key)} else {postMedia(key)}}
 func startMediaRepeat(_ key:String,_ media:Int32) {
  stopMediaRepeat(key)
  let timer=DispatchSource.makeTimerSource(queue:.main)
  timer.schedule(deadline:.now()+0.45,repeating:0.12,leeway:.milliseconds(15))
  timer.setEventHandler { [weak self] in
   guard let self,self.physical.contains(key),self.mappingEnabled,(self.filter.installed || self.testingBypassFilter),self.isTrusted() else {self?.stopMediaRepeat(key);return}
   self.emitMedia(media)
  }
  mediaRepeatTimers[key]=timer;timer.resume()
 }
 func stopMediaRepeat(_ key:String) {if let timer=mediaRepeatTimers.removeValue(forKey:key) {timer.setEventHandler{};timer.cancel()}}
 func postMedia(_ key:Int32) {for state:Int32 in [0xA,0xB] {let data=Int((key << 16) | (state << 8));NSEvent.otherEvent(with:.systemDefined,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,subtype:8,data1:data,data2:-1)?.cgEvent?.post(tap:.cghidEventTap)}}
 func switchApplication(){post(55,.maskCommand,true);post(48,.maskCommand,true);post(48,.maskCommand,false);DispatchQueue.main.asyncAfter(deadline:.now()+0.15){self.post(55,[],false)}}
 func releaseAll(){
  for key in Array(mediaRepeatTimers.keys) {stopMediaRepeat(key)}
  for key in Array(keyRepeatTimers.keys) {stopKeyRepeat(key)}
  for (key,held) in sent.filter({!$0.value.isModifier}) {sent.removeValue(forKey:key);post(held.code,held.flags.union(combinedModifiers(sent)),false)}
  for key in Array(sent.keys) {guard let held=sent.removeValue(forKey:key) else {continue};if held.isModifier && !sent.values.contains(where:{$0.isModifier && $0.code == held.code}) {postModifier(held.code,combinedModifiers(sent))}}
  physical.removeAll()
 }
 func cancelCapture(){if let monitor=captureMonitor {NSEvent.removeMonitor(monitor)};captureMonitor=nil;recordingShortcut=nil}
 func capture(_ id:String){
  releaseAll();cancelCapture();recordingShortcut=id;message="请在键盘上按下需要的快捷键（Esc 取消）"
  captureMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
   guard let self else{return event}; if event.keyCode == 53 {self.cancelCapture();self.message="已取消快捷键录制";return nil}
   let allowed:NSEvent.ModifierFlags=[.command,.option,.control,.shift,.function];let flags=event.modifierFlags.intersection(allowed)
   var cg:CGEventFlags=[];if flags.contains(.command){cg.insert(.maskCommand)};if flags.contains(.option){cg.insert(.maskAlternate)};if flags.contains(.control){cg.insert(.maskControl)};if flags.contains(.shift){cg.insert(.maskShift)};if flags.contains(.function){cg.insert(.maskSecondaryFn)}
   let prefix=(flags.contains(.control) ? "⌃" : "")+(flags.contains(.option) ? "⌥" : "")+(flags.contains(.shift) ? "⇧" : "")+(flags.contains(.command) ? "⌘" : "")
   let label=prefix+(event.charactersIgnoringModifiers?.uppercased() ?? "键\(event.keyCode)")
   self.custom[id]=Shortcut(code:event.keyCode,flags:cg.rawValue,label:label);if let data=try? JSONEncoder().encode(self.custom){UserDefaults.standard.set(data,forKey:"customShortcuts")}
   self.mappings[id]="自定义…";UserDefaults.standard.set(self.mappings,forKey:"buttonMappings");self.cancelCapture();self.message="已保存快捷键 \(label)";return nil
  }
 }
 func setEnabled(_ enabled:Bool){
  guard enabled != mappingEnabled else{return}
  if enabled {
   refreshPermissions();guard accessibilityGranted && inputAccess == 0 && postEventGranted else {message="请先授予所需权限";showPermissions=true;return}
   do {try filter.install(manager:manager,codes:codes);mappingEnabled=true;UserDefaults.standard.set(true,forKey:"mappingEnabled");message="映射已启用 · 原始按键已拦截"}
   catch {message="未启用映射：\(error.localizedDescription)"}
  } else {
   releaseAll()
   do {try filter.remove();mappingEnabled=false;UserDefaults.standard.set(false,forKey:"mappingEnabled");message="映射已关闭 · 已恢复原始按键"}
   catch {message="恢复原始按键失败：\(error.localizedDescription)"}
  }
 }
 func setMapping(_ id:String,_ value:String){if value == "自定义…" {capture(id);return};releaseAll();mappings[id]=value;UserDefaults.standard.set(mappings,forKey:"buttonMappings")}
 func learn(_ id:String){if mappingEnabled {message="请先关闭映射再识别按键";return};releaseAll();learning=id;preventUntil=Date().addingTimeInterval(0.3);message="请按一下「\(buttons.first{$0.id==id}?.title ?? id)」；点击取消可退出"}
 func stop(){permissionTimer?.invalidate();permissionTimer=nil;cancelCapture();releaseAll();do {try filter.remove()} catch {print("恢复遥控器原始按键失败：\(error)")};if manager != nil {IOHIDManagerUnscheduleFromRunLoop(manager,CFRunLoopGetMain(),CFRunLoopMode.defaultMode.rawValue);IOHIDManagerClose(manager,0)}}
}
struct MainView:View {
 @ObservedObject var model:RemoteModel
 @ObservedObject var voice:RemoteVoice
 let green=Color(red:0.32,green:0.82,blue:0.57)
 var body:some View {
  VStack(alignment:.leading,spacing:0) {
   HStack(alignment:.center) {
    VStack(alignment:.leading,spacing:4) {
     Text("小米遥控器 · 按键映射").font(.system(size:22,weight:.semibold))
     HStack(spacing:6){Circle().fill(model.connected ? green : .orange).frame(width:7,height:7);Text(model.connected ? "遥控器已连接" : "等待遥控器连接").foregroundColor(.secondary)}.font(.system(size:11))
    }
    Spacer()
    Toggle("启用映射",isOn:Binding(get:{model.mappingEnabled},set:{model.setEnabled($0)})).toggleStyle(.switch).controlSize(.small)
    Button("权限状态\((!model.accessibilityGranted || model.inputAccess != 0 || !model.postEventGranted) ? " · 需处理" : "")"){model.refreshPermissions();model.showPermissions=true}.padding(.leading,12)
   }.padding(.horizontal,24).padding(.top,19).padding(.bottom,12)
   HStack(spacing:14) {
    HStack(spacing:7){Circle().fill(voice.serviceReady ? green : (voice.enabled ? Color.orange : Color.gray)).frame(width:7,height:7);Text("遥控器麦克风").fontWeight(.medium);Toggle("",isOn:Binding(get:{voice.enabled},set:{voice.setEnabled($0)})).labelsHidden().toggleStyle(.switch).controlSize(.small)}
    Text(voice.status).foregroundColor(.secondary).lineLimit(1)
    Spacer(minLength:8)
    HStack(alignment:.bottom,spacing:3){ForEach(0..<10,id:\.self){index in RoundedRectangle(cornerRadius:2).fill(voice.inputLevel > Double(index)/10 ? green : Color.white.opacity(0.12)).frame(width:8,height:CGFloat(6+index))}}
     .accessibilityElement(children:.ignore).accessibilityLabel("遥控器收音音量").accessibilityValue(voice.inputDecibels.map{String(format:"%.0f dBFS",$0)} ?? "无信号")
    Text(voice.inputDecibels.map{String(format:"%.0f dBFS",$0)} ?? "— dBFS").font(.system(size:11,design:.monospaced)).foregroundColor(.secondary)
    Text(voice.receiving ? "收音中" : "未收音").foregroundColor(voice.receiving ? green : .secondary)
   }.font(.system(size:11)).padding(.horizontal,14).padding(.vertical,10).background(Color.white.opacity(0.045)).cornerRadius(8).padding(.horizontal,24)
   HStack(spacing:8) {
    Image(systemName:"info.circle");Text(model.message).lineLimit(1)
    Spacer();if model.learning != nil {Button("取消识别"){model.learning=nil;model.message="已取消识别"}.buttonStyle(.link)}
   }.font(.system(size:11)).foregroundColor(.secondary).padding(.horizontal,26).padding(.top,10)
   ScrollView([.horizontal,.vertical]) {
    MappingCallouts(model:model,green:green).padding(.horizontal,20).padding(.vertical,12)
   }
   HStack{Text("引线指向遥控器实体按键；选择「识别」可重新识别该键。").font(.system(size:11)).foregroundColor(.secondary);Spacer()}.padding(.horizontal,24).padding(.bottom,12)
  }.frame(minWidth:780,minHeight:660).background(Color(red:0.10,green:0.12,blue:0.14)).preferredColorScheme(.dark)
   .sheet(isPresented:$model.showPermissions) {PermissionView(model:model,voice:voice)}
 }
}
struct PermissionView:View {
 @ObservedObject var model:RemoteModel
 @ObservedObject var voice:RemoteVoice
 @State private var audioDriver:AudioDriverStatus?
 @Environment(\.dismiss) var dismiss
 var body:some View {
  VStack(alignment:.leading,spacing:16) {
   HStack {VStack(alignment:.leading,spacing:5){Text("权限状态").font(.system(size:22,weight:.bold));Text("授权后返回此窗口，状态会自动刷新。") .foregroundColor(.secondary).font(.system(size:12))};Spacer();Button("完成"){dismiss()}.keyboardShortcut(.cancelAction)}
   Divider()
   row("输入监控", "读取这只遥控器的物理按键。", model.inputAccess == 0 ? "已授权" : model.inputAccess == 1 ? "未授权" : "尚未确认", model.inputAccess == 0, model.inputAccess == 0 ? "设置" : "去授权",model.requestInputMonitoring)
   row("辅助功能", "将遥控器按键映射为键盘操作。",model.accessibilityGranted ? "已授权":"未授权",model.accessibilityGranted,model.accessibilityGranted ? "设置" : "去授权",model.requestAccessibility)
   row("发送按键事件", "向其他应用发送模拟按键；可能与辅助功能共用系统设置。",model.postEventGranted ? "已授权":"未授权",model.postEventGranted,model.postEventGranted ? "设置" : "去授权",model.requestPostEvents)
   row("自动化：系统事件", "仅在使用「睡眠」动作时需要。授权检查不会让电脑睡眠。",model.automationStatus,model.automationStatus == "已授权",model.automationStatus == "已授权" ? "检查":"请求授权",model.requestAutomation)
   Divider()
   Text("音频设备").font(.system(size:13,weight:.semibold))
   connectionRow("虚拟音频驱动", audioDriver?.name == "vRemoteDr 2ch" ? "使用旧应用的共享驱动，已检测到输入与输出。" : "检测 MiRemote 的输入与输出设备。", audioDriver.map { "\($0.name) · 已检测" } ?? "未检测到", audioDriver != nil)
   Divider()
   Text("遥控器连接状态").font(.system(size:13,weight:.semibold))
   connectionRow("HID · 按键连接", "系统检测到的遥控器按键设备。", model.connected ? "已连接" : "未连接", model.connected)
   connectionRow("BLE · 语音连接", "遥控器的蓝牙语音连接；需开启遥控器麦克风。", voice.enabled ? (voice.bleConnected ? "已连接" : "未连接") : "未检测", voice.bleConnected)
   Text("遥控器语音通过蓝牙接收，不使用 Mac 麦克风或摄像头。") .font(.system(size:11)).foregroundColor(.secondary)
  }.padding(24).frame(width:620).onAppear{model.refreshPermissions();audioDriver=AudioDriverStatus.preferred()}.onReceive(Timer.publish(every:3,on:.main,in:.common).autoconnect()){_ in audioDriver=AudioDriverStatus.preferred()}
 }
 func row(_ title:String,_ detail:String,_ state:String,_ granted:Bool,_ button:String,_ action:@escaping ()->Void)->some View {
  HStack(alignment:.center,spacing:12){Circle().fill(granted ? Color.green : Color.orange).frame(width:8,height:8);VStack(alignment:.leading,spacing:3){Text(title).font(.system(size:13,weight:.semibold));Text(detail).font(.system(size:11)).foregroundColor(.secondary)};Spacer();Text(state).font(.system(size:12)).foregroundColor(granted ? .green : .orange);Button(button,action:action).frame(width:82)}.padding(10).background(Color.white.opacity(0.05)).cornerRadius(8)
 }
 func connectionRow(_ title:String,_ detail:String,_ state:String,_ connected:Bool)->some View {
  HStack(alignment:.center,spacing:12){Circle().fill(connected ? Color.green : Color.orange).frame(width:8,height:8);VStack(alignment:.leading,spacing:3){Text(title).font(.system(size:13,weight:.semibold));Text(detail).font(.system(size:11)).foregroundColor(.secondary)};Spacer();Text(state).font(.system(size:12)).foregroundColor(connected ? .green : .orange)}.padding(10).background(Color.white.opacity(0.05)).cornerRadius(8)
 }
}
final class Delegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
 let model=RemoteModel()
 let voice=RemoteVoice()
 var window:NSWindow!
 var statusItem:NSStatusItem!
 private let battery=RemoteBattery()
 private var batteryTimer:Timer?
 private var displayedMenu:NSMenu?
 private var batteryItem:NSMenuItem?
 private var doubleClickMonitor:Any?
 private var globalDoubleClickMonitor:Any?
 private var doubleClickHandled=false
 func applicationDidFinishLaunching(_ note:Notification) {
  NSApp.setActivationPolicy(.accessory)
  window=NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:850),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
  window.isReleasedWhenClosed=false
  window.delegate=self
  window.title="小米遥控器 · 按键映射";window.minSize=NSSize(width:780,height:660);window.contentView=NSHostingView(rootView:MainView(model:model,voice:voice));window.center()
  statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
  if let button=statusItem.button {
   let image=NSImage(systemSymbolName:"appletvremote.gen4",accessibilityDescription:"小米遥控器按键映射") ?? NSImage(systemSymbolName:"rectangle.roundedtop",accessibilityDescription:"小米遥控器按键映射")
   image?.isTemplate=true;button.image=image;button.toolTip="小米遥控器：单击打开菜单，双击打开窗口";button.target=self;button.action=#selector(statusClicked(_:));button.sendAction(on:[.leftMouseUp,.rightMouseUp])
  }
  battery.onUpdate={ [weak self] in self?.updateBatteryItem() }
  battery.refresh()
  batteryTimer=Timer.scheduledTimer(withTimeInterval:120,repeats:true){[weak self] _ in self?.battery.refresh()}
  model.start();showWindow()
 }
 @objc func statusClicked(_ sender:NSStatusBarButton) {
  showMenu(sender)
 }
 private func updateBatteryItem() {
  guard let item=batteryItem else {return}
  if !model.connected {item.title="遥控器未连接"}
  else if !battery.connected {item.title="电量暂不可用"}
  else if let value=battery.percent {item.title="遥控器电量 · \(value)%"}
  else {item.title="遥控器电量 · 暂不可用"}
 }
 private func showMenu(_ sender:NSStatusBarButton) {
  guard displayedMenu == nil else {return}
  let menu=NSMenu();menu.autoenablesItems=false
  let level=NSMenuItem(title:"正在读取遥控器电量…",action:nil,keyEquivalent:"");level.isEnabled=false;menu.addItem(level);batteryItem=level;updateBatteryItem()
  menu.addItem(.separator())
  let show=NSMenuItem(title:"打开按键映射",action:#selector(showWindow),keyEquivalent:"");show.target=self;menu.addItem(show)
  menu.addItem(.separator());let quit=NSMenuItem(title:"退出小米遥控器",action:#selector(quitApp),keyEquivalent:"");quit.target=self;menu.addItem(quit)
  displayedMenu=menu
  let firstClickTime=NSApp.currentEvent?.timestamp ?? ProcessInfo.processInfo.systemUptime
  doubleClickHandled=false
  let detectDoubleClick: (NSEvent)->Bool = { [weak self,weak sender,weak menu] event in
   guard let self,let sender,let menu,!self.doubleClickHandled,let window=sender.window else {return false}
   let elapsed=event.timestamp-firstClickTime
   guard elapsed > 0, elapsed <= NSEvent.doubleClickInterval,
         window.convertToScreen(sender.convert(sender.bounds,to:nil)).contains(NSEvent.mouseLocation) else {return false}
   self.doubleClickHandled=true;menu.cancelTracking();DispatchQueue.main.async {self.showWindow()};return true
  }
  doubleClickMonitor=NSEvent.addLocalMonitorForEvents(matching:.leftMouseDown) { event in detectDoubleClick(event) ? nil : event }
  globalDoubleClickMonitor=NSEvent.addGlobalMonitorForEvents(matching:.leftMouseDown) { event in _ = detectDoubleClick(event) }
  battery.refresh()
  statusItem.menu=menu;sender.performClick(nil);statusItem.menu=nil
  if let monitor=doubleClickMonitor {NSEvent.removeMonitor(monitor)}
  if let monitor=globalDoubleClickMonitor {NSEvent.removeMonitor(monitor)}
  globalDoubleClickMonitor=nil;doubleClickMonitor=nil;displayedMenu=nil;batteryItem=nil
 }
 @objc func showWindow(){NSApp.setActivationPolicy(.regular);window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
 func windowWillClose(_ notification:Notification){NSApp.setActivationPolicy(.accessory)}
 @objc func quitApp(){NSApp.terminate(nil)}
 func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool {showWindow();return true}
 func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{false}
 func applicationWillTerminate(_ note:Notification){voice.setEnabled(false);batteryTimer?.invalidate();if let monitor=doubleClickMonitor {NSEvent.removeMonitor(monitor)};if let monitor=globalDoubleClickMonitor {NSEvent.removeMonitor(monitor)};model.stop();if statusItem != nil {NSStatusBar.system.removeStatusItem(statusItem)}}
}
if CommandLine.arguments.contains("--voice-meter-self-test") {
 guard voiceInputDecibels([]) == nil, voiceInputDecibels([0,0]) == nil,
       abs((voiceInputDecibels([328,-328]) ?? 0) + 40) < 0.1,
       voiceInputLevel([]) == 0, voiceInputLevel([0,0]) == 0,
       voiceInputLevel([32767]) > 0.99,
       voiceInputLevel([328, -328]) > 0.65 && voiceInputLevel([328, -328]) < 0.68 else {
  fputs("FAIL: voice input meter normalization\n",stderr);exit(1)
 }
 print("PASS: voice input meter silence, reference level and full scale");exit(0)
}
if CommandLine.arguments.contains("--callout-self-test") {
 guard validateMappingCallouts() else { fputs("FAIL: callout layout does not cover each button and slot once\n",stderr); exit(1) }
 print("PASS: callout layout covers all twelve buttons with unique slots"); exit(0)
}
if CommandLine.arguments.contains("--modifier-self-test") {
 let m=RemoteModel();m.isTrusted={true};m.mappingEnabled=true;m.testingBypassFilter=true
 guard resolvedButtonMappings(nil) == defaultButtonMappings, defaultButtonMappings.count == 12, defaultButtonMappings.allSatisfy({ key,value in buttons.contains(where:{$0.id==key}) && choices.contains(where:{$0.id==value}) }), resolvedButtonMappings(["back":"Esc"])["back"] == "Esc", resolvedButtonMappings(["back":"Esc"])["voice"] == "Option ⌥" else {fputs("FAIL: defaults and existing settings\n",stderr);exit(1)}
 print("PASS: twelve defaults and existing user overrides")
 m.codes=["up":"7:82","down":"7:81","left":"7:80","right":"7:79","back":"7:241"]
 m.mappings=["up":"Command ⌘","down":"Shift ⇧","left":"Option ⌥","right":"Control ⌃","back":"关闭窗口 (⌘W)"]
 var events:[(CGEventType,CGKeyCode,CGEventFlags)]=[];m.eventSink={e in events.append((e.type,CGKeyCode(e.getIntegerValueField(.keyboardEventKeycode)),e.flags))}
 func require(_ condition:Bool,_ label:String){if !condition {fputs("FAIL: \(label)\n",stderr);exit(1)};print("PASS: \(label)")}
 m.event(page:7,usage:82,down:true);m.event(page:7,usage:81,down:true)
 require(events.count==2 && events[0].0 == .flagsChanged && events[0].2.contains(.maskCommand) && events[1].2.contains(.maskCommand) && events[1].2.contains(.maskShift),"modifier press flags are combined")
 m.event(page:7,usage:82,down:false)
 require(events.last?.0 == .flagsChanged && events.last!.2.contains(.maskShift) && !events.last!.2.contains(.maskCommand),"modifier release preserves other modifier")
 m.event(page:7,usage:241,down:true);m.event(page:7,usage:241,down:false)
 require(events[3].1 == 13 && events[3].2.contains(.maskCommand) && events[3].2.contains(.maskShift) && events[4].0 == .keyUp,"command W preserves held modifiers and releases")
 m.event(page:7,usage:81,down:false);require(events.last!.2.intersection([.maskShift,.maskCommand]).isEmpty,"last modifier releases cleanly")
 m.event(page:7,usage:80,down:true);m.event(page:7,usage:79,down:true);m.releaseAll()
 require(events.last!.0 == .flagsChanged && events.last!.2.intersection([.maskAlternate,.maskControl]).isEmpty,"cleanup releases all modifiers")
 var mediaEvents:[Int32]=[];m.mediaSink={mediaEvents.append($0)};m.codes["volumeUp"]="7:128";m.codes["volumeDown"]="7:129";m.mappings["volumeUp"]="系统音量 +";m.mappings["volumeDown"]="系统音量 −"
 m.event(page:7,usage:128,down:true);require(mediaEvents == [0],"volume press sends one immediate event")
 RunLoop.main.run(until:Date(timeIntervalSinceNow:0.72));require(mediaEvents.count >= 3 && mediaEvents.allSatisfy{$0 == 0},"holding volume repeats")
 m.event(page:7,usage:128,down:false);let released=mediaEvents.count;RunLoop.main.run(until:Date(timeIntervalSinceNow:0.32));require(mediaEvents.count == released,"volume repeat stops after release")
 m.event(page:7,usage:129,down:true);m.releaseAll();let cleaned=mediaEvents.count;RunLoop.main.run(until:Date(timeIntervalSinceNow:0.55));require(mediaEvents.count == cleaned,"cleanup cancels volume repeat")
 events.removeAll();m.mappings["up"]="方向上";m.event(page:7,usage:82,down:true);RunLoop.main.run(until:Date(timeIntervalSinceNow:0.72));require(events.count >= 3 && events.allSatisfy{$0.0 == .keyDown && $0.1 == 126},"arrow hold emits repeated key down")
 m.event(page:7,usage:82,down:false);let count=events.count;require(events.last?.0 == .keyUp,"arrow release emits key up");RunLoop.main.run(until:Date(timeIntervalSinceNow:0.25));require(events.count == count,"arrow repeat stops after release")
 events.removeAll();m.event(page:7,usage:241,down:true);RunLoop.main.run(until:Date(timeIntervalSinceNow:0.7));require(events.count == 1,"command W does not repeat");m.event(page:7,usage:241,down:false)
 exit(0)
}
let app=NSApplication.shared;let delegate=Delegate();app.delegate=delegate
signal(SIGTERM,SIG_IGN)
let terminationSignal=DispatchSource.makeSignalSource(signal:SIGTERM,queue:.main)
terminationSignal.setEventHandler{NSApp.terminate(nil)};terminationSignal.resume()
app.run()
