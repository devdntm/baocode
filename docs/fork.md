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
  - `lib/fork/` — общее для форка: строки, вид Cursor (`chat.look`), прокрутка
    трекпада (`workbench.scroll.momentum`);
  - `packages/fork_scroll_momentum/` — плагин macOS: инерция трекпада от системы;
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
| `lib/ide/workbench/contributions/all.dart` | `CursorLayoutContribution` (Toggle Cursor Layout, Toggle Chats, `CursorLayoutService`), `PlanContribution` (вид плана в редакторе IDE), `ClaudeContextContribution` (индекс в статус-баре), `CursorImportContribution` (Import from Cursor: команда и баннер) |
| `lib/settings/pages/general_page.dart` | строка `workbench.ide.layout` первой в группе IDE |
| `lib/ide/ide_workbench.dart` | параметр `agents` (список чатов) и выбор сетки: `CursorWorkbenchGrid` при `workbench.ide.layout: cursor` |
| `lib/ide/workbench/parts/activity_bar.dart` | параметр `axis`: иконки видов строкой над сайдбаром (`_row`); вертикальный код не тронут |
| `lib/ide/ide_layout.dart` | `IdeLayoutToggle(mirrored:)`: иконки сайдбара и чата меняются сторонами |
| `lib/ide/workbench/parts/title_bar.dart` | в раскладке Cursor тумблер списка чатов и тумблер чата слева, сайдбара справа |
| `lib/sidebar/sidebar.dart` | `Sidebar.projectMenuExtra` (пункты форка в меню проекта: индекс claude-context, Import from Cursor…); `SidebarGrouping.recent` (Pinned / Today / Last 7 days / Last 30 days / Older); параметры `project` (чаты одного проекта, без имени проекта в строках и без Open Project) и `grouping` (фиксированная группировка, без меню By …) |
| `lib/workbench.dart` | `_ideAgentsBar`: список чатов проекта (`IdeAgentsBar`) для `IdeWorkbench.agents`; `PlanSessions.of` / `.created`: в какой беседе запускать задачи плана и новый агент для «Build in New Agent»; `_fileLinks`: ссылка на план открывает вкладку Plan (`planPageRequest`), `keepPlan` |
| `lib/chat/side_panel/side_panel_view.dart` | вкладка Plan есть всегда у локального проекта: `ProjectPlansPage` (список планов проекта) вокруг `_planPage`; `PlanContext` (беседа, проект) вокруг предпросмотра плана; «Save to Project» в меню вкладки плана; `tabs.plansListed` |
| `lib/chat/side_panel/side_panel_controller.dart`, `side_panel_view.dart`, `lib/workbench.dart` | `SidePanelSection.browser`: раздел Browser (`BrowserMirror`), пока `ForkBrowser.offered`; `ForkBrowser.revealInPanel`, `ForkBrowserContribution.registerView` |
| `lib/browser/browser_tools.dart`, `lib/browser/browser_steps.dart` | `ForkBrowser.used(tabId)` у инструментов; меню шага «Show in Browser Tab» |
| `lib/ide/workbench/contributions/all.dart` (ещё) | `ForkBrowserContribution`: вкладка Browser в IDE и View: Open Browser |
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
| `packages/bao_markdown/lib/src/editor/md_style.dart`, `md_display.dart`, `md_editor.dart` | `MarkdownEditorStyle`: `blank` (пустая строка), `codePadding` (отступы у кода), `bullet`, `listGap`/`itemGap` (поля списков; `_gapOver`, поле `gap` в `_RowKey`), `fitTables` (`md_table.dart`: `build` → `_build` с шириной) |
| `lib/ide/markdown/markdown_preview.dart`, `lib/stash/stash_editor.dart` | стиль редактора через `CursorType.markdown` |
| `packages/bao_editor/tool/generate_textmate_assets.mjs`, `packages/bao_editor/pubspec.yaml`, `assets/textmate/manifest.json`, `LICENSE.txt` | встроенная тема Cursor Dark Midnight |
| `test/theme/theme_sweep_test.dart`, `test/ide/workbench/color_theme_picker_test.dart` | 14 встроенных тем, Cursor Dark Midnight в списке |
| `pubspec.yaml` | зависимости `yaml` (front matter плана) и `fork_scroll_momentum` (инерция трекпада); ассеты `tool/claude_context/bao_index.js` и `tool/cursor_import/cursor_memsearch_import.py` |
| `lib/main.dart` | `ChatLook.follow` (`chat.look`), `ScrollMomentum.follow` (`workbench.scroll.momentum`), `gestureSettings` окна (порог трекпада) |
| `lib/theme/app_theme.dart` | `buildAppTheme`: при `chat.look: cursor` текст темы с трекингом macOS (`CursorType.theme`); `codeStyle`/`uiCodeStyle` без межбуквенного интервала; `textFaint` от текста темы, где она его не задаёт |
| `lib/chat/widgets/markdown_view.dart` | `baseStyle`/`codeStyle` Cursor; `MarkdownOptions.chat()` и `cursorLook`: отступы блоков, заголовки, жирный, списки, отступы вокруг встроенного кода |
| `lib/chat/widgets/inline_code.dart` | плашка встроенного кода Cursor: цвет, радиус, одна на строку |
| `lib/chat/widgets/code_citation.dart` | блок кода Cursor: фон, рамка, радиус, без заголовка (`_plain`), отступы |
| `lib/chat/composer/composer.dart` | `_minEditorHeight`: на строку ниже при `chat.look: cursor` |
| `lib/chat/composer/composer_picker.dart` | `_buildPill`: режим — `CursorModePill` при `chat.look: cursor` |
| `lib/chat/chat_screen.dart` | `_footUnder`: в IDE ветка и размер контекста под полем ввода; `RunCommandPanel` вместо `InteractionPanel` для вопроса approve-blocked |
| `lib/chat/widgets/command_step.dart` | `CursorCommandCard` при `chat.look: cursor` |
| `lib/chat/chat_session.dart` | `RestoresCheckpoints`: `canRestoreAt`, `restoreCheckpoint`, `revertFilesFrom`, `restoredAt` (в `send` — с места чекпоинта); `ChangesReverted` перечитывает ревью |
| `lib/chat/chat_history_view.dart` | `CheckpointHover` под сообщением, бледные строки после чекпоинта, вопрос в `_submitEdit` |
| `lib/chat/widgets/shell_highlight.dart` | `shellPrograms`: программы команды для заголовка карточки |
| `lib/chat/step_folds.dart` | `isQuickStep`: команды не сворачиваются в «Ran N commands» при `chat.look: cursor` |
| `lib/ide/workbench/parts/explorer_view.dart` | `PlanExplorerPane`: раздел Plans в Explorer |
| `lib/ide/services/explorer.dart` | раздел Plans открыт с начала при `chat.look: cursor` |
| `lib/base/smooth_scroll.dart` | `velocityTrackerBuilder`: трекпад не докручивает сам, когда инерцию даёт система |

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
- ставит копии свою иконку — оригинальную с лентой DEV в углу
  (`tool/dev_app/AppIcon-dev.icns`, исходник `AppIcon-dev.png`): кладёт её в
  `Contents/Resources/AppIcon.icns` и убирает `CFBundleIconName`, чтобы система
  брала её, а не иконку из каталога ассетов;
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
  - id не показываются;
  - иконки статусов как у Cursor, тонкие контуры бледного цвета
    ([`todo_status_icons.dart`](../lib/plan/todo_status_icons.dart)): ожидает —
    круг, в работе — пунктирный круг, выполнена — круг с галочкой, отменена —
    перечёркнутый круг; те же иконки в меню статуса.

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

