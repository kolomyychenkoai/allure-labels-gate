# Контракт: что скрипт читает в папке результатов Allure

Путь к папке у каждого проекта свой, а содержимое одинаковое у всех адаптеров Allure.
Всё ниже снято с настоящих прогонов, которые лежат в `tests/real/`, кроме двух мест, помеченных
«по исходникам Allure»:

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
  `{"name":"feature","value":""}`. Ключа `value` может не быть вовсе: адаптер Java не пишет
  `null`-поля (по исходникам Allure). Для скрипта все три случая (нет лейбла, пустое значение,
  нет значения) — «лейбла нет».
- `name` — имя теста, которое видно в отчёте. В JUnit 5 это `@DisplayName`, без него —
  `method()`; в Jest — строка из `it(...)`. Исключение по слову `allure` ищется здесь.
  Без `@DisplayName` слово в имени метода исключает тест (`allureInMethodName()`). Если
  `@DisplayName` задан, имени метода в `name` нет: метод `allureInMethodNameOnly`
  с `@DisplayName("display name without the word")` проверяется, а метод
  `allureInDisplayName` с `@DisplayName("checkAllureReport")` — нет.
- `fullName` — полное имя: `пакет.Класс.метод` в Java, `файл#describe имя` в Jest.
  Печатается в отчёте скрипта, чтобы тест можно было найти.

## Перезапуски и параметризованные тесты

- **Перезапуск** (surefire `rerunFailingTestsCount`, `jest.retryTimes`) пишет второй файл
  с теми же `name` и `fullName`: `flaky()` лежит дважды, `failed` и `passed`.
- **Параметризованный тест** даёт файл на каждый вызов. В Java у вызовов один `fullName`
  и разные `name` (`parameterized(String) [1] value=a`, `… [2] value=b`).

Поэтому один тест для скрипта — пара `name` + `fullName`: перезапуски сливаются, вызовы
параметризованного теста остаются отдельными. Склеивать по одному `fullName` нельзя.

Лейбл у перезапущенного теста засчитан, если он есть хотя бы в одной попытке. В Jest лейблы
ставятся вызовом в теле теста, и попытка, упавшая раньше этого вызова, остаётся без лейбла;
в Java лейблы из аннотаций одинаковы у всех попыток. Случай — `tests/cases/retries`.

## Пропущенные тесты

Отключённый тест тоже пишет результат со статусом `skipped`. В Java лейблы из аннотаций
у него есть. В Jest лейблы ставятся вызовом внутри тела теста, тело не выполняется — у
`it.skip` лейблов нет совсем. Поэтому скрипт не проверяет тест, у которого все попытки
со статусом `skipped`; если хоть одна попытка выполнялась, тест проверяется.
Случай — `tests/cases/skipped`.

## Чего скрипт не видит (по исходникам Allure)

Лейблы, которые Allure 3 добавляет при построении отчёта (`defaultLabels` в конфиге отчёта),
в файлах результатов отсутствуют, и скрипт их не учитывает. Лейблы из `allure.properties`
и `-Dallure.label.<имя>=<значение>` адаптер Java пишет в каждый файл, их скрипт видит.
