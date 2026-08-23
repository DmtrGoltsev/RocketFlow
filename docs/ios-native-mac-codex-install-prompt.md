# Промпт для Codex на новом Mac: проверка и установка RocketFlow на iPhone

Скопируйте весь блок ниже в новую задачу Codex на Mac. Handoff публикуется двумя
коммитами: tooling commit A фиксирует `.gitignore`, Device config example, все
Mac scripts/tests и validation step workflow `ios-verify`, затем проходит manual
iOS Verify на exact SHA A. Последующий docs commit B содержит этот prompt и
ссылается на immutable SHA A/run A ниже. SHA B намеренно не фиксируется и не
должен совпадать с A.

```text
Ты работаешь на новом Mac и должен безопасно подготовить, проверить, подписать,
установить и запустить native iOS RocketFlow на моём физическом iPhone. Доведи
задачу до доказуемого результата. Рутинные команды выполняй сам; обращайся ко
мне только для неизбежных системных подтверждений macOS/GitHub/Apple и
физического взаимодействия с iPhone.

Исходные данные:
REPOSITORY="DmtrGoltsev/RocketFlow"
BRANCH="codex/native-ios-companion"
TOOLING_SHA="a66b501f2a5ec8d8d25dc518a9fcd097e5ee1149"
TOOLING_RUN_ID="32669924719"
TOOLING_RUN_URL="https://github.com/DmtrGoltsev/RocketFlow/actions/runs/32669924719"
TOOLING_JOB_ID="97269056380"
IMMUTABLE_APP_SHA="35e98d965cf49a356e5a7a7ebdbc59afaa1f9fb3"
IMMUTABLE_APP_CI_RUN="32655691351"
MASTER_BASELINE_SHA="7d1ac74cf8f2bf7935c2578f3675db4ca54764bb"
CANDIDATE_CI_POLICY_SHA="0bbf4acb0ba9620b931fa843dc9d2997379304fb"
NATIVE_DIR="ios"
PROJECT="RocketFlow.xcodeproj"
VERIFY_SCHEME="RocketFlow-CI"
DEVICE_SCHEME="RocketFlow"
TARGET="RocketFlow"
MINIMUM_IOS="16.0"
XCODEGEN_VERSION="2.46.0"
API_BASE_URL="http://45.10.110.42/rocket-api"
HEALTH_URL="http://45.10.110.42/rocket-api/health"
DEFAULT_DEVICE_MODE="no-push"
TOOLING_PATHS=(
  ".github/workflows/ios-verify.yml"
  ".gitignore"
  "ios/Config/Device.xcconfig.example"
  "ios/scripts/mac-handoff-common.sh"
  "ios/scripts/mac-preflight.sh"
  "ios/scripts/mac-verify.sh"
  "ios/scripts/mac-build-device.sh"
  "ios/scripts/mac-install-device.sh"
  "ios/scripts/tests/mac-handoff-tests.sh"
)

Критические правила:
- TOOLING_SHA, TOOLING_RUN_ID/URL и TOOLING_JOB_ID являются финальным immutable
  tooling evidence. Если GitHub run отсутствует, URL/ID не согласованы или run
  head SHA не равен TOOLING_SHA, остановись до build/sign/install.
- TOOLING_SHA является immutable commit A для exact `TOOLING_PATHS` выше;
  это полный identity scope: `.gitignore`, Device example, все текущие Mac
  scripts/tests и workflow с `Validate Mac handoff scripts` step.
  TOOLING_RUN_ID обязан быть успешным manual iOS Verify именно на SHA A. Текущий
  checkout содержит более поздний docs commit B или последующий candidate HEAD;
  равенство HEAD и TOOLING_SHA не требуется и обычно неверно.
- IMMUTABLE_APP_SHA и IMMUTABLE_APP_CI_RUN являются отдельным историческим
  доказательством green app build/test. Не приравнивай app SHA, tooling SHA и
  текущий docs HEAD.
- CI scheduling из CANDIDATE_CI_POLICY_SHA пока candidate-only. `origin/master`
  на MASTER_BASELINE_SHA не содержит этот commit или `ios-verify`; automatic
  PR/push-to-master contract станет default-branch behavior только после merge.
  Branch protection не настроена, а её docs-настройки только рекомендательные.
  Production deploy/package/rollback workflows этим CI commit не менялись.
- Сначала прочитай `AGENTS.md`, `Ru_OrchestratorRules.md` и
  `Ru_SubagentFirstFinishNew.md`. Основной чат действует как оркестратор:
  запускает настоящего planner, проверяет план и выдаёт bounded подзадачи
  отдельным audit/toolchain/QA исполнителям с осознанными reasoning levels.
- Первый технический этап только read-only audit. Не меняй tracked source,
  config, scripts, workflows или docs без доказанного blocker и отдельного
  решения пользователя. Эта задача не является implementation-задачей.
- Не создавай commit и не делай push. Допустимы только ignored
  `ios/Config/Device.xcconfig`, DerivedData, Xcode/Firebase local metadata и
  sanitized evidence вне репозитория.
- Не выполняй Archive, export IPA, App Store/TestFlight/ad hoc/public
  distribution и не используй сторонние signing-сервисы.
- Не выполняй backend/web deploy, Flyway/migration/seed и не подключайся к
  production DB. Production остаётся на backend SHA
  `50a63270ae094fe08ee57b945be0930cb1115dfe`, Flyway V21. Candidate V22 для iOS
  device registrations не deployed.
- Режим по умолчанию `no-push`: отсутствие Firebase/APNs/V22 не блокирует signed
  build, install, launch, login, Planner/Calendar/Focus и local reminders.
- Режим `push` опционален и включается только после явного выбора пользователя,
  проверки локального ignored Firebase plist, bundle match, Apple provisioning
  и APNs/Firebase setup. Даже успешный push-capable build не доказывает
  production push, пока V22 не deployed.
- Не проси и не принимай в чате macOS/Apple ID/GitHub пароли, 2FA-коды,
  certificates, provisioning profiles, private keys, Firebase/APNs credentials,
  bearer/refresh tokens или production secrets.
- Пользователь выбирает только Apple Team, owner-controlled bundle identifier и
  физический iPhone. Apple Account добавляется только через Xcode UI; Team ID и
  bundle identifier записываются только в ignored `Device.xcconfig` для
  scripted build, не в Xcode project и не в чат. UDID, Team ID, serial,
  certificate/profile details и device identifiers всегда редактируй из
  evidence.
- Production login/password пользователь вводит только непосредственно в
  приложение на iPhone. Не извлекай токены из Keychain, device logs или traffic.
- Tooling scripts обязаны fail closed проверить exact endpoint
  `http://45.10.110.42/rocket-api` и ATS allowlist: `NSExceptionDomains`
  содержит ровно один domain `45.10.110.42`, для него insecure HTTP разрешён и
  `NSIncludesSubdomains=false`; broad-load keys и любые дополнительные exception
  domains запрещены. Не создавай и не используй `Local.xcconfig` в этом
  handoff. Любая смена endpoint/ATS или отсутствие script-level проверки — stop
  и отдельный security review. HTTPS остаётся внешним gate для public/App Store.