## Импорт из Cursor

[`lib/integrations/cursor_import/`](../lib/integrations/cursor_import/). Мастер «Import from Cursor» открывается тремя способами:

- уведомление IDE при открытии папки, где есть `.cursor`, `.cursorrules` или проект в `~/.cursor/projects/<путь с дефисами>`; после «Not now» для этой папки оно больше не показывается (`<data>/cache/cursor-import/put-off.json`);
- команда палитры «Import from Cursor…»;
- меню проекта в сайдбаре.

Части выбираются галочками:

- **Правила.** `.cursor/rules/**/*.mdc` и `.cursorrules` переносятся в `.claude/rules/*.md`: `globs` становятся `paths:`, `alwaysApply` и `description` убираются. Правило, которое Cursor применял «по описанию», в Claude Code будет читаться всегда — мастер это помечает. Существующие файлы не перезаписываются; текст каждого правила можно раскрыть и посмотреть до импорта.
- **MCP.** Из `.cursor/mcp.json` в `.mcp.json` добавляются только серверы, которых там ещё нет: `${env:X}` превращается в `${X}`, у сервера с `url` без `type` ставится `http`.
- **История в memsearch.** Скрипт [`tool/cursor_import/cursor_memsearch_import.py`](../tool/cursor_import/cursor_memsearch_import.py) (бывший `~/.claude/scripts/cursor_memsearch_import.py`, с командой `count` и `CLAUDE_BIN`) работает в три этапа:
  - `summarize` пересказывает реплики Claude Haiku в кэш `.memsearch/cursor-import-cache`;
  - `assemble` раскладывает пересказы по дневным журналам `.memsearch/memory`; дни, где импорт Cursor уже есть, не перезаписываются;
  - затем `memsearch index` в коллекцию проекта (`derive-collection.sh` плагина).

  Работа платная и долгая: мастер сначала показывает число реплик, затем прогресс; после закрытия мастера она продолжается. Пункт доступен, только если стоят плагин memsearch и его CLI.
