using System;
using System.Linq;
using Godot;
using Godot.Collections;

namespace Evron;

/// A camada política no banco e a cor de cada país. A camada (o dono de cada pixel, ver Territory) fica numa linha só, comprimida; a cor é uma
/// coluna do cadastro (RGB de 24 bits) e, se o autor não escolheu, sai do id por um passo de matiz áureo: países vizinhos tendem a cores bem diferentes.
public partial class Registry
{
    const string TerritoryMigration = """
        create table territory(
            id integer primary key check (id = 1),
            w integer not null,
            h integer not null,
            data blob not null,
            saved_at integer not null default (unixepoch()));
        alter table entity add column color integer;
        """;

    const string TerritoryBoundaryMigration = "alter table territory add column boundaries blob";

    /// Grava a camada política (substitui a anterior). Devolve o tamanho gravado, em bytes.
    public long SaveTerritory(Territory t)
    {
        var data = t.Pack();
        _db.Run("insert into territory(id, w, h, data, boundaries, saved_at) values (1, @0, @1, @2, @3, unixepoch()) " +
                "on conflict(id) do update set w = @0, h = @1, data = @2, boundaries = @3, saved_at = unixepoch()",
                t.Size.X, t.Size.Y, data, t.PackBoundaries());
        return data.Length;
    }

    /// Lê a camada política gravada para o Territory. false se não há nenhuma (começa vazio) ou se é de outra grade (não é aplicada).
    public bool LoadTerritory(Territory t)
    {
        var r = _db.Rows("select w, h, data, boundaries from territory where id = 1");
        if (r.Count == 0) return false;
        return t.Restore((byte[])r[0][2]!, Convert.ToInt32(r[0][0]), Convert.ToInt32(r[0][1]), (byte[]?)r[0][3]);
    }

    /// A cor do cadastro (RGB de 24 bits): a escolhida ou a automática.
    public long EntityColor(long id)
    {
        var r = _db.Rows("select color from entity where id = @0", id);
        if (r.Count == 0) throw new ArgumentException($"entidade {id} não existe");
        return r[0][0] != null ? Convert.ToInt64(r[0][0]) : DefaultColor(id);
    }

    /// Escolhe a cor (RGB de 24 bits, 0 a 16777215).
    public void SetEntityColor(long id, long rgb)
    {
        if (rgb < 0 || rgb > 0xFFFFFF) throw new ArgumentException($"cor fora de 0..16777215: {rgb}");
        if (_db.Run("update entity set color = @0 where id = @1", rgb, id) == 0) throw new ArgumentException($"entidade {id} não existe");
    }

    static long DefaultColor(long id)
    {
        double hue = (id * 0.6180339887498949) % 1.0;
        var c = Color.FromHsv((float)hue, 0.45f, 0.92f);
        return ((long)Math.Round(c.R * 255) << 16) | ((long)Math.Round(c.G * 255) << 8) | (long)Math.Round(c.B * 255);
    }

    /// A paleta da camada política: id e cor (RGB) de cada país que pode ter território (id até 65535).
    public Array<Dictionary> CountryPalette() => new(
        _db.Rows("select id, color from entity where kind = 'pais' and id <= 65535 order by id")
           .Select(r => new Dictionary { ["id"] = Convert.ToInt64(r[0]), ["rgb"] = r[1] != null ? Convert.ToInt64(r[1]) : DefaultColor(Convert.ToInt64(r[0])) }));
}