1. Оркестрация и audit-first

После обязательного planner выполни в таком порядке:
- read-only repository auditor: revision, docs, scripts/config contracts,
  tracked/ignored state, current production/release boundaries;
- Mac toolchain verifier: Xcode/Swift/XcodeGen/GitHub CLI и simulator inventory;
- simulator QA executor: exact XcodeGen/project/package parity и tests;
- device/signing executor: только после green audit и simulator gates;
- final reviewer: evidence/redaction, git cleanliness и честный verdict.

Audit и toolchain inventory можно собирать параллельно. Signing/device install
всегда идут последовательно после успешного simulator verification. Если
subagent/delegation недоступны, сообщи orchestration blocker и не подменяй
основной чат ручным исполнением.

2. Подготовка Mac

Сохрани в локальный sanitized evidence версии/результаты:
`sw_vers`, `uname -m`, `xcode-select -p`, `xcodebuild -version`,
`swift --version`, `git --version`, `gh --version`, `xcodegen --version`,
`xcrun devicectl version` или доступный эквивалент.

Нужен полный Xcode с iOS 16+ SDK, а не только Command Line Tools. До любой
системной установки коротко сообщи пользователю, что и зачем устанавливается,
какая команда будет выполнена и ожидается ли системное окно/password/restart.
Пароль администратора вводится только в системном prompt.

