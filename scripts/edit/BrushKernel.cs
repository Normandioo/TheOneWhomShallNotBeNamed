using System;
using System.Collections.Generic;
using Godot;

namespace Evron;

/// O trabalho pixel a pixel do pincel de terreno (terrain_brush.gd decide o quê e quando; aqui se faz).
/// Uma pincelada: Begin, uma ou mais Dab, End. Guarda a altura original de cada pixel na primeira vez que o mexe e,
/// no End, devolve uma TerrainEdit com o antes e o depois só desses pixels.
/// Os modos e a física estão descritos em terrain_brush.gd e em docs/arquitetura.md.
public partial class BrushKernel : RefCounted
{
    // Mesma ordem do enum Op de terrain_brush.gd (o C# não expõe enums ao GDScript).
    private enum Op { Raise, Lower, Flatten, Smooth, Mountains, Erode, Valleys, Land, Sea }

    /// Costa: a terra nova fica a LandM do nível do mar e o mar novo a SeaM; só o miolo do pincel (peso ≥ 0,5) muda, então a costa
    /// nova é nítida e não sobra meio-termo. O que já é terra (ou mar) não muda de altura.
    public const float LandM = 5f, SeaM = -50f;

    private const double Incision = 0.02;     // vales: fração do desnível entalhada por passada, por raiz da captação
    private const double RiverShare = 0.008;  // vales: vira rio quem recebe a água de 0,8% da região pintada...
    private const double RiverMin = 12.0;     // ...e no mínimo de 12 pixels
    private const double TalusM = 150.0;      // erosão: desnível entre pixels vizinhos (9,8 km) que ainda se sustenta
    private const float SeaCeiling = -1f;     // vales: o sedimento não levanta o mar acima disto (não cria ilha)

    private Terrain _t = null!;
    private readonly TerrainNoise _noise = new();
    private readonly Dictionary<int, float> _before = new();
    private readonly Dictionary<int, byte> _beforeR = new();
    private readonly Dictionary<int, float> _strokeW = new();  // vales: maior peso do pincel por pixel na pincelada
    private Dictionary<int, double> _lastFlow = new();
    private readonly List<int> _idx = new();
    private readonly List<float> _w = new();

    public void Setup(Terrain terrain) => _t = terrain;

    public void Begin(long seed)
    {
        _before.Clear();
        _beforeR.Clear();
        _strokeW.Clear();
        _noise.SetSeed((int)seed);
    }

    /// Uma marca do pincel em n. op = terrain_brush.gd Op; target = altura do início (nivelar);
    /// mountainGain e mountainCap: as constantes de Montanhas (terrain_brush.gd).
    /// Tudo em double, como o GDScript passa: em float, 0,3 viraria 0,30000001 e o relevo sairia diferente.
    public void Dab(int op, Vector3 n, double radiusKm, double strength, double roughness, double target,
        double mountainGain, double mountainCap)
    {
        _t.DiskInto(n, radiusKm, _idx, _w);
        switch ((Op)op)
        {
            case Op.Erode:
                for (int pass = 0; pass < 3; pass++)  // 3 passadas por marca: o material escorre mais de um pixel
                    ErodePass(strength);
                return;
            case Op.Valleys:
                Valleys(strength);
                return;
        }
        double k = Math.Clamp(strength / 500.0, 0.02, 1.0);
        float[]? means = null;  // float, como o PackedFloat32Array do GDScript de origem
        if ((Op)op == Op.Smooth)  // médias lidas antes de mexer, senão o resultado depende da ordem dos pixels
        {
            means = new float[_idx.Count];
            for (int i = 0; i < _idx.Count; i++)
                means[i] = (float)_t.NeighborMean(_idx[i]);
        }
        double ridgePower = Mathf.Lerp(1.4, 3.0, roughness);  // montanhas: maciço arredondado -> cristas finas
        for (int i = 0; i < _idx.Count; i++)
        {
            int p = _idx[i];
            double w = _w[i];
            double h = _t.H[p];
            Remember(p);
            switch ((Op)op)
            {
                case Op.Raise:
                    h += strength * w * HillShape(p, roughness);
                    break;
                case Op.Lower:
                    h -= strength * w * HillShape(p, roughness);
                    break;
                case Op.Flatten:
                    double goal = target + (_noise.Fbm(_t.DirOf(p)) - 0.5) * roughness * 300.0;
                    h += (goal - h) * w * k;
                    break;
                case Op.Smooth:
                    h += (means![i] - h) * w * k;
                    break;
                case Op.Land:
                    if (w >= 0.5 && h < LandM) h = LandM;
                    break;
                case Op.Sea:
                    if (w >= 0.5 && h > SeaM) h = SeaM;
                    break;
                case Op.Mountains:
                    // max(0, ...): vale não escava. A crista sobe de 0 a 1,5; abaixo de ~0,15 o terreno fica como está.
                    double crest = Math.Max(Math.Pow(_noise.Ridge(_t.DirOf(p)), ridgePower) * 1.5 - 0.15, 0.0);
                    double cap = _before[p] + strength * mountainGain * mountainCap;
                    h = Math.Min(h + strength * mountainGain * w * crest, Math.Max(cap, h));
                    break;
            }
            _t.SetH(p, (float)h);
        }
    }

