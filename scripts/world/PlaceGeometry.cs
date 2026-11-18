using System;
using System.Collections.Generic;
using System.Linq;

namespace Evron;

/// Geometria de contornos desenhados à mão sobre a esfera de Evron: validar, achar o centro, a área, se um ponto está dentro e a distância até a
/// borda. Tudo em double e em vetores unitários (a mesma convenção de EvronGeo: dir = (cos lat · sin lon, sin lat, cos lat · cos lon)), então nada
/// depende de uma grade: o contorno atravessa a longitude 180° e cobre o polo sem caso especial. Os lados são arcos de círculo máximo.
/// Limite: um contorno é a região MENOR (a do lado do centro dos vértices): ele precisa caber a menos de 85° do seu centro.
internal readonly struct Vec
{
    public readonly double X, Y, Z;

    public Vec(double x, double y, double z) { X = x; Y = y; Z = z; }

    public static Vec FromLatLon(double latDeg, double lonDeg)
    {
        double lat = latDeg * Math.PI / 180.0, lon = lonDeg * Math.PI / 180.0;
        return new Vec(Math.Cos(lat) * Math.Sin(lon), Math.Sin(lat), Math.Cos(lat) * Math.Cos(lon));
    }

    public (double Lat, double Lon) ToLatLon() => (Math.Asin(Math.Clamp(Y, -1.0, 1.0)) * 180.0 / Math.PI, Math.Atan2(X, Z) * 180.0 / Math.PI);

    public double Dot(Vec o) => X * o.X + Y * o.Y + Z * o.Z;
    public Vec Cross(Vec o) => new(Y * o.Z - Z * o.Y, Z * o.X - X * o.Z, X * o.Y - Y * o.X);
    public double Length => Math.Sqrt(Dot(this));
    public Vec Unit() { double l = Length; return l < 1e-300 ? this : new Vec(X / l, Y / l, Z / l); }
    public static Vec operator +(Vec a, Vec b) => new(a.X + b.X, a.Y + b.Y, a.Z + b.Z);
    public static Vec operator -(Vec a, Vec b) => new(a.X - b.X, a.Y - b.Y, a.Z - b.Z);
    public static Vec operator *(Vec a, double k) => new(a.X * k, a.Y * k, a.Z * k);

    /// Ângulo entre direções (rad). atan2 em vez de acos: não perde precisão em distâncias curtas.
    public static double Angle(Vec a, Vec b) => Math.Atan2(a.Cross(b).Length, a.Dot(b));
}

/// Um contorno validado: os pontos como foram dados (já sem o ponto final repetido), os vetores e o centro.
internal sealed class Polygon
{
    public required double[] LatLon { get; init; }  // lat0, lon0, lat1, lon1, ...
    public required Vec[] V { get; init; }
    public required Vec Center { get; init; }
}

internal static class PlaceGeometry
{
    public const double R = EvronGeo.RadiusKm;
    public const double MaxRadiusRad = 85.0 * Math.PI / 180.0;
    public const int MaxPoints = 2000;
    const double SameDeg = 1e-9;

