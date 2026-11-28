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
    private const int EditTileSize = 64;
    internal readonly HashSet<int> EditedTiles = new();

    /// Há edições de relevo ainda não gravadas no banco?
    public bool HasEdits => EditedTiles.Count > 0;
    private int EditTilesAcross => (Size.X + EditTileSize - 1) / EditTileSize;

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
        EditedTiles.Clear();
        _rowTop = int.MaxValue;
        _rowBottom = -1;
        Dirty = RiversDirty = false;
        H = new float[Size.X * Size.Y];
        Buffer.BlockCopy(height.GetData(), 0, H, 0, H.Length * sizeof(float));
        R = new byte[H.Length];
        _origSea = new bool[H.Length];
        for (int i = 0; i < H.Length; i++) _origSea[i] = H[i] < 0f;
        _heightImg = height;
        _riverImg = Image.CreateFromData(Size.X, Size.Y, false, Image.Format.R8, R);
    }

    private bool[] _origSea = [];  // o mar do Gleba (antes das edições): os mapas de imagem não sabem da costa nova

    /// Onde a costa mudou desde o Gleba, para os mapas de imagem (clima, biomas, solos...) seguirem a costa editada: R8, 255 = virou terra,
    /// 128 = virou mar, 0 = como no Gleba. Calculado junto da costa (fora da pincelada).
    public Image CoastChangeImage()
    {
        var b = new byte[H.Length];
        for (int i = 0; i < H.Length; i++)
            if ((H[i] < 0f) != _origSea[i]) b[i] = H[i] < 0f ? (byte)128 : (byte)255;
        return Image.CreateFromData(Size.X, Size.Y, false, Image.Format.R8, b);
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
        MarkEditedTile(idx);
        MarkHeightRows(idx / Size.X, idx / Size.X);
    }

    private void MarkHeightRows(int top, int bottom)
    {
        _rowTop = Math.Min(_rowTop, top);
        _rowBottom = Math.Max(_rowBottom, bottom);
        Dirty = true;
    }

    private void MarkEditedTile(int index) =>
        EditedTiles.Add(index / Size.X / EditTileSize * EditTilesAcross + index % Size.X / EditTileSize);

    private Rect2I EditTileRect(int tile)
    {
        int x = tile % EditTilesAcross * EditTileSize, y = tile / EditTilesAcross * EditTileSize;
        return new Rect2I(x, y, Math.Min(EditTileSize, Size.X - x), Math.Min(EditTileSize, Size.Y - y));
    }

    internal bool ValidEditedTile(int tile, byte[] data) =>
        tile >= 0 && tile / EditTilesAcross <= (Size.Y - 1) / EditTileSize &&
        data.Length == EditTileRect(tile).Size.X * EditTileRect(tile).Size.Y * (sizeof(float) + 1);

    // Cada linha contém as altitudes float32 seguidas da intensidade dos rios editados.
    internal byte[] PackEditedTile(int tile)
    {
        var rect = EditTileRect(tile);
        int width = rect.Size.X, stride = width * (sizeof(float) + 1);
        var data = new byte[rect.Size.Y * stride];
        for (int y = 0; y < rect.Size.Y; y++)
        {
            int cell = (rect.Position.Y + y) * Size.X + rect.Position.X;
            Buffer.BlockCopy(H, cell * sizeof(float), data, y * stride, width * sizeof(float));
            Buffer.BlockCopy(R, cell, data, y * stride + width * sizeof(float), width);
        }
        return data;
    }

    internal void RestoreEditedTile(int tile, byte[] data)
    {
        var rect = EditTileRect(tile);
        int width = rect.Size.X, stride = width * (sizeof(float) + 1);
        for (int y = 0; y < rect.Size.Y; y++)
        {
            int cell = (rect.Position.Y + y) * Size.X + rect.Position.X;
            Buffer.BlockCopy(data, y * stride, H, cell * sizeof(float), width * sizeof(float));
            Buffer.BlockCopy(data, y * stride + width * sizeof(float), R, cell, width);
        }
        MarkHeightRows(rect.Position.Y, rect.End.Y - 1);
        RiversDirty = true;
    }

    public float HeightAt(Vector3 n) => H[PixelOf(n)];

    // ---- costa (para o mapa político) ----

    public const float CoastMaxKm = 80f;  // até onde a distância à costa interessa (o halo e os anéis vão até ~40 km)
    private bool[]? _lake;  // lagos do Gleba: água acima do nível do mar; fixos (a edição de altura não os move)

    /// Os lagos do Gleba ("Waterbodies.png": cinza 30 = oceano, cinza 80 = terra, as outras cores são lagos). Outro tamanho é recusado (false).
    public bool SetLakes(Image waterbodies)
    {
        if (waterbodies == null || waterbodies.GetSize() != Size) return false;
        var img = (Image)waterbodies.Duplicate();
        img.Convert(Image.Format.Rgb8);
        var rgb = img.GetData();
        _lake = new bool[H.Length];
        for (int i = 0; i < H.Length; i++)
        {
            int r = rgb[3 * i], g = rgb[3 * i + 1], b = rgb[3 * i + 2];
            _lake[i] = !(r == g && g == b && (r == 30 || r == 80));
        }
        return true;
    }

    /// As edições dos lagos (camada pintada "lago"): 1 = lago, 2 = seco, 0 = como no Gleba. null = nenhuma.
    public Territory? LakeEdits { get; set; }
    public const int LakeAdded = 1, LakeRemoved = 2;

    /// Lago no pixel: o do Gleba, com as edições por cima.
    public bool IsLake(int p) => LakeEdits?.Get(p) switch
    {
        LakeAdded => true,
        LakeRemoved => false,
        _ => _lake != null && _lake[p],
    };

    /// Água no pixel: mar (altitude abaixo de 0) ou lago.
    internal bool Water(int p) => H[p] < 0f || IsLake(p);

    /// A costa para o mapa político, RGH (meia precisão): R = distância com sinal até a costa em km (+ terra, − água, até ±CoastMaxKm),
    /// G = 1 em lago. Distância por chanfro com a largura real de cada linha (passos de 1 pixel e diagonais: erro de poucos %), suavizada
    /// (gaussiana de 1,2 px: some a escada de pixels) e presa a ±0,5 px da original, então a costa desenhada não sai de meio pixel do dado
    /// e ilhas e canais de 1 pixel ficam (como em tools/mapa_politico.py). Recalcular quando a altitude muda.
    public Image? CoastImage()
    {
        try { return CoastImageCore(); }
        catch (Exception e) when (e is OutOfMemoryException || (e is AggregateException a && a.InnerException is OutOfMemoryException))
        {
            GC.Collect();  // ~200 MB de arrays temporários: sem RAM, devolve null e quem chama mantém a costa anterior
            GD.PushWarning("CoastImage: sem memória; a costa anterior foi mantida.");
            return null;
        }
    }

    Image CoastImageCore()
    {
        int w = Size.X, h = Size.Y, n = w * h;
        double dyKm = Math.PI * EvronGeo.RadiusKm / h;
        var dx = new float[h];
        var diag = new float[h];  // entre a linha y e a y−1
        for (int y = 0; y < h; y++)
        {
            double c = Math.Max(Math.Cos(Math.PI * (0.5 - (y + 0.5) / h)), 0.01);
            dx[y] = (float)(c * 2 * Math.PI * EvronGeo.RadiusKm / w);
            double cm = Math.Max(Math.Cos(Math.PI * (0.5 - (double)y / h)), 0.01) * 2 * Math.PI * EvronGeo.RadiusKm / w;
            diag[y] = (float)Math.Sqrt(cm * cm + dyKm * dyKm);
        }
        var water = new bool[n];
        for (int i = 0; i < n; i++) water[i] = Water(i);
        float dy = (float)dyKm;
        // Uma varredura de ida e uma de volta; as colunas x de x0 até x1 (exclusive), andando em volta da longitude.
        void Sweep(float[] d, int x0, int x1)
        {
            int cols = ((x1 - x0) % w + w) % w;
            if (cols == 0) cols = w;
            for (int y = 0; y < h; y++)
            {
                int row = y * w, up = row - w;
                float sx = dx[y], sd = diag[y];
                for (int c = 0, x = x0; c < cols; c++, x = x == w - 1 ? 0 : x + 1)
                {
                    int xl = x == 0 ? w - 1 : x - 1, xr = x == w - 1 ? 0 : x + 1;
                    float v = Math.Min(d[row + x], d[row + xl] + sx);
                    if (y > 0) v = Math.Min(v, Math.Min(d[up + x] + dy, Math.Min(d[up + xl], d[up + xr]) + sd));
                    d[row + x] = v;
                }
            }
            int last = (x0 + cols - 1) % w;
            for (int y = h - 1; y >= 0; y--)
            {
                int row = y * w, down = row + w;
                float sx = dx[y], sd = y < h - 1 ? diag[y + 1] : 0f;
                for (int c = 0, x = last; c < cols; c++, x = x == 0 ? w - 1 : x - 1)
                {
                    int xl = x == 0 ? w - 1 : x - 1, xr = x == w - 1 ? 0 : x + 1;
                    float v = Math.Min(d[row + x], d[row + xr] + sx);
                    if (y < h - 1) v = Math.Min(v, Math.Min(d[down + x] + dy, Math.Min(d[down + xl], d[down + xr]) + sd));
                    d[row + x] = v;
                }
            }
        }
        float[] Chamfer(bool sourceIsWater)
        {
            var d = new float[n];
            for (int i = 0; i < n; i++) d[i] = water[i] == sourceIsWater ? 0f : CoastMaxKm;
            Sweep(d, 0, w);
            // A volta na longitude 180°: o que atravessa a emenda só chega numa segunda varredura, e só a faixa em volta dela pode mudar.
            int band = Math.Min(w / 2 - 1, (int)Math.Ceiling(CoastMaxKm / dx[h / 20]) + 2);  // largura do pixel a ~81° (mais perto do polo, aproximada)
            Sweep(d, w - band, band);
            return d;
        }
        float[] toWater = null!, toLand = null!;
        System.Threading.Tasks.Parallel.Invoke(() => toWater = Chamfer(true), () => toLand = Chamfer(false));
        var raw = toWater;  // no mesmo vetor: menos 33 MB de pico
        for (int i = 0; i < n; i++) if (water[i]) raw[i] = -toLand[i];

        // Gaussiana separável (σ = 1,2 px, raio 3), com a volta na longitude; depois presa a ±0,5 px da original.
        var k = new float[7];
        for (int j = -3; j <= 3; j++) k[j + 3] = (float)Math.Exp(-j * j / (2 * 1.2 * 1.2));
        float ks = 0;
        foreach (var v in k) ks += v;
        for (int j = 0; j < 7; j++) k[j] /= ks;
        var tmp = toLand;  // já não é preciso depois de raw
        System.Threading.Tasks.Parallel.For(0, h, y =>
        {
            int row = y * w;
            for (int x = 0; x < w; x++)
            {
                float s = 0;
                for (int j = -3; j <= 3; j++)
                {
                    int xx = x + j;
                    s += k[j + 3] * raw[row + (xx < 0 ? xx + w : xx >= w ? xx - w : xx)];
                }
                tmp[row + x] = s;
            }
        });
        float half = (float)(0.5 * dyKm);
        ushort one = BitConverter.HalfToUInt16Bits((Half)1f), zero = BitConverter.HalfToUInt16Bits((Half)0f);
        var data = new byte[n * 4];  // escrito direto como ushort (RGH): sem cópia intermediária de 33 MB
        System.Threading.Tasks.Parallel.For(0, h, y =>
        {
            var halves = System.Runtime.InteropServices.MemoryMarshal.Cast<byte, ushort>(data.AsSpan());
            int r0 = Math.Max(y - 3, 0), r6 = Math.Min(y + 3, h - 1);
            for (int x = 0; x < w; x++)
            {
                float s = 0;
                for (int j = -3; j <= 3; j++) s += k[j + 3] * tmp[Math.Clamp(y + j, r0, r6) * w + x];
                int i = y * w + x;
                halves[2 * i] = BitConverter.HalfToUInt16Bits((Half)Math.Clamp(s, raw[i] - half, raw[i] + half));
                halves[2 * i + 1] = IsLake(i) && H[i] >= 0f ? one : zero;
            }
        });
        return Image.CreateFromData(w, h, false, Image.Format.Rgh, data);
    }

    public float GetRiver(int idx) => R[idx] / 255f;

    public void SetRiver(int idx, float value)
    {
        SetRiverByte(idx, (byte)Math.Round(Math.Clamp(value, 0f, 1f) * 255f));
    }

    internal void SetRiverByte(int idx, byte value)
    {
        if (R[idx] == value) return;
        R[idx] = value;
        MarkEditedTile(idx);
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
