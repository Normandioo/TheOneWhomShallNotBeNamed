## Carrega as texturas da Terra e da Lua (NASA, ver docs/arquitetura.md), importadas pelo Godot com mipmaps
## (data/space/*.import), para não tremer ao afastar o zoom. Se o arquivo não existir, devolve null e o corpo
## fica de uma cor só.

static func load_texture(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null
