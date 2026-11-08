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
| `lib/ide/workbench/contributions/all.dart` | `CursorLayoutContribution` (Toggle Cursor Layout, Toggle Chats, `CursorLayoutService`), `PlanContribution` (вид плана в редакторе IDE), `ClaudeContextContribution` (индекс в статус-баре) |
| `lib/settings/pages/general_page.dart` | строка `workbench.ide.layout` первой в группе IDE |
| `lib/ide/ide_workbench.dart` | параметр `agents` (список чатов) и выбор сетки: `CursorWorkbenchGrid` при `workbench.ide.layout: cursor` |
| `lib/ide/workbench/parts/activity_bar.dart` | параметр `axis`: иконки видов строкой над сайдбаром (`_row`); вертикальный код не тронут |
| `lib/ide/ide_layout.dart` | `IdeLayoutToggle(mirrored:)`: иконки сайдбара и чата меняются сторонами |
| `lib/ide/workbench/parts/title_bar.dart` | в раскладке Cursor тумблер списка чатов и тумблер чата слева, сайдбара справа |
| `lib/sidebar/sidebar.dart` | `Sidebar.projectMenuExtra` (пункты форка в меню проекта: индекс claude-context); `SidebarGrouping.recent` (Pinned / Today / Last 7 days / Last 30 days / Older); параметры `project` (чаты одного проекта, без имени проекта в строках и без Open Project) и `grouping` (фиксированная группировка, без меню By …) |
| `lib/workbench.dart` | `_ideAgentsBar`: список чатов проекта (`IdeAgentsBar`) для `IdeWorkbench.agents`; `PlanSessions.of` / `.created`: в какой беседе запускать задачи плана и новый агент для «Build in New Agent»; `_fileLinks`: ссылка на план открывает вкладку Plan (`planPageRequest`), `keepPlan` |
| `lib/chat/side_panel/side_panel_view.dart` | вкладка Plan есть всегда у локального проекта: `ProjectPlansPage` (список планов проекта) вокруг `_planPage`; `PlanContext` (беседа, проект) вокруг предпросмотра плана; «Save to Project» в меню вкладки плана; `tabs.plansListed` |
| `lib/chat/side_panel/side_panel_controller.dart` | `SidePanelTabs.plansListed` (страница Plan без открытого плана), `keepPlan` (план сессии, прочитанный с историей, без показа) |
| `lib/chat/side_panel/file_open.dart` | `FileLinkTarget.keepPlan` |
| `lib/chat/chat_screen.dart` | `_followPlan`: план, прочитанный с историей (`planReplayed`), кладётся во вкладку Plan без переключения на неё |
| `lib/chat/chat_session.dart` | `planReplayed` |
| `lib/chat/widgets/plan_start.dart` | для файла плана `PlanStartBar` — это `PlanBuildBar` (Build как в Cursor) |
| `lib/chat/widgets/plan_card.dart` | последняя карточка файла плана: Build под ней, и под свёрнутой строкой отправленного на доработку плана |
| `lib/kernel/kernel_event.dart`, `lib/kernel/transcript.dart` | `PlanWritten.replayed`, `Transcript.planReplayed` |
| `lib/kernel/claude_code/claude_code_translator.dart` | `PlanWritten` и при повторном чтении истории (`replayed: replaying`) |
| `lib/ide/markdown/markdown_preview.dart` | `PlanPreview.footer` (задачи плана под текстом) и `PlanPreview.frontMatter` (у плана — только `overview`) |
| `packages/bao_markdown/lib/src/editor/md_editor.dart` | параметр `footer`: виджет после строк в той же прокрутке |
| `pubspec.yaml` | зависимость `yaml` (front matter плана); ассет `tool/claude_context/bao_index.js` |

Колонка редактора с панелью в
[`lib/ide/cursor_layout/cursor_grid.dart`](../lib/ide/cursor_layout/cursor_grid.dart)
(`_editorColumn`, `_panelSlot`, `_dragPanel`, `_dragTo`) скопирована из
`lib/ide/workbench/parts/grid.dart`, где она приватная. При слиянии upstream
сверяй её с оригиналом: `git diff ORIG_HEAD -- lib/ide/workbench/parts/grid.dart`.

Группировка `recent` хранится в state.json как `"grouping": "recent"`. Сборка
upstream такого значения не знает и показывает «By project» (`_grouping` в
sidebar.dart откатывается к `project`), а само значение не трогает.

В списке чатов IDE «Skills» и «Stash» переключают окно в режим чата и открывают
там свою страницу: эти страницы встают на место чата.

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

## Вид плана

План — файл в папке `plans` (`ClaudeTranslator.isPlanPath`) или `*.plan.md` — показывается как в Cursor ([`lib/plan/`](../lib/plan/)).

