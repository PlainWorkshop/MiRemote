import SwiftUI

private struct CalloutSpec: Identifiable {
 let id: String
 let point: CGPoint
 let left: Bool
 let row: Int
}

private let callouts: [CalloutSpec] = [
 .init(id:"power",point:CGPoint(x:0,y:2.83),left:true,row:0),
 .init(id:"up",point:CGPoint(x:0,y:1.83),left:true,row:1),
 .init(id:"left",point:CGPoint(x:-0.48,y:1.36),left:true,row:2),
 .init(id:"down",point:CGPoint(x:0,y:0.89),left:true,row:3),
 .init(id:"home",point:CGPoint(x:-0.54,y:0.25),left:true,row:4),
 .init(id:"volumeUp",point:CGPoint(x:0,y:-0.38),left:true,row:5),
 .init(id:"voice",point:CGPoint(x:0,y:2.35),left:false,row:0),
 .init(id:"right",point:CGPoint(x:0.48,y:1.49),left:false,row:1),
 .init(id:"select",point:CGPoint(x:0,y:1.36),left:false,row:2),
 .init(id:"menu",point:CGPoint(x:0.54,y:0.25),left:false,row:3),
 .init(id:"back",point:CGPoint(x:0,y:0.25),left:false,row:4),
 .init(id:"volumeDown",point:CGPoint(x:0,y:-0.85),left:false,row:5)
]

func validateMappingCallouts() -> Bool {
 let ids = callouts.map(\.id)
 let buttonIDs = buttons.map(\.id)
 let rows = callouts.map { "\($0.left)-\($0.row)" }
 return ids.count == buttonIDs.count && Set(ids) == Set(buttonIDs) && Set(rows).count == callouts.count && callouts.allSatisfy { (0..<6).contains($0.row) }
}

struct MappingCallouts: View {
 @ObservedObject var model: RemoteModel
 let green: Color
 private let width: CGFloat = 1020
 private let height: CGFloat = 620
 private let modelWidth: CGFloat = 240
 private let modelHeight: CGFloat = 600
 private let cardWidth: CGFloat = 270
 private func rowY(_ row: Int) -> CGFloat { 52 + CGFloat(row) * 99 }
 private func point(_ item: CalloutSpec) -> CGPoint {
  CGPoint(x: width/2 + item.point.x * modelHeight/7.3, y: height/2 - item.point.y * modelHeight/7.3)
 }
 var body: some View {
  ZStack {
   Remote3D().frame(width:modelWidth,height:modelHeight).position(x:width/2,y:height/2)
   Path { path in
    for item in callouts {
     let p = point(item)
     let exitX: CGFloat = item.left ? width/2 - modelWidth/2 : width/2 + modelWidth/2
     let endX: CGFloat = item.left ? cardWidth + 14 : width - cardWidth - 14
     let y = rowY(item.row)
     path.move(to:p)
     path.addLine(to:CGPoint(x:exitX,y:p.y))
     path.addLine(to:CGPoint(x:(exitX+endX)/2,y:y))
     path.addLine(to:CGPoint(x:endX,y:y))
    }
   }.stroke(Color(red:0.45,green:0.62,blue:0.57).opacity(0.7),style:StrokeStyle(lineWidth:1,lineCap:.round,lineJoin:.round)).allowsHitTesting(false)
   ForEach(callouts) { item in
    Circle().fill(green).frame(width:6,height:6).position(point(item)).allowsHitTesting(false)
    if let spec = buttons.first(where: {$0.id == item.id}) {
     MappingCalloutCard(spec:spec,model:model,green:green)
      .frame(width:cardWidth,height:84)
      .position(x:item.left ? cardWidth/2 : width-cardWidth/2,y:rowY(item.row))
    }
   }
  }.frame(width:width,height:height)
 }
}

private struct MappingCalloutCard: View {
 let spec: ButtonSpec
 @ObservedObject var model: RemoteModel
 let green: Color
 var body: some View {
  VStack(alignment:.leading,spacing:6) {
   HStack(spacing:7) {
    Image(systemName:spec.icon).foregroundColor(green).frame(width:17)
    Text(spec.title).font(.system(size:13,weight:.semibold))
    Spacer()
    Text(model.codes[spec.id] == nil ? "未识别" : "已识别").font(.system(size:10)).foregroundColor(model.codes[spec.id] == nil ? .secondary : green)
   }
   HStack(spacing:5) {
    Picker("\(spec.title)映射",selection:Binding(get:{model.mappings[spec.id] ?? "不映射"},set:{model.setMapping(spec.id,$0)})) {
     ForEach(choices) { option in
      Text(option.id == "自定义…" && model.custom[spec.id] != nil ? "自定义 (\(model.custom[spec.id]!.label))" : option.id).tag(option.id)
     }
    }.labelsHidden().frame(maxWidth:.infinity)
    if model.mappings[spec.id] == "自定义…" { Button("修改"){model.capture(spec.id)}.buttonStyle(.link) }
    Button(model.learning == spec.id ? "等待" : "识别"){model.learn(spec.id)}.disabled(!model.connected || model.learning != nil)
   }.controlSize(.small)
  }.padding(.horizontal,12).padding(.vertical,9).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading)
   .background(RoundedRectangle(cornerRadius:9).fill(Color.white.opacity(0.045)))
   .overlay(RoundedRectangle(cornerRadius:9).stroke(Color.white.opacity(0.075),lineWidth:1))
 }
}
