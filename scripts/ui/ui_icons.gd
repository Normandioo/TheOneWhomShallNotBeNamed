extends RefCounted
## Os ícones do desenho da interface (traço fino, um estilo só; formas do Lucide, licença ISC). Cada um é um SVG que vira textura na hora,
## em branco: quem usa pinta pelo tema (icon_normal_color etc.), então o mesmo ícone serve em qualquer estado. Sem arquivos de imagem.

const PATHS := {
	"navigate": "M3 3l7.07 16.97 2.51-7.39 7.39-2.51L3 3z",
	"territory": "m9.06 11.9 8.07-8.06a2.85 2.85 0 1 1 4.03 4.03l-8.06 8.08 M7.07 14.94c-1.66 0-3 1.35-3 3.02 0 1.33-2.5 1.52-2 2.02 1.08 1.1 2.49 2.02 4 2.02 2.2 0 4-1.8 4-4.04a3.01 3.01 0 0 0-3-3.02z",
	"relief": "M8 3l4 8 5-5 5 15H2L8 3z",
	"place": "M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z M12 7a3 3 0 1 0 0 6a3 3 0 1 0 0-6Z",
	"undo": "M3 7v6h6 M21 17a9 9 0 0 0-9-9 9 9 0 0 0-6 2.3L3 13",
	"redo": "M21 7v6h-6 M3 17a9 9 0 0 1 9-9 9 9 0 0 1 6 2.3l3 2.7",
	"search": "M11 3a8 8 0 1 0 0 16a8 8 0 1 0 0-16Z M21 21l-4.3-4.3",
	"alert": "M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z M12 9v4 M12 17h.01",
	"help": "M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18Z M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3 M12 17h.01",
	"gear": "M4 6h16 M4 12h16 M4 18h16 M9 4v4 M15 10v4 M8 16v4",
	"play": "M7 4l13 8-13 8z",
	"pause": "M7 4h4v16H7z M13 4h4v16h-4z",
	"clock": "M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18Z M12 7v5l3 2",
	"plus": "M12 5v14 M5 12h14",
	"close": "M18 6 6 18 M6 6l12 12",
	"chevron_up": "m6 15 6-6 6 6",
	"chevron_down": "m6 9 6 6 6-6",
	"chevron_left": "m15 18-6-6 6-6",
	"file": "M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z M14 2v6h6 M8 13h8 M8 17h8",
	"government": "M3 21h18 M5 21V10 M19 21V10 M10 21V10 M14 21V10 M2 10l10-7 10 7z",
	"people": "M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z M2 21c0-4 3-6 7-6s7 2 7 6 M16 3.5a4 4 0 0 1 0 7.5 M18 15c2.5.7 4 2.6 4 6",
	"population": "M4 21V11h5v10 M10 21V4h5v17 M16 21v-7h5v7 M2 21h20",
	"resources": "M6 3h12l4 6-10 12L2 9z M2 9h20 M12 21 8 9l4-6 4 6z",
	"economy": "M3 21V9l6 4V9l6 4V4h6v17z M7 17h2 M13 17h2",
	"calendar": "M4 5h16v16H4z M4 10h16 M8 3v4 M16 3v4",
	"area": "M3 6l6-3 6 3 6-3v15l-6 3-6-3-6 3z M9 3v15 M15 6v15",
	"warning": "M12 3 2 20h20z M12 10v4 M12 17h.01",
	"politics": "M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z M4 22v-7",
	"religion": "M12 8a4 4 0 1 0 0 8a4 4 0 1 0 0-8Z M12 2v2 M12 20v2 M4.93 4.93l1.41 1.41 M17.66 17.66l1.41 1.41 M2 12h2 M20 12h2 M6.34 17.66l-1.41 1.41 M19.07 4.93l-1.41 1.41",
	"culture": "M12 22a1 1 0 0 1 0-20 10 9 0 0 1 10 9 5 5 0 0 1-5 5h-2.25a1.75 1.75 0 0 0-1.4 2.8l.3.4a1.75 1.75 0 0 1-1.4 2.8z M13.5 6.5h.01 M17.5 10.5h.01 M6.5 12.5h.01 M8.5 7.5h.01",
	"ethnicity": "M12 10a2 2 0 0 0-2 2c0 1.02-.1 2.51-.26 4 M14 13.12c0 2.38 0 6.38-1 8.88 M17.29 21.02c.12-.6.43-2.3.5-3.02 M2 12a10 10 0 0 1 18-6 M2 16h.01 M21.8 16c.2-2 .131-5.354 0-6 M5 19.5C5.5 18 6 15 6 12a6 6 0 0 1 .34-2 M8.65 22c.21-.66.45-1.32.57-2 M9 6.8a6 6 0 0 1 9 5.2v2",
	"race": "M2 15c6.667-6 13.333 0 20-6 M9 22c1.798-1.998 2.518-3.995 2.807-5.993 M15 2c-1.798 1.998-2.518 3.995-2.807 5.993 M17 6l-2.5-2.5 M14 8l-.5-.5 M7 18l2.5 2.5 M3.5 14.5l.5.5 M20 9l.5.5 M6.5 12.5l1 1 M16.5 10.5l1 1 M10 11l1 1",
	"language": "m5 8 6 6 M4 14l6-6 2-3 M2 5h12 M7 2h1 M22 22l-5-10-5 10 M14 18h6",
	"satellite": "M12 2a10 10 0 1 0 0 20a10 10 0 1 0 0-20Z M2 12h20 M12 2a15 15 0 0 1 4 10a15 15 0 0 1-4 10a15 15 0 0 1-4-10a15 15 0 0 1 4-10Z",
	"climate": "M14 4v10.54a4 4 0 1 1-4 0V4a2 2 0 0 1 4 0Z",
	"ecology": "M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.48 19 2c1 2 2 4.18 2 8 0 5.5-4.78 10-10 10Z M2 21c0-3 1.85-5.36 5.08-6",
	"soils": "M3 6h18 M3 12h18 M3 18h18 M7 6v6 M15 12v6 M11 18v3",
	"hydrology": "M12 22a7 7 0 0 0 7-7c0-2-1-3.9-3-5.5s-3.5-4-4-6.5c-.5 2.5-2 4.9-4 6.5C6 11.1 5 13 5 15a7 7 0 0 0 7 7z",
	"geology": "M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z",
	"organization": "M3 3h18v18H3Z M3 9h18 M3 15h18 M9 3v18 M15 3v18",
	"overlays": "M12 2 2 7l10 5 10-5-10-5Z M2 17l10 5 10-5 M2 12l10 5 10-5",
	"bucket": "m19 11-8-8-8.6 8.6a2 2 0 0 0 0 2.8l5.2 5.2c.8.8 2 .8 2.8 0L19 11Z M5 2l5 5 M2 13h15",
	"eraser": "m7 21-4.3-4.3c-1-1-1-2.5 0-3.4l9.6-9.6c1-1 2.5-1 3.4 0l5.6 5.6c1 1 1 2.5 0 3.4L13 21 M22 21H7 M5 11l9 9",
	"eyedropper": "m2 22 1-1h3l9-9 M3 21v-3l9-9 M15 6l3.4-3.4a2.1 2.1 0 1 1 3 3L18 9l.4.4a2.1 2.1 0 1 1-3 3l-3.8-3.8a2.1 2.1 0 1 1 3-3l.4.4Z",
	"border": "M12 20h9 M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z",
	"raise": "M12 19V5 M5 12l7-7 7 7",
	"lower": "M12 5v14 M19 12l-7 7-7-7",
	"level": "M2 12h20 M6 7h12 M6 17h12",
	"smooth": "M2 12c2-3 4-3 6 0s4 3 6 0 4-3 6 0",
	"mountains": "M8 3l4 8 5-5 5 15H2L8 3z",
	"erosion": "M12.8 19.6A2 2 0 1 0 14 16H2 M17.5 8a2.5 2.5 0 1 1 2 4H2 M9.8 4.4A2 2 0 1 1 11 8H2",
	"valley": "M2 6l10 12L22 6",
	"more": "M5 12h.01 M12 12h.01 M19 12h.01",
	"check": "M20 6 9 17l-5-5",
	"merge": "M18 15a3 3 0 1 0 0 6a3 3 0 1 0 0-6Z M6 3a3 3 0 1 0 0 6a3 3 0 1 0 0-6Z M6 21V9a9 9 0 0 0 9 9",
	"upload": "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4 M17 8l-5-5-5 5 M12 3v12",
	"grow": "M15 3h6v6 M9 21H3v-6 M21 3l-7 7 M3 21l7-7",
	"grow_all": "M3 7V5a2 2 0 0 1 2-2h2 M17 3h2a2 2 0 0 1 2 2v2 M21 17v2a2 2 0 0 1-2 2h-2 M7 21H5a2 2 0 0 1-2-2v-2 M12 8v8 M8 12h8",
	"snap": "m6 15-4-4 6.75-6.77a7.79 7.79 0 0 1 11 11L13 22l-4-4 6.39-6.36a2.14 2.14 0 0 0-3-3L6 15 M5 8l4 4 M12 15l4 4",
	"world": "M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18Z M3 12h18",
	"animal": "M5.5 8a2 2 0 1 0 0 4a2 2 0 1 0 0-4Z M9.5 3.5a2 2 0 1 0 0 4a2 2 0 1 0 0-4Z M14.5 3.5a2 2 0 1 0 0 4a2 2 0 1 0 0-4Z M18.5 8a2 2 0 1 0 0 4a2 2 0 1 0 0-4Z M12 12c-3 0-6 3.5-6 6.5 0 1.5 1.2 2.5 2.7 2.5 1.2 0 2-.6 3.3-.6s2.1.6 3.3.6c1.5 0 2.7-1 2.7-2.5 0-3-3-6.5-6-6.5z",
	"hammer": "M4 20l9.6-9.6 M10 5.5l3.5-3.5 7.5 7.5-3.5 3.5z",
	"house": "M3 10.5 12 3l9 7.5 M5 9v12h14V9 M10 21v-6h4v6",
	"patch": "M5 8c2-4 8-5 12-3s5 7 2 10-9 5-12 2-4-5-2-9z",
	"generate": "M12 3v4 M12 17v4 M3 12h4 M17 12h4 M6 6l2.5 2.5 M15.5 15.5 18 18 M18 6l-2.5 2.5 M8.5 15.5 6 18",
}

static var _cache := {}


## O ícone `name` com `size` pixels de lado, em branco. Nome que não existe devolve null.
static func get_icon(name: String, size := 20) -> Texture2D:
	var key := "%s@%d" % [name, size]
	if _cache.has(key):
		return _cache[key]
	if not PATHS.has(name):
		return null
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="%s"/></svg>' % PATHS[name]
	var image := Image.new()
	if image.load_svg_from_string(svg, size / 24.0) != OK:
		return null
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture
