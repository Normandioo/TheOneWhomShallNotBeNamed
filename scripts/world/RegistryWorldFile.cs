using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Evron;

/// O mundo como pasta portátil (especificação 8.4, aceite 12): Evron.world/ com world.sqlite, clock.json (o relógio) e manifest.json
/// (formato, versão do esquema, data e o SHA-256 de cada arquivo). Exportar copia o banco com VACUUM INTO (cópia consistente com o banco
/// aberto); o export é montado em uma pasta temporária e publicado com uma única renomeação. Importar verifica tudo ANTES de trocar o banco do usuário e guarda o
/// banco anterior ao lado. O conteúdo importado não é confiável: nada nele é executado, e um esquema mais novo é recusado.
public partial class Registry
{
    public const string WorldFormat = "evron.world";
    public const int WorldFormatVersion = 1;

    /// Exporta o mundo aberto para a pasta dir (criada se faltar). clockPath: o salvamento do relógio ("" ou inexistente = sem relógio).
    /// Devolve "" se deu certo, senão o motivo.
    public string ExportWorld(string dir, string clockPath)
    {
        string? staging = null;
        try
        {
            dir = Path.TrimEndingDirectorySeparator(Path.GetFullPath(dir));
            if (Directory.Exists(dir) || File.Exists(dir))
                return "já existe uma exportação nesse caminho";
            staging = dir + ".tmp-" + Guid.NewGuid().ToString("N");
            Directory.CreateDirectory(staging);
            string db = Path.Combine(staging, "world.sqlite");
            _db.Run("vacuum into @0", db);
            var files = new JsonObject { ["world.sqlite"] = Describe(db) };
            if (clockPath != "" && File.Exists(clockPath))
            {
                string clock = Path.Combine(staging, "clock.json");
                File.Copy(clockPath, clock);
                files["clock.json"] = Describe(clock);
            }
            var manifest = new JsonObject
            {
                ["format"] = WorldFormat,
                ["format_version"] = WorldFormatVersion,
                ["schema_version"] = _db.SchemaVersion(),
                ["exported_at"] = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
                ["files"] = files,
            };
            File.WriteAllText(Path.Combine(staging, "manifest.json"), manifest.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            Directory.Move(staging, dir);
            return "";
        }
        catch (Exception e)
        {
            return "não consegui exportar: " + e.Message;
        }
        finally
        {
            if (staging != null && Directory.Exists(staging))
            {
                try
                {
                    foreach (var file in new[] { "world.sqlite", "clock.json", "manifest.json" })
                        File.Delete(Path.Combine(staging, file));
                    Directory.Delete(staging);
                }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
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
            if (File.Exists(Path.Combine(dir, "clock.json")) && !files.ContainsKey("clock.json"))
                return "clock.json existe, mas não está listado no manifesto";
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
        var changes = new List<(string Destination, string? Stage, string Backup, bool Existed)>();
        var installed = new Stack<(string Destination, string Backup, bool Existed)>();
        string suffix = ".evron-import-" + Guid.NewGuid().ToString("N");
        try
        {
            var manifest = JsonNode.Parse(File.ReadAllText(Path.Combine(dir, "manifest.json")))!;
            var files = manifest["files"]!.AsObject();
            void Stage(string destination, string? name)
            {
                if (Directory.Exists(destination)) throw new IOException("O destino é uma pasta: " + destination);
                string? staged = name == null ? null : destination + suffix;
                string backup = destination + ".antes-importacao";
                bool existed = File.Exists(destination);
                changes.Add((destination, staged, backup, existed));
                if (staged != null)
                {
                    File.Copy(Path.Combine(dir, name!), staged);
                    if (Sha256(staged) != (string?)files[name!]!["sha256"])
                        throw new IOException(name + " mudou durante a importação");
                }
                if (existed) File.Copy(destination, backup, true);
            }
            Stage(dbPath + "-journal", null);
            Stage(dbPath, "world.sqlite");
            if (clockPath != "")
            {
                Stage(clockPath, files.ContainsKey("clock.json") ? "clock.json" : null);
                Stage(clockPath + ".bak", null);
            }
            foreach (var change in changes)
            {
                if (change.Stage == null) File.Delete(change.Destination);
                else File.Move(change.Stage, change.Destination, true);
                installed.Push((change.Destination, change.Backup, change.Existed));
            }
            return "";
        }
        catch (Exception e)
        {
            string restoreError = "";
            while (installed.TryPop(out var change))
            {
                try
                {
                    if (change.Existed) File.Copy(change.Backup, change.Destination, true);
                    else File.Delete(change.Destination);
                }
                catch (Exception rollback) { restoreError += " Falha ao restaurar: " + rollback.Message; }
            }
            return "não consegui importar: " + e.Message + restoreError;
        }
        finally
        {
            foreach (var change in changes)
                if (change.Stage != null)
                    try { File.Delete(change.Stage); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }

    static JsonObject Describe(string path) => new() { ["bytes"] = new FileInfo(path).Length, ["sha256"] = Sha256(path) };

    static string Sha256(string path)
    {
        using var f = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(f)).ToLowerInvariant();
    }
}
