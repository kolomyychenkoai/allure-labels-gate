# Контракт: что скрипт читает в папке результатов Allure

Путь к папке у каждого проекта свой, а содержимое одинаковое у всех адаптеров Allure.
Всё ниже снято с настоящих прогонов, которые лежат в `tests/real/`:

| папка | откуда | версия адаптера |
|---|---|---|
| `tests/real/java-junit5` | Spring-сервис на Maven, JUnit 5, тесты `sources/LabelsContractTest.java` | allure-junit5 2.25.0 |
| `tests/real/js-jest` | официальный пример `allure-examples/jest-npm-cjs-js`, тесты `sources/labels.spec.js` | allure-jest 3.0.6 |

Имя машины и пути в этих файлах заменены на `ci-agent` и `/work/…`, остальное как записал адаптер.

Документация Allure: [как устроен файл результата](https://allurereport.org/docs/how-it-works-test-result-file/),
[перезапуски](https://allurereport.org/docs/history-and-retries/).

## Какие файлы — тесты

Один тест — один файл `<uuid>-result.json` в корне папки. Остальное скрипт не читает:
`*-container.json` (фикстуры), `*-attachment.*`, `*-globals.json`, `executor.json`,
`environment.properties`, `categories.json`, `history/`, недописанные `.allure-write-*.tmp`.

    ls tests/real/java-junit5 | sed 's/.*-//' | sort | uniq -c

## Поля, на которые опирается скрипт

    jq -c '{name, fullName, status, labels}' tests/real/*/*-result.json

- `labels` — массив `{"name": …, "value": …}`. Имя может повторяться.
- Пустая аннотация пишется как пустая строка: `@Feature("")` и `feature("")` дают
  `{"name":"feature","value":""}`. Ключа `value` может не быть вовсе — адаптер Java не пишет
  `null`-поля. Для скрипта все три случая (нет лейбла, пустое значение, нет значения) — «лейбла нет».
- `name` — имя теста, которое видно в отчёте. В JUnit 5 это `@DisplayName`, без него —
  `method()`; в Jest — строка из `it(...)`. Исключение по слову `allure` ищется здесь.
  Имя метода в `name` не попадает, если задан `@DisplayName`:
  `allureInMethodNameOnly()` проверяется, `@DisplayName("checkAllureReport")` — нет.
- `fullName` — полное имя: `пакет.Класс.метод` в Java, `файл#describe имя` в Jest.
  Печатается в отчёте скрипта, чтобы тест можно было найти.

## Перезапуски и параметризованные тесты

- **Перезапуск** (surefire `rerunFailingTestsCount`, `jest.retryTimes`) пишет второй файл
  с теми же `name` и `fullName`: `flaky()` лежит дважды, `failed` и `passed`.
- **Параметризованный тест** даёт файл на каждый вызов. В Java у вызовов один `fullName`
  и разные `name` (`parameterized(String) [1] value=a`, `… [2] value=b`).

Поэтому один тест для скрипта — пара `name` + `fullName`: перезапуски сливаются, вызовы
параметризованного теста остаются отдельными. Склеивать по одному `fullName` нельзя.

## Пропущенные тесты

Отключённый тест тоже пишет результат со статусом `skipped`, и скрипт его проверяет.
В Java лейблы из аннотаций у него есть. В Jest лейблы ставятся вызовом внутри тела теста,
тело не выполняется — у `it.skip` лейблов нет совсем.

## Чего скрипт не видит

Лейблы, которые Allure 3 добавляет при построении отчёта (`defaultLabels` в конфиге отчёта),
в файлах результатов отсутствуют, и скрипт их не учитывает. Лейблы из `allure.properties`
и `-Dallure.label.<имя>=<значение>` адаптер Java пишет в каждый файл, их скрипт видит.
