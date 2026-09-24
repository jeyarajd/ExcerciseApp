import RealityKit
import simd

/// One cross-section of a body part: an ellipse at height `y`, `rx` wide (x) and `rz` deep (z),
/// shifted forward by `z`. A list of rings, top to bottom, is smoothed and swept into a mesh.
struct Ring {
    var y: Float
    var rx: Float
    var rz: Float
    var z: Float = 0

    init(_ y: Float, _ r: Float) {
        self.y = y; rx = r; rz = r
    }

    init(_ y: Float, _ rx: Float, _ rz: Float, z: Float = 0) {
        self.y = y; self.rx = rx; self.rz = rz; self.z = z
    }

    func scaled(_ s: Float) -> Ring { Ring(y * s, rx * s, rz * s, z: z * s) }
}

/// Smooth, sculpted meshes for the coach: surfaces of revolution with elliptical cross-sections,
/// smoothed with Catmull-Rom splines and lit with averaged normals, so the body reads as one
/// soft shape instead of boxes and balls.
enum MeshKit {
    /// Sweeps rings (top to bottom) around the local Y axis. Start and end with a radius of 0 for
    /// a closed shape.
    static func lathe(_ rings: [Ring], segments: Int = 36, smoothing: Int = 5) -> MeshResource {
        let rows = smooth(rings, steps: smoothing)
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(rows.count * segments)
        for ring in rows {
            for s in 0..<segments {
                let a = Float(s) / Float(segments) * 2 * .pi
                positions.append([ring.rx * sin(a), ring.y, ring.z + ring.rz * cos(a)])
            }
        }
        var indices: [UInt32] = []
        for j in 0..<(rows.count - 1) {
            for s in 0..<segments {
                let s1 = (s + 1) % segments
                let a = UInt32(j * segments + s), b = UInt32((j + 1) * segments + s)
                let c = UInt32(j * segments + s1), d = UInt32((j + 1) * segments + s1)
                indices += [a, b, c, c, b, d]
            }
        }
        var normals = smoothNormals(positions, indices)
        // Poles: every vertex sits on one point, so point the normal straight along the axis.
        for (row, sign) in [(0, Float(1)), (rows.count - 1, Float(-1))] where max(rows[row].rx, rows[row].rz) < 1e-4 {
            for s in 0..<segments { normals[row * segments + s] = [0, sign, 0] }
        }
        return build(positions, normals, indices)
    }

    /// An ellipsoid centred on the origin.
    static func ellipsoid(_ rx: Float, _ ry: Float, _ rz: Float, segments: Int = 32) -> MeshResource {
        let steps = 14
        let rings = (0...steps).map { i -> Ring in
            let a = Float(i) / Float(steps) * .pi
            return Ring(ry * cos(a), rx * sin(a), rz * sin(a))
        }
        return lathe(rings, segments: segments, smoothing: 1)
    }

    /// A rounded limb hanging down the -Y axis: radii from top to bottom, evenly spaced over
    /// `length`, with rounded ends.
    static func limb(length: Float, radii: [Float], depth: Float = 1, top: Float = 0) -> MeshResource {
        let first = radii.first ?? 0.05, last = radii.last ?? 0.05
        var rings = [Ring(top + first * 0.9, 0, 0), Ring(top + first * 0.55, first * 0.83, first * 0.83 * depth)]
        for (i, r) in radii.enumerated() {
            let y = top - length * Float(i) / Float(max(radii.count - 1, 1))
            rings.append(Ring(y, r, r * depth))
        }
        let end = top - length
        rings += [Ring(end - last * 0.55, last * 0.83, last * 0.83 * depth), Ring(end - last * 0.9, 0, 0)]
        return lathe(rings)
    }

