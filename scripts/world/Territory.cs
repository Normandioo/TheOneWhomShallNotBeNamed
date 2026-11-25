using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using Godot;

namespace Evron;

/// A camada política: o DONO de cada pixel do mapa (0 = ninguém), na mesma grade da altitude (EvronGeo, equiretangular). O dono é o id de um
/// cadastro de país (de 1 a 65535). Cada pixel tem um dono só: não há fresta nem sobreposição entre países, e a borda nasce onde duas cores se
/// encontram. Ilhas, buracos e países grandes são naturais. Guarda 2 bytes por pixel (little endian), que é o formato RG8 que a GPU recebe.
/// Quem pinta (o pincel, o balde, a borracha) devolve uma TerritoryEdit com os pixels mexidos, para a pilha de desfazer; a persistência no banco
/// é do Registry (SaveTerritory/LoadTerritory). Não conhece tela nem comandos.
public partial class Territory : RefCounted
{
    public const int MaxOwner = 65535;

    public bool IsResource { get; set; }  // camada de um recurso: os donos são ocorrências, não cadastros

    public Vector2I Size { get; private set; }
    public bool Dirty { get; set; }      // algo mudou desde a última OwnersImage() levada à GPU
    public long Version { get; private set; }  // sobe a cada edição (desfazer e refazer também): invalida o que foi calculado

    internal byte[] B = Array.Empty<byte>();
    private Terrain? _terrain;
    private Image? _img;
    private int _rowTop = int.MaxValue;  // faixa de linhas mexidas desde a última OwnersImage()
    private int _rowBottom = -1;
    private Dictionary<int, ushort>? _stroke;  // pincelada em andamento: pixel -> dono de antes
    private readonly List<int> _idx = new();
    private readonly List<float> _w = new();
    private System.Collections.Generic.Dictionary<int, double>? _areas;
    private long _areasVersion = -1;

    /// Liga ao terreno (a grade e o "só em terra" vêm dele) e começa sem nenhum dono.
    public void Setup(Terrain terrain)
    {
        _terrain = terrain;
        Size = terrain.Size;
        B = new byte[Size.X * Size.Y * 2];
        _img = Image.CreateFromData(Size.X, Size.Y, false, Image.Format.Rg8, B);
        ResetTiles();
        _rowTop = int.MaxValue;
        _rowBottom = -1;
        ResetBoundaries();
        Touch();
        Dirty = true;
    }

    public int Get(int idx) => B[idx * 2] | (B[idx * 2 + 1] << 8);

    internal void Put(int idx, int owner)
    {
        B[idx * 2] = (byte)(owner & 255);
        B[idx * 2 + 1] = (byte)(owner >> 8);
        int y = idx / Size.X;
        _rowTop = Math.Min(_rowTop, y);
        _rowBottom = Math.Max(_rowBottom, y);
        _compTop = Math.Min(_compTop, y);
        _compBottom = Math.Max(_compBottom, y);
        MarkTile(idx);
        Dirty = true;
    }

    internal void Touch() => Version++;

    /// O dono do pixel que contém a direção n.
    public int OwnerAt(Vector3 n) => Get(_terrain!.PixelOf(n));

    /// A imagem RG8 dos donos (OwnersImage), atualizada (a mesma instância sempre: a textura do globo a usa). Só a faixa de linhas mexidas é copiada.
    public Image OwnersImage()
    {
        if (_rowBottom >= _rowTop)
        {
            int rows = _rowBottom - _rowTop + 1;
            var band = new byte[rows * Size.X * 2];
            Buffer.BlockCopy(B, _rowTop * Size.X * 2, band, 0, band.Length);
            var img = Godot.Image.CreateFromData(Size.X, rows, false, Image.Format.Rg8, band);
            _img!.BlitRect(img, new Rect2I(0, 0, Size.X, rows), new Vector2I(0, _rowTop));
            _rowTop = int.MaxValue;
            _rowBottom = -1;
        }
        return _img!;
    }