    /// Valida os pontos (lat, lon em graus, alternados) e devolve o contorno, ou lança ArgumentException dizendo o que está errado.
    public static Polygon Validate(double[] flat)
    {
        if (flat.Length % 2 != 0) throw new ArgumentException("os pontos vêm em pares (lat, lon)");
        var pts = new List<(double Lat, double Lon)>();
        for (int i = 0; i < flat.Length; i += 2)
        {
            double lat = flat[i], lon = flat[i + 1];
            if (!double.IsFinite(lat) || !double.IsFinite(lon) || lat < -90 || lat > 90 || lon < -180 || lon > 180)
                throw new ArgumentException($"ponto {i / 2 + 1} fora do planeta (lat {lat}, lon {lon})");
            pts.Add((lat, lon));
        }
        if (pts.Count > 1 && Same(pts[0], pts[^1])) pts.RemoveAt(pts.Count - 1);  // o contorno fecha sozinho
        if (pts.Count < 3) throw new ArgumentException("o contorno precisa de ao menos 3 pontos diferentes");
        if (pts.Count > MaxPoints) throw new ArgumentException($"o contorno tem pontos demais ({pts.Count}; o máximo é {MaxPoints})");
        for (int i = 0; i < pts.Count; i++)
            if (Same(pts[i], pts[(i + 1) % pts.Count])) throw new ArgumentException($"os pontos {i + 1} e {(i + 1) % pts.Count + 1} estão no mesmo lugar");
        var v = pts.Select(p => Vec.FromLatLon(p.Lat, p.Lon)).ToArray();
        var c = Centroid(v);
        if (v.Max(p => Vec.Angle(c, p)) > MaxRadiusRad) throw new ArgumentException("o contorno é grande demais (precisa caber a menos de 85° do seu centro); divida-o em regiões");
        if (SelfIntersects(v, c)) throw new ArgumentException("o contorno cruza ele mesmo");
        if (AreaKm2(v) < 1.0) throw new ArgumentException("o contorno não tem área (os pontos estão em linha)");
        return new Polygon { LatLon = pts.SelectMany(p => new[] { p.Lat, p.Lon }).ToArray(), V = v, Center = c };
    }

    /// Os vetores de pontos já guardados (sem validar de novo).
    public static Vec[] ToVecs(double[] flat)
    {
        var v = new Vec[flat.Length / 2];
        for (int i = 0; i < v.Length; i++) v[i] = Vec.FromLatLon(flat[2 * i], flat[2 * i + 1]);
        return v;
    }

    static bool Same((double Lat, double Lon) a, (double Lat, double Lon) b) => Math.Abs(a.Lat - b.Lat) < SameDeg && Math.Abs(a.Lon - b.Lon) < SameDeg;

    /// O centro: a média dos vetores, normalizada (vale em qualquer longitude e perto dos polos).
    public static Vec Centroid(Vec[] v)
    {
        var sum = new Vec(0, 0, 0);
        foreach (var p in v) sum += p;
        return sum.Length < 1e-12 ? v[0] : sum.Unit();
    }

    /// Área em km² pela soma dos ângulos sólidos dos triângulos (centro, p_i, p_i+1), com sinal: vale também para contorno côncavo.
    public static double AreaKm2(Vec[] v)
    {
        var c = Centroid(v);
        double sum = 0;
        for (int i = 0; i < v.Length; i++) sum += SolidAngle(c, v[i], v[(i + 1) % v.Length]);
        return Math.Abs(sum) * R * R;
    }

    // Van Oosterom & Strackee: tan(Ω/2) = a·(b×c) / (1 + a·b + b·c + c·a)
    static double SolidAngle(Vec a, Vec b, Vec c) => 2.0 * Math.Atan2(a.Dot(b.Cross(c)), 1.0 + a.Dot(b) + b.Dot(c) + c.Dot(a));

    /// O ponto está dentro? Soma o giro do rumo (visto do ponto) de cada vértice ao seguinte: ±2π dentro, 0 fora. Sem grade, então o contorno
    /// atravessa a longitude 180° ou cobre o polo normalmente. Um ponto sobre um vértice conta como dentro.
    public static bool Contains(Vec p, Vec[] v)
    {
        // O giro do rumo é ±2π também para um ponto quase no lado oposto do planeta (a curva "dá a volta" nele). Um contorno cabe a menos de 85° do
        // seu centro, então um ponto mais longe que isso não está dentro, e dentro dessa distância o antípoda do ponto nunca cai no contorno.
        if (Vec.Angle(p, Centroid(v)) > MaxRadiusRad) return false;
        double first = 0, prev = 0, sum = 0;
        for (int i = 0; i < v.Length; i++)
        {
            double b = Bearing(p, v[i]);
            if (double.IsNaN(b)) return true;
            if (i == 0) first = b; else sum += Wrap(b - prev);
            prev = b;
        }
        sum += Wrap(first - prev);
        return Math.Abs(sum) > Math.PI;
    }

