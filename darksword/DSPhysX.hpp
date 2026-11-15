//
//  DSPhysX.hpp
//  DarkPubg
//
//  Real-Time Client-Side NVIDIA PhysX Scene Reconstruction & Ray-Triangle Vischeck
//  Adapted for 64-bit iOS ARM64 (Unreal Engine 4 / ShadowTrackerExtra)
//  Zero hooks, 100% memory read-only, authentic PhysX geometry extraction.
//

#pragma once

#if defined(__APPLE__)
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <os/lock.h>
#else
#include <chrono>
typedef double CFAbsoluteTime;
static inline CFAbsoluteTime CFAbsoluteTimeGetCurrent() {
    auto now = std::chrono::steady_clock::now().time_since_epoch();
    return std::chrono::duration<double>(now).count();
}
struct os_unfair_lock_s { int dummy; };
typedef struct os_unfair_lock_s os_unfair_lock;
#define OS_UNFAIR_LOCK_INIT { 0 }
static inline void os_unfair_lock_lock(os_unfair_lock *) {}
static inline void os_unfair_lock_unlock(os_unfair_lock *) {}
#endif

#include <cmath>
#include <vector>
#include <algorithm>
#include <atomic>
#include <unordered_set>
#include <unordered_map>
#include <mutex>

namespace DarkPhysX
{
    // =========================================================================
    // 1. 3D Math Primitives & Quaternion Operations
    // =========================================================================
    struct V3 {
        float x, y, z;
        V3() : x(0), y(0), z(0) {}
        V3(float X, float Y, float Z) : x(X), y(Y), z(Z) {}
        V3 operator+(const V3 &o) const { return { x + o.x, y + o.y, z + o.z }; }
        V3 operator-(const V3 &o) const { return { x - o.x, y - o.y, z - o.z }; }
        V3 operator*(float s) const { return { x * s, y * s, z * s }; }
        V3 multiply(const V3 &o) const { return { x * o.x, y * o.y, z * o.z }; }
        float lengthSq() const { return x * x + y * y + z * z; }
        float length() const { return sqrtf(lengthSq()); }
        bool isFinite() const { return std::isfinite(x) && std::isfinite(y) && std::isfinite(z); }
    };

    static inline float Dot(const V3 &a, const V3 &b) {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }

    static inline V3 Cross(const V3 &a, const V3 &b) {
        return { a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x };
    }

    struct Quat {
        float x, y, z, w;
        Quat() : x(0), y(0), z(0), w(1) {}
        Quat(float X, float Y, float Z, float W) : x(X), y(Y), z(Z), w(W) {}
        Quat conjugate() const { return { -x, -y, -z, w }; }
        V3 rotate(const V3 &v) const {
            V3 qv(x, y, z);
            V3 t = Cross(qv, v) * 2.0f;
            return v + t * w + Cross(qv, t);
        }
        V3 rotateInv(const V3 &v) const {
            return conjugate().rotate(v);
        }
        Quat operator*(const Quat &o) const {
            return {
                w * o.x + x * o.w + y * o.z - z * o.y,
                w * o.y - x * o.z + y * o.w + z * o.x,
                w * o.z + x * o.y - y * o.x + z * o.w,
                w * o.w - x * o.x - y * o.y - z * o.z
            };
        }
        bool isSane() const {
            float m2 = x * x + y * y + z * z + w * w;
            return m2 > 0.85f && m2 < 1.15f;
        }
    };

    struct Transform {
        Quat q;
        V3 p;
        Transform() : q(), p() {}
        Transform(const Quat &Q, const V3 &P) : q(Q), p(P) {}
        V3 transform(const V3 &v) const {
            return q.rotate(v) + p;
        }
        V3 transformInv(const V3 &v) const {
            return q.rotateInv(v - p);
        }
        Transform operator*(const Transform &o) const {
            return { q * o.q, transform(o.p) };
        }
        Transform inverse() const {
            Quat iq = q.conjugate();
            return { iq, iq.rotate(p * -1.0f) };
        }
    };

    struct MeshScale {
        V3 scale;
        Quat rotation;
        MeshScale() : scale(1.0f, 1.0f, 1.0f), rotation() {}
        V3 transform(const V3 &v) const {
            return rotation.rotateInv(scale.multiply(rotation.rotate(v)));
        }
    };

