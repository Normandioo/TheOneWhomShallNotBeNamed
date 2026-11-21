using System;
using Godot;

namespace Evron;

public partial class Registry
{
    private const string TerrainTilesMigration = """
        create table terrain_tile(
            tile integer primary key,
            w integer not null,
            h integer not null,
            data blob not null
        );
        """;

    public bool SaveTerrain(Terrain terrain)
    {
        if (terrain.EditedTiles.Count == 0) return true;
        try
        {
            _db.Tx(() =>
            {
                foreach (int tile in terrain.EditedTiles)
                    _db.Run("insert into terrain_tile(tile, w, h, data) values (@0, @1, @2, @3) " +
                        "on conflict(tile) do update set w = @1, h = @2, data = @3",
                        tile, terrain.Size.X, terrain.Size.Y, terrain.PackEditedTile(tile));
                return true;
            });
            terrain.EditedTiles.Clear();
            return true;
        }
        catch (Exception err)
        {
            GD.PushError($"Não consegui gravar o relevo: {err.Message}");
            return false;
        }
    }

    public bool LoadTerrain(Terrain terrain)
    {
        try
        {
            var rows = _db.Rows("select tile, w, h, data from terrain_tile");
            foreach (var row in rows)
            {
                int tile = Convert.ToInt32(row[0]);
                if (Convert.ToInt32(row[1]) != terrain.Size.X || Convert.ToInt32(row[2]) != terrain.Size.Y ||
                    row[3] is not byte[] data || !terrain.ValidEditedTile(tile, data))
                    throw new InvalidOperationException("bloco de relevo inválido ou de outra grade");
            }
            foreach (var row in rows)
                terrain.RestoreEditedTile(Convert.ToInt32(row[0]), (byte[])row[3]!);
            return true;
        }
        catch (Exception err)
        {
            GD.PushError($"Não consegui carregar o relevo: {err.Message}");
            return false;
        }
    }
}