Требуется exact XcodeGen 2.46.0. Не генерируй проект другой версией. Сначала
используй `ios/scripts/mac-preflight.sh`; если он указывает официальный install
path, следуй ему. Иначе сверяй официальный XcodeGen release и checksum с
`.github/workflows/ios-verify.yml`. Не принимай случайную более новую Homebrew
версию как эквивалент.

3. GitHub без передачи токена

- Выполни `gh auth status`.
- Если входа нет, запусти
  `gh auth login --hostname github.com --git-protocol https --web`.
- Пользователь только подтверждает browser/device authorization; токен не
  показывай и не сохраняй в evidence.
- Выполни `gh auth setup-git` и повторно проверь статус.

4. Чистый clone, актуальные docs и immutable tooling

- Используй `~/Developer/RocketFlow`. Если каталог уже существует, ничего не
  удаляй: проверь remote/status или создай новый чистый sibling-каталог.
- Клонируй `gh repo clone "$REPOSITORY"`.
- Выполни `git fetch --prune origin`.
- Проверь наличие `origin/$BRANCH` и выполни detached checkout актуального
  `origin/$BRANCH`, чтобы читать последний candidate/docs state после fetch.
- Сохрани наблюдаемый `DOCS_HEAD="$(git rev-parse HEAD)"`. Это не pinned marker и
  он не обязан совпадать с TOOLING_SHA.
- Проверь `git cat-file -e "$TOOLING_SHA^{commit}"` и что TOOLING_SHA является
  ancestor текущего DOCS_HEAD:
  `git merge-base --is-ancestor "$TOOLING_SHA" "$DOCS_HEAD"`.
- Проверь, что IMMUTABLE_APP_SHA является ancestor TOOLING_SHA через
  `git merge-base --is-ancestor "$IMMUTABLE_APP_SHA" "$TOOLING_SHA"`.
- Докажи, что exact `TOOLING_PATHS` byte-for-byte не менялись после commit A:
  `git diff --exit-code "$TOOLING_SHA..$DOCS_HEAD" -- "${TOOLING_PATHS[@]}"`.
  Любой diff является blocker; docs commit B может менять только документацию.
- Проверь `git status --short`: до локальной device-конфигурации worktree должен
  быть чистым.
- Не переключай checkout обратно на TOOLING_SHA: последующая процедура должна
  использовать актуальные docs при доказанно неизменном tooling A.

5. Источники истины

До запуска скриптов прочитай как минимум:
- `AGENTS.md`;
- `Ru_OrchestratorRules.md`;
- `Ru_SubagentFirstFinishNew.md`;
- `README.md`;
- `docs/33-current-state-summary.md`;
- `docs/58-github-cicd-policy.md`;
- `docs/70-native-ios-parity-contract.md`;
- `docs/71-native-ios-delivery.md`;
- `docs/72-native-ios-mac-device-handoff.md`;
- `docs/ios-native-mac-codex-install-prompt.md`;
- `ios/README.md`;
- `ios/project.yml` и committed `Package.resolved`;
- `.github/workflows/ios-verify.yml`;
- `ios/Config/Device.xcconfig.example`;
- `ios/RocketFlow/Resources/Info.plist` и `RocketFlow.entitlements`;
- четыре `ios/scripts/mac-*.sh` файла и их `--help`/usage.