- **Темы.** Темы Cursor из `/Applications/Cursor.app/…/extensions/theme-cursor` упаковываются в `.vsix` (`ditto`) и ставятся как расширение.
- **Клавиши.** Кнопка открывает существующий импорт клавиш из настроек (`AppSettings.showImport`, он знает Cursor).

## Вид Cursor: `chat.look`

`"chat.look": "cursor"` (в Dev включено, по умолчанию `baocode`) —
[`lib/fork/cursor_look.dart`](../lib/fork/cursor_look.dart). Значения взяты из
CSS самого Cursor (`/Applications/Cursor.app/.../workbench.*.css`, `.rendered-markdown`)
и сверены по скриншотам.

- **Шрифт.** Семейства те же, что у Cursor: SF Pro и Menlo. Разница была в
  интервале: Material 3 даёт тексту внутри `Material`/`Scaffold` `letterSpacing: 0.25`,
  и буквы BaoCode стояли реже. При `chat.look: cursor` тема тянет текст, как это
  делает сама macOS (`CursorType.tracking`, −0,003 em), код идёт без интервала.
  Тема собирается при запуске: после смены настройки нужен перезапуск.
- **Чат:** 14/22,4; абзацы через 10, заголовки 17/17/14/13 с 16 до и 4 после;
  жирный — 600 в цвете текста; встроенный код — Menlo 12 на плашке цвета
  текста (8%), отступ 0,3 em, радиус 4; списки с отступом 28.
- **Markdown вне чата** (предпросмотр `.md` в IDE, планы, предпросмотр файла в
  чате, Customize, Stash) — тот же текст через `CursorType.markdown`: размер,
  интервал, встроенный код; заголовки и жирный — как в предпросмотре Cursor
  (`##` 20 pt, 600, в цвете текста; жирный 600). Правки в `bao_markdown`
  (`MarkdownEditorStyle`, всё по умолчанию выключено): пустая строка между
  абзацами 10 pt (`blank`), по 0,3 em по бокам кода на плашке (`codePadding`,
  неразрывные пробелы только для показа), маркер списка крупнее (`bullet`),
  10 pt над списком сразу после абзаца и под ним, 2 pt между пунктами
  (`listGap`, `itemGap`), отступ уровня 20.
