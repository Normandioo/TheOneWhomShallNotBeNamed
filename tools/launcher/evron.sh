#!/usr/bin/env bash
# Atalho dos playtesters (Linux): baixa a versão mais nova do jogo, e os mapas quando mudam, e abre o Evron.
# Sem internet ou com falha no download, abre a versão já instalada. O mundo do jogador fica em ~/.local/share, fora daqui.
base="${EVRON_URL:-https://github.com/Normandioo/TheOneWhomShallNotBeNamed/releases}"
raiz="$(cd "$(dirname "$0")" && pwd)"
jogo="$raiz/jogo" antigo="$raiz/jogo.antigo" temp="$raiz/baixando"
mundo="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Evron"

texto() { curl -fsSL --connect-timeout 10 "$1"; }

# Baixa o pacote e extrai em $2; qualquer falha para antes de tocar no que está instalado.
pacote() {
	mkdir -p "$temp" "$2" && curl -fL --connect-timeout 10 --retry 2 -o "$temp/pacote.tar.gz" "$1" \
		&& tar -xzf "$temp/pacote.tar.gz" -C "$2" && rm "$temp/pacote.tar.gz"
}

# Uma troca interrompida no meio deixa os mapas na pasta antiga: devolve antes de tudo.
devolver_mapas() {
	if [ -d "$antigo/data" ] && [ -d "$jogo" ] && [ ! -d "$jogo/data" ]; then mv "$antigo/data" "$jogo/data"; fi
}

atualizar_jogo() {
	local nova copia f
	nova="$(texto "$base/latest/download/versao.txt")" || return 1
	[ "$nova" = "$(cat "$jogo/versao.txt" 2>/dev/null)" ] && return 0
	echo "Baixando a versão nova do jogo..."
	pacote "$base/latest/download/Evron-linux.tar.gz" "$temp/jogo" || return 1
	# Uma versão nova pode converter o banco: guarda uma cópia do mundo antes (ficam as 5 últimas).
	if [ -f "$mundo/evron_world.db" ]; then
		copia="$mundo/copias-atualizacao/$(date +%Y%m%d-%H%M%S-%N)"
		mkdir -p "$copia" || return 1
		for f in evron_world.db evron_world.db-wal evron_world.json evron_world.json.bak; do
			if [ -f "$mundo/$f" ]; then cp "$mundo/$f" "$copia/" || return 1; fi
		done
		ls -1d "$mundo"/copias-atualizacao/*/ | sort -r | tail -n +6 | while read -r f; do rm -rf "$f"; done
	fi
	echo "$nova" >"$temp/jogo/versao.txt" || return 1
	rm -rf "$antigo"
	if [ -d "$jogo" ]; then mv "$jogo" "$antigo" || return 1; fi
	mv "$temp/jogo" "$jogo" || return 1
	devolver_mapas && rm -rf "$antigo"
}

atualizar_mapas() {
	local mapas
	mapas="$(texto "$base/download/mapas/mapas.version" | tr -d '\r')" || return 1
	[ -n "$mapas" ] || return 1
	[ "$mapas" = "$(cat "$jogo/data/mapas.version" 2>/dev/null)" ] && return 0
	echo "Baixando os mapas (é grande; só quando eles mudam)..."
	pacote "$base/download/mapas/Evron-mapas.tar.gz" "$temp/mapas" && [ -d "$temp/mapas/evron" ] || return 1
	mkdir -p "$jogo/data" && rm -rf "$jogo/data/evron" && mv "$temp/mapas/evron" "$jogo/data/evron" \
		&& echo "$mapas" >"$jogo/data/mapas.version"
}

if [ -d "$antigo" ] && [ ! -d "$jogo" ]; then mv "$antigo" "$jogo"; fi
devolver_mapas
rm -rf "$temp"
if ! { atualizar_jogo && atualizar_mapas; }; then
	echo "Não deu para atualizar."
	devolver_mapas
	if [ ! -f "$jogo/Evron.x86_64" ] || [ ! -d "$jogo/data/evron" ]; then
		echo "Não há uma versão completa instalada. Confira a internet e tente de novo."
		exit 1
	fi
	echo "Abrindo a versão já instalada."
fi
rm -rf "$temp"
if [ -z "$EVRON_NAO_ABRIR" ]; then
	chmod +x "$jogo/Evron.x86_64"
	cd "$jogo" && exec ./Evron.x86_64
fi
