# Иконки предметов

PNG для загрузки в Roblox (Asset Manager → Images / Decals):

| Файл | ItemId |
|---|---|
| `SmallRock.png` | SmallRock |
| `Stick.png` | Stick |
| `FistWeapon.png` | FistWeapon |

Куда вставлять: `src/items_config.json` → поле `"icon"` у нужного ItemId:

```json
"Stick": {
  "kind": "resource",
  "display_name": "Ветка",
  "icon": "rbxassetid://123456789",
  "max_stack": 99
}
```

Пока `icon` пустой — ViewportFrame из 3D. Свой `rbxassetid://…` перекрывает превью.
