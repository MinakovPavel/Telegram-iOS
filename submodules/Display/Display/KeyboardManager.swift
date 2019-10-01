import Foundation
import UIKit
import AsyncDisplayKit

struct KeyboardSurface {
    let host: UIView
}

private func getFirstResponder(_ view: UIView) -> UIView? {
    if view.isFirstResponder {
        return view
    } else {
        for subview in view.subviews {
            if let result = getFirstResponder(subview) {
                return result
            }
        }
        return nil
    }
}

private func isViewVisibleInHierarchy(_ view: UIView, _ initial: Bool = true) -> Bool {
    guard let window = view.window else {
        return false
    }
    if view.isHidden || view.alpha == 0.0 {
        return false
    }
    if view.superview === window {
        return true
    } else if let superview = view.superview {
        if initial && view.frame.minY >= superview.frame.height {
            return false
        } else {
            return isViewVisibleInHierarchy(superview, false)
        }
    } else {
        return false
    }
}

class KeyboardManager {
    private let host: StatusBarHost
    
    private weak var previousPositionAnimationMirrorSource: CATracingLayer?
    private weak var previousFirstResponderView: UIView?
    private var interactiveInputOffset: CGFloat = 0.0
    
    var surfaces: [KeyboardSurface] = [] {
        didSet {
            self.updateSurfaces(oldValue)
        }
    }
    
    init(host: StatusBarHost) {
        self.host = host
    }
    
    func getCurrentKeyboardHeight() -> CGFloat {
        guard let keyboardView = self.host.keyboardView else {
            return 0.0
        }
        if !isViewVisibleInHierarchy(keyboardView) {
            return 0.0
        }
        return keyboardView.bounds.height
    }
    
    func updateInteractiveInputOffset(_ offset: CGFloat, transition: ContainedViewLayoutTransition, completion: @escaping () -> Void) {
        guard let keyboardView = self.host.keyboardView else {
            return
        }
        
        self.interactiveInputOffset = offset
        
        let previousBounds = keyboardView.bounds
        let updatedBounds = CGRect(origin: CGPoint(x: 0.0, y: -offset), size: previousBounds.size)
        keyboardView.layer.bounds = updatedBounds
        if transition.isAnimated {
            transition.animateOffsetAdditive(layer: keyboardView.layer, offset: previousBounds.minY - updatedBounds.minY, completion: completion)
        } else {
            completion()
        }
        
        //transition.updateSublayerTransformOffset(layer: keyboardView.layer, offset: CGPoint(x: 0.0, y: offset))
    }
    
    private func updateSurfaces(_ previousSurfaces: [KeyboardSurface]) {
        guard let keyboardWindow = self.host.keyboardWindow else {
            return
        }
        
        var firstResponderView: UIView?
        var firstResponderDisableAutomaticKeyboardHandling: UIResponderDisableAutomaticKeyboardHandling = []
        for surface in self.surfaces {
            if let view = getFirstResponder(surface.host) {
                firstResponderView = surface.host
                firstResponderDisableAutomaticKeyboardHandling = view.disableAutomaticKeyboardHandling
                break
            }
        }
        
        if let firstResponderView = firstResponderView {
            let containerOrigin = firstResponderView.convert(CGPoint(), to: nil)
            var filteredTranslation = containerOrigin.x
            if firstResponderDisableAutomaticKeyboardHandling.contains(.forward) {
                filteredTranslation = max(0.0, filteredTranslation)
            }
            if firstResponderDisableAutomaticKeyboardHandling.contains(.backward) {
                filteredTranslation = min(0.0, filteredTranslation)
            }
            let horizontalTranslation = CATransform3DMakeTranslation(filteredTranslation, 0.0, 0.0)
            let currentTransform = keyboardWindow.layer.sublayerTransform
            if !CATransform3DEqualToTransform(horizontalTranslation, currentTransform) {
                //print("set to \(CGPoint(x: containerOrigin.x, y: self.interactiveInputOffset))")
                keyboardWindow.layer.sublayerTransform = horizontalTranslation
            }
            if let tracingLayer = firstResponderView.layer as? CATracingLayer, firstResponderDisableAutomaticKeyboardHandling.isEmpty {
                if let previousPositionAnimationMirrorSource = self.previousPositionAnimationMirrorSource, previousPositionAnimationMirrorSource !== tracingLayer {
                    previousPositionAnimationMirrorSource.setPositionAnimationMirrorTarget(nil)
                }
                tracingLayer.setPositionAnimationMirrorTarget(keyboardWindow.layer)
                self.previousPositionAnimationMirrorSource = tracingLayer
            } else if let previousPositionAnimationMirrorSource = self.previousPositionAnimationMirrorSource {
                previousPositionAnimationMirrorSource.setPositionAnimationMirrorTarget(nil)
                self.previousPositionAnimationMirrorSource = nil
            }
        } else {
            keyboardWindow.layer.sublayerTransform = CATransform3DIdentity
            if let previousPositionAnimationMirrorSource = self.previousPositionAnimationMirrorSource {
                previousPositionAnimationMirrorSource.setPositionAnimationMirrorTarget(nil)
                self.previousPositionAnimationMirrorSource = nil
            }
            if let previousFirstResponderView = previousFirstResponderView {
                if previousFirstResponderView.window == nil {
                    keyboardWindow.isHidden = true
                    keyboardWindow.layer.cancelAnimationsRecursive(key: "position")
                    keyboardWindow.layer.cancelAnimationsRecursive(key: "bounds")
                    keyboardWindow.isHidden = false
                }
            }
        }
        
        self.previousFirstResponderView = firstResponderView
    }
}

private func endAnimations(view: UIView) {
    view.layer.removeAllAnimations()
    for subview in view.subviews {
        endAnimations(view: subview)
    }
}

func viewTreeContainsFirstResponder(view: UIView) -> Bool {
    if view.isFirstResponder {
        return true
    } else {
        for subview in view.subviews {
            if viewTreeContainsFirstResponder(view: subview) {
                return true
            }
        }
        return false
    }
}

final class KeyboardViewManager {
    private let host: StatusBarHost
    
    init(host: StatusBarHost) {
        self.host = host
    }
    
    func dismissEditingWithoutAnimation(view: UIView) {
        if viewTreeContainsFirstResponder(view: view) {
            view.endEditing(true)
            if let keyboardWindow = self.host.keyboardWindow {
                for view in keyboardWindow.subviews {
                    endAnimations(view: view)
                }
            }
        }
    }
    
    func update(leftEdge: CGFloat, transition: ContainedViewLayoutTransition) {
        guard let keyboardWindow = self.host.keyboardWindow else {
            return
        }
        let t = keyboardWindow.layer.sublayerTransform
        let currentOffset = CGPoint(x: t.m41, y: t.m42)
        transition.updateSublayerTransformOffset(layer: keyboardWindow.layer, offset: CGPoint(x: leftEdge, y: currentOffset.y), completion: { _ in
        })
    }
}
