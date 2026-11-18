extends "res://tests/test_suite.gd"
## Acesso ao SQLite pelo C# (WorldDb), sem cena: abrir, gravar e ler, inclusive um instante de 64 bits e a chave estrangeira.


func run() -> void:
	var db = load("res://scripts/data/WorldDb.cs").new()
	db.Open(":memory:")
	db.Execute("create table entity(id integer primary key, name text not null)")
	db.Execute("create table link(a integer not null references entity(id), t integer not null)")
	db.Execute("insert into entity(name) values ('Aldeia provisória')")
	var big := 9007199254740993  # 2^53 + 1: se passasse por double, perderia o último dígito
	db.Execute("insert into link values (1, %d)" % big)
	if db.QueryLong("select count(*) from entity") != 1:
		return fail("deveria haver 1 entidade")
	if db.QueryLong("select t from link") != big:
		return fail("instante de 64 bits não voltou igual")
	# Chave estrangeira ligada (a conexão a liga ao abrir; sem isso o SQLite aceita vínculos órfãos em silêncio).
	if db.QueryLong("pragma foreign_keys") != 1:
		return fail("a chave estrangeira não está ligada")
	ok("SQLite %s via C#: gravar, ler, inteiro de 64 bits e chave estrangeira" % db.Version())
	db.Close()