    // =========================================================================
    // 2. Mesh & Collision Representation
    // =========================================================================
    enum GeomKind {
        GeomSphere = 0,
        GeomPlane = 1,
        GeomCapsule = 2,
        GeomBox = 3,
        GeomConvex = 4,
        GeomTriMesh = 5,
        GeomHeightField = 6
    };

    struct Mesh {
        std::vector<V3> verts;
        std::vector<uint32_t> indices;
        V3 aabbLo;
        V3 aabbHi;
        V3 center;
        int kind;
        uint64_t actor;
        uint64_t shape;

        Mesh() : kind(0), actor(0), shape(0) {
            aabbLo = { 999999.0f, 999999.0f, 999999.0f };
            aabbHi = { -999999.0f, -999999.0f, -999999.0f };
            center = { 0, 0, 0 };
        }

        void computeBounds() {
            if (verts.empty()) return;
            aabbLo = verts[0];
            aabbHi = verts[0];
            V3 sum = { 0, 0, 0 };
            for (const auto &v : verts) {
                if (v.x < aabbLo.x) aabbLo.x = v.x;
                if (v.y < aabbLo.y) aabbLo.y = v.y;
                if (v.z < aabbLo.z) aabbLo.z = v.z;
                if (v.x > aabbHi.x) aabbHi.x = v.x;
                if (v.y > aabbHi.y) aabbHi.y = v.y;
                if (v.z > aabbHi.z) aabbHi.z = v.z;
                sum = sum + v;
            }
            center = sum * (1.0f / (float)verts.size());
        }
    };

    // =========================================================================
    // 3. Fast Ray-Geometry Intersection (Möller-Trumbore & Slab AABB)
    // =========================================================================
    static inline bool RayAABB(const V3 &orig, const V3 &dir, const V3 &lo, const V3 &hi, float maxT, float *tHit = nullptr) {
        float tmin = 0.0f, tmax = maxT;
        const float o[3] = { orig.x, orig.y, orig.z };
        const float d[3] = { dir.x, dir.y, dir.z };
        const float b0[3] = { lo.x, lo.y, lo.z };
        const float b1[3] = { hi.x, hi.y, hi.z };

        for (int i = 0; i < 3; ++i) {
            if (fabsf(d[i]) < 1e-7f) {
                if (o[i] < b0[i] || o[i] > b1[i]) return false;
                continue;
            }
            float t1 = (b0[i] - o[i]) / d[i];
            float t2 = (b1[i] - o[i]) / d[i];
            if (t1 > t2) std::swap(t1, t2);
            if (t1 > tmin) tmin = t1;
            if (t2 < tmax) tmax = t2;
            if (tmin > tmax) return false;
        }
        if (tHit) *tHit = tmin;
        return true;
    }

    static inline bool RayTri(const V3 &orig, const V3 &dir, float maxT,
                              const V3 &v0, const V3 &v1, const V3 &v2,
                              float &t)
    {
        const V3 e1 = v1 - v0;
        const V3 e2 = v2 - v0;
        const V3 p = Cross(dir, e2);
        const float det = Dot(e1, p);
        if (fabsf(det) < 1.0e-5f) return false;

        const float invDet = 1.0f / det;
        const V3 tvec = orig - v0;
        const float u = Dot(tvec, p) * invDet;
        if (u < 0.0f || u > 1.0f) return false;

        const V3 qvec = Cross(tvec, e1);
        const float v = Dot(dir, qvec) * invDet;
        if (v < 0.0f || u + v > 1.0f) return false;

        const float tHit = Dot(e2, qvec) * invDet;
        if (tHit <= 0.02f || tHit >= maxT) return false;
        t = tHit;
        return true;
    }

    // =========================================================================
    // 4. Memory Snapshot Storage & Synchronized State
    // =========================================================================
    static os_unfair_lock s_meshLock = OS_UNFAIR_LOCK_INIT;
    static std::vector<Mesh> s_activeMeshes;
    static uint64_t s_cachedScene = 0;
    static uint64_t s_cachedRigidArrayData = 0;
    static int s_cachedRigidCount = 0;
    static uint32_t s_cachedRigidOffset = 0;
    static CFAbsoluteTime s_lastSceneScanTime = 0;
    static V3 s_lastScanOrigin = { 999999.0f, 999999.0f, 999999.0f };

