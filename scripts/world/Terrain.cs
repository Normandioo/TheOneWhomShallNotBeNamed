using System;
using System.Collections.Generic;
using Godot;

namespace Evron;

/// A altitude do mundo em memória: metros, float32, equiretangular (EvronGeo), num float[] (rápido de ler e gravar).
/// Também guarda os rios do pincel Vales (0..255, mesma grade). Sabe achar os pixels de um disco na esfera (o pincel),
/// os vizinhos de um pixel e ler e gravar alturas. Não conhece tela nem comandos: quem edita guarda o "antes"
/// (BrushKernel). A GPU recebe as imagens por HeightImage() e RiversImage().
public partial class Terrain : RefCounted
{
    public Vector2I Size { get; private set; }
    public bool Dirty { get; set; }        // a altitude mudou desde o último HeightImage()
    public bool RiversDirty { get; set; }  // os rios mudaram desde o último RiversImage()

    internal float[] H = Array.Empty<float>();
    internal byte[] R = Array.Empty<byte>();
    private Image? _heightImg;
    private Image? _riverImg;
    private int _rowTop = int.MaxValue;  // faixa de linhas mexidas desde o último HeightImage()
    private int _rowBottom = -1;

    // Os 8 vizinhos (dx, dy) e o passo de cada um em pixels (diagonal = √2).
    internal static readonly (int Dx, int Dy, double Step)[] Neighbors =
    {
        (-1, -1, 1.414), (0, -1, 1.0), (1, -1, 1.414), (-1, 0, 1.0),
        (1, 0, 1.0), (-1, 1, 1.414), (0, 1, 1.0), (1, 1, 1.414),
    };

    /// Copia a altitude (Image FORMAT_RF) para a memória do núcleo; a imagem passa a ser a que vai para a GPU.
    public void Setup(Image height)
    {
        if (height.GetFormat() != Image.Format.Rf)
            throw new ArgumentException($"altitude deveria ser FORMAT_RF, veio {height.GetFormat()}");
        Size = height.GetSize();
        H = new float[Size.X * Size.Y];
        Buffer.BlockCopy(height.GetData(), 0, H, 0, H.Length * sizeof(float));
        R = new byte[H.Length];
        _heightImg = height;
        _riverImg = Image.CreateFromData(Size.X, Size.Y, false, Image.Format.R8, R);
    }

    /// A imagem da altitude, atualizada com as edições (a mesma instância sempre: a textura do globo a usa).
    /// Só a faixa de linhas mexidas é copiada (uma pincelada de 1000 km: ~2 MiB em vez de 32).
    public Image HeightImage()
    {
        if (_rowBottom >= _rowTop)
        {
            int rows = _rowBottom - _rowTop + 1;
            var band = new byte[rows * Size.X * sizeof(float)];
            Buffer.BlockCopy(H, _rowTop * Size.X * sizeof(float), band, 0, band.Length);
            var img = Image.CreateFromData(Size.X, rows, false, Image.Format.Rf, band);
            _heightImg!.BlitRect(img, new Rect2I(0, 0, Size.X, rows), new Vector2I(0, _rowTop));
            _rowTop = int.MaxValue;
            _rowBottom = -1;
        }
        return _heightImg!;
    }

    /// A imagem dos rios (R8), atualizada com as edições.
    public Image RiversImage()
    {
        _riverImg!.SetData(Size.X, Size.Y, false, Image.Format.R8, R);
        return _riverImg;
    }

    public float GetH(int idx) => H[idx];

    public void SetH(int idx, float meters)
    {
        H[idx] = meters;
        int y = idx / Size.X;
        _rowTop = Math.Min(_rowTop, y);
        _rowBottom = Math.Max(_rowBottom, y);
        Dirty = true;
    }

    public float HeightAt(Vector3 n) => H[PixelOf(n)];

    public float GetRiver(int idx) => R[idx] / 255f;

    public void SetRiver(int idx, float value)
    {
        R[idx] = (byte)Math.Round(Math.Clamp(value, 0f, 1f) * 255f);
        RiversDirty = true;
    }

    /// Índice do pixel que contém a direção n.
    public int PixelOf(Vector3 n)
    {
        var (lat, lon) = EvronGeo.LatLon(n);
        int x = Mod((int)Math.Floor((lon / 360.0 + 0.5) * Size.X), Size.X);
        int y = Math.Clamp((int)Math.Floor((0.5 - lat / 180.0) * Size.Y), 0, Size.Y - 1);
        return y * Size.X + x;
    }