    /// Fecha a pincelada (com os rios, se markRivers) e devolve a edição, ou null se nada mudou.
    public TerrainEdit? End(bool markRivers)
    {
        if (markRivers)
            MarkRivers();
        if (_before.Count == 0 && _beforeR.Count == 0)
            return null;
        var idx = new int[_before.Count];
        var before = new float[_before.Count];
        int j = 0;
        foreach (var (p, h) in _before)
        {
            idx[j] = p;
            before[j++] = h;
        }
        var ridx = new int[_beforeR.Count];
        var rbefore = new byte[_beforeR.Count];
        j = 0;
        foreach (var (p, r) in _beforeR)
        {
            ridx[j] = p;
            rbefore[j++] = r;
        }
        _before.Clear();
        _beforeR.Clear();
        return new TerrainEdit(_t, idx, before, ridx, rbefore);
    }

    /// Vales: pixel -> área de captação da última marca (para os testes e para estudar).
    public Godot.Collections.Dictionary LastFlow()
    {
        var d = new Godot.Collections.Dictionary();
        foreach (var (p, a) in _lastFlow)
            d[p] = a;
        return d;
    }

    /// Forma da marca de elevar/rebaixar: 1 (cone liso) misturado com ondulação (média 1, desvio ~1,2).
    private double HillShape(int p, double roughness)
    {
        if (roughness <= 0.0)
            return 1.0;
        return Math.Max(Mathf.Lerp(1.0, 1.0 + (_noise.Fbm(_t.DirOf(p)) - 0.5) * 5.0, roughness), 0.0);
    }

    /// Erosão térmica: cada pixel acima de TalusM em relação a um vizinho mais baixo manda parte do excesso para ele.
    /// As mudanças são calculadas sobre as alturas de antes e aplicadas juntas: não depende da ordem; conserva a massa.
    private void ErodePass(double strength)
    {
        double k = Math.Clamp(strength / 500.0, 0.02, 1.0);
        var delta = new Dictionary<int, double>();
        for (int i = 0; i < _idx.Count; i++)
        {
            int p = _idx[i];
            double h = _t.H[p];
            foreach (var (dx, dy, _) in Terrain.Neighbors)
            {
                int q = _t.Neighbor(p, dx, dy);
                if (q < 0)
                    continue;
                double drop = h - _t.H[q];
                if (drop > TalusM)
                {
                    double moved = (drop - TalusM) * 0.125 * k * _w[i];  // 8 vizinhos: 1/8 cada, no máximo
                    delta[p] = delta.GetValueOrDefault(p) - moved;
                    delta[q] = delta.GetValueOrDefault(q) + moved;
                }
            }
        }
        foreach (var (p, d) in delta)
        {
            Remember(p);
            _t.SetH(p, (float)(_t.H[p] + d));
        }
    }