Сверь документацию со скриптами. Если имена, flags, defaults, config keys,
scheme/configuration или redaction policy расходятся, не угадывай интерфейс и не
редактируй source: остановись с точным diff/contract blocker.

6. Локальное evidence

Создай каталог вне Git, например
`~/Desktop/rocketflow-ios-evidence-YYYYMMDD-HHMMSS`. Сохраняй туда:
- sanitized tool versions и revision inventory;
- preflight/verify/build/install logs;
- `.xcresult`, если скрипт его создаёт;
- sanitized built-product/signing/Info.plist checks;
- smoke checklist и `SUMMARY_SANITIZED.md`.

Не сохраняй credentials, cookies, tokens, Team ID, UDID, serial, certificates,
profiles, plist contents, private task text, account email или production
response bodies. Ничего не загружай и не коммить.

7. Independent CI evidence

Через `gh` проверь оба независимых слоя:
- IMMUTABLE_APP_CI_RUN завершён `success`, его head SHA строго равен
  IMMUTABLE_APP_SHA; baseline содержит 540 unit и 2 UI tests, xcresult artifact
  `9497494137`, generated-project artifact `9497494432`;
- TOOLING_RUN_ID по TOOLING_RUN_URL завершён `success`, job ID равен
  TOOLING_JOB_ID, а head SHA строго равен TOOLING_SHA. Канонические результаты:
  Mac handoff contracts `174/174` PASS, `0` skipped; XcodeGen `2.46.0`
  generation, committed-project parity, package resolution/lock parity и no-sign
  simulator build PASS; unit `540` passed / `0` failed, UI `2` passed / `0`
  failed, total `542` passed / `0` failed. Artifacts:
  `RocketFlow-xcresult`, ID `9501177125`, `1,317,064` bytes; и
  `RocketFlow-xcodeproj-xcodegen-2.46.0`, ID `9501179599`, `25,070` bytes.
  Workflow step `Validate Mac handoff scripts` обязан выполнить именно
  `bash -n ios/scripts/*.sh ios/scripts/tests/*.sh` и
  `bash ios/scripts/tests/mac-handoff-tests.sh` до Xcode build/test gates.

Run A не доказывает последующий docs commit B; это нормально, поскольку diff
tooling paths между A и текущим HEAD проверяется отдельно. Не подменяй tooling
run старым app run. Если run отсутствует, pending,
failed, cancelled, имеет другой head SHA или ожидаемые artifacts/gates не
совпадают, остановись до signing/install.

Оба iOS evidence run являются manual feature-branch runs, пока candidate policy
не merged. Не заявляй, что `master` уже автоматически выполняет `ios-verify`, и
не представляй branch-protection recommendations как настроенные checks.

8. XcodeGen parity, packages и simulator

Из корня repository сначала прочитай usage:
- `bash ios/scripts/mac-preflight.sh --help`;
- `bash ios/scripts/mac-verify.sh --help`;

`mac-preflight.sh` требует уже заполненный Device.xcconfig, поэтому на этом этапе
его не запускай. Сначала выполни:

- `bash ios/scripts/mac-verify.sh`.

Не придумывай flags, которых нет в usage. `mac-preflight.sh` должен подтвердить
полный Xcode, exact XcodeGen 2.46.0, required CLIs, доступный iPhoneOS SDK с
версией не ниже 16.0 и repository layout. `mac-verify.sh` должен воспроизвести
XcodeGen generation/committed project parity, package resolution/lock parity,
no-sign simulator build и tests.

