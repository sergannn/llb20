# LLB Scraper

Импортирует данные `llb.su` в SQLite без внешних Python-зависимостей.

## Быстрый smoke-test

```bash
export LLB_USERNAME='...'
export LLB_PASSWORD='...'
python3 tools/llb_scraper/llb_scraper.py --login sample-all
```

По умолчанию база создается в `data/llb.sqlite3`.
Авторизационная cookie-сессия сохраняется в `data/llb_cookies.txt`, поэтому
после первого входа скрипт переиспользует ее и отправляет форму логина только
если сессия протухла.

## Полезные команды

```bash
# Игроки: первая страница. На сайте страницы нумеруются с page=0.
python3 tools/llb_scraper/llb_scraper.py players --limit-pages 1

# Детали игроков и попытка вытащить ЭЛО/рейтинг из карточки.
python3 tools/llb_scraper/llb_scraper.py --login player-details --limit 50

# Завершенные турниры.
python3 tools/llb_scraper/llb_scraper.py tournaments --kind results --limit-pages 5

# Детали турниров, включая внутренний comp_id.
python3 tools/llb_scraper/llb_scraper.py tournament-details --limit 50

# Стадии, участники и матчи для турниров, у которых уже найден comp_id.
python3 tools/llb_scraper/llb_scraper.py matches --limit-competitions 10
```

## Регулярное обновление свежих турниров

Для приложения нужен маленький оперативный слой поверх большой исторической
базы: турниры со временем переезжают из `next`/`online` в `results`, а составы
участников могут меняться. Для этого есть cron-friendly скрипт:

```bash
tools/llb_scraper/run_recent_sync.sh
```

Он обновляет первые страницы игроков, списки `next`, `online` и свежие
`results`, заново получает детали турниров, принудительно перечитывает стадии,
участников и матчи, а затем импортирует SQLite в MySQL. При импорте используется
`--replace-competition-data`: старые участники/матчи удаляются только для тех
`comp_id`, которые были перечитаны в свежей SQLite-базе.

Основные переменные:

```bash
LLB_SYNC_DB=data/llb_recent_sync.sqlite3
LLB_SYNC_NEXT_PAGES=5
LLB_SYNC_ONLINE_PAGES=3
LLB_SYNC_RESULT_PAGES=8
LLB_SYNC_DETAIL_LIMIT=600
LLB_SYNC_MATCH_LIMIT=600
LLB_SYNC_PLAYER_PAGES=1
LLB_SYNC_PLAYER_DETAIL_LIMIT=0
```

На `llb.panfilius.ru` cron запускает это каждый час через `flock`; лог лежит в
`/root/llb_mobile_scraper/data/logs/recent_sync.log`.

## Полный импорт

```bash
python3 tools/llb_scraper/llb_scraper.py --login all
```

После первого успешного запуска можно не передавать пароль, если cookie еще
актуальна:

```bash
python3 tools/llb_scraper/llb_scraper.py --login all
```

Практичнее идти партиями:

```bash
python3 tools/llb_scraper/llb_scraper.py --login all \
  --player-pages 100 \
  --player-details 500 \
  --tournament-pages 100 \
  --tournament-details 500 \
  --competitions 100
```

Полный импорт большой: сейчас публичный каталог показывает примерно 75k игроков
и больше 2k страниц результатов турниров. Запускай с лимитами и увеличивай их
постепенно; скрипт пишет `INSERT OR REPLACE`, поэтому повторные прогоны безопасны.

## Импорт на нескольких компьютерах

Каждый компьютер пишет отдельную SQLite-базу, потом мастер объединяет шарды:

```bash
python3 tools/llb_scraper/llb_scraper.py --db data/llb_worker_1.sqlite3 --login shard \
  --player-start-page 0 \
  --player-pages 506 \
  --player-details 25300 \
  --tournament-start-page 0 \
  --tournament-pages 699 \
  --tournament-details 13980 \
  --competitions 13980

python3 tools/llb_scraper/llb_scraper.py --db data/llb.sqlite3 merge data/llb_worker_*.sqlite3
```

Есть SSH-координатор:

```bash
python3 tools/llb_scraper/distributed_run.py check
python3 tools/llb_scraper/distributed_run.py deploy
python3 tools/llb_scraper/distributed_run.py run
python3 tools/llb_scraper/distributed_run.py pull
python3 tools/llb_scraper/distributed_run.py merge
```

Диапазоны и SSH-хосты лежат в `tools/llb_scraper/distributed.example.json`.
Перед запуском на удалённых машинах нужен рабочий `python3`; координатор проверяет
это командой `check`.

Для серверов `postagents` и `panfilius` есть готовый конфиг:

```bash
export LLB_USERNAME='...'
export LLB_PASSWORD='...'
python3 tools/llb_scraper/distributed_run.py --config tools/llb_scraper/distributed.servers.json check
python3 tools/llb_scraper/distributed_run.py --config tools/llb_scraper/distributed.servers.json deploy
python3 tools/llb_scraper/distributed_run.py --config tools/llb_scraper/distributed.servers.json run
```

Координатор прокидывает `LLB_USERNAME` и `LLB_PASSWORD` в SSH-команду только на
время запуска, не записывая пароль в конфиги.