- **Бледный текст по теме.** `AppColors.textFaint` (`disabledForeground`): где
  тема его не задаёт (Cursor Dark Midnight), — её текст на 50%, а не серый
  `#CCCCCC80` из реестра VS Code; так выглядят зачёркнутые задачи плана,
  пустые кружки задач и прочие бледные подписи.
- **Как у Cursor в цвете текста:** заголовки, жирный, шапка таблицы, маркеры
  списков; маркер — крупный кружок; пункты «свободного» списка (с пустыми
  строками между ними) через 10 pt.
- **Таблицы** во всю ширину чата или страницы: колонки делят её по
  содержимому, как авто-раскладка таблицы в браузере (у каждой не меньше её
  самого длинного слова), текст переносится; где не влезают и слова, они
  рвутся, как у Cursor ([`cursor_table.dart`](../lib/fork/cursor_table.dart);
  в markdown — `MarkdownEditorStyle.fitTables`). Шапка без заливки, линии
  бледные, радиус 10.
- **Блоки кода.** В чате — на фоне чата, рамка цвета текста 10%, радиус 10,
  без строки с языком (язык только подсвечивает; копирование — по наведению;
  у цитаты файла заголовок остаётся), строки не переносятся
  (`code_citation.dart`, `_CodeCardState`). В markdown — заливка цвета текста
  8% без рамки, радиус 6, отступы 10/8.
- **Чекпоинты** ([`checkpoints.dart`](../lib/fork/checkpoints.dart)). Под своим
  сообщением, у которого после него есть правки агента, при наведении — стрелка
  назад в его правом нижнем углу, как у Cursor (подсказка «Restore
  checkpoint»). После подтверждения файлы возвращаются к состоянию до
  этого сообщения (`rewind_files` Claude Code, правки его инструментов, не
  команд), сообщение и всё после него бледнеют; следующее сообщение идёт с
  этого места (`rewind_conversation`, как правка сообщения), «Keep the
  conversation» снимает это. Правка старого сообщения с правками после него
  спрашивает: «Revert and submit» / «Continue without reverting».
- **Поле ввода** на строку ниже: текст сразу над кнопками. Режим (Agent, Ask,
  Plan) — круглая плашка цвета текста без рамки, надпись и иконка светлые
  ([`mode_pill.dart`](../lib/fork/mode_pill.dart), `ComposerPicker._buildPill`).
- **IDE:** колонка чата доходит до низа окна, и в ряду статус-бара под ней —
  ветка и «146K / 1M», как в режиме чата (левые пункты статус-бара — под списком
  чатов, правые — под редактором; `cursor_grid.dart`, `_chatPart`); чат на месте
  редактора — с этой строкой под полем ввода. В Explorer
  раздел Plans ([`plan_explorer_pane.dart`](../lib/plan/plan_explorer_pane.dart)),
  открытый с начала; клик открывает план в редакторе.
- **Команды** ([`command_card.dart`](../lib/fork/command_card.dart)): карточка
  «›_ описание  cd, python3»; пока ничего не выведено — одна строка; когда вывод
  есть — его последние 4 строки, бледнее кверху; по клику — команда и весь вывод.
  Цвета — от цвета текста темы: заголовок 60%, программы и хвост вывода 36%,
  открытый вывод 55%. Команда — в цветах темы редактора (грамматика shell через `colorizeBlock`, как у блоков кода). Каждая команда отдельно, не в «Ran N commands».
- **Отказ auto mode** ([`run_command_panel.dart`](../lib/fork/run_command_panel.dart)):
  вопрос мода approve-blocked (заголовок `Auto mode`, варианты `Разрешить`,
  `Отклонить`, `Allowlist '<программа>'`) рисуется карточкой «Run command: npm»:
  команда, слева «Ask Every Time ⌄» / «Allowlist 'npm'», справа Skip и Run ⏎
  (Enter, Esc). Ответ — вариант самого мода, логика (`Bash(npm:*)` в
  `permissions.allow`) у него же, так что в терминале это обычный вопрос.

## Страница браузера