    // ---- pincel ----

    /// Começa uma pincelada (os pixels mexidos até End() viram uma edição só).
    public void Begin() => _stroke = new Dictionary<int, ushort>();

    /// Uma marca do pincel: o disco de radiusKm em n passa a ser do dono `owner` (0 = apaga). landOnly: só pinta onde a altitude é de terra (≥ 0), e então
    /// a costa do país segue a costa do mapa. onlyOwner ≥ 0: só troca os pixels que hoje são desse dono (a borracha de um país não apaga o vizinho).
    /// Devolve quantos pixels mudaram.
    public int Dab(Vector3 n, double radiusKm, int owner, bool landOnly, int onlyOwner)
    {
        if (owner < 0 || owner > MaxOwner) throw new ArgumentException($"dono fora de 0..{MaxOwner}: {owner}");
        if (_stroke == null) Begin();
        _terrain!.DiskInto(n, radiusKm, _idx, _w);
        int changed = 0;
        foreach (int i in _idx)
        {
            int cur = Get(i);
            if (cur == owner || (onlyOwner >= 0 && cur != onlyOwner)) continue;
            if (owner != 0 && landOnly && _terrain.H[i] < 0f) continue;
            if (owner != 0 && !Allowed(i)) continue;
            _stroke!.TryAdd(i, (ushort)cur);
            Put(i, owner);
            changed++;
        }
        return changed;
    }

    /// Termina a pincelada: a edição com o que mudou, ou null se nada mudou.
    public TerritoryEdit? End()
    {
        var s = _stroke;
        _stroke = null;
        if (s == null || s.Count == 0) return null;
        var idx = new int[s.Count];
        var before = new ushort[s.Count];
        int k = 0;
        foreach (var (i, old) in s)
        {
            idx[k] = i;
            before[k++] = old;
        }
        Touch();
        return new TerritoryEdit(this, idx, before);
    }

    /// O balde: o dono `owner` passa a ocupar toda a região conectada (4 vizinhos, com a volta na longitude) de pixels do mesmo dono do pixel de n.
    /// landOnly: a região é só de terra, ou só de água, conforme o pixel clicado (clicar no mar com landOnly não faz nada). Devolve a edição, ou null.
    public TerritoryEdit? Fill(Vector3 n, int owner, bool landOnly)
    {
        if (owner < 0 || owner > MaxOwner) throw new ArgumentException($"dono fora de 0..{MaxOwner}: {owner}");
        var t = _terrain!;
        int start = t.PixelOf(n);
        int cur = Get(start);
        bool startLand = t.H[start] >= 0f;
        if (cur == owner || (owner != 0 && landOnly && !startLand) || (owner != 0 && !Allowed(start))) return null;
        var seen = new HashSet<int> { start };
        var stack = new Stack<int>();
        stack.Push(start);
        var changed = new List<int>();
        while (stack.Count > 0)
        {
            int p = stack.Pop();
            changed.Add(p);
            foreach (var (dx, dy) in new[] { (-1, 0), (1, 0), (0, -1), (0, 1) })
            {
                int q = t.Neighbor(p, dx, dy);
                if (q < 0 || seen.Contains(q) || Get(q) != cur) continue;
                if (landOnly && (t.H[q] >= 0f) != startLand) continue;
                if (owner != 0 && !Allowed(q)) continue;
                seen.Add(q);
                stack.Push(q);
            }
        }
        return Apply(changed, owner);
    }

    /// Apaga todo o território de um dono (vira 0). Devolve a edição (para desfazer), ou null se ele não tinha nada.
    public TerritoryEdit? ClearOwner(int owner)
    {
        var all = new List<int>();
        for (int i = 0; i < Size.X * Size.Y; i++)
            if (Get(i) == owner) all.Add(i);
        return Apply(all, 0);
    }

