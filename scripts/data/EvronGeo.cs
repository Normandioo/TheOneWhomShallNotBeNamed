using System;
using Godot;

namespace Evron;

/// A geografia de Evron para o núcleo em C#: a MESMA convenção de evron_geo.gd e dos shaders (testada em edit_suite).
/// dir = (cos lat · sin lon, sin lat, cos lat · cos lon); u = lon/360 + 0,5; v = 0,5 − lat/180. Ângulos em graus.
internal static class EvronGeo
{
    public const double RadiusKm = 6371.0;  // a Terra (definido pelo autor em 18/11/2026; antes 8.282,3 km)

    public static Vector3 Dir(double latDeg, double lonDeg)
    {
        double lat = latDeg * Math.PI / 180.0, lon = lonDeg * Math.PI / 180.0;
        return new Vector3((float)(Math.Cos(lat) * Math.Sin(lon)), (float)Math.Sin(lat), (float)(Math.Cos(lat) * Math.Cos(lon)));
    }

    /// (lat, lon) em graus.
    public static (double Lat, double Lon) LatLon(Vector3 n) =>
        (Math.Asin(Math.Clamp(n.Y, -1.0, 1.0)) * 180.0 / Math.PI, Math.Atan2(n.X, n.Z) * 180.0 / Math.PI);

    /// Ângulo entre direções (rad). atan2 em vez de acos: o Vector3 é float32 e acos erra perto de 1.
    public static double Angle(Vector3 a, Vector3 b) => Math.Atan2(a.Cross(b).Length(), a.Dot(b));
}
