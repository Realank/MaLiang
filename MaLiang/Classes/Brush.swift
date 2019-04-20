//
//  Brush.swift
//  MaLiang
//
//  Created by Harley.xk on 2017/11/6.
//

import Foundation
import MetalKit
import UIKit

public struct Pan {
    var point: CGPoint
    var force: CGFloat
}

open class Brush {
    
    // unique identifier, automatically set
    public internal(set) var id: UUID

    // opacity of texture, affects the darkness of stroke
    // set opacity to 1 may cause heavy aliasing
    open var opacity: CGFloat = 0.3
    
    // width of stroke line in points
    open var pointSize: CGFloat = 4

    // this property defines the minimum distance (measureed in points) of nearest two textures
    // defaults to 1, this means erery texture calculated will be rendered, dictance calculation will be skiped
    open var pointStep: CGFloat = 1
    
    // sensitive of pointsize changed from force, from 0 - 1
    open var forceSensitive: CGFloat = 0
    
    /// color of stroke
    open var color: UIColor = .black
    
    /// interal texture
    open private(set) var textureID: UUID?

    /// target to draw
    weak var target: Canvas?
    
    /// create new brush with registered textureid in target
    public init(textureID: UUID? = nil, target: Canvas) {
        id = UUID()
        self.target = target
        self.textureID = textureID
        if let id = textureID {
            texture = target.findTexture(by: id)?.texture
        }
        self.updatePointPipeline()
    }
    
    /// use this brush to draw
    open func use() {
        target?.currentBrush = self
    }
    
    open func line(from: CGPoint, to: CGPoint) -> MLLine {
        let color = self.color.toMLColor(opacity: opacity)        
        let line = MLLine(begin: from, end: to, pointSize: pointSize,
                          pointStep: pointStep, color: color,
                          scaleFactor: target?.screenTarget.scale ?? 1,
                          offset: target?.screenTarget.contentOffset ?? .zero)
        return line
    }
    
    open func pan(from: Pan, to: Pan) -> MLLine {
        let color = self.color.toMLColor(opacity: opacity)
        var endForce = from.force * 0.95 + to.force * 0.05
        endForce = pow(endForce, forceSensitive)
        let line = MLLine(begin: from.point, end: to.point,
                          pointSize: pointSize * endForce, pointStep: pointStep, color: color,
                          scaleFactor: target?.screenTarget.scale ?? 1,
                          offset: target?.screenTarget.contentOffset ?? .zero)
        return line
    }
    
    // MARK: - Render Actions
    
    private weak var texture: MTLTexture?
    
    private var pipelineState: MTLRenderPipelineState!
    
    private func updatePointPipeline() {
        
        guard let target = target, let device = target.device else {
            return
        }
        
        let library = device.libraryForMaLiang()
        let vertex_func = library?.makeFunction(name: "vertex_point_func")
        
        var fragment_func_name = "fragment_point_func"
        if texture == nil {
            fragment_func_name = "fragment_point_func_without_texture"
        } else if renderType == .original {
            fragment_func_name = "fragment_point_func_original"
        }
        
        let fragment_func = library?.makeFunction(name: fragment_func_name)
        let rpd = MTLRenderPipelineDescriptor()
        rpd.vertexFunction = vertex_func
        rpd.fragmentFunction = fragment_func
        rpd.colorAttachments[0].pixelFormat = target.colorPixelFormat
        setupBlendOptions(for: rpd.colorAttachments[0]!)
        pipelineState = try! device.makeRenderPipelineState(descriptor: rpd)
    }
    
    
    /// Blending options for this brush, override to implement your own blending options
    open func setupBlendOptions(for attachment: MTLRenderPipelineColorAttachmentDescriptor) {
        attachment.isBlendingEnabled = true

        attachment.rgbBlendOperation = .add
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        
        attachment.alphaBlendOperation = .add
        attachment.sourceAlphaBlendFactor = .oneMinusDestinationAlpha
        attachment.destinationAlphaBlendFactor = .one
    }

    internal func render(lineStrip: MLLineStrip, on renderTarget: RenderTarget? = nil) {
        
        let renderTarget = renderTarget ?? target?.screenTarget
        
        guard lineStrip.lines.count > 0, let target = renderTarget else {
            return
        }
        
        /// make sure reauable command buffer is ready
        target.prepareForDraw()
        
        /// get commandEncoder form resuable command buffer
        let commandEncoder = target.makeCommandEncoder()
        
        commandEncoder?.setRenderPipelineState(pipelineState)
        
        if let vertex_buffer = lineStrip.retrieveBuffers() {
            commandEncoder?.setVertexBuffer(vertex_buffer, offset: 0, index: 0)
            commandEncoder?.setVertexBuffer(target.uniform_buffer, offset: 0, index: 1)
            commandEncoder?.setVertexBuffer(target.transform_buffer, offset: 0, index: 2)
            if let texture = texture {
                commandEncoder?.setFragmentTexture(texture, index: 0)
            }
            commandEncoder?.drawPrimitives(type: .point, vertexStart: 0, vertexCount: lineStrip.vertexCount)
        }
        
        commandEncoder?.endEncoding()
    }
}