    // =========================================================================
    // 5. Heuristic Scene & Actor Detection for 64-bit iOS
    // =========================================================================
    static inline bool LooksLikeActor(uint64_t a) {
        if (!ds_pubg_valid(a)) return false;
        // In PhysX 3.4 64-bit: PxBase vtable is 8 bytes.
        // mConcreteType is usually at +0x08 or +0x04.
        uint16_t t8 = ds_pubg_read_u16(a + 0x08);
        if (t8 == 6 || t8 == 7) return true; // eRIGID_DYNAMIC = 6, eRIGID_STATIC = 7
        uint16_t t4 = ds_pubg_read_u16(a + 0x04);
        if (t4 == 6 || t4 == 7) return true;
        return false;
    }

    static inline bool ReadTransform(uint64_t addr, Transform &outT) {
        if (!ds_pubg_valid(addr)) return false;
        float buf[7] = {};
        if (!ds_pubg_read(addr, buf, sizeof(buf))) return false;
        outT.q = { buf[0], buf[1], buf[2], buf[3] };
        outT.p = { buf[4], buf[5], buf[6] };
        return outT.q.isSane() && outT.p.isFinite() && outT.p.lengthSq() < (1.0e10f);
    }

    static inline bool FindActorPose(uint64_t actor, bool dynamic, Transform &outPose) {
        // Static GlobalPose (NpRigidStatic: offset 0x50 .. 0x70)
        if (!dynamic) {
            static const uint32_t kStaticOffsets[] = { 0x50, 0x58, 0x60, 0x68, 0x70 };
            for (uint32_t off : kStaticOffsets) {
                if (ReadTransform(actor + off, outPose)) return true;
            }
        } else {
            // Dynamic Body2World (NpRigidDynamic: offset 0x70 .. 0x90)
            static const uint32_t kDynOffsets[] = { 0x70, 0x78, 0x80, 0x88, 0x90 };
            for (uint32_t off : kDynOffsets) {
                if (ReadTransform(actor + off, outPose)) return true;
            }
        }
        return false;
    }

    static inline bool LooksLikeScene(uint64_t sc, uint32_t &outRigidOff, uint64_t &outData, int &outNum) {
        if (!ds_pubg_valid(sc)) return false;
        // In NpScene: scan candidate TArray offsets for RigidActors (0x1200 .. 0x2200)
        static const uint32_t kRigidCandidates[] = {
            0x1844, 0x1840, 0x1848, 0x1850, 0x1860, 0x1880,
            0x1400, 0x1480, 0x1500, 0x1600, 0x1700, 0x1800,
            0x1900, 0x1A00, 0x1B00, 0x1C00, 0x1D00, 0x1E00
        };
        for (uint32_t off : kRigidCandidates) {
            uint64_t data = ds_pubg_read_ptr(sc + off);
            int num = (int)ds_pubg_read_u32(sc + off + 8);
            if (ds_pubg_valid(data) && num > 5 && num < 100000) {
                int validCount = 0;
                int probe = std::min(num, 8);
                for (int i = 0; i < probe; ++i) {
                    uint64_t a = ds_pubg_read_ptr(data + (uint64_t)i * 8);
                    if (LooksLikeActor(a)) validCount++;
                }
                if (validCount >= 2) {
                    outRigidOff = off;
                    outData = data;
                    outNum = num;
                    return true;
                }
            }
        }
        return false;
    }

    static inline uint64_t DiscoverPhysXScene(uint64_t world, uint64_t localPawn) {
        // Strategy 1: Through LocalPlayer MeshComponent -> FBodyInstance (0x550) -> RigidActorSync -> Scene
        if (localPawn && ds_pubg_valid(localPawn)) {
            uint64_t meshComp = ds_pubg_read_ptr(localPawn + 0x510ULL); // ASTExtraBaseCharacter.Mesh
            if (meshComp && ds_pubg_valid(meshComp)) {
                uint64_t bi = meshComp + 0x550ULL; // UPrimitiveComponent.BodyInstance
                for (uint32_t off = 0x80; off < 0x220; off += 8) {
                    uint64_t actor = ds_pubg_read_ptr(bi + off);
                    if (LooksLikeActor(actor)) {
                        for (uint32_t scOff = 0x20; scOff < 0xC0; scOff += 8) {
                            uint64_t sc = ds_pubg_read_ptr(actor + scOff);
                            uint32_t rOff = 0; uint64_t rData = 0; int rNum = 0;
                            if (LooksLikeScene(sc, rOff, rData, rNum)) {
                                s_cachedRigidOffset = rOff;
                                s_cachedRigidArrayData = rData;
                                s_cachedRigidCount = rNum;
                                return sc;
                            }
                        }
                    }
                }
            }
        }

        // Strategy 2: Scan UWorld physics scene pointer window (0x70 .. 0x200)
        if (world && ds_pubg_valid(world)) {
            for (uint32_t wOff = 0x70; wOff < 0x1E0; wOff += 8) {
                uint64_t physScene = ds_pubg_read_ptr(world + wOff);
                if (ds_pubg_valid(physScene)) {
                    for (uint32_t pOff = 0x0; pOff < 0x80; pOff += 8) {
                        uint64_t sc = ds_pubg_read_ptr(physScene + pOff);
                        uint32_t rOff = 0; uint64_t rData = 0; int rNum = 0;
                        if (LooksLikeScene(sc, rOff, rData, rNum)) {
                            s_cachedRigidOffset = rOff;
                            s_cachedRigidArrayData = rData;
                            s_cachedRigidCount = rNum;
                            return sc;
                        }
                    }
                }
            }
        }
        return 0;
    }

