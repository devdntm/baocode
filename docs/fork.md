# Форк devdntm/baocode

Форк `baocode-dev/baocode` с раскладкой Cursor в режиме IDE, планом как в Cursor,
claude-context в интерфейсе и импортом проектов из Cursor. Главное правило:
upstream должен вливаться без конфликтов, а данные пользователя не трогаются.

## Remote и обновление

```sh
git remote -v
# origin    git@github.com:devdntm/baocode.git            форк, сюда push
# upstream  https://github.com/baocode-dev/baocode.git   только fetch

git fetch upstream && git merge upstream/main
```

Push в `upstream` отключён (`git remote set-url --push upstream DISABLED`), чтобы
случайно не отправить туда коммиты форка. Работа идёт в `main`.

Перед большим слиянием проверь его в отдельном worktree:

```sh
git worktree add ../baocode-merge-check main
cd ../baocode-merge-check && git merge --no-commit upstream/main
cd - && git worktree remove --force ../baocode-merge-check
```

## Правила кода

- **Новый код — в новых файлах**, по фичам:
  - `lib/fork/` — общее для форка (строки);
  - `lib/ide/cursor_layout/` — раскладка Cursor;
  - `lib/plan/` — вид плана и его задачи;
  - `lib/integrations/claude_context/` — индекс claude-context;
  - `lib/integrations/cursor_import/` — импорт из Cursor.
- **Правки upstream-файлов — точечные:** параметр, ветка `if`, регистрация. Каждая
  помечается комментарием `// fork:` с пояснением и вносится в таблицу ниже.
  Если нужен приватный кусок upstream-кода, его выносят в общую функцию с
  минимальным диффом, а не копируют.
- **Строки форка — в [`lib/fork/fork_strings.dart`](../lib/fork/fork_strings.dart)**
  (en + zh), виджеты читают их через `context.fork`. В `lib/l10n/app_*.arb` и
  сгенерированные `app_localizations*.dart` форк ничего не добавляет: это главный
  источник конфликтов при слияниях.
- **Новые настройки по умолчанию выключены.** Поведение upstream не меняется,
  всё включается в `settings.json` сборки BaoCode Dev.
- **Тесты форка** лежат рядом с фичей: `test/fork/`, `test/plan/`,
  `test/ide/cursor_layout/`, `test/integrations/`.

## Окружение для сборки и тестов

- **Flutter той же версии, что в CI** (`FLUTTER_VERSION` в
  `.github/workflows/checks.yml`, сейчас 3.47.5). На этой машине он стоит
  отдельно, в `~/flutter-3.47.5`; `flutter` в PATH старее и проект не собирает:

  ```sh
  ~/flutter-3.47.5/bin/flutter test test/fork/
  FLUTTER=~/flutter-3.47.5/bin/flutter tool/dev_app/build_dev_app.sh
  ```

- **Rust для `packages/bao_iroh`.** Его хук сборки компилирует `rust/` через
  `rustup` (версия из `rust/rust-toolchain.toml`) либо берёт готовую библиотеку
  из `packages/bao_iroh/build/prebuilt/<target>/libbao_iroh.dylib`. Пока
  `rust/` не отличается от релиза upstream (`git diff v<версия> -- packages/bao_iroh`),
  arm64-библиотеку можно взять из установленного BaoCode той же версии:

  ```sh
  mkdir -p packages/bao_iroh/build/prebuilt/aarch64-apple-darwin
  cp /Applications/BaoCode.app/Contents/Frameworks/bao_iroh.framework/Versions/A/bao_iroh \
    packages/bao_iroh/build/prebuilt/aarch64-apple-darwin/libbao_iroh.dylib
  ```

  Этого хватает для `flutter test`. Релизная сборка macOS универсальная, ей
  нужен и `x86_64-apple-darwin`, а в установленном приложении только arm64:
  для неё нужен `rustup`.

## Точки `// fork:` в upstream-файлах

Найти все: `git grep -n "// fork:" -- lib test`.

| Файл | Что подключает |
| --- | --- |
| `lib/ide/workbench/contributions/all.dart` | `CursorLayoutContribution`: команда View: Toggle Cursor Layout |
| `lib/settings/pages/general_page.dart` | строка `workbench.ide.layout` первой в группе IDE |
| `lib/ide/ide_workbench.dart` | параметр `agents` (список чатов) и выбор сетки: `CursorWorkbenchGrid` при `workbench.ide.layout: cursor` |
| `lib/ide/workbench/parts/activity_bar.dart` | параметр `axis`: иконки видов строкой над сайдбаром (`_row`); вертикальный код не тронут |
| `lib/ide/ide_layout.dart` | `IdeLayoutToggle(mirrored:)`: иконки сайдбара и чата меняются сторонами |
| `lib/ide/workbench/parts/title_bar.dart` | в раскладке Cursor тумблер чата слева, сайдбара справа |

