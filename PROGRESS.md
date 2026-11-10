# Баланс / заметки

- Шансы и scale деревьев — как выставил игрок в JSON, не трогать.
- Трава: `grass_coverage` / `grass_height` / `grass_noise_scale`. `Terrain.Decoration`/`GrassLength` из скрипта часто нельзя — включать вручную в Studio.
- MegaTree: `mega_tree_lift` = -2, непрозрачные.
- Генерация: пол на `base_height+8` (не Y=0 — иначе спавн внутри земли); ObjectGen/пруды — `task.wait` каждый чанк (иначе timeout → пустая карта).
- Пустыни нет. Край: `edge_margin` 128. Пруды ок.
