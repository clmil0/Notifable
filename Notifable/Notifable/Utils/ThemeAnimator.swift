import SwiftUI
import UIKit

/// Performs a circular reveal animation from a given origin point when changing themes.
struct ThemeAnimator {
    
    static func animateThemeChange(from origin: CGPoint, onSnapshotTaken: @escaping () -> Void) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first(where: { $0.isKeyWindow }) else {
            onSnapshotTaken()
            return
        }
        
        // 1. Capture highly optimized snapshot view of current state (old theme)
        guard let overlayView = window.snapshotView(afterScreenUpdates: false) else {
            onSnapshotTaken()
            return
        }
        
        // 2. Add the snapshot overlay to the window
        overlayView.frame = window.bounds
        overlayView.isUserInteractionEnabled = false
        window.addSubview(overlayView)
        
        // 3. Toggle the theme immediately (underneath the snapshot)
        onSnapshotTaken()
        
        // 4. Calculate max radius
        let corners: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: window.bounds.width, y: 0),
            CGPoint(x: 0, y: window.bounds.height),
            CGPoint(x: window.bounds.width, y: window.bounds.height)
        ]
        let maxRadius = corners.map { corner in
            sqrt(pow(corner.x - origin.x, 2) + pow(corner.y - origin.y, 2))
        }.max() ?? window.bounds.height
        
        // 5. Create matching path structures for smooth interpolation
        func makePath(radius: CGFloat) -> CGPath {
            let path = UIBezierPath(rect: window.bounds)
            path.append(
                UIBezierPath(
                    arcCenter: origin,
                    radius: radius,
                    startAngle: 0,
                    endAngle: 2 * .pi,
                    clockwise: true
                )
            )
            path.usesEvenOddFillRule = true
            return path.cgPath
        }
        
        let initialPath = makePath(radius: 2)
        let finalPath = makePath(radius: maxRadius)
        
        let maskLayer = CAShapeLayer()
        maskLayer.fillRule = .evenOdd
        maskLayer.path = initialPath
        overlayView.layer.mask = maskLayer
        
        // 6. Start animation on next frame (minimal delay)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = initialPath
        animation.toValue = finalPath
        animation.duration = 0.35
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        
        CATransaction.setCompletionBlock {
            overlayView.removeFromSuperview()
        }
        maskLayer.add(animation, forKey: "circularReveal")
        maskLayer.path = finalPath
        CATransaction.commit()
    }
}