До принятия TOOLING_SHA проверь в run A отдельный успешный запуск
`bash ios/scripts/tests/mac-handoff-tests.sh`. Expanded contract suite должен
fail closed покрывать как минимум: placeholder/unsupported signing config,
redaction и paths with spaces; exact XcodeGen; `no-push` stripping; Firebase
plist presence/bundle match; exact production endpoint и strict ATS allowlist без
broad loads или дополнительных exception domains; iPhoneOS SDK >=16; install
mode/argument contract; post-build bundle/codesign/entitlements; Team и
`application-identifier`; embedded provisioning/device match. Если этих
script-level проверок нет, не заменяй их ручным чтением файлов: остановись,
потому что tooling A не соответствует handoff contract.

Дополнительно проверь после scripts:
- `git diff --exit-code -- ios/RocketFlow.xcodeproj`;
- committed `Package.resolved` не изменился;
- `git status --short` не содержит tracked changes;
- выбран реальный available simulator, а не hardcoded unavailable model;
- build использует scheme `RocketFlow-CI` и signing disabled;
- фактический test result соответствует script/CI verdict.

Любой project/package drift, compile/test failure или tracked mutation является
blocker. Сохрани diagnostics, но не исправляй код в install-задаче.

9. Локальная device-конфигурация

Только после green simulator gate:
- сначала выполни fail-closed guard:
  `if [[ -e ios/Config/Device.xcconfig || -L ios/Config/Device.xcconfig ]]; then echo "Device.xcconfig already exists; review it without overwriting." >&2; exit 1; fi`;
  если файл уже существует, не перезаписывай его и не копируй example поверх
  него. Остановись и переиспользуй его только после осознанной проверки, что это
  ожидаемый локальный config;
- только при отсутствии файла скопируй `ios/Config/Device.xcconfig.example` в
  `ios/Config/Device.xcconfig`;
- выполни `git check-ignore -v ios/Config/Device.xcconfig`; если файл не ignored,
  остановись до внесения Team/bundle данных;
- выполни
  `if git ls-files --error-unmatch -- ios/Config/Device.xcconfig >/dev/null 2>&1; then echo "Device.xcconfig must remain untracked." >&2; exit 1; fi`;
  config должен оставаться ignored и untracked;
- прочитай comments/example и заполни только документированные keys:
  `DEVELOPMENT_TEAM`, `PRODUCT_BUNDLE_IDENTIFIER`, `CODE_SIGN_STYLE`,
  `CODE_SIGNING_ALLOWED`, `CODE_SIGNING_REQUIRED`;
- попроси пользователя выбрать Apple Team, уникальный owner-controlled bundle
  identifier и один подключённый iPhone;
- запиши выбранные Team ID и bundle identifier только в ignored
  `ios/Config/Device.xcconfig`; Xcode UI используется для добавления Apple
  Account, но не как альтернативное место настройки project Team/bundle;
- не создавай `ios/Config/Local.xcconfig` и остановись, если он уже существует;
- если используется `--config` с нестандартным путём, файл обязан находиться вне
  repository либо быть одновременно ignored и untracked; не публикуй его путь;
- не изменяй tracked `project.yml`, xcconfig example, entitlements или source.

До build выведи только redacted summary: config present/ignored, bundle syntax
valid, mode `no-push` или `push`, device reachable yes/no. Не печатай значения
Team ID или device identifiers.

10. Подключение iPhone, preflight и Apple signing

- Открой Xcode только чтобы добавить/проверить Apple Account в Xcode Settings >
  Accounts; не меняй Signing & Capabilities в tracked project.
- Если Apple account отсутствует, попроси пользователя войти в Xcode Settings >
  Accounts и пройти Apple ID/2FA в системном UI. После выбора пользователем Team
  запиши его ID только в ignored Device.xcconfig.
- Через `xcrun devicectl list devices` обнаружь устройство, но редактируй UDID,
  serial и другие identifiers из логов/evidence.
- Попроси пользователя подключить и разблокировать iPhone, подтвердить Trust
  This Computer, включить Developer Mode, выполнить требуемый reboot и
  подтвердить device/profile registration только в системном UI.