    // =========================================================================
    // 6. Shape & Geometry Extraction (Box, Convex, TriangleMesh)
    // =========================================================================
    static inline void CollectActorShapes(uint64_t actor, std::vector<uint64_t> &outShapes) {
        outShapes.clear();
        if (!ds_pubg_valid(actor)) return;
        // Probe ShapeMgr list in NpRigidActor
        static const uint32_t kShapeMgrOffsets[] = { 0x0C, 0x10, 0x18, 0x20, 0x28, 0x30 };
        for (uint32_t off : kShapeMgrOffsets) {
            uint64_t list = ds_pubg_read_ptr(actor + off);
            uint16_t cnt = ds_pubg_read_u16(actor + off + 8);
            if (cnt > 0 && cnt <= 32) {
                if (cnt == 1 && ds_pubg_valid(list)) {
                    outShapes.push_back(list);
                    return;
                } else if (ds_pubg_valid(list)) {
                    for (int i = 0; i < cnt; ++i) {
                        uint64_t sh = ds_pubg_read_ptr(list + (uint64_t)i * 8);
                        if (ds_pubg_valid(sh)) outShapes.push_back(sh);
                    }
                    if (!outShapes.empty()) return;
                }
            }
        }
    }

    static inline bool ExtractShapeMesh(uint64_t actor, uint64_t shape, bool dynamic, Mesh &outMesh) {
        if (!ds_pubg_valid(shape)) return false;
        outMesh = Mesh();
        outMesh.actor = actor;
        outMesh.shape = shape;

        // 1. Read actor global transform
        Transform globalPose;
        if (!FindActorPose(actor, dynamic, globalPose)) return false;

        // 2. Read shape local transform (Shape2Actor)
        Transform localPose;
        ReadTransform(shape + 0x50, localPose); // Shape2Actor offset

        Transform worldPose = globalPose * localPose;

        // 3. Scan geometry type at shape + 0x70 .. 0xA0
        int geomType = -1;
        uint64_t geomAddr = 0;
        for (uint32_t gOff = 0x60; gOff <= 0xA0; gOff += 8) {
            int t = (int)ds_pubg_read_u32(shape + gOff);
            if (t >= 3 && t <= 5) {
                geomType = t;
                geomAddr = shape + gOff;
                break;
            }
        }
        if (geomType < 0) return false;
        outMesh.kind = geomType;

        // Case A: Box Geometry (Type 3)
        if (geomType == GeomBox) {
            V3 halfExtents;
            if (!ds_pubg_read(geomAddr + 4, &halfExtents, sizeof(halfExtents))) return false;
            if (halfExtents.x < 5.0f || halfExtents.y < 5.0f || halfExtents.z < 5.0f) return false;
            if (halfExtents.x > 15000.0f || halfExtents.y > 15000.0f || halfExtents.z > 15000.0f) return false;

            // Generate 8 box vertices
            V3 localVerts[8] = {
                { -halfExtents.x, -halfExtents.y, -halfExtents.z },
                {  halfExtents.x, -halfExtents.y, -halfExtents.z },
                {  halfExtents.x,  halfExtents.y, -halfExtents.z },
                { -halfExtents.x,  halfExtents.y, -halfExtents.z },
                { -halfExtents.x, -halfExtents.y,  halfExtents.z },
                {  halfExtents.x, -halfExtents.y,  halfExtents.z },
                {  halfExtents.x,  halfExtents.y,  halfExtents.z },
                { -halfExtents.x,  halfExtents.y,  halfExtents.z }
            };

            outMesh.verts.resize(8);
            for (int i = 0; i < 8; ++i) {
                outMesh.verts[i] = worldPose.transform(localVerts[i]);
            }

            // 12 Triangles (36 indices)
            static const uint32_t boxIdx[36] = {
                0, 1, 2,  0, 2, 3,  // Bottom
                4, 6, 5,  4, 7, 6,  // Top
                0, 4, 5,  0, 5, 1,  // Front
                2, 6, 7,  2, 7, 3,  // Back
                0, 3, 7,  0, 7, 4,  // Left
                1, 5, 6,  1, 6, 2   // Right
            };
            outMesh.indices.assign(boxIdx, boxIdx + 36);
            outMesh.computeBounds();
            return true;
        }

        // Case B: Triangle Mesh (Type 5 - Buildings, stairs, walls, rocks)
        if (geomType == GeomTriMesh) {
            uint64_t triMeshPtr = ds_pubg_read_ptr(geomAddr + 0x24);
            if (!ds_pubg_valid(triMeshPtr)) {
                triMeshPtr = ds_pubg_read_ptr(geomAddr + 0x20);
            }
            if (!ds_pubg_valid(triMeshPtr)) return false;

            int nbV = (int)ds_pubg_read_u32(triMeshPtr + 0x10);
            int nbT = (int)ds_pubg_read_u32(triMeshPtr + 0x14);
            uint64_t vp = ds_pubg_read_ptr(triMeshPtr + 0x18);
            uint64_t ip = ds_pubg_read_ptr(triMeshPtr + 0x20);
            uint8_t flags = (uint8_t)ds_pubg_read_u8(triMeshPtr + 0x28);

            if (nbV < 3 || nbT < 1 || nbV > 12000 || nbT > 24000) return false;
            if (!ds_pubg_valid(vp) || !ds_pubg_valid(ip)) return false;

            // Read scale
            MeshScale scale;
            ds_pubg_read(geomAddr + 0x04, &scale, sizeof(scale));

            // Read vertices
            std::vector<V3> rawV((size_t)nbV);
            if (!ds_pubg_read(vp, rawV.data(), (size_t)nbV * sizeof(V3))) return false;

            // Read indices
            bool i16 = (flags & 2u) != 0;
            size_t idxCount = (size_t)nbT * 3;
            outMesh.indices.resize(idxCount);

            if (i16) {
                std::vector<uint16_t> rawIdx16(idxCount);
                if (!ds_pubg_read(ip, rawIdx16.data(), idxCount * 2)) return false;
                for (size_t i = 0; i < idxCount; ++i) {
                    if (rawIdx16[i] >= (uint16_t)nbV) return false;
                    outMesh.indices[i] = rawIdx16[i];
                }
            } else {
                if (!ds_pubg_read(ip, outMesh.indices.data(), idxCount * 4)) return false;
                for (size_t i = 0; i < idxCount; ++i) {
                    if (outMesh.indices[i] >= (uint32_t)nbV) return false;
                }
            }

            // Transform vertices to World Space
            outMesh.verts.resize((size_t)nbV);
            for (int i = 0; i < nbV; ++i) {
                V3 scaled = scale.transform(rawV[(size_t)i]);
                outMesh.verts[(size_t)i] = worldPose.transform(scaled);
            }

            outMesh.computeBounds();
            return true;
        }

        return false;
    }

