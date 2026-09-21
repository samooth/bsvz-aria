//! Groth16 verifier + reference prover over BN254.
const std = @import("std");
const zc = @import("zig-curve");
const tp = @import("zig-pairing").bn254_tower_pairing;

pub const Fr = zc.bn254.Fr;
pub const G1 = zc.bn254.G1;
pub const G2 = zc.bn254.G2;
const G1Proj = zc.bn254.G1Projective;
const CF = @TypeOf(@as(G1, undefined).x);
pub const Fp12T = tp.Fp12T;
const testing = std.testing;

fn smG2(p: G2, s: Fr) G2 {
    // Use same pattern but for G2 - need G2Proj and affine for G2
    const CF2 = @TypeOf(@as(G2, undefined).x);
    const G2P = zc.bn254.G2Projective;
    const proj = G2P{ .x = p.x, .y = p.y, .z = CF2.one() };
    var result = G2P.zero();
    var base = proj;
    for (s.toBytes()) |byte| {
        var i: u3 = 0;
        while (true) : (i += 1) {
            if ((byte >> i) & 1 == 1) result = result.add(base);
            base = base.dbl();
            if (i == 7) break;
        }
    }
    const zi = result.z.inv();
    const zi2 = zi.mul(zi);
    const zi3 = zi2.mul(zi);
    return .{ .x = result.x.mul(zi2), .y = result.y.mul(zi3), .infinity = false };
}

fn sm(p: G1, s: Fr) G1 {
    const proj = tp_(p);
    var result = G1Proj.zero();
    var base = proj;
    for (s.toBytes()) |byte| {
        var i: u3 = 0;
        while (true) : (i += 1) {
            if ((byte >> i) & 1 == 1) result = result.add(base);
            base = base.dbl();
            if (i == 7) break;
        }
    }
    return aff(result);
}

fn tp_(p: G1) G1Proj {
    return .{ .x = p.x, .y = p.y, .z = CF.one() };
}

fn aff(p: G1Proj) G1 {
    if (p.isZero()) return .{ .x = CF.zero(), .y = CF.zero(), .infinity = true };
    const zi = p.z.inv();
    const zi2 = zi.mul(zi);
    const zi3 = zi2.mul(zi);
    return .{ .x = p.x.mul(zi2), .y = p.y.mul(zi3), .infinity = false };
}

fn neg(a: G1) G1 {
    if (a.infinity) return a;
    return .{ .x = a.x, .y = a.y.neg(), .infinity = false };
}

/// Groth16 verify: e(-A,B)*e(alpha1,beta2)*e(C,delta2)*e(PV,gamma2)==1
pub fn verify(
    a1: G1,
    b2: G2,
    g2: G2,
    d2: G2,
    ic: []const G1,
    pa: G1,
    pb: G2,
    pc: G1,
    pub_in: []const Fr,
) bool {
    var pv = tp_(ic[0]);
    for (pub_in, 0..) |pi, i| pv = pv.add(tp_(sm(ic[i + 1], pi)));
    const l = tp.pairing(neg(pa), pb);
    const r1 = tp.pairing(a1, b2);
    const r2 = tp.pairing(pc, d2);
    const r3 = tp.pairing(aff(pv), g2);
    return l.mul(r1).mul(r2).mul(r3).eql(Fp12T.one());
}

