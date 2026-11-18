using System;
using System.Linq;
using Godot;
using Godot.Collections;

namespace Evron;

/// Fronteiras desenhadas à mão: um lugar pode ser um CONTORNO (polígono de vértices lat/lon unidos por arcos de círculo máximo), além de ponto
/// e disco. O contorno é validado (3 a 2000 pontos, sem lados que se cruzem, com área, a menos de 85° do centro) e guarda o centro em
/// place.lat/lon (onde fica o rótulo) com radius_km = 0. Quem tem vértices é contorno, aconteça o que acontecer com o raio.
public partial class Registry
{
    const string BordersMigration = """
        create table place_vertex(
            place_id integer not null references place(id),
            seq integer not null,
            lat real not null check (lat >= -90 and lat <= 90),
            lon real not null check (lon >= -180 and lon <= 180),
            primary key (place_id, seq));
        """;

    /// Cria um lugar com contorno. latLon: lat0, lon0, lat1, lon1, ... em graus (o último ponto não precisa repetir o primeiro).
    /// Recusa menos de 3 pontos, pontos repetidos em sequência, lados que se cruzam, contorno sem área ou grande demais.
    public long AddPolygonPlace(string name, string kind, double[] latLon, string note)
    {
        var poly = PlaceGeometry.Validate(latLon);
        var (lat, lon) = poly.Center.ToLatLon();
        return _db.Tx(() =>
        {
            long id = _db.Insert("insert into place(name, kind, lat, lon, radius_km, note) values (@0, @1, @2, @3, 0, @4)", Clean(name), kind, lat, lon, note == "" ? null : note);
            InsertVertices(id, poly);
            return id;
        });
    }

    /// Troca o contorno de um lugar (ou transforma um ponto ou disco em contorno). Devolve 1 se trocou; a validação é a de AddPolygonPlace.
    public long SetPlaceVertices(long placeId, double[] latLon)
    {
        var poly = PlaceGeometry.Validate(latLon);
        var (lat, lon) = poly.Center.ToLatLon();
        return _db.Tx(() =>
        {
            if (_db.Run("update place set lat = @0, lon = @1, radius_km = 0 where id = @2", lat, lon, placeId) == 0) throw new ArgumentException($"lugar {placeId} não existe");
            _db.Run("delete from place_vertex where place_id = @0", placeId);
            InsertVertices(placeId, poly);
            return 1L;
        });
    }

    void InsertVertices(long placeId, Polygon poly)
    {
        for (int i = 0; i < poly.LatLon.Length / 2; i++)
            _db.Run("insert into place_vertex(place_id, seq, lat, lon) values (@0, @1, @2, @3)", placeId, i, poly.LatLon[2 * i], poly.LatLon[2 * i + 1]);
    }

    /// Os vértices do contorno (lat0, lon0, lat1, lon1, ...), ou vazio se o lugar é ponto ou disco.
    public double[] PlaceVertices(long placeId) =>
        _db.Rows("select lat, lon from place_vertex where place_id = @0 order by seq", placeId).SelectMany(r => new[] { Convert.ToDouble(r[0]), Convert.ToDouble(r[1]) }).ToArray();

    /// A área do lugar em km²: a do contorno, a do disco ou 0 (ponto).
    public double PlaceAreaKm2(long placeId)
    {
        var v = PlaceVertices(placeId);
        if (v.Length >= 6) return PlaceGeometry.AreaKm2(PlaceGeometry.ToVecs(v));
        double r = Convert.ToDouble(Place(placeId)["radius_km"].AsDouble());
        return r > 0 ? 2 * Math.PI * PlaceGeometry.R * PlaceGeometry.R * (1 - Math.Cos(r / PlaceGeometry.R)) : 0;
    }
}