    // =========================================================================
    // 7. Periodic Scene Updating Loop
    // =========================================================================
    static inline void UpdateScene(const V3 &playerLoc, uint64_t world, uint64_t localPawn, float rangeMeters = 120.0f) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        float distSinceScan = (playerLoc - s_lastScanOrigin).length();
        if ((now - s_lastSceneScanTime) < 1.2 && distSinceScan < 10.0f) {
            return;
        }
        s_lastSceneScanTime = now;
        s_lastScanOrigin = playerLoc;

        if (!s_cachedScene || !LooksLikeActor(ds_pubg_read_ptr(s_cachedRigidArrayData))) {
            s_cachedScene = DiscoverPhysXScene(world, localPawn);
        }
        if (!s_cachedScene || !s_cachedRigidArrayData || s_cachedRigidCount <= 0) {
            return;
        }

        uint32_t rOff = 0; uint64_t rData = 0; int rNum = 0;
        if (LooksLikeScene(s_cachedScene, rOff, rData, rNum)) {
            s_cachedRigidArrayData = rData;
            s_cachedRigidCount = rNum;
        }

        int count = std::min(s_cachedRigidCount, 12000);
        std::vector<uint64_t> actors((size_t)count);
        if (!ds_pubg_read(s_cachedRigidArrayData, actors.data(), (size_t)count * 8)) {
            return;
        }

