using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using Godot;

namespace Evron;

/// Camadas que dependem de outras: a máscara (pintar uma província só dentro do seu país), a composição para a tela (as províncias
/// por cima dos países, os países onde não há província) e o contorno fechado em terra sem dono (o mundo começa vazio).
public partial class Territory
{
    private Territory? _maskLayer;
    private int _maskOwner;
    private byte[]? _compBytes;
    private Image? _compImg;
    private ulong[] _compKey = System.Array.Empty<ulong>();  // as camadas de baixo da última composição (mudou = refaz tudo)
    internal int _compTop = 0, _compBottom = int.MaxValue;   // faixa de linhas mexidas desde a última composição que usou esta camada

    /// Pintar (pincel, balde, contorno) só onde `layer` é do dono `owner`; null tira a máscara. Apagar não tem máscara.
    public void SetMask(Territory? layer, int owner)
    {
        _maskLayer = layer;
        _maskOwner = owner;
    }

    private bool Allowed(int i) => _maskLayer == null || _maskLayer.Get(i) == _maskOwner;

    /// A camada como a tela mostra: onde esta não tem dono, vale a primeira de `below` que tem (a mais próxima primeiro).
    /// Sem camadas embaixo, é OwnersImage(). A mesma imagem é reaproveitada.
    public Image Composite(Godot.Collections.Array below)
    {
        if (below.Count == 0) return OwnersImage();
        var layers = below.Select(v => v.As<Territory>()).ToArray();
        var key = layers.Select(l => l.GetInstanceId()).ToArray();
        int top = _compTop, bottom = _compBottom;
        foreach (var l in layers)
        {
            top = Math.Min(top, l._compTop);
            bottom = Math.Max(bottom, l._compBottom);
        }
        if (_compBytes == null || _compImg == null || !key.SequenceEqual(_compKey))
        {
            (top, bottom) = (0, Size.Y - 1);  // primeira vez ou outras camadas embaixo: tudo
            _compBytes = new byte[B.Length];
            _compKey = key;
        }
        bottom = Math.Min(bottom, Size.Y - 1);
        if (bottom >= top)
        {
            // Só as linhas mexidas desde a última vez (a composição inteira leva ~0,1 s: durante a pincelada travaria o quadro).
            int from = top * Size.X * 2, to = (bottom + 1) * Size.X * 2;
            Compose(B, layers, _compBytes, from, to);
            if (_compImg == null)
                _compImg = Image.CreateFromData(Size.X, Size.Y, false, Image.Format.Rg8, _compBytes);
            else
            {
                var band = new byte[to - from];
                Buffer.BlockCopy(_compBytes, from, band, 0, band.Length);
                _compImg.BlitRect(Image.CreateFromData(Size.X, bottom - top + 1, false, Image.Format.Rg8, band),
                    new Rect2I(0, 0, Size.X, bottom - top + 1), new Vector2I(0, top));
            }
        }
        foreach (var l in layers.Append(this)) (l._compTop, l._compBottom) = (int.MaxValue, -1);
        return _compImg!;
    }

    /// A prévia de um plano (como PreviewImage) já composta sobre as camadas de baixo.
    public Image PreviewImageOver(TerritoryBoundaryPlan plan, Godot.Collections.Array below)
    {
        var top = PreviewImage(plan).GetData();
        var bytes = new byte[top.Length];
        Compose(top, below.Select(v => v.As<Territory>()).ToArray(), bytes, 0, top.Length);
        return Image.CreateFromData(Size.X, Size.Y, false, Image.Format.Rg8, bytes);
    }

    private static void Compose(byte[] top, Territory[] layers, byte[] into, int from, int to)
    {
        for (int i = from; i < to; i += 2)
        {
            byte lo = top[i], hi = top[i + 1];
            for (int k = 0; (lo | hi) == 0 && k < layers.Length; k++)
            {
                lo = layers[k].B[i];
                hi = layers[k].B[i + 1];
            }
            into[i] = lo;
            into[i + 1] = hi;
        }
    }

    /// Contorno fechado: o que fica DENTRO do traço (fechado do último ponto de volta ao primeiro) e não tem dono passa para `target`.
    /// "Dentro" = tudo o que não é a maior região do lado de fora. landOnly: só terra. Para remodelar, id é o de um contorno já
    /// aplicado (Source 0). Devolve {plan} ou {message}, como PlanBoundaryClaim.
    public Godot.Collections.Dictionary PlanLoopClaim(int target, Vector3[] controls, int id, bool landOnly)
    {
        if (_stroke != null || !ValidOwner(target)) return RefuseBoundary("Selecione no mapa quem recebe a área.");
        if (controls.Length < 3) return RefuseBoundary("Desenhe um contorno com pelo menos três pontos.");
        if (!controls[^1].IsEqualApprox(controls[0])) controls = controls.Append(controls[0]).ToArray();
        if (!ValidBoundaryPoints(controls)) return RefuseBoundary("Desenhe uma linha contínua com pontos distintos.");

        _boundaries.TryGetValue(id, out var previous);
        if (id != 0 && (previous == null || previous.Target != target || previous.Source != 0))
            return RefuseBoundary("Este contorno não pertence ao selecionado.");
        int length = Size.X * Size.Y;
        BitArray? restored = null;
        if (previous != null)
        {
            restored = new BitArray(length);
            foreach (int p in previous.Pixels)
            {
                if (Get(p) != previous.Target)
                    return RefuseBoundary("Parte deste contorno foi repintada. Desfaça a pintura antes de remodelar o traço.");
                restored[p] = true;
            }
        }
        int OwnerBefore(int p) => restored != null && restored[p] ? 0 : Get(p);

        var edges = RasterizeBoundary(SmoothBoundary(controls));
        var labels = new int[length];
        var sizes = new List<double> { 0 };
        var stack = new Stack<int>();
        var terrain = _terrain!;
        for (int start = 0; start < length; start++)
        {
            if (labels[start] != 0) continue;
            int label = sizes.Count;
            double area = 0;
            labels[start] = label;
            stack.Push(start);
            while (stack.Count > 0)
            {
                int p = stack.Pop();
                area += RowCellKm2(p / Size.X, Size.X, Size.Y);
                foreach (var (x, y) in BoundaryNeighbors)
                {
                    int q = terrain.Neighbor(p, x, y);
                    if (q < 0 || labels[q] != 0 || edges.Contains(BoundaryEdge(p, q))) continue;
                    labels[q] = label;
                    stack.Push(q);
                }
            }
            sizes.Add(area);
        }
        if (sizes.Count <= 2) return RefuseBoundary("O traço não fechou uma área. Termine perto de onde começou.");
        int outside = sizes.IndexOf(sizes.Max());
        var region = new List<int>();
        for (int p = 0; p < length; p++)
            if (labels[p] != outside && OwnerBefore(p) == 0 && Allowed(p) && (!landOnly || terrain.H[p] >= 0f)) region.Add(p);
        if (region.Count == 0) return RefuseBoundary("Dentro do contorno não há terra sem dono (nem dentro do limite permitido).");

        var pixels = region.ToArray();
        var plan = new TerritoryBoundaryPlan
        {
            Map = this,
            Version = Version,
            Previous = previous,
            Choices = new[] { pixels },
            Next = new TerritoryBoundary(id == 0 ? _nextBoundary : id, 0, target, controls, pixels),
        };
        return new Godot.Collections.Dictionary { ["plan"] = plan };
    }
}