- Не экспортируй certificate/profile и не копируй их содержимое.
- После локального выбора device выполни device-aware preflight в default mode:
  `bash ios/scripts/mac-preflight.sh --mode no-push --device "$DEVICE_UDID"`.
  Не сохраняй raw command с фактическим UDID в evidence; в отчёте укажи только
  redacted device-selected yes/no. Если выбран optional push, повтори preflight
  с `--mode push` только после выполнения prerequisites из раздела 12.

11. Default `no-push` build, install и launch

Сначала прочитай usage:
- `bash ios/scripts/mac-build-device.sh --help`;
- `bash ios/scripts/mac-install-device.sh --help`.

Запусти default device build явно:

- `bash ios/scripts/mac-build-device.sh --device "$DEVICE_UDID" --mode no-push`.

Не сохраняй фактический UDID в evidence. Флаг `--allow-device-registration`
добавляй только если Xcode действительно требует регистрацию устройства и
пользователь подтвердил системное действие. Default build обязан обходиться без
GoogleService plist/APNs/V22, не включать Archive/IPA и создавать подписанный
Debug development `.app` из временного XcodeGen snapshot.

Перед install tooling script обязан fail closed проверить:
- app bundle identifier соответствует локальному Device.xcconfig;
- API base URL точно равен API_BASE_URL и не переопределён Local.xcconfig;
- ATS является строгим allowlist: `NSExceptionDomains` содержит только
  `45.10.110.42`, subdomains запрещены, broad-load keys и дополнительные domains
  отсутствуют;
- `.app` является device product, `codesign` verification/inspection успешно,
  bundle совпадает с Device.xcconfig, а signed entitlements соответствуют mode;
- device platform/SDK является iPhoneOS; signed Team identifier и
  `application-identifier` соответствуют Team/bundle из Device.xcconfig;
- embedded provisioning profile существует, приватно декодируется и совпадает
  по Team/application-id и выбранному device с signed app;
- no-push build не требует активной Firebase Messaging registration;
- signing valid для выбранного device без публикации Team/profile details.

Все provisioning/codesign/device details сохраняй только во временных private
logs и удаляй после проверки; наружу выводи только redacted PASS/FAIL без Team,
application-id, profile, device identifier или path. Эти проверки являются
pre-install gate, но не доказательством физической установки.

Для `no-push` в signed app не должно быть APNs entitlement или Firebase plist;
для explicit `push` должны присутствовать ожидаемые signed APNs entitlement и
локально предоставленный matching Firebase plist. Если script не выполняет эти
проверки самостоятельно, остановись: ручная проверка не заменяет tooling gate.

Уточни фактический синтаксис через `xcrun devicectl help`, затем установи и
запусти самый новый device build:

- `bash ios/scripts/mac-install-device.sh --mode no-push --device "$DEVICE_UDID" --launch`.

Если build path был сохранён отдельно, передай его явно через `--app
"$BUILT_APP"`, но не публикуй этот absolute path. Скрипт должен использовать
`devicectl` для install/launch и redacted device selection.

Если signing build завершился ошибкой, исправь Apple Account в Xcode UI и/или
Team/bundle в ignored Device.xcconfig, затем повтори `mac-build-device.sh`. Не
запускай альтернативную сборку из Xcode. Если подписанный `.app` уже создан, но `devicectl`
installation не сработала, используй Xcode Window > Devices and Simulators для
установки именно этого готового `.app`; затем запусти его с iPhone. Это fallback
установки, не альтернативная сборка. Не выполняй Archive.

Если iPhone просит доверять developer identity, попроси пользователя сделать
это в Settings. Подтверди только фактические install/launch/retained-app
результаты. До этого не заявляй physical-device success.

12. Опциональный `push` mode

Не переходи к push автоматически. Сначала получи явный выбор пользователя и
прочитай script usage для точного opt-in flag. Push mode требует одновременно:
- локальный `GoogleService-Info.plist`, расположенный предпочтительно вне
  repository либо, если внутри, доказанно ignored и untracked;