    /// A soft tube along a path, tapering to points at both ends: smiles and eyebrows.
    static func tube(_ path: [SIMD3<Float>], radius: Float, segments: Int = 10) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        for (j, p) in path.enumerated() {
            let prev = path[max(j - 1, 0)], next = path[min(j + 1, path.count - 1)]
            let tangent = normalize(next - prev)
            var side = cross(tangent, [0, 0, 1])
            if length(side) < 1e-4 { side = cross(tangent, [0, 1, 0]) }
            let n = normalize(side), b = cross(tangent, n)
            // Round the ends off rather than leaving open rings.
            let u = Float(j) / Float(max(path.count - 1, 1))
            let r = radius * min(1, sin(u * .pi) * 2.2)
            for s in 0..<segments {
                let a = Float(s) / Float(segments) * 2 * .pi
                positions.append(p + r * (cos(a) * n + sin(a) * b))
            }
        }
        var indices: [UInt32] = []
        for j in 0..<(path.count - 1) {
            for s in 0..<segments {
                let s1 = (s + 1) % segments
                let a = UInt32(j * segments + s), b = UInt32((j + 1) * segments + s)
                let c = UInt32(j * segments + s1), d = UInt32((j + 1) * segments + s1)
                indices += [a, c, b, c, d, b]  // this frame winds the other way round from `lathe`
            }
        }
        return build(positions, smoothNormals(positions, indices), indices)
    }

    /// A shape made by extruding a (y, z) outline along X, e.g. the curved studio backdrop.
    static func sweep(_ outline: [SIMD2<Float>], width: Float) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        for p in outline {
            positions.append([-width / 2, p.x, p.y])
            positions.append([width / 2, p.x, p.y])
        }
        var indices: [UInt32] = []
        for i in 0..<(outline.count - 1) {
            let a = UInt32(i * 2), b = a + 1, c = a + 2, d = a + 3
            indices += [a, b, c, c, b, d]
        }
        return build(positions, smoothNormals(positions, indices), indices)
    }

    // MARK: - Helpers

    private static func smooth(_ rings: [Ring], steps: Int) -> [Ring] {
        guard rings.count > 2, steps > 1 else { return rings }
        var out: [Ring] = []
        for i in 0..<(rings.count - 1) {
            let p0 = rings[max(i - 1, 0)], p1 = rings[i], p2 = rings[i + 1], p3 = rings[min(i + 2, rings.count - 1)]
            for k in 0..<steps {
                let t = Float(k) / Float(steps)
                out.append(catmullRom(p0, p1, p2, p3, t))
            }
        }
        out.append(rings[rings.count - 1])
        return out
    }

    private static func catmullRom(_ p0: Ring, _ p1: Ring, _ p2: Ring, _ p3: Ring, _ t: Float) -> Ring {
        func f(_ a: Float, _ b: Float, _ c: Float, _ d: Float) -> Float {
            let t2 = t * t, t3 = t2 * t
            return 0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
        }
        return Ring(f(p0.y, p1.y, p2.y, p3.y),
                    max(0, f(p0.rx, p1.rx, p2.rx, p3.rx)),
                    max(0, f(p0.rz, p1.rz, p2.rz, p3.rz)),
                    z: f(p0.z, p1.z, p2.z, p3.z))
    }

    private static func smoothNormals(_ positions: [SIMD3<Float>], _ indices: [UInt32]) -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        for t in stride(from: 0, to: indices.count, by: 3) {
            let a = Int(indices[t]), b = Int(indices[t + 1]), c = Int(indices[t + 2])
            let n = cross(positions[b] - positions[a], positions[c] - positions[a])  // area-weighted
            normals[a] += n; normals[b] += n; normals[c] += n
        }
        return normals.map { length($0) > 1e-12 ? normalize($0) : [0, 1, 0] }
    }

    private static func build(_ positions: [SIMD3<Float>], _ normals: [SIMD3<Float>], _ indices: [UInt32]) -> MeshResource {
        var descriptor = MeshDescriptor(name: "shape")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [descriptor])) ?? .generateSphere(radius: 0.01)
    }
}