Upstream убрал её из боковой панели в 1.9.0 (`b19154e8`, #665); в форке она
вернулась, как у Cursor, при `chat.look: cursor` и подключённом браузере
([`lib/fork/browser/`](../lib/fork/browser/)):

- **Зеркало вкладки** — `browser_mirror.dart`, файл upstream до удаления, строки
  форка. Показывает вкладку, с которой агент работал последним
  (`ForkBrowser.used` из инструментов `browser_*`), или выбранную из
  общих; в ней можно кликать и печатать.
- **В режиме чата** — раздел Browser боковой панели (`SidePanelSection.browser`).
- **В IDE** — вкладка редактора (`FileViews`, путь `ForkBrowser.idePath`, файла
  нет): View: Open Browser в палитре.
- **Шаг браузера в чате** — правый клик «Show in Browser Tab»: вкладка в IDE,
  в окне агентов — раздел боковой панели.

## Встроенная тема Cursor Dark Midnight

Тема Cursor Dark Midnight (из `theme-cursor` в Cursor.app, Anysphere; лицензии у
файла нет) встроена рядом с Bao Dark/Bao Light: исходник —
`packages/bao_editor/tool/textmate_themes/theme-cursor/`, в бандле —
`assets/textmate/themes/theme-cursor/`, запись в `manifest.json`, папка в
`pubspec.yaml` пакета. Генератор ассетов (`generate_textmate_assets.mjs`) несёт
её в `localThemes`; у неё нет `include`, поэтому генератор его не требует.
Остальные темы Cursor ставит «Import from Cursor» расширением.

## Прокрутка трекпада: `workbench.scroll.momentum`

`"workbench.scroll.momentum": "system"` (в Dev включено, по умолчанию `flutter`) —
[`lib/fork/scroll_momentum.dart`](../lib/fork/scroll_momentum.dart) и плагин
[`packages/fork_scroll_momentum`](../packages/fork_scroll_momentum).

- **Инерция.** Встраиватель Flutter для macOS выбрасывает события инерции системы
  (`dispatchGestureEvent` в `FlutterViewController.mm`) и докручивает сам по своей
  физике. Плагин ставит локальный монитор `scrollWheel` и шлёт в Dart каждое событие
  инерции с точкой под курсором (view Flutter, её точки) и дельтами; Dart продолжает
  ими жест трекпада (`PointerPanZoom*` своего устройства), как пальцами, 1:1. Своя
  докрутка Flutter для трекпада выключена (`NoFlingVelocityTracker` в
  `BaoScrollBehavior.velocityTrackerBuilder`; редактор берёт его же).
- **Порог.** Списки брали жест трекпада после 18 px (`kTouchSlop`), и начало
  свайпа терялось; теперь 3 px (`MediaQuery.gestureSettings`). Жест инерции
  начинается шагом чуть за порог: Flutter выбрасывает то, что сдвинулось до
  принятия жеста.
- Колесо мыши не тронуто.

## Окружение Claude Code: claude-setup

Всё, что BaoCode Dev ждёт от Claude Code на машине, лежит в отдельном приватном
репозитории `devdntm/claude-setup` (локально `~/Downloads/claude-setup`):

- маркетплейс `arseniy-local` с плагинами `approve-blocked` и `cursor-plan`;
- глобальный `~/.claude/CLAUDE.md` и `~/.claude/scripts`;
- фрагменты `~/.claude/settings.json` и `~/.claude.json` (сервер `claude-context`);
- `docker-compose.yml` Milvus, `package.json` сервера claude-context, конфиг memsearch.

`~/.claude/local-marketplace`, `~/.claude/CLAUDE.md` и `~/.claude/scripts` — ссылки
в этот репозиторий, так что правки плагинов и правил сразу видны в его git. На
новой машине:

```sh
git clone git@github.com:devdntm/claude-setup.git ~/Downloads/claude-setup
~/Downloads/claude-setup/install.sh --baocode   # --check: только показать, чего нет
```

Мод `plan-pane` (задачи плана текстом в чате) с видом плана не нужен: он
выключен и из маркетплейса убран, в истории `claude-setup` он остался.
