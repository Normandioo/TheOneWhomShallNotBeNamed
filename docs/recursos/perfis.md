# Perfis de recurso: de onde vem cada ligação

Consulta em 25/11/2026. **O site pubs.usgs.gov recusou a leitura automática das páginas (HTTP 403).** O que está abaixo vem dos
resumos devolvidos pela busca, não das páginas completas. Para confirmar, abra os links no navegador.

Os perfis geram **áreas pintadas** (dá para trocar para pontos em "Gerar"). O tamanho da mancha marca a região apta, não o
tamanho de uma jazida.

Os **pesos, a aptidão mínima, a quantidade e os tamanhos são escolhas de projeto**, sem calibração. Os nomes das províncias
geológicas e dos tipos de vulcanismo são hipótese na calibração dos mapas.

| Perfil | O que a fonte diz | Fontes | O que o perfil NÃO cobre |
|---|---|---|---|
| Cobre | Pórfiro de granodiorito a tonalito; teores altos onde há calcário; maior fonte de cobre | [modelo de 2010](https://pubs.usgs.gov/sir/2010/5070/b), [capítulo de 1995](https://webarchive.library.unt.edu/eot2008/20081105215000/http:/pubs.usgs.gov/of/1995/ofr-95-0831/CHAP11.pdf) | Cobre em sedimentos, a segunda maior fonte ([modelo](https://pubs.usgs.gov/publication/sir20105070M)); calcário vizinho. Andesito, dacito e "arco" são inferência do contexto de arco |
| Estanho | Granitos silícicos tardios a pós-orogênicos; veios, greisen e skarn; cerca de 80% do estanho identificado está em depósitos de cascalho vindos desses granitos | [skarn](https://pubs.usgs.gov/bul/b1693/html/bull2i5q.htm), [greisen](https://pubs.usgs.gov/bul/b1693/html/bull217y.htm), [veios](https://pubs.usgs.gov/bul/b1693/html/bull89rn.htm), [visão geral](https://www.usgs.gov/publications/tin) | O cascalho é aproximado por "granito a até 20 km de rio grande"; o fluxo dos rios é relativo |
| Ferro | Formação bandada (sílex, muitas vezes metamorfizada); skarn; **ferro de pântano**, onde água subterrânea com ferro chega a brejos (o ferro dos povos do norte até o século XVI); **laterita**, crosta de clima quente e úmido sobre rocha com ferro | [bandada](https://pubs.usgs.gov/bul/b1693/html/bull971h.htm), [skarn](https://pubs.usgs.gov/bul/b1693/html/bull86em.htm), [ferro de pântano (Britannica)](https://www.britannica.com/science/bog-iron-ore), [(USGS)](https://www.usgs.gov/publications/bog-iron-formation-nassawango-creek-watershed-maryland-usa), [laterita](https://www.britannica.com/science/laterite) | Idade das rochas (os mapas não têm); a renovação do ferro de pântano (uma vez por geração). Quartzito saiu: é comum e quase nunca tem ferro |
| Sal | Evaporação maior que a entrada de água em bacias fechadas, sobretudo em clima árido; salinas de costa | [minerais de deserto](https://pubs.usgs.gov/gip/deserts/minerals), [água subterrânea e evaporitos](https://www.usgs.gov/publications/ground-water-control-evaporite-deposition) | Bacia fechada (o mapa não tem legenda): usa-se "lago em clima árido". As salinas de costa vêm do conhecimento geral, sem fonte conferida |

## Revisão de 25/11/2026 (problemas do mesmo tipo do quartzito)

- **Um sinal fraco bastava sozinho:** quartzito (ferro), granito (estanho), "árido e plano" (sal). Agora cada perfil exige um tipo
  reconhecido de jazida; sílex e clima árido são só reforço.
- **Contagem dupla:** anfibolito valia na laterita e no cinturão antigo; saiu da laterita.
- **Modelos genéricos removidos:** "Minério de montanha" (não diz qual minério), "Jazida em rocha sedimentar" (cobria quase metade
  da terra) e "Sal em região seca" (contava sílex como sal).
- **Solo de cultivo:** passa a preferir planícies de rio grande (aluviais) e o clima temperado.
- **Automático:** um corte de "80% da melhor aptidão" foi testado e retirado: deixava entrar só lugares com dois tipos de jazida ao
  mesmo tempo. A pontuação mínima de cada perfil decide.

## Como testar

- **Obediência e repetição:** `tests/suites/generation_suite.gd`.
- **Estabilidade:** botão "Testar estabilidade". Mede quanto os lugares aptos mudam com limites e pesos em ±10%, e quantas
  sugestões de outra semente caem perto das anteriores, comparado com pontos sorteados.
- **Avaliação às cegas:** botão "Avaliar às cegas". Mistura sugestões da regra com sorteios; o autor julga sem saber qual é qual.
  O resultado vai para `user://avaliacoes_gerador.csv`. Os fatos mostrados (rocha, clima...) podem dar pistas da origem.
- **Gabarito:** as respostas da avaliação às cegas testam qualquer regra do recurso ("Comparar com gabarito"; toda prévia já mostra
  o resultado). Mede quantos lugares aprovados a regra aceita e quantos rejeitados recusa. Um terço fica reservado para o "Teste
  final". Limites: os lugares vieram da regra avaliada e de sorteios, então dizem pouco sobre regiões nunca julgadas; o gabarito é
  achado pelo nome do recurso (renomear o separa).
- **Calibração na Terra:** não foi feita.
- Nada disso mede precisão no mundo de Evron: não há jazidas conhecidas lá.