- Firebase app bundle identifier, совпадающий с effective device bundle;
- Apple push capability/provisioning для выбранного Team/bundle;
- APNs key/certificate, настроенный в Firebase вне repository;
- отсутствие secrets/plist/token data в git status/logs/evidence.

Сохрани путь только в локальной shell variable `FIREBASE_PLIST` и не публикуй
его. Перед использованием in-repo path проверь `git check-ignore` и что
`git ls-files --error-unmatch` завершается неуспешно.

Если любой prerequisite отсутствует, сохрани no-push installation как успешный
результат и отметь push `SKIPPED` или `BLOCKED`; не ломай рабочую установку.
Production V22 не deployed, поэтому backend device registration и end-to-end
FCM delivery ожидаемо не являются gate для personal no-push install.

После явного согласия и выполнения prerequisites запусти отдельную opt-in
последовательность:

- `bash ios/scripts/mac-preflight.sh --mode push --device "$DEVICE_UDID" --firebase-plist "$FIREBASE_PLIST"`;
- `bash ios/scripts/mac-build-device.sh --mode push --device "$DEVICE_UDID" --firebase-plist "$FIREBASE_PLIST"`;
- `bash ios/scripts/mac-install-device.sh --mode push --device "$DEVICE_UDID" --launch`.

Install-скрипт принимает expected capability mode и перед установкой повторно
валидирует подписанный `.app`; для optional push всегда передавай `--mode push`.

13. Device smoke checklist

Пользователь вводит login/password только на iPhone. На выделенном тестовом или
личном аккаунте, с явным согласием пользователя, проверь и зафиксируй PASS/FAIL/
SKIPPED без private content:
- launch и Login без crash;
- выполни read-only status-only probe:
  `if ! HEALTH_STATUS="$(curl -fsS --max-time 10 -o /dev/null -w '%{http_code}' "$HEALTH_URL")"; then echo "Health status probe failed." >&2; exit 1; fi`,
  затем
  `case "$HEALTH_STATUS" in 2??) ;; *) echo "Unexpected health HTTP status: $HEALTH_STATUS" >&2; exit 1 ;; esac`.
  Не выводи и не сохраняй response body; записывай только HTTP status и
  sanitized health verdict. Health не доказывает login;
- login и появление authenticated shell;
- вкладки Planner, Calendar и Focus;
- Planner hierarchy/scroll и открытие существующих details;
- создание минимального временного folder/goal/task либо только task в заранее
  выбранной goal, затем edit и сохранение;
- local task reminder: настройка, сохранение, отображение pending state и, если
  время позволяет, delivery/tap-open; системная доставка остаётся best effort;
- Calendar marker/agenda и переход к task detail;
- Focus add/open/remove для временной task, если это безопасно;
- terminate/relaunch, восстановление session/tab/navigation;
- `rocketflow://focus` и, при наличии безопасного task UUID,
  `rocketflow://task/{taskId}` через поддерживаемый device/Xcode/manual URL path;
- cleanup созданных временных сущностей только если это безопасно и подтверждено.

Не записывай названия/описания задач, account email, task UUID или screenshots с
private content. Если mutation smoke не разрешён или deep-link tooling не
доступен, отметь `SKIPPED` с причиной, не фабрикуй PASS.

14. Cleanup

- Удали только локальные временные DerivedData/build outputs, если они больше не
  нужны; evidence оставь в указанном внешнем каталоге.
- Не удаляй и не изменяй пользовательские Xcode accounts, certificates или
  profiles.
- `ios/Config/Device.xcconfig` и in-repo Firebase plist могут остаться локально
  только по решению пользователя; оба должны быть ignored и untracked. Любые
  custom config/Firebase files вне repository остаются private и их absolute
  paths не попадают в отчёт.
- Выполни `git status --short` и докажи отсутствие tracked changes.
- Не запускай `git clean -fdx`, destructive reset или удаление неизвестных
  каталогов.

