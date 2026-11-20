using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Evron;

/// O mundo como pasta portátil (especificação 8.4, aceite 12): Evron.world/ com world.sqlite, clock.json (o relógio) e manifest.json
/// (formato, versão do esquema, data e o SHA-256 de cada arquivo). Exportar copia o banco com VACUUM INTO (cópia consistente com o banco
/// aberto); cada arquivo é escrito como .tmp e só então renomeado. Importar verifica tudo ANTES de trocar o banco do usuário e guarda o
/// banco anterior ao lado. O conteúdo importado não é confiável: nada nele é executado, e um esquema mais novo é recusado.
public partial class Registry
{
    public const string WorldFormat = "evron.world";
    public const int WorldFormatVersion = 1;

    /// Exporta o mundo aberto para a pasta dir (criada se faltar). clockPath: o salvamento do relógio ("" ou inexistente = sem relógio).
    /// Devolve "" se deu certo, senão o motivo.
    public string ExportWorld(string dir, string clockPath)
    {
        try
        {
            Directory.CreateDirectory(dir);
            var files = new JsonObject();
            string db = Path.Combine(dir, "world.sqlite");
            File.Delete(db + ".tmp");
            _db.Run("vacuum into @0", db + ".tmp");
            files["world.sqlite"] = Describe(db + ".tmp");
            if (clockPath != "" && File.Exists(clockPath))
            {
                File.Copy(clockPath, Path.Combine(dir, "clock.json.tmp"), true);
                files["clock.json"] = Describe(Path.Combine(dir, "clock.json.tmp"));
            }
            var manifest = new JsonObject
            {
                ["format"] = WorldFormat,
                ["format_version"] = WorldFormatVersion,
                ["schema_version"] = _db.SchemaVersion(),
                ["exported_at"] = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
                ["files"] = files,
            };
            File.WriteAllText(Path.Combine(dir, "manifest.json.tmp"), manifest.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            foreach (var name in new[] { "world.sqlite", "clock.json", "manifest.json" })  // o manifesto por último: sem ele a pasta não vale
                if (File.Exists(Path.Combine(dir, name + ".tmp")))
                    File.Move(Path.Combine(dir, name + ".tmp"), Path.Combine(dir, name), true);
            return "";
        }
        catch (Exception e)
        {
            return "não consegui exportar: " + e.Message;
        }
    }

    /// Confere uma pasta exportada sem mudar nada: manifesto, formato, hashes, integridade do SQLite e versão do esquema.
    /// Devolve "" se pode ser importada, senão o motivo.
    public string CheckWorld(string dir)
    {
        try
        {
            string manifestPath = Path.Combine(dir, "manifest.json");
            if (!File.Exists(manifestPath)) return "a pasta não tem manifest.json";
            var manifest = JsonNode.Parse(File.ReadAllText(manifestPath)) as JsonObject;
            if (manifest == null || (string?)manifest["format"] != WorldFormat) return "não é um mundo do Evron";
            if ((int?)manifest["format_version"] is not int fv || fv > WorldFormatVersion) return "formato de uma versão mais nova do Evron";
            if (manifest["files"] is not JsonObject files || files["world.sqlite"] == null) return "o manifesto não lista o world.sqlite";
            foreach (var (name, info) in files)
            {
                if (name != "world.sqlite" && name != "clock.json") return $"arquivo inesperado no manifesto: {name}";
                string path = Path.Combine(dir, name);
                if (!File.Exists(path)) return $"falta {name}";
                if (Sha256(path) != (string?)info?["sha256"]) return $"{name} não confere com o manifesto (arquivo alterado ou corrompido)";
            }
            var check = new WorldDb();
            check.Open(Path.Combine(dir, "world.sqlite"));
            try
            {
                if (check.QueryText("PRAGMA integrity_check") != "ok") return "o banco está corrompido";
                if (check.SchemaVersion() > Migrations.Length) return "o banco é de uma versão mais nova do Evron";
            }
            finally { check.Close(); }
            return "";
        }
        catch (Exception e)
        {
            return "não consegui ler a pasta: " + e.Message;
        }
    }

    /// Troca o banco (dbPath) e o relógio (clockPath) do usuário pelos da pasta, depois de CheckWorld. O banco e o relógio anteriores
    /// ficam ao lado com o sufixo .antes-importacao. Este Registry não pode estar com dbPath aberto. Devolve "" ou o motivo.
    public string ImportWorld(string dir, string dbPath, string clockPath)
    {
        string why = CheckWorld(dir);
        if (why != "") return why;
        try
        {
            File.Copy(Path.Combine(dir, "world.sqlite"), dbPath + ".tmp", true);
            if (File.Exists(dbPath)) File.Copy(dbPath, dbPath + ".antes-importacao", true);
            File.Move(dbPath + ".tmp", dbPath, true);
            File.Delete(dbPath + "-journal");
            string clock = Path.Combine(dir, "clock.json");
            if (clockPath != "" && File.Exists(clock))
            {
                if (File.Exists(clockPath)) File.Copy(clockPath, clockPath + ".antes-importacao", true);
                File.Copy(clock, clockPath, true);
            }
            return "";
        }
        catch (Exception e)
        {
            return "não consegui importar: " + e.Message;
        }
    }

    static JsonObject Describe(string path) => new() { ["bytes"] = new FileInfo(path).Length, ["sha256"] = Sha256(path) };

    static string Sha256(string path)
    {
        using var f = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(f)).ToLowerInvariant();
    }
}
