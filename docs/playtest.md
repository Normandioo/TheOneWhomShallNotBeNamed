# Versões para os playtesters

A cada push na `main`, o GitHub Actions (job `publicar` em `.github/workflows/ci.yml`) roda a suíte do núcleo, exporta o jogo
para Windows e Linux e publica uma release. O atalho no computador do playtester baixa a versão nova antes de abrir o jogo.
Se a compilação, o teste ou a exportação falhar, nada é publicado.

O repositório é público: o jogo e os mapas publicados podem ser baixados por qualquer pessoa.

## Quem publica

1. **Mapas (antes do primeiro playtester, e de novo só quando mudarem):**
   `powershell -ExecutionPolicy Bypass -File tools\publicar_mapas.ps1`
   Usa `data/evron/` do projeto (outra pasta: `-Dados <pasta que contém evron>`) e precisa do `gh` autenticado.
   São uns 460 MB de envio.
2. **Jogo:** é só levar as mudanças à `main` e dar push. Acompanhe na aba *Actions*.

Os playtesters recebem tudo o que chega à `main`: trabalho pela metade deve ficar em outro ramo.

Mudanças em `tools/launcher/` **não** chegam sozinhas: o atalho não se atualiza, e cada playtester precisa baixá-lo de novo.

## Quem testa (só na primeira vez)

Abra a [release mais nova](https://github.com/Normandioo/TheOneWhomShallNotBeNamed/releases/latest) e baixe o atalho.

- **Windows:** `Evron-atalho-windows.zip`. Extraia numa pasta própria (fora de *Arquivos de Programas*) e abra sempre por
  `Evron.bat`. Se o Windows avisar que o arquivo veio da internet, escolha *Mais informações* → *Executar assim mesmo*.
- **Linux:** `Evron-atalho-linux.tar.gz`. Extraia numa pasta própria e rode `./evron.sh`.

Na primeira vez ele baixa o jogo e os mapas. Depois baixa só o que mudou. Sem internet, abre a versão já instalada.
Feche o jogo antes de abrir o atalho de novo.

O mundo do playtester fica fora da pasta do jogo. Antes de cada versão nova o atalho copia o mundo para
`copias-atualizacao/` (as 5 últimas), na pasta de dados do Evron:
`%APPDATA%\Godot\app_userdata\Evron` no Windows, `~/.local/share/godot/app_userdata/Evron` no Linux.
Para voltar a uma cópia, feche o jogo e copie os arquivos dela por cima.