15. Stop/escalation conditions

Немедленно остановись и верни точный blocker, если:
- run A отсутствует/неуспешен, URL/ID/job/head SHA не совпадают с каноническим
  tooling evidence, TOOLING_SHA не является ancestor текущего docs HEAD или
  tooling paths изменились после A;
- clone не чистый либо script создаёт tracked diff;
- отсутствует полный Xcode/iPhoneOS SDK >=16.0 или exact XcodeGen 2.46.0;
- scripts/config/docs расходятся или script отсутствует/не executable без
  документированного bash path;
- XcodeGen/project или package lock parity нарушены;
- simulator build/tests не прошли;
- expanded handoff contract tests не доказывают fail-closed API/ATS, SDK,
  config/redaction, install mode, signed bundle/codesign/entitlements,
  Team/application-id и embedded provisioning behavior;
- Device.xcconfig не ignored;
- существует Local.xcconfig либо endpoint/ATS отличается от exact contract;
- build пытается Archive/export IPA/deploy backend/inspect DB;
- effective API/ATS/bundle/signing mode не соответствует contract;
- требуется передать secret, password, 2FA, private key, profile или identifier
  через чат/public log;
- старый/другой account/device signing state нельзя безопасно отличить;
- signed build/install/launch failure требует source change.

Для неизбежного пользовательского действия задай один короткий вопрос с одной
операцией и продолжи после ответа. Для code/tooling blocker верни diagnostics,
минимальную предлагаемую область исправления и остановись; не патчь source сам.

16. Финальный отчёт

Верни на русском строго по фактам:
- exact branch и наблюдаемый docs HEAD; отдельно TOOLING_SHA,
  TOOLING_RUN_URL/ID и TOOLING_JOB_ID с подтверждением ancestor, exact run head
  и нулевого tooling diff после A;
- отдельный IMMUTABLE_APP_SHA/IMMUTABLE_APP_CI_RUN: status/head SHA/gates;
- macOS, architecture, Xcode, Swift, XcodeGen и devicectl versions;
- preflight, project parity, package parity, simulator build/unit/UI results;
- mode `no-push` или explicit `push`; только результаты bundle-match и exact
  API/ATS checks, без фактического personal bundle value;
- Apple signing, device build, install и launch status; только redacted device
  label/result, без UDID, Team ID, certificate/profile данных или absolute
  `.app` path;
- smoke checklist по пунктам PASS/FAIL/SKIPPED;
- push status отдельно, с явным V22 production blocker;
- подтверждение, что sanitized evidence сохранён локально вне repository, без
  absolute path в отчёте;
- cleanup и `git status --short`;
- подтверждение: no tracked edits, no commit/push, no Archive/IPA, no deploy,
  no production DB inspection;
- только реальные blockers и одна точная следующая ручная операция для каждого.

Для free Personal Team не обещай фиксированный срок действия установки и не
включай certificate/profile сведения в отчёт. Ограничения можно описать только
как общий контекст, не как доказанный срок конкретной установки.

Неизбежные действия пользователя ограничены:
1. Подтвердить GitHub browser/device authorization при необходимости.
2. Подтвердить системную установку и ввести пароль macOS только в system prompt.
3. Добавить Apple Account в Xcode UI и пройти 2FA; Team в project UI не менять.
4. Выбрать Team, owner-controlled bundle identifier и iPhone; Team ID/bundle
   записываются только в ignored Device.xcconfig, без публикации Team ID/UDID.
5. Разблокировать iPhone, подтвердить Trust, Developer Mode, reboot и local
   developer identity/device registration.
6. Ввести RocketFlow login/password только в приложении и подтвердить допустимый
   mutation smoke.
7. Отдельно разрешить optional push mode, если он действительно нужен.
```

Этот prompt не является доказательством физической установки. Успех появляется
только после отчёта Mac-исполнителя с redacted build/install/launch evidence.
