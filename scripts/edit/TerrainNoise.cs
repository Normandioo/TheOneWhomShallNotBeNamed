using System;
using Godot;

namespace Evron;

/// Ruídos para os pincéis procedurais. Todos são funções da posição 3D na esfera (em km): sem emenda na longitude 180°,
/// sem estiramento nos polos, e a mesma posição dá o mesmo valor para uma mesma semente.
/// - Fbm: ondulação suave e natural (colinas); 0..1, média ~0,5.
/// - Ridge: cristas finas de montanha (ridged multifractal + deslocamento de domínio); 0..1, cristas altas perto de 1.
internal sealed class TerrainNoise
{
    private const double RidgeBaseKm = 320.0;
    private const int RidgeOctaves = 6;
    private const float WarpKm = 120f;  // deslocamento que faz as cristas serpentearem em vez de seguirem a grade
    private const double HillBaseKm = 100.0;

    private readonly FastNoiseLite _ridge = new()
    {
        NoiseType = FastNoiseLite.NoiseTypeEnum.Simplex,
        FractalType = FastNoiseLite.FractalTypeEnum.Ridged,
        FractalOctaves = RidgeOctaves,
        FractalGain = 0.55f,
        Frequency = (float)(1.0 / RidgeBaseKm),  // calculado em double, como no GDScript de origem
        DomainWarpEnabled = true,
        DomainWarpAmplitude = WarpKm,
        DomainWarpFrequency = (float)(1.0 / (RidgeBaseKm * 1.5)),
    };

    private readonly FastNoiseLite _fbm = new()
    {
        NoiseType = FastNoiseLite.NoiseTypeEnum.Simplex,
        FractalType = FastNoiseLite.FractalTypeEnum.Fbm,
        FractalOctaves = 4,
        FractalGain = 0.6f,
        Frequency = (float)(1.0 / HillBaseKm),
    };

    public void SetSeed(int seed)
    {
        _ridge.Seed = seed;
        _fbm.Seed = seed + 1013;
    }

    /// Ondulação 0..1 (média ~0,5) em n.
    public double Fbm(Vector3 n)
    {
        var p = n * (float)EvronGeo.RadiusKm;
        return Math.Clamp(_fbm.GetNoise3D(p.X, p.Y, p.Z) * 0.8 + 0.5, 0.0, 1.0);
    }

    /// Crista 0..1 em n. O ruído medido vai de −0,67 a 0,92 (mediana 0,3): normalizado para essa faixa.
    public double Ridge(Vector3 n)
    {
        var p = n * (float)EvronGeo.RadiusKm;
        return Math.Clamp((_ridge.GetNoise3D(p.X, p.Y, p.Z) + 0.2) / 0.9, 0.0, 1.0);
    }
}