    /// Direção na esfera do centro do pixel idx.
    public Vector3 DirOf(int idx)
    {
        int x = idx % Size.X, y = idx / Size.X;
        return EvronGeo.Dir(90.0 - (y + 0.5) * 180.0 / Size.Y, ((x + 0.5) / Size.X - 0.5) * 360.0);
    }

    /// Os pixels a menos de radiusKm (pela superfície) da direção n, com o peso do pincel, para o GDScript:
    /// [PackedInt32Array índices, PackedFloat32Array pesos].
    public Godot.Collections.Array Disk(Vector3 n, float radiusKm)
    {
        var idx = new List<int>();
        var w = new List<float>();
        DiskInto(n, radiusKm, idx, w);
        return new Godot.Collections.Array { idx.ToArray(), w.ToArray() };
    }

    /// O disco do pincel: peso 1 no centro e 0 na borda, sem degrau ((1 − (d/r)²)²). Dá a volta na longitude 180°
    /// e passa pelos polos.
    internal void DiskInto(Vector3 n, double radiusKm, List<int> idx, List<float> weight)
    {
        idx.Clear();
        weight.Clear();
        double a = radiusKm / EvronGeo.RadiusKm;  // raio angular (rad)
        var (latDeg, lonDeg) = EvronGeo.LatLon(n);
        double lat0 = latDeg * Math.PI / 180.0;
        int yTop = Math.Clamp((int)Math.Floor((0.5 - (lat0 + a) / Math.PI) * Size.Y), 0, Size.Y - 1);
        int yBottom = Math.Clamp((int)Math.Floor((0.5 - (lat0 - a) / Math.PI) * Size.Y), 0, Size.Y - 1);
        double xc = (lonDeg / 360.0 + 0.5) * Size.X;
        double cosA = Math.Cos(a);
        for (int y = yTop; y <= yBottom; y++)
        {
            double lat = Math.PI * (0.5 - (y + 0.5) / Size.Y);
            // Meia largura em longitude do disco nesta linha (lei dos cossenos); perto do polo, a linha inteira.
            double c = (cosA - Math.Sin(lat) * Math.Sin(lat0)) / Math.Max(Math.Cos(lat) * Math.Cos(lat0), 1e-9);
            if (c > 1.0)
                continue;
            double halfLon = c < -1.0 ? Math.PI : Math.Acos(c);
            int nPx = Math.Min((int)Math.Ceiling(halfLon / Math.Tau * Size.X) + 1, Size.X / 2);
            for (int k = -nPx; k <= nPx; k++)
            {
                int x = Mod((int)Math.Floor(xc) + k, Size.X);
                var p = EvronGeo.Dir(lat * 180.0 / Math.PI, ((x + 0.5) / Size.X - 0.5) * 360.0);
                double d = EvronGeo.Angle(p, n) / a;
                if (d < 1.0)
                {
                    idx.Add(y * Size.X + x);
                    weight.Add((float)((1.0 - d * d) * (1.0 - d * d)));
                }
            }
        }
    }

    /// O vizinho (dx, dy) do pixel p, com a volta na longitude; −1 fora do mapa (acima do polo).
    internal int Neighbor(int p, int dx, int dy)
    {
        int y = p / Size.X + dy;
        if (y < 0 || y >= Size.Y)
            return -1;
        return y * Size.X + Mod(p % Size.X + dx, Size.X);
    }

    /// Para onde a água escoa (D8): o vizinho de maior declive descendo, ou −1 (poço). height dá a altura a usar.
    internal int Steepest(int p, Func<int, double> height, out double drop)
    {
        double h = height(p);
        int best = -1;
        drop = 0.0;
        foreach (var (dx, dy, step) in Neighbors)
        {
            int q = Neighbor(p, dx, dy);
            if (q < 0)
                continue;
            double dd = (h - height(q)) / step;
            if (dd > drop)
            {
                drop = dd;
                best = q;
            }
        }
        return best;
    }

    /// Média das alturas num quadrado (2r+1)² em volta de um pixel, com a volta na longitude. Em double: nos platôs
    /// planos do Gleba as médias diferem por pouco, e arredondar para float mudaria o rumo da água.
    internal double NeighborMean(int idx, int r = 1)
    {
        int x = idx % Size.X, y = idx / Size.X;
        double s = 0.0;
        int count = 0;
        for (int dy = -r; dy <= r; dy++)
        {
            int yy = y + dy;
            if (yy < 0 || yy >= Size.Y)
                continue;
            for (int dx = -r; dx <= r; dx++)
            {
                s += H[yy * Size.X + Mod(x + dx, Size.X)];
                count++;
            }
        }
        return s / count;
    }

    internal static int Mod(int a, int m) => ((a % m) + m) % m;
}