- **Формат.** Задачи лежат во front matter, как у Cursor: `todos: [{id, content, status}]`, статусы `pending`, `in_progress`, `completed`, `cancelled` ([`plan_todos.dart`](../lib/plan/plan_todos.dart)). Старые планы с разделом `## Задачи` читаются как раньше; при первом изменении задач из интерфейса они переносятся во front matter, а раздел удаляется из текста.
- **Задачи — в конце документа,** в той же прокрутке, что и текст (`MarkdownEditor.footer`). Блок «N To-dos»:
  - «+ New» добавляет задачу;
  - по клику задача выбирается, появляются «N To-dos Selected», крестик и «Build in New Agent»;
  - по наведению — Run и меню: статус, удаление;
  - id не показываются.

  Front matter плана таблицей свойств не рисуется: видно только `overview`. Файл перечитывается раз в секунду, так что отметки агента видны сразу.
- **Build** ([`plan_build.dart`](../lib/plan/plan_build.dart)) стоит рядом с выбором модели:
  - пока план ждёт одобрения, кнопка называется Start, как в upstream, но одобряет план вместе с открытыми задачами;
  - после одобрения Build отправляет открытые задачи в этот чат, стрелка рядом — «Build in New Agent».

  Строка есть во вкладке Plan, на последней карточке плана в истории и над планом в редакторе IDE.
- **Куда уходят задачи.** В беседу, которая написала план, иначе в чат IDE этой папки (новый, если его нет). Текст: `/cursor-plan:todos id1 id2 <путь>`, если у агента есть эта команда, иначе шаблон Cursor с просьбой ставить статусы во front matter.
- **Планы проекта** ([`project_plans.dart`](../lib/plan/project_plans.dart)). Вкладка Plan боковой панели есть у любого локального проекта: слева список его планов, справа открытый. В список попадают:
  - `.cursor/plans/*.plan.md`;
  - планы из `~/.claude/plans`, о которых упоминают транскрипты проекта.

  «Save to Project» (в меню у стрелки рядом с Build и в меню вкладки плана) копирует план в `.cursor/plans/<заголовок>_<8 hex>.plan.md` в формате Cursor и открывает копию.
- **После перезапуска** беседа помнит свой план: `PlanWritten` отправляется и при повторном чтении истории, а вкладка Plan восстанавливается без переключения на неё. Ссылка на файл плана из текста чата открывает вкладку Plan.
- **В редакторе IDE** — предпросмотр markdown с задачами под текстом и строкой Build сверху (`PlanContribution`). Исходник — обычный текстовый редактор. Читается только локальный файл: план беседы на SSH-хосте показывается без задач.

Новые планы пишутся в этом формате по правилам плагина `cursor-plan@arseniy-local` (`~/.claude/local-marketplace/plugins/cursor-plan`, с версии 0.1.2): `prompts/plan-mode.md` и навык `todos`, который ставит статусы во front matter.

## Индекс claude-context

[`lib/integrations/claude_context/`](../lib/integrations/claude_context/) и помощник [`tool/claude_context/bao_index.js`](../tool/claude_context/bao_index.js) (в приложении — ассет, копируется в `<data>/cache/claude-context/`).

- **Помощник.**
  - `check` считает индекс прямо в Milvus и сверяет с merkle-снимком: чанки, файлы в индексе и в проекте, недостающие по папкам, статус из `mcp-codebase-snapshot.json`. `get_indexing_status` не вызывается: он врёт.
  - `index [--force]` запускает сервер claude-context дочерним процессом с командой и окружением из `mcpServers`, просит `index_codebase` по MCP-stdio и держит его до честного `completed`.
  - `clear` вызывает `clear_index`.

  С `--json` каждая строка вывода — событие. Запускается через `node` сервера; процесс записан в `state/claude-context-processes.json`, так что после падения BaoCode его остаток будет завершён.
- **Где видно.**
  - Статус-бар IDE: «Index 2488/2488», при индексации — проценты. По клику — меню: сколько проиндексировано, недостающие папки, Index, Reindex All… (с подтверждением), Check.
  - Меню проекта в сайдбаре режима чата: «Index for Search» с состоянием и «Reindex All…».
- **«Index interrupted»:** снапшот говорит `indexing`, а сервера нет. Нужна полная переиндексация.
- **Под `flutter test`** индекс не трогается (`ClaudeContextIndex.enabled`): иначе тесты читали бы настоящий `~/.claude.json` и запускали node.

## Мод `/plan-pane`

С видом плана мод `plan-pane` не нужен: он выводит задачи текстом в чат. Это плагин `plan-pane@arseniy-local` из
`~/.claude/local-marketplace`. Отключить его: `/plugin` → `plan-pane` → Disable,
или поставить `false` у `"plan-pane@arseniy-local"` в `enabledPlugins` файла
`~/.claude/settings.json`.
