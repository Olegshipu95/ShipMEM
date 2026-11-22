# ShipMEM

Дипломный проект по исследованию локальности обращений к памяти в C++.
Для экспериментов используется CppTrader с нагрузкой NASDAQ ITCH.

## Статус проекта

Ход работы описан в [моём статусе проекта (PDF)](my_progress/diploma-worklog.pdf).
Актуальный исходник статуса — [diploma-worklog.tex](my_progress/diploma-worklog.tex).

В статусе можно увидеть, какой план я сделал по проекту, а также его последовательное 
выполнение. Также я пытаюсь конспектировать всё самое важное из прочтённой документации, 
чтобы:
- Все не забыть))
- Иметь хорошую отчетность для Spectral
- Потом легче написать текст диплома

## Подготовительная сборка CppTrader на Linux

Из корня ShipMEM инициализируйте сабмодуль. Git переключит его на коммит,
зафиксированный в ShipMEM.

```bash
git submodule update --init --recursive -- CppTrader
```

Для зависимостей на deb системе команды:

```bash
sudo apt-get update
sudo apt-get install -y build-essential cmake git python3-venv binutils-dev libssl-dev uuid-dev
```

Установка зависимостей и Штатный скрипт сборки:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install gil

cd CppTrader
gil update
(cd build && ./unix.sh)
```

После сборки тесты 'CppTrader':
```bash
./bin/cpptrader-tests
```

А также Бенчмарк для профилирования читает распакованный файл NASDAQ ITCH 5.0 из 
стандартного ввода:

```bash
./bin/cpptrader-performance-market_manager < /path/to/itch-file
```

## Сборка для измерений

Для актуальных замеров используется Clang 23.1.5 из сабмодуля
`llvm-project` 
и libc++, libc++abi и libunwind из той же ревизии. 

Сбор LLVM
из корня ShipMEM:

```bash
git submodule update --init --recursive -- llvm-project
```

Команды сборки Clang, библиотек и CppTrader приведены в
[журнале](my_progress/diploma-worklog.pdf). Для измерений
используется сборка CppTrader с `-O3 -DNDEBUG -g` в
`CppTrader/temp/clang-23.1.5`. 

## Подготовка CPU 1 к измерениям


Изоляция среды для более точных тестов требует изоляцию CPU-1 от context switch и 
управляемых прерываний. На тестовом ПК выбран

1. В меню GRUB выделите обычную запись Linux и нажмите **e**. Допишите
   к строке, начинающейся с `linux`:

   ```text
   isolcpus=domain,managed_irq,1 nohz_full=1 irqaffinity=0,2-15
   ```

   Загрузитесь через **Ctrl+X**. Эти параметры действуют
   до перезагрузки. Они исключают CPU 1 из обычной балансировки задач,
   сокращают периодический тик и направляют прерывания по умолчанию
   на остальные CPU. Некоторые прерывания и явно привязанные задачи
   всё ещё могут выполняться на CPU 1.

2. Проверьте конфигурацию после загрузки:

   ```bash
   cat /proc/cmdline
   cat /sys/devices/system/cpu/isolated
   cat /sys/devices/system/cpu/nohz_full
   ```

   Для серии с изоляцией оба списка должны содержать `1`. Для серии
   без изоляции загрузитесь через обычную запись GRUB и проверьте,
   что CPU 1 отсутствует в обоих списках.

3. На стенде с `intel_pstate` после каждой загрузки выставьте оба
   предела частоты CPU 1 на 3300 МГц:

   ```bash
   sudo cpupower -c 1 frequency-set -d 3300MHz -u 3300MHz
   cat /sys/devices/system/cpu/cpu1/cpufreq/scaling_min_freq \
       /sys/devices/system/cpu/cpu1/cpufreq/scaling_max_freq
   powerprofilesctl get
   ```

   Оба предела должны быть `3300000` кГц. 

## Запуск серии

для доступа
бенчмарка к пользовательским счётчикам:

```bash
sudo sysctl -w kernel.perf_event_paranoid=2
```

Из корня ShipMEM Скрипт читает локальный
`CppTrader/tools/itch/sample.itch`, прогревает файловый кэш и запускает
бенчмарк через `taskset -c 1` три раза для прогрева и 100 раз для замеров.

```bash
sudo turbostat --quiet --cpu 1 --show CPU,Busy%,Bzy_MHz -- \
    runuser -u "$(id -un)" -- bash scripts/6.Measure_power_profile.sh \
    CppTrader/temp/clang-23.1.5/fixed-3300-isolated-100 \
    2>&1 | tee /tmp/shipmem-turbostat-fixed-3300-isolated.txt
```

Каталог результатов должен быть новым. После завершения обеих серий выведите медианы и 
квартильные интервалы:

```bash
python3 scripts/5.Summarize_cpptrader.py \
    CppTrader/temp/clang-23.1.5/fixed-3300-isolated-100
```