    /// Erosão hidráulica, em 4 passadas por marca:
    ///  1) cada pixel do disco escoa para o vizinho mais baixo (D8);
    ///  2) a área de captação soma de cima para baixo;
    ///  3) cada pixel que escoa é entalhado em proporção a raiz(área − 1) × desnível (espigão não entalha, canal sim);
    ///  4) o sedimento desce o rio e deposita onde o terreno achata; um poço retém 60% e o resto sai.
    /// Terra continua terra (piso de 1 m) e mar continua mar (o depósito não passa de SeaCeiling).
    private void Valleys(double strength)
    {
        double gain = Math.Clamp(strength / 100.0, 0.1, 10.0);
        int n = _idx.Count;
        for (int i = 0; i < n; i++)
            _strokeW[_idx[i]] = Math.Max(_strokeW.GetValueOrDefault(_idx[i]), _w[i]);
        var recv = new int[n];
        var drop = new double[n];
        var order = new int[n];
        var hs = new float[n];
        Func<int, double> height = q => _t.H[q];
        for (int pass = 0; pass < 4; pass++)
        {
            for (int i = 0; i < n; i++)
            {
                recv[i] = _t.Steepest(_idx[i], height, out drop[i]);
                hs[i] = _t.H[_idx[i]];
                order[i] = i;
            }
            Array.Sort(order, (a, b) => hs[b] != hs[a] ? hs[b].CompareTo(hs[a]) : a.CompareTo(b));  // do alto ao baixo
            var area = new Dictionary<int, double>(n);
            foreach (int i in order)
            {
                int p = _idx[i];
                double a = area.GetValueOrDefault(p) + 1.0;
                area[p] = a;
                if (recv[i] >= 0)
                    area[recv[i]] = area.GetValueOrDefault(recv[i]) + a;
            }
            _lastFlow = area;
            // Entalhe e sedimento, do alto para baixo, sobre as alturas de antes da passada.
            var delta = new double[n];
            var sediment = new Dictionary<int, double>();
            foreach (int i in order)
            {
                int p = _idx[i];
                double h = hs[i];
                double cut = 0.0;
                if (recv[i] >= 0)
                {
                    double d = drop[i];
                    cut = Math.Min(Incision * gain * Math.Sqrt(Math.Max(area[p] - 1.0, 0.0)) * d * _w[i], d * 0.5);
                    cut = Math.Min(cut, Math.Max(h - Math.Min(h, 1.0), 0.0));  // terra continua terra
                }
                double load = sediment.GetValueOrDefault(p) + cut;
                double flat = recv[i] < 0 ? 0.6 : Math.Clamp(1.0 - drop[i] / 60.0, 0.0, 1.0) * 0.6;
                double deposit = load * flat;
                delta[i] = deposit - cut;
                if (recv[i] >= 0)
                    sediment[recv[i]] = sediment.GetValueOrDefault(recv[i]) + load - deposit;
            }
            for (int i = 0; i < n; i++)
            {
                if (Math.Abs(delta[i]) <= 1e-6)
                    continue;
                int p = _idx[i];
                float h = _t.H[p];
                float nh = (float)(h + delta[i]);
                if (h < 0f)
                    nh = Math.Min(nh, Math.Max(h, SeaCeiling));  // o sedimento que sobra segue para o mar aberto
                if (nh == h)
                    continue;
                Remember(p);
                _t.SetH(p, nh);
            }
        }
    }

    /// Rios da pincelada inteira, marcados ao soltar o mouse (o terreno já está entalhado). A captação é acumulada na
    /// REGIÃO de todas as marcas, não em cada disco: o rio é contínuo ao longo do traço. Só o tronco principal de cada
    /// confluência conta (senão afluentes quase iguais viram uma mancha), e só em terra. A água é roteada sobre a
    /// altura suavizada (5x5): sem os degraus do Gleba, ela não fica presa em platôs.
    private void MarkRivers()
    {
        if (_strokeW.Count == 0)
            return;
        var idx = new int[_strokeW.Count];
        _strokeW.Keys.CopyTo(idx, 0);
        var smooth = new Dictionary<int, double>();
        Func<int, double> hs = q =>
        {
            if (!smooth.TryGetValue(q, out double v))
                smooth[q] = v = _t.NeighborMean(q, 2);
            return v;
        };
        var recv = new Dictionary<int, int>();
        var hp = new double[idx.Length];
        var order = new int[idx.Length];
        for (int i = 0; i < idx.Length; i++)
        {
            int best = _t.Steepest(idx[i], hs, out _);
            if (best >= 0)
                recv[idx[i]] = best;
            hp[i] = hs(idx[i]);
            order[i] = i;
        }
        Array.Sort(order, (a, b) => hp[b] != hp[a] ? hp[b].CompareTo(hp[a]) : a.CompareTo(b));
        var area = new Dictionary<int, double>();
        foreach (int i in order)
        {
            int p = idx[i];
            double a = area.GetValueOrDefault(p) + 1.0;
            area[p] = a;
            if (recv.TryGetValue(p, out int r))
                area[r] = area.GetValueOrDefault(r) + a;
        }
        var biggestIn = new Dictionary<int, double>();
        foreach (var (p, r) in recv)
            biggestIn[r] = Math.Max(biggestIn.GetValueOrDefault(r), area[p]);
        double threshold = Math.Max(RiverShare * idx.Length, RiverMin);
        foreach (int p in idx)
        {
            double a = area.GetValueOrDefault(p, 1.0);
            bool mainStem = !recv.TryGetValue(p, out int r) || a >= biggestIn.GetValueOrDefault(r);
            if (a >= threshold && mainStem && _strokeW[p] > 0.15f && _t.H[p] > 1f)
            {
                _beforeR.TryAdd(p, _t.R[p]);
                _t.SetRiver(p, Math.Max(_t.GetRiver(p), (float)Math.Min(0.4 + Math.Sqrt(a) * 0.03, 1.0)));
            }
        }
        _strokeW.Clear();
    }

    private void Remember(int p) => _before.TryAdd(p, _t.H[p]);
}