        float maxRangeSq = (rangeMeters * 100.0f) * (rangeMeters * 100.0f);
        std::vector<Mesh> nextMeshes;
        nextMeshes.reserve(128);

        std::unordered_set<uint64_t> seenShapes;

        for (int i = 0; i < count; ++i) {
            uint64_t actor = actors[(size_t)i];
            if (!LooksLikeActor(actor)) continue;

            uint16_t t8 = ds_pubg_read_u16(actor + 0x08);
            bool isDyn = (t8 == 6);

            Transform pose;
            if (!FindActorPose(actor, isDyn, pose)) continue;

            float d2 = (pose.p - playerLoc).lengthSq();
            if (d2 > maxRangeSq) continue;

            std::vector<uint64_t> shapes;
            CollectActorShapes(actor, shapes);
            for (uint64_t sh : shapes) {
                if (!seenShapes.insert(sh).second) continue;
                Mesh m;
                if (ExtractShapeMesh(actor, sh, isDyn, m)) {
                    nextMeshes.push_back(std::move(m));
                    if (nextMeshes.size() >= 120) break;
                }
            }
            if (nextMeshes.size() >= 120) break;
        }

        if (!nextMeshes.empty()) {
            os_unfair_lock_lock(&s_meshLock);
            s_activeMeshes = std::move(nextMeshes);
            os_unfair_lock_unlock(&s_meshLock);
        }
    }

    // =========================================================================
    // 8. Live Vischeck: LineOfSight Ray-Triangle Query
    // =========================================================================
    static inline bool LineOfSight(const V3 &start, const V3 &end, float slackCm = 25.0f) {
        if (!start.isFinite() || !end.isFinite()) return false;
        V3 delta = end - start;
        float len = delta.length();
        if (len < 10.0f) return true; // Right next to each other

        V3 dir = delta * (1.0f / len);
        float maxT = len - slackCm;
        if (maxT <= 5.0f) return true;

        os_unfair_lock_lock(&s_meshLock);
        if (s_activeMeshes.empty()) {
            os_unfair_lock_unlock(&s_meshLock);
            return true; // No meshes loaded, defer to timestamps
        }

        // Iterate through all active world collision meshes
        for (const auto &m : s_activeMeshes) {
            if (m.verts.size() < 3 || m.indices.size() < 3) continue;

            // Fast AABB rejection
            float tBox = 0.0f;
            if (!RayAABB(start, dir, m.aabbLo, m.aabbHi, maxT, &tBox)) {
                continue;
            }

            // Detailed Triangle Intersection
            size_t numTris = m.indices.size() - (m.indices.size() % 3);
            for (size_t i = 0; i + 2 < numTris; i += 3) {
                uint32_t i0 = m.indices[i];
                uint32_t i1 = m.indices[i + 1];
                uint32_t i2 = m.indices[i + 2];
                if (i0 >= m.verts.size() || i1 >= m.verts.size() || i2 >= m.verts.size()) continue;

                float tHit = 0.0f;
                if (RayTri(start, dir, maxT, m.verts[i0], m.verts[i1], m.verts[i2], tHit)) {
                    if (tHit > 20.0f && tHit < maxT) {
                        os_unfair_lock_unlock(&s_meshLock);
                        return false; // Occluded by wall/object!
                    }
                }
            }
        }

        os_unfair_lock_unlock(&s_meshLock);
        return true; // Clear line of sight!
    }

    // =========================================================================
    // 9. Snapshot Retrieval for Wireframe Rendering (IMG-5994 Style)
    // =========================================================================
    static inline std::vector<Mesh> GetSnapshot() {
        os_unfair_lock_lock(&s_meshLock);
        std::vector<Mesh> copy = s_activeMeshes;
        os_unfair_lock_unlock(&s_meshLock);
        return copy;
    }

    static inline int GetMeshCount() {
        os_unfair_lock_lock(&s_meshLock);
        int n = (int)s_activeMeshes.size();
        os_unfair_lock_unlock(&s_meshLock);
        return n;
    }
}
