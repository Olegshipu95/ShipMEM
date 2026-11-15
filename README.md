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

## Сборка CppTrader на Linux

Из корня ShipMEM инициализируйте сабмодуль. Git переключит его на коммит,
зафиксированный в ShipMEM.

```bash
git submodule update --init --recursive
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
