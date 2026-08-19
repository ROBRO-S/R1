Братан, старый README нужно **полностью сжечь и написать новый**. Тот текст был для прототипа, а сейчас у тебя уже полноценная архитектура с ассетами, модулями и правильной структурой.

Вот профессиональный README, который отражает текущее состояние проекта и сразу настроит команду на правильный лад:

```markdown
#  R1: DST Survival Project

**Процедурный survival-crafting в стиле Don't Starve Together на Roblox.**
Автоматическая генерация мира, система биомов, ресурсы и подготовка к крафту.

##  Требования к окружению

Перед началом работы установи:
1.  **Roblox Studio** (последняя версия)
2.  **VS Code** + расширение [Luau Language Server](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.luau-lsp)
3.  **Git**
4.  **Aftman** (менеджер тулчейна) — *критически важно!*

##  Быстрый старт

### 1. Клонирование и настройка
```bash
git clone https://github.com/ROBRO-S/R1.git
cd R1
aftman install
```
*Проверка:* `rojo --version` должен показать актуальную версию из `aftman.toml`.

### 2. Запуск синхронизации
```bash
rojo serve
```
Ожидаемый вывод: `Serving project 'R1 Project' at http://localhost:34872`

### 3. Подключение Studio
1. Открой любой пустой Place в Roblox Studio.
2. Вкладка **Plugins** → **Rojo** → Connect к `localhost:34872`.
3. Убедись, что в Explorer появились:
    -   `ServerScriptService/Main`, `TerrainGenerator`, `ObjectGenerator`
    -   `ReplicatedStorage/assets/BigTree`

> ⚠️ **ВАЖНО:** Весь код и ассеты управляются через Git + Rojo. Никогда не редактируй скрипты напрямую в Studio!

## 📂 Структура проекта

```text
R1/
├── src/
│   ├── assets/            # Модели ресурсов (.rbxm)
│   │   └── BigTree.rbxm   # Шаблон большого дерева
│   ├── server/            # Серверная логика
│   │   ├── scripts/
│   │   │   └── Main.server.lua      # Точка входа (bootstrap)
│   │   ├── TerrainGenerator.module.luau  # Генерация ландшафта
│   │   └── ObjectGenerator.module.luau   # Спавн деревьев/веток
│   └── client/            # Клиентские скрипты (пока пусто)
├── docs/                  # GDD, задачи, документация
├── default.project.json   # Конфигурация Rojo
├── aftman.toml            # Версии инструментов
└── .gitignore
```

## 🔄 Как работает генерация мира

1.  При старте сервера `Main.server.lua` проверяет наличие флага `WorldGenerated_v1`.
2.  Если флага нет → запускается полная генерация:
    -   `TerrainGenerator` создает ландшафт через воксели.
    -   `ObjectGenerator` расставляет деревья и ветки через Raycast.
3.  После генерации ставится флаг, чтобы не повторять процесс.
4.  Для сброса мира удали `WorldGenerated_v1` из Workspace и перезапусти сервер.

## 🤝 Workflow для команды

1.  **Начало работы:** `git pull origin main`
2.  **Разработка:** Создавай ветку `git checkout -b feature/name`
3.  **Тест:** Пиши код в VS Code → Rojo мгновенно обновляет Studio.
4.  **Сдача:** Push ветки → Pull Request → Code Review → Merge.

> 🚫 **ЗАПРЕЩЕНО:** Пушить в `main` напрямую. Хранить бинарные `.rbxl` в Git (кроме шаблона). Редактировать ассеты вне папки `src/assets/`.

## 📄 Лицензия
[Укажи лицензию, если применимо]
```

