using System;
using System.Collections.Generic;
using System.Linq;
using Godot;

namespace Evron;

/// A prévia de uma geração: as sugestões, o que sairia e o que fica. Nada muda no mundo até Registry.ApplyGeneration.
/// Cada sugestão pode ser tirada e devolvida antes de aplicar; as que ficam de fora viram supressões.
public partial class ResourcePlan : RefCounted
{
    /// Donos de mentira da prévia na camada: nenhuma ocorrência usa ids a partir daqui (Registry.AddArea).
    public const int PreviewBase = 60000;
    private const int PreviewRejected = 65000;

    internal ResourceRule Rule = new();
    internal List<Proposal> Proposals = new();
    internal long TypeId;
    internal string Signature = "";   // o estado das ocorrências e supressões quando a prévia foi feita
    internal long LayerVersion;
    internal HashSet<int> ReplacedAreas = new();
    internal List<long> Replaced = new();

    /// "" = a prévia vale; senão o motivo de não haver prévia.
    public string Error { get; internal set; } = "";
    public int Count => Proposals.Count;
    public int ReplacedCount => Replaced.Count;                    // geradas não fixadas que saem
    public int ProtectedCount { get; internal set; }               // manuais e fixadas, que ficam como estão
    public int SuppressedCount { get; internal set; }              // sugestões que o autor já tinha removido
    public bool IsArea => Rule.Output == "area";
    public bool Scored => Rule.Prefer.Length > 0;                  // a regra tem indícios: cada sugestão tem aptidão e motivos

    public int AcceptedCount() => Proposals.Count(p => !p.Rejected);

    public double AcceptedKm2() => Proposals.Where(p => !p.Rejected).Sum(p => p.Km2);

    public double AcceptedReserve() => Proposals.Where(p => !p.Rejected).Sum(p => p.Reserve);

    /// {lat, lon, km2, rejected, score, why}
    public Godot.Collections.Dictionary Proposal(int i)
    {
        var p = Proposals[i];
        return new Godot.Collections.Dictionary { ["lat"] = p.Lat, ["lon"] = p.Lon, ["km2"] = p.Km2, ["rejected"] = p.Rejected, ["score"] = p.Score, ["why"] = p.Why, ["reserve"] = p.Reserve };
    }

    public void Toggle(int i) => Proposals[i].Rejected = !Proposals[i].Rejected;

    /// Por que a sugestão i foi escolhida (ResourceGenerator.Explanation).
    public Godot.Collections.Dictionary Explain(int i) => ResourceGenerator.Explanation(Rule, Proposals[i].Matched, Proposals[i].Score);

    /// A sugestão em área que contém o pixel, ou -1.
    public int IndexAtPixel(int pixel) => Proposals.FindIndex(p => Array.IndexOf(p.Pixels, pixel) >= 0);

    /// A camada como ficaria: sem as áreas que saem, com as sugestões (as tiradas, em cinza).
    public Image PreviewImage(Territory layer)
    {
        var bytes = (byte[])layer.B.Clone();
        void Put(int p, int owner)
        {
            bytes[p * 2] = (byte)(owner & 255);
            bytes[p * 2 + 1] = (byte)(owner >> 8);
        }
        if (ReplacedAreas.Count > 0)
            for (int p = 0; p < bytes.Length / 2; p++)
                if (ReplacedAreas.Contains(layer.Get(p))) Put(p, 0);
        Paint(bytes, 0);
        return Image.CreateFromData(layer.Size.X, layer.Size.Y, false, Image.Format.Rg8, bytes);
    }

    /// Quantos recursos cabem pintados numa prévia conjunta (cada um ocupa uma faixa de donos de mentira).
    public const int CombinedLimit = (PreviewRejected - PreviewBase) / ResourceGenerator.MaxCount;

    /// As sugestões em área de VÁRIOS recursos numa imagem só, para a prévia conjunta. Onde duas se sobrepõem, a do último
    /// cobre a outra só na tela: cada recurso grava na própria camada. size: a grade do terreno.
    public static Image CombinedImage(Vector2I size, Godot.Collections.Array<ResourcePlan> plans)
    {
        var bytes = new byte[size.X * size.Y * 2];
        for (int k = 0; k < Math.Min(plans.Count, CombinedLimit); k++) plans[k].Paint(bytes, k * ResourceGenerator.MaxCount);
        return Image.CreateFromData(size.X, size.Y, false, Image.Format.Rg8, bytes);
    }

    private void Paint(byte[] bytes, int offset)
    {
        for (int i = 0; i < Proposals.Count; i++)
        {
            int owner = Proposals[i].Rejected ? PreviewRejected : PreviewBase + offset + i;
            foreach (int p in Proposals[i].Pixels)
            {
                bytes[p * 2] = (byte)(owner & 255);
                bytes[p * 2 + 1] = (byte)(owner >> 8);
            }
        }
    }

    /// As cores dos donos de mentira: [{id, rgb, top}]. position: o lugar do recurso na prévia conjunta (0 numa prévia só).
    public Godot.Collections.Array<Godot.Collections.Dictionary> PreviewPalette(long rgb, long position)
    {
        var entries = new Godot.Collections.Array<Godot.Collections.Dictionary>();
        for (int i = 0; i < Proposals.Count; i++)
        {
            long id = PreviewBase + position * ResourceGenerator.MaxCount + i;
            entries.Add(new Godot.Collections.Dictionary { ["id"] = id, ["rgb"] = rgb, ["top"] = id });
        }
        entries.Add(new Godot.Collections.Dictionary { ["id"] = PreviewRejected, ["rgb"] = 0x707070, ["top"] = PreviewRejected });
        return entries;
    }
}
