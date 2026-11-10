import AppKit
import SwiftUI
import SceneKit

struct Remote3D: NSViewRepresentable {
 func makeNSView(context:Context)->SCNView {
  let view=SCNView(); view.scene=buildScene(); view.backgroundColor=NSColor(calibratedRed:0.10,green:0.12,blue:0.14,alpha:1); view.allowsCameraControl=false; view.autoenablesDefaultLighting=false; view.antialiasingMode = .multisampling4X; view.defaultCameraController.interactionMode = .orbitTurntable; return view
 }
 func updateNSView(_ view:SCNView,context:Context) {}
 private func buildScene()->SCNScene {
  let scene=SCNScene(); let root=scene.rootNode
  func material(_ color:NSColor,_ rough:CGFloat=0.7)->SCNMaterial {let m=SCNMaterial();m.diffuse.contents=color;m.lightingModel = .physicallyBased;m.roughness.contents=rough;m.metalness.contents=0.03;return m}
  let bodyMat=material(NSColor(calibratedRed:0.18,green:0.20,blue:0.21,alpha:1));let bezel=material(NSColor(calibratedWhite:0.065,alpha:1));let buttonMat=material(NSColor(calibratedRed:0.22,green:0.24,blue:0.25,alpha:1));let symbol=material(NSColor(calibratedWhite:0.84,alpha:1));let orange=material(NSColor(calibratedRed:1,green:0.50,blue:0.20,alpha:1))
  let body=SCNBox(width:1.68,height:6.45,length:0.36,chamferRadius:0.22); body.materials=[bodyMat];let shell=SCNNode(geometry:body);root.addChildNode(shell)
  func disc(_ x:CGFloat,_ y:CGFloat,_ radius:CGFloat,_ depth:CGFloat,_ z:CGFloat,_ mat:SCNMaterial){let geometry=SCNCylinder(radius:radius,height:depth);geometry.radialSegmentCount=64;geometry.materials=[mat];let n=SCNNode(geometry:geometry);n.eulerAngles.x = .pi/2;n.position=SCNVector3(x,y,z);root.addChildNode(n)}
  func box(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ depth:CGFloat,_ radius:CGFloat,_ z:CGFloat,_ mat:SCNMaterial){let g=SCNBox(width:w,height:h,length:depth,chamferRadius:radius);g.materials=[mat];let n=SCNNode(geometry:g);n.position=SCNVector3(x,y,z);root.addChildNode(n)}
  func text(_ string:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ mat:SCNMaterial) {let t=SCNText(string:string,extrusionDepth:0.002);t.font=NSFont.systemFont(ofSize:1,weight:.medium);t.flatness=0.05;t.materials=[mat];let n=SCNNode(geometry:t);let bounds=n.boundingBox;let width=CGFloat(bounds.max.x-bounds.min.x),height=CGFloat(bounds.max.y-bounds.min.y);let scale=size/max(width,height,0.01);n.scale=SCNVector3(scale,scale,scale);n.position=SCNVector3(x-(CGFloat(bounds.min.x)+width/2)*scale,y-(CGFloat(bounds.min.y)+height/2)*scale,0.236);root.addChildNode(n)}
  // Rounded, uniformly weighted geometry keeps the symbols crisp at any view angle.
  func stroke(_ points:[(CGFloat,CGFloat)],_ mat:SCNMaterial,_ width:CGFloat = 0.017) {
   guard points.count >= 2 else { return }
   for i in 1..<points.count {
    let a=points[i-1], b=points[i], dx=b.0-a.0, dy=b.1-a.1
    let length=hypot(dx,dy); guard length > 0 else { continue }
    let shape=SCNCapsule(capRadius:width/2,height:length+width);shape.radialSegmentCount=12;shape.materials=[mat]
    let n=SCNNode(geometry:shape);n.position=SCNVector3((a.0+b.0)/2,(a.1+b.1)/2,0.241);n.eulerAngles.z = -atan2(dx,dy);root.addChildNode(n)
   }
  }
  func arc(_ x:CGFloat,_ y:CGFloat,_ r:CGFloat,_ from:CGFloat,_ to:CGFloat,_ mat:SCNMaterial) {
   let steps=24
   let pts=(0...steps).map { i -> (CGFloat,CGFloat) in let t=from+(to-from)*CGFloat(i)/CGFloat(steps);return (x+r*sin(t),y+r*cos(t)) }
   stroke(pts,mat)
  }
  for y:CGFloat in [2.83,2.35] {disc(0,y,0.20,0.040,0.193,bezel);disc(0,y,0.176,0.048,0.207,buttonMat)}
  arc(0,2.83,0.075,.pi/4,7 * .pi/4,orange);stroke([(0,2.84),(0,2.93)],orange,0.020)
  box(0,2.365,0.052,0.10,0.008,0.025,0.241,symbol)
  arc(0,2.35,0.068,.pi/2,3 * .pi/2,symbol);stroke([(0,2.282),(0,2.257)],symbol);stroke([(-0.045,2.257),(0.045,2.257)],symbol)
  disc(0,1.36,0.73,0.035,0.194,bezel);disc(0,1.36,0.71,0.045,0.209,buttonMat);disc(0,1.36,0.312,0.048,0.231,bezel);disc(0,1.36,0.289,0.050,0.241,buttonMat)
  for x:CGFloat in [-0.54,0,0.54] {disc(x,0.25,0.205,0.035,0.194,bezel);disc(x,0.25,0.182,0.045,0.208,buttonMat)}
  stroke([(-0.623,0.25),(-0.54,0.322),(-0.457,0.25)],symbol)
  stroke([(-0.603,0.255),(-0.603,0.185),(-0.477,0.185),(-0.477,0.255)],symbol)
  stroke([(0.045,0.32),(-0.030,0.25),(0.045,0.18)],symbol,0.021)
  for y:CGFloat in [0.30,0.25,0.20] {stroke([(0.478,y),(0.602,y)],symbol,0.018)}
  box(0,-0.62,0.39,0.99,0.037,0.19,0.194,bezel);box(0,-0.62,0.35,0.95,0.046,0.17,0.210,buttonMat);stroke([(-0.055,-0.38),(0.055,-0.38)],symbol);stroke([(0,-0.325),(0,-0.435)],symbol);stroke([(-0.055,-0.85),(0.055,-0.85)],symbol);text("NFC",0,-2.65,0.15,bezel)
  let cam=SCNCamera();cam.usesOrthographicProjection=true;cam.orthographicScale=3.65;let camera=SCNNode();camera.camera=cam;camera.position=SCNVector3(0,0,12);root.addChildNode(camera)
  func light(_ type:SCNLight.LightType,_ intensity:CGFloat,_ x:Float,_ y:Float,_ z:Float){let l=SCNLight();l.type=type;l.intensity=intensity;let n=SCNNode();n.light=l;n.position=SCNVector3(x,y,z);root.addChildNode(n)}
  light(.ambient,120,0,0,0);light(.omni,320,-4,6,7);light(.omni,130,5,-2,4)
  return scene
 }
}