    /// Rascunho -> cadastro novo: os pixels de `draft` com dono `draftOwner` passam a ser de `owner` nesta camada (só onde a máscara do nível de cima
    /// deixa). Edição para desfazer, ou null se não sobrou nada.
    public TerritoryEdit? TakeFrom(Territory draft, int draftOwner, int owner)
    {
        if (owner < 1 || owner > MaxOwner) throw new ArgumentException($"dono fora de 1..{MaxOwner}: {owner}");
        if (draft.Size != Size) throw new ArgumentException("o rascunho tem outra grade");
        var all = new List<int>();
        for (int i = 0; i < Size.X * Size.Y; i++)
            if (draft.Get(i) == draftOwner && Allowed(i)) all.Add(i);
        return Apply(all, owner);
    }

    /// Onde o território de `owner` (nesta camada) cai sobre `other`: dono em `other` -> km² (0 = terra sem dono). Para sugerir a quem o rascunho pertence.
    public Godot.Collections.Dictionary OverlapKm2(Territory other, int owner)
    {
        var sums = new System.Collections.Generic.Dictionary<int, double>();
        int w = Size.X, h = Size.Y;
        for (int y = 0; y < h; y++)
        {
            double cell = RowCellKm2(y, w, h);
            for (int x = 0; x < w; x++)
            {
                int i = y * w + x;
                if (Get(i) != owner) continue;
                int o = other.Get(i);
                sums[o] = sums.GetValueOrDefault(o) + cell;
            }
        }
        var result = new Godot.Collections.Dictionary();
        foreach (var (o, km) in sums) result[o] = km;
        return result;
    }

    /// O centro de cada dono: dono -> [direção unitária (Vector3), área km², raio equivalente km]. Uma varredura só; para pôr o nome de cada área no globo.
    public Godot.Collections.Dictionary Centroids()
    {
        int w = Size.X, h = Size.Y;
        var sx = new System.Collections.Generic.Dictionary<int, Vector3>();
        var area = new System.Collections.Generic.Dictionary<int, double>();
        for (int y = 0; y < h; y++)
        {
            double lat = Math.PI * (0.5 - (y + 0.5) / h), cell = RowCellKm2(y, w, h), cl = Math.Cos(lat), sl = Math.Sin(lat);
            for (int x = 0; x < w; x++)
            {
                int o = Get(y * w + x);
                if (o == 0) continue;
                double lon = ((x + 0.5) / w - 0.5) * 2.0 * Math.PI;
                var v = new Vector3((float)(cl * Math.Sin(lon) * cell), (float)(sl * cell), (float)(cl * Math.Cos(lon) * cell));
                sx[o] = sx.GetValueOrDefault(o) + v;
                area[o] = area.GetValueOrDefault(o) + cell;
            }
        }
        var result = new Godot.Collections.Dictionary();
        foreach (var (o, sum) in sx)
            if (sum.Length() > 0.0f) result[o] = new Godot.Collections.Array { sum.Normalized(), area[o] };
        return result;
    }

    /// Unir: todo o território de `from` passa a ser de `to` (um gesto só para desfazer). Edição ou null se `from` não tinha nada.
    public TerritoryEdit? ReplaceOwner(int from, int to)
    {
        if (to < 0 || to > MaxOwner) throw new ArgumentException($"dono fora de 0..{MaxOwner}: {to}");
        if (from == 0 || from == to) return null;
        var all = new List<int>();
        for (int i = 0; i < Size.X * Size.Y; i++)
            if (Get(i) == from) all.Add(i);
        return Apply(all, to);
    }

    /// Apaga o território de vários donos numa passada só (apagar um por um varreria o mapa inteiro para cada um). Edição ou null.
    public TerritoryEdit? ClearOwners(int[] owners)
    {
        var set = new HashSet<int>(owners);
        var all = new List<int>();
        for (int i = 0; i < Size.X * Size.Y; i++)
            if (set.Contains(Get(i))) all.Add(i);
        return Apply(all, 0);
    }

