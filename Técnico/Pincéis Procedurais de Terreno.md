---
tags: [tecnico, estudo]
---
# Pincéis Procedurais de Terreno

Estudo feito de memória da literatura de geração de terreno (Perlin, Musgrave, Quilez); **não conferi fontes online** nesta sessão. Serve de mapa para decidir o que implementar. Ligado a [[Geografia e Ambiente]] e [[E0 - Prova Técnica]].

## Por que o pincel simples parece falso
Um cone ou prato liso tem uma só escala e nenhuma direção: a natureza tem relevo em muitas escalas (uma serra tem cristas, vales, esporões). O truque comum é **somar ruído em várias escalas** (fractal) dentro de uma máscara de pincel.

## Técnicas
| Técnica | O que dá | Custo | No projeto |
|---|---|---|---|
| **fBm** (soma de oitavas de ruído) | Ondulação natural, colinas | Baixo | Elevar/Rebaixar/Nivelar (rugosidade) |
| **Ridged multifractal** (1 − \|ruído\|, oitavas) | Cristas finas e vales em V: serras | Baixo | Montanhas |
| **Domain warping** (deslocar a posição antes de ler o ruído) | Cristas que serpenteiam, sem aspecto de grade | Baixo | Montanhas |
| **Erosão térmica** (material escorre acima do ângulo de repouso) | Encostas e picos arredondados, entulho nos vales | Baixo-médio | Erosão |
| **Erosão hidráulica** (chuva, fluxo, sedimento) | Redes de drenagem, vales entalhados, leques | Alto | **Não feito** (próximo passo) |
| **Terraços** (quantizar a altura com suavização) | Degraus, mesas | Baixo | Não feito |
| **Carvar rios** (pincel que segue o declive e entalha) | Vales fluviais | Médio | Não feito |
| **Máscaras por declive/altura** (ruído só onde...) | Rocha só em encosta, areia só no plano | Baixo | Não feito |
| **Ruído em 3D na esfera** | Sem emenda em 180° nem estiramento nos polos | — | Todos |

## Princípios que adotamos
1. **O ruído é função da posição na esfera (em km)**, não do pixel: o mesmo lugar dá o mesmo relevo, em qualquer zoom e resolução.
2. **A semente fica na pincelada.** Marcas da mesma pincelada se somam e a serra *cresce*; outra pincelada = outro relevo. Semente fixa repete (testes, e depois o histórico reproduzível da proposta).
3. **Montanhas só somam** (`max(0, ...)`): um vale do ruído é "sem mudança", nunca "escavar". O primeiro erro foi tratar vale como negativo: no meio do continente isso passava de 0 m e criava água.
4. **Cada pincelada = um comando** com o antes e o depois só dos pixels mexidos ([[Modelo de Dados]]).
5. **A erosão conserva massa** (testado): o que sai de cima entra embaixo.

## Os modos hoje
- **Elevar / Rebaixar:** cone liso misturado com fBm pela *Rugosidade* (0% = cone liso, 100% = colina irregular).
- **Nivelar:** vai à altura do ponto inicial, com textura fraca de ruído.
- **Suavizar:** média ponderada.
- **Montanhas:** cristas. *Rugosidade* baixa = maciço arredondado e largo; alta = cristas finas, menos volume.
- **Erosão:** térmica, 3 passadas por marca.

## Limites conhecidos (vistos na galeria)
- Pixel de 12,7 km: as cristas mais finas têm ~25 km; o resultado não alcança a riqueza de um mapa feito em resolução maior.
- **A erosão térmica borra:** arredonda tudo, mas não entalha vales nem cria drenagem. Para o aspecto "erodido de verdade" falta a hidráulica.
- Rugosidade 0% em Montanhas faz um platô muito alto e largo (muito branco); talvez limitar a altura.
- Nada disso muda ainda as camadas derivadas do Gleba (clima, biomas, rios): ficam desatualizadas ([[Simulação]]).

## Ideias seguintes (por valor)
1. Erosão hidráulica simplificada (fluxo + entalhe) para rios e vales.
2. Direção: cristas alinhadas ao traço do mouse (cordilheira em linha).
3. Terraços e mesas; máscaras por declive.
4. Pré-visualização do resultado antes de soltar o mouse ([[Interação Esperada]]).
