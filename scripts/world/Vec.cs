using System;

namespace Evron;

/// Um vetor em double na convenção de EvronGeo: dir = (cos lat · sin lon, sin lat, cos lat · cos lon).
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
