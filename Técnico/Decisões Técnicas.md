---
tags: [tecnico, decisao]
---
# Decisões Técnicas

| Tema | Decisão | Motivo |
|---|---|---|
| Plataforma | PC, aplicação local | O núcleo funciona sem servidor nem IA |
| Engine | Godot 4.7.2 (Steam) | Reaproveita o Projeto Marte (globo, câmera, testes, arquitetura). A proposta recomendava CesiumJS e deixava Godot como alternativa; o globo e a projeção já existiam no Marte |
| Base de código | Cópia do Projeto Marte sem histórico (commit 337b804) | Arquitetura e testes prontos; o que era de Marte saiu |
| Banco | SQLite com R*Tree (planejado) | Proposta; local e transacional |
| Altitude | float32 em metros | float16 perde mais de 4 m acima de 4 km |
| Mapas | `data/evron/` fora do git, refeito do `mapas.zip` | O zip é a fonte; 99 MB de imagens não vão para o git |
| Visual | Sem pixel art ([[Estilo Visual]]) | É uma ferramenta de consulta |
| Colaboração simultânea | Não na primeira versão | Proposta: decidir a prioridade depois |

Pastas: o projeto fica em `E:\ProjetoEvron` e este cofre em `E:\ProjetoEvron-Cofre`. Ver [[Estrutura do Projeto Godot]].