Колонка редактора с панелью в
[`lib/ide/cursor_layout/cursor_grid.dart`](../lib/ide/cursor_layout/cursor_grid.dart)
(`_editorColumn`, `_panelSlot`, `_dragPanel`, `_dragTo`) скопирована из
`lib/ide/workbench/parts/grid.dart`, где она приватная. При слиянии upstream
сверяй её с оригиналом: `git diff ORIG_HEAD -- lib/ide/workbench/parts/grid.dart`.

Раскладка Cursor пока зеркалит тумблеры только в заголовке macOS
(`title_bar.dart`); заголовок Windows (`window_header.dart`) не тронут.
Ширина и видимость списка чатов хранятся в состоянии окна (`ide.views[папка]`
в state.json) под ключами `cursor.agentsWidth` и `cursor.agents`
(`CursorLayoutService`).

## BaoCode Dev: отдельное приложение

Сборка форка ставится рядом с обычным BaoCode как `/Applications/BaoCode Dev.app`
со своей папкой данных. Собирает её
[`tool/dev_app/build_dev_app.sh`](../tool/dev_app/build_dev_app.sh):

```sh
tool/dev_app/build_dev_app.sh              # flutter build + установка
tool/dev_app/build_dev_app.sh --skip-build # поставить то, что уже собрано
```

Что делает скрипт:

- собирает `flutter build macos --release` и копирует `BaoCode.app` в
  `/Applications/BaoCode Dev.app`;
- меняет в `Info.plist` `CFBundleIdentifier` на `dev.baocode.desktop.dev`,
  `CFBundleName`/`CFBundleDisplayName` на `BaoCode Dev` и задаёт
  `LSEnvironment.BAOCODE_DATA_DIR` = `~/Library/Application Support/baocode-dev`
  (абсолютным путём). Dart-код не меняется: папку из `BAOCODE_DATA_DIR` берёт
  `resolveDataDirectory` ([lib/platform/data_dir.dart](../lib/platform/data_dir.dart));
- убирает из копии Finder-расширение (`Contents/PlugIns/FinderExtension.appex`):
  у него тот же id, что у расширения основного BaoCode. Убирает и
  `CFBundleURLTypes`: когда схему `baocode://` заявляют два приложения, система
  выбирает любое из них;
- подписывает копию ad hoc (`codesign --force --deep --sign -`);
- если папки `baocode-dev` ещё нет, копирует в неё всю папку `baocode`, кроме
  `state/*-processes.json` и `updates/`. Копия делается клонами APFS (`cp -c`) и
  почти не занимает места. Оригинал только читается. Копировать приходится до
  первого запуска: папку из `BAOCODE_DATA_DIR` приложение не создаёт, а сообщает,
  что её нет;
- прописывает в `baocode-dev/User/settings.json` `"update.mode": "none"`, чтобы
  Dev не обновился до релиза upstream, и включает фичи форка (список — в
  скрипте, `DEV_SETTINGS`).

Копируется вся папка, а не `DataDirectory.items`: в этом списке нет
`turn-stats/`, `usage/`, `bots/` и `claude/`, и без них Dev потерял бы
статистику, ботов и скачанный Claude Code.

Чтобы начать Dev с чистой копии, закрой BaoCode Dev, удали
`~/Library/Application Support/baocode-dev` и запусти скрипт с `--skip-build`.

### Что общее и что своё

Для Claude Code CLI оба приложения одинаковы: оба запускают `claude` с одним
`~/.claude` и `~/.claude.json`, поэтому история чатов, настройки, плагины, MCP и
вход у них общие.

После копии у каждого приложения своё:

- отметки BaoCode: закрепления, архив, переименования чатов, черновики, вкладки;
- статистика ходов и стоимости (`turn-stats/`, `usage/`; её видят `usage_report`
  и навык baocode-usage);
- встроенный MCP-сервер `baocode`: он обслуживает приложение, запустившее сессию.

### Ограничения

- **Не открывай один и тот же чат в обоих приложениях одновременно:** два
  процесса `claude` будут писать в один транскрипт. Разные чаты параллельно —
  можно.
- Команда `code`, ссылки `baocode://` и пункт Finder «Открыть в BaoCode» ведут в
  основной BaoCode: у команды и меню Finder зашит id `dev.baocode.desktop`, а
  схему ссылок Dev не заявляет.
- Боты переносятся вместе с папкой, но индекс memsearch бота
  (`bots/*/.memsearch/.index-state.json`) хранит путь основной папки. Если
  поиск по памяти бота в Dev врёт, переиндексируй его.
- Обычный `flutter build macos` не кладёт в приложение сервер для SSH-remote
  (его добавляет `tool/build_macos.dart`); для удалённых папок пользуйся основным
  BaoCode.
- Сборка подписана ad hoc и открывается только на этой машине.

## Мод `/plan-pane`

После того как появится вид плана (`lib/plan/`), мод `plan-pane` не нужен: он
выводит задачи текстом в чат. Это плагин `plan-pane@arseniy-local` из
`~/.claude/local-marketplace`. Отключить его: `/plugin` → `plan-pane` → Disable,
или поставить `false` у `"plan-pane@arseniy-local"` в `enabledPlugins` файла
`~/.claude/settings.json`.