    /// Rumo de p para q (rad, no plano tangente em p: leste = +x, norte = +y); NaN se coincidem.
    static double Bearing(Vec p, Vec q)
    {
        if ((q - p).Length < 1e-12) return double.NaN;
        var east = new Vec(0, 1, 0).Cross(p);
        east = east.Length < 1e-12 ? new Vec(1, 0, 0) : east.Unit();  // no polo o "leste" é arbitrário
        var north = p.Cross(east);
        return Math.Atan2(q.Dot(east), q.Dot(north));
    }

    static double Wrap(double a)
    {
        while (a > Math.PI) a -= 2 * Math.PI;
        while (a < -Math.PI) a += 2 * Math.PI;
        return a;
    }

    /// Distância (km) do ponto à borda do contorno (o arco mais próximo).
    public static double DistanceToBoundaryKm(Vec p, Vec[] v)
    {
        double best = double.MaxValue;
        for (int i = 0; i < v.Length; i++) best = Math.Min(best, EdgeDistance(p, v[i], v[(i + 1) % v.Length]));
        return best * R;
    }

    static double EdgeDistance(Vec p, Vec a, Vec b)
    {
        var n = a.Cross(b);
        if (n.Length < 1e-12) return Math.Min(Vec.Angle(p, a), Vec.Angle(p, b));
        n = n.Unit();
        double along = p.Dot(n);
        var c = p - n * along;
        if (c.Length < 1e-12) return Math.Min(Vec.Angle(p, a), Vec.Angle(p, b));  // p é o polo do círculo máximo: todos os pontos estão a 90°
        c = c.Unit();
        if (a.Cross(c).Dot(n) >= 0 && c.Cross(b).Dot(n) >= 0) return Math.Abs(Math.Asin(Math.Clamp(along, -1.0, 1.0)));  // o pé da perpendicular cai no arco
        return Math.Min(Vec.Angle(p, a), Vec.Angle(p, b));
    }

    /// Dois lados não vizinhos se tocam ou se cruzam? Visto no plano gnomônico em torno do centro, onde os círculos máximos são retas.
    static bool SelfIntersects(Vec[] v, Vec c)
    {
        var east = new Vec(0, 1, 0).Cross(c);
        east = east.Length < 1e-12 ? new Vec(1, 0, 0) : east.Unit();
        var north = c.Cross(east);
        var p = v.Select(q => { double k = q.Dot(c); return (X: q.Dot(east) / k, Y: q.Dot(north) / k); }).ToArray();
        int n = p.Length;
        for (int i = 0; i < n; i++)
            for (int j = i + 1; j < n; j++)
            {
                if (j == i + 1 || (i == 0 && j == n - 1)) continue;  // lados vizinhos
                if (SegmentsMeet(p[i], p[(i + 1) % n], p[j], p[(j + 1) % n])) return true;
            }
        return false;
    }

    static bool SegmentsMeet((double X, double Y) a, (double X, double Y) b, (double X, double Y) c, (double X, double Y) d)
    {
        double o1 = Orient(a, b, c), o2 = Orient(a, b, d), o3 = Orient(c, d, a), o4 = Orient(c, d, b);
        if (((o1 > 0 && o2 < 0) || (o1 < 0 && o2 > 0)) && ((o3 > 0 && o4 < 0) || (o3 < 0 && o4 > 0))) return true;
        const double eps = 1e-12;
        return (Math.Abs(o1) < eps && OnSegment(a, b, c)) || (Math.Abs(o2) < eps && OnSegment(a, b, d))
            || (Math.Abs(o3) < eps && OnSegment(c, d, a)) || (Math.Abs(o4) < eps && OnSegment(c, d, b));
    }

    static double Orient((double X, double Y) a, (double X, double Y) b, (double X, double Y) c) => (b.X - a.X) * (c.Y - a.Y) - (b.Y - a.Y) * (c.X - a.X);

    static bool OnSegment((double X, double Y) a, (double X, double Y) b, (double X, double Y) p) =>
        Math.Min(a.X, b.X) - 1e-12 <= p.X && p.X <= Math.Max(a.X, b.X) + 1e-12 && Math.Min(a.Y, b.Y) - 1e-12 <= p.Y && p.Y <= Math.Max(a.Y, b.Y) + 1e-12;
}