test "groth16: full roundtrip" {
    const NW = 5;
    const NC = 3;
    // circuit x^3+x+5=35
    var A: [NC][NW]Fr = undefined;
    var B: [NC][NW]Fr = undefined;
    var C: [NC][NW]Fr = undefined;
    for (0..NW) |w| {
        A[0][w] = if (w == 1) Fr.one() else Fr.zero();
        A[1][w] = if (w == 3) Fr.one() else Fr.zero();
        A[2][w] = if (w == 0) Fr.fromInt(5) else if (w == 1 or w == 4) Fr.one() else Fr.zero();
        B[0][w] = if (w == 1) Fr.one() else Fr.zero();
        B[1][w] = if (w == 1) Fr.one() else Fr.zero();
        B[2][w] = if (w == 0) Fr.one() else Fr.zero();
        C[0][w] = if (w == 3) Fr.one() else Fr.zero();
        C[1][w] = if (w == 4) Fr.one() else Fr.zero();
        C[2][w] = if (w == 2) Fr.one() else Fr.zero();
    }
    const wit = [NW]Fr{ Fr.one(), Fr.fromInt(3), Fr.fromInt(35), Fr.fromInt(9), Fr.fromInt(27) };

    for (0..NC) |i| {
        var av = Fr.zero();
        var bv = Fr.zero();
        var cv = Fr.zero();
        for (0..NW) |w| {
            av = av.add(A[i][w].mul(wit[w]));
            bv = bv.add(B[i][w].mul(wit[w]));
            cv = cv.add(C[i][w].mul(wit[w]));
        }
        try testing.expect(av.mul(bv).eql(cv));
    }

    // synthetic setup
    const tau = Fr.fromInt(42);
    const alpha = Fr.fromInt(11111);
    const beta = Fr.fromInt(22222);
    const gamma = Fr.fromInt(44444);
    const delta = Fr.fromInt(33333);
    const gen1 = zc.bn254.G1_generator;
    const gen2 = zc.bn254.G2_generator;
    const a1 = sm(gen1, alpha);
    const b2 = smG2(gen2, beta);
    const g2 = smG2(gen2, gamma);
    const d2 = smG2(gen2, delta);

    // Lagrange over domain {1,2,3}
    var L: [NC][NC]Fr = undefined;
    const dom = [_]Fr{ Fr.one(), Fr.fromInt(2), Fr.fromInt(3) };
    for (0..NC) |i| {
        var co = [_]Fr{ Fr.one(), Fr.zero(), Fr.zero() };
        const xi = dom[i];
        var de = Fr.one();
        for (0..NC) |j| {
            if (j == i) continue;
            var nx = [_]Fr{ Fr.zero(), Fr.zero(), Fr.zero() };
            for (0..NC) |k| {
                nx[k] = nx[k].sub(co[k].mul(dom[j]));
                if (k + 1 < NC) nx[k + 1] = nx[k + 1].add(co[k]);
            }
            for (0..NC) |k| co[k] = nx[k];
            de = de.mul(xi.sub(dom[j]));
        }
        const di = de.inv();
        for (0..NC) |k| L[i][k] = co[k].mul(di);
    }

    // wire polys evaluated at tau
    var aw_tau = Fr.zero();
    var bw_tau = Fr.zero();
    for (0..NW) |w| {
        for (0..NC) |ci| {
            var lv = Fr.one();
            for (0..NC) |j| {
                if (j != ci)
                    lv = lv.mul(tau.sub(dom[j])).mul(dom[ci].sub(dom[j]).inv());
            }
            aw_tau = aw_tau.add(wit[w].mul(A[ci][w]).mul(lv));
            bw_tau = bw_tau.add(wit[w].mul(B[ci][w]).mul(lv));
        }
    }

    // IC for public wires (0=one, 2=out)
    var ic: [2]G1 = undefined;
    for ([_]usize{ 0, 2 }) |wi| {
        var sum = Fr.zero();
        for (0..NC) |ci| {
            var lv = Fr.one();
            for (0..NC) |j| {
                if (j != ci)
                    lv = lv.mul(tau.sub(dom[j])).mul(dom[ci].sub(dom[j]).inv());
            }
            sum = sum.add(lv.mul(beta.mul(A[ci][wi]).add(alpha.mul(B[ci][wi])).add(C[ci][wi])));
        }
        ic[wi / 2] = sm(gen1, sum.mul(gamma.inv()));
    }

    // H quotient via poly division
    var aw_x: [NC]Fr = .{ Fr.zero(), Fr.zero(), Fr.zero() };
    var bw_x: [NC]Fr = .{ Fr.zero(), Fr.zero(), Fr.zero() };
    var cw_x: [NC]Fr = .{ Fr.zero(), Fr.zero(), Fr.zero() };
    for (0..NW) |w| {
        for (0..NC) |k| {
            aw_x[k] = aw_x[k].add(wit[w].mul(A[k][w]));
            bw_x[k] = bw_x[k].add(wit[w].mul(B[k][w]));
            cw_x[k] = cw_x[k].add(wit[w].mul(C[k][w]));
        }
    }

    // DEBUG: print coefficients for comparison with spike
    for (0..3) |k| {
        const bytes = aw_x[k].toBytes();
        std.debug.print(" {x} {x}", .{ bytes[0], bytes[1] });
    }
    for (0..3) |k| {
        const bytes = bw_x[k].toBytes();
        std.debug.print(" {x} {x}", .{ bytes[0], bytes[1] });
    }
    std.debug.print("\n", .{});

    // num = pmul(aw_x,bw_x) - cw_x padded
    var num: [6]Fr = .{ Fr.zero(), Fr.zero(), Fr.zero(), Fr.zero(), Fr.zero(), Fr.zero() };
    for (0..NC) |i| {
        for (0..NC) |j|
            num[i + j] = num[i + j].add(aw_x[i].mul(bw_x[j]));
    }
    for (0..NC) |k| num[k] = num[k].sub(cw_x[k]);

    // vanish poly t(x)=(x-1)(x-2)(x-3)
    var vp = [_]Fr{ Fr.one(), Fr.zero(), Fr.zero(), Fr.zero() };
    for (dom) |rt| {
        var nv = [_]Fr{ Fr.zero(), Fr.zero(), Fr.zero(), Fr.zero() };
        for (0..4) |k| {
            nv[k] = nv[k].sub(vp[k].mul(rt));
            if (k > 0) nv[k] = nv[k].add(vp[k - 1]);
        }
        vp = nv;
    }

    // DEBUG: verify vanish poly evaluates to zero at domain points
    for (dom) |x| {
        var vv = Fr.zero();
        var pw2 = Fr.one();
        for (0..4) |k| {
            vv = vv.add(vp[k].mul(pw2));
            pw2 = pw2.mul(x);
        }
        std.debug.print("VP[{d}]={d}\n", .{ @as(u32, @intCast(x.toInt())), vv.toU64() });
    }
    std.debug.print("VP coeffs:", .{});
    for (0..4) |k| {
        const bytes = vp[k].toBytes();
        std.debug.print(" {x}", .{bytes[0]});
    }
    std.debug.print("\n", .{});

    // Evaluate num and t at tau directly (skip poly division)
    var num_at_tau = Fr.zero();
    {
        var pw = Fr.one();
        for (0..6) |k| {
            num_at_tau = num_at_tau.add(num[k].mul(pw));
            pw = pw.mul(tau);
        }
    }
    var t_at_tau = Fr.zero();
    {
        var pw = Fr.one();
        for (0..4) |k| {
            t_at_tau = t_at_tau.add(vp[k].mul(pw));
            pw = pw.mul(tau);
        }
    }

    // h(tau) = num(tau) / t(tau)
    const h_tau = num_at_tau.mul(t_at_tau.inv());

    var t_tau = Fr.zero();
    {
        var pw2 = Fr.one();
        for (0..4) |k| {
            t_tau = t_tau.add(vp[k].mul(pw2));
            pw2 = pw2.mul(tau);
        }
    }

    // prover scalars
    const rv = Fr.fromInt(7);
    const sv = Fr.fromInt(11);
    const asc = alpha.add(aw_tau).add(rv.mul(delta));
    const bsc = beta.add(bw_tau).add(sv.mul(delta));
    var priv_sum = Fr.zero();
    for (2..NW) |w| {
        for (0..NC) |ci| {
            var lv = Fr.one();
            for (0..NC) |j| {
                if (j != ci)
                    lv = lv.mul(tau.sub(dom[j])).mul(dom[ci].sub(dom[j]).inv());
            }
            priv_sum = priv_sum.add(
                wit[w].mul(beta.mul(A[ci][w]).add(alpha.mul(B[ci][w])).add(C[ci][w])).mul(lv),
            );
        }
    }
    const rsd = rv.mul(sv).mul(delta);
    const csc = priv_sum.add(h_tau.mul(t_tau)).mul(delta.inv())
        .add(sv.mul(asc)).add(rv.mul(bsc)).sub(rsd);

    const ok = verify(a1, b2, g2, d2, &ic, sm(gen1, asc), smG2(gen2, bsc), sm(gen1, csc), &.{Fr.fromInt(35)});
    // SANITY: scalar mul basics
    const one_g1 = sm(gen1, Fr.one());
    std.debug.print("\nSAN sm(1)==gen1:{}\n", .{one_g1.eql(gen1)});
    const two_g1 = sm(gen1, Fr.fromInt(2));
    std.debug.print("SAN sm(2)==dbl:{}\n", .{two_g1.eql(gen1.dbl())});
    const five_g1 = sm(gen1, Fr.fromInt(5));
    var iter5 = gen1;
    for (0..4) |_| iter5 = iter5.add(gen1);
    std.debug.print("SAN sm(5)==5*gen:{}\n", .{five_g1.eql(iter5)});
    try testing.expect(ok);
}
