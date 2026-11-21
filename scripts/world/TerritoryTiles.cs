using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using Godot;

namespace Evron;

/// A camada em mosaicos (tiles) de 512 × 512 pixels para gravar (especificação 17.1): cada tile mexido é marcado e só ele é regravado;
/// tile todo sem dono não é gravado. Na memória a camada continua uma grade só (as ferramentas trabalham por índice de pixel).
/// shortcut: a textura do globo ainda é enviada inteira à GPU (o Godot não atualiza um pedaço de Texture2D); se pesar, passar a um
/// Texture2DArray por tile.
public partial class Territory
{
    public const int TileSize = 512;

    private bool[] _dirtyTiles = Array.Empty<bool>();
    internal string? SyncedKey;  // com que banco e nível os tiles gravados batem com esta camada (null = gravar tudo de novo)

    public int TilesX => (Size.X + TileSize - 1) / TileSize;
    public int TilesY => (Size.Y + TileSize - 1) / TileSize;

    private void ResetTiles()
    {
        _dirtyTiles = new bool[TilesX * TilesY];
        SyncedKey = null;
    }

    private void MarkTile(int idx) => _dirtyTiles[(idx / Size.X / TileSize) * TilesX + (idx % Size.X) / TileSize] = true;

    /// Quantos tiles mudaram desde a última gravação.
    public int DirtyTileCount()
    {
        int n = 0;
        foreach (bool d in _dirtyTiles) if (d) n++;
        return n;
    }

    internal IEnumerable<(int Tx, int Ty)> Tiles(bool onlyDirty)
    {
        for (int ty = 0; ty < TilesY; ty++)
            for (int tx = 0; tx < TilesX; tx++)
                if (!onlyDirty || _dirtyTiles[ty * TilesX + tx]) yield return (tx, ty);
    }

    internal void ClearDirtyTiles() => Array.Clear(_dirtyTiles);

    private (int X0, int Y0, int W, int H) TileRect(int tx, int ty) =>
        (tx * TileSize, ty * TileSize, Math.Min(TileSize, Size.X - tx * TileSize), Math.Min(TileSize, Size.Y - ty * TileSize));

    /// O tile comprimido (deflate), ou null se ele não tem nenhum dono.
    internal byte[]? PackTile(int tx, int ty)
    {
        var (x0, y0, w, h) = TileRect(tx, ty);
        var raw = new byte[w * h * 2];
        bool any = false;
        for (int y = 0; y < h; y++)
            Buffer.BlockCopy(B, ((y0 + y) * Size.X + x0) * 2, raw, y * w * 2, w * 2);
        foreach (byte b in raw) if (b != 0) { any = true; break; }
        if (!any) return null;
        using var ms = new MemoryStream();
        using (var z = new DeflateStream(ms, CompressionLevel.Fastest, true)) z.Write(raw, 0, raw.Length);
        return ms.ToArray();
    }

    /// Monta a camada a partir dos tiles gravados (os que faltam são sem dono). Recusa outra grade. Não cria edição.
    internal bool RestoreTiles(int w, int h, IEnumerable<(int Tx, int Ty, byte[] Data)> tiles, byte[]? boundaries)
    {
        if (w != Size.X || h != Size.Y) return false;
        var bytes = new byte[B.Length];
        foreach (var (tx, ty, data) in tiles)
        {
            if (tx < 0 || ty < 0 || tx >= TilesX || ty >= TilesY) throw new InvalidDataException($"tile fora da grade: {tx},{ty}");
            var (x0, y0, tw, th) = TileRect(tx, ty);
            var raw = new byte[tw * th * 2];
            using (var z = new DeflateStream(new MemoryStream(data), CompressionMode.Decompress)) z.ReadExactly(raw, 0, raw.Length);
            for (int y = 0; y < th; y++)
                Buffer.BlockCopy(raw, y * tw * 2, bytes, ((y0 + y) * Size.X + x0) * 2, tw * 2);
        }
        RestoreBoundaries(boundaries);
        B = bytes;
        _rowTop = 0;
        _compTop = 0;
        _compBottom = Size.Y - 1;
        _rowBottom = Size.Y - 1;
        Dirty = true;
        Touch();
        ClearDirtyTiles();
        return true;
    }
}