    /// Vários donos de uma vez (pixel -> dono novo), numa edição só; null se nada muda.
    internal TerritoryEdit? Rewrite(System.Collections.Generic.Dictionary<int, int> owners)
    {
        var idx = new List<int>();
        var before = new List<ushort>();
        foreach (var (p, owner) in owners)
        {
            int cur = Get(p);
            if (cur == owner) continue;
            idx.Add(p);
            before.Add((ushort)cur);
            Put(p, owner);
        }
        if (idx.Count == 0) return null;
        Touch();
        return new TerritoryEdit(this, idx.ToArray(), before.ToArray());
    }

    private TerritoryEdit? Apply(List<int> pixels, int owner)
    {
        if (pixels.Count == 0) return null;
        var idx = pixels.ToArray();
        var before = new ushort[idx.Length];
        for (int k = 0; k < idx.Length; k++)
        {
            before[k] = (ushort)Get(idx[k]);
            Put(idx[k], owner);
        }
        Touch();
        return new TerritoryEdit(this, idx, before);
    }

    // ---- consulta ----

    /// Quantos pixels são do dono.
    public long Pixels(int owner)
    {
        long n = 0;
        for (int i = 0; i < Size.X * Size.Y; i++)
            if (Get(i) == owner) n++;
        return n;
    }

    /// A área do território do dono em km² (cada linha pesa pela largura real dos seus pixels: perto do polo eles são estreitos). Calculada para todos
    /// os donos de uma vez e guardada até a próxima edição.
    public double AreaKm2(int owner)
    {
        if (_areas == null || _areasVersion != Version)
        {
            var sum = new double[MaxOwner + 1];  // um vetor por dono: sem dicionário por linha (a varredura é feita a cada pincelada)
            int w = Size.X, h = Size.Y;
            for (int y = 0; y < h; y++)
            {
                double pixelArea = RowCellKm2(y, w, h);
                for (int i = y * w * 2, end = (y + 1) * w * 2; i < end; i += 2)
                {
                    int o = B[i] | (B[i + 1] << 8);
                    if (o != 0) sum[o] += pixelArea;
                }
            }
            var areas = new System.Collections.Generic.Dictionary<int, double>();
            for (int o = 1; o <= MaxOwner; o++)
                if (sum[o] > 0) areas[o] = sum[o];
            _areas = areas;
            _areasVersion = Version;
        }
        return _areas.GetValueOrDefault(owner);
    }

    /// A área de um pixel da linha y (km²): perto do polo os pixels são estreitos.
    public static double RowCellKm2(int y, int w, int h)
    {
        double top = Math.PI * (0.5 - (double)y / h), bottom = Math.PI * (0.5 - (double)(y + 1) / h);
        return EvronGeo.RadiusKm * EvronGeo.RadiusKm * (2 * Math.PI / w) * (Math.Sin(top) - Math.Sin(bottom));
    }

    // ---- persistência (quem grava é o Registry) ----

    /// Os donos comprimidos (deflate): a camada é quase toda zeros e áreas planas, e cabe em poucas centenas de KB.
    public byte[] Pack()
    {
        using var ms = new MemoryStream();
        using (var z = new DeflateStream(ms, CompressionLevel.Fastest, true)) z.Write(B, 0, B.Length);
        return ms.ToArray();
    }

    /// Restaura os donos de Pack(); recusa uma camada de outro tamanho (a grade da altitude mudou). Não cria edição: é uma abertura de arquivo.
    public bool Unpack(byte[] data, int w, int h) => Restore(data, w, h, null);

    internal bool Restore(byte[] data, int w, int h, byte[]? boundaries)
    {
        if (w != Size.X || h != Size.Y) return false;
        var bytes = new byte[B.Length];
        using (var z = new DeflateStream(new MemoryStream(data), CompressionMode.Decompress)) z.ReadExactly(bytes, 0, bytes.Length);
        RestoreBoundaries(boundaries);
        B = bytes;
        _rowTop = 0;
        _compTop = 0;
        _compBottom = Size.Y - 1;
        _rowBottom = Size.Y - 1;
        Dirty = true;
        Touch();
        return true;
    }
}
