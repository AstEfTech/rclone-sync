# rclone-sync: Google Drive → локальный диск

Односторонняя синхронизация Google Drive → локальный диск на Raspberry Pi каждые 15 минут (источник, приёмник и пользователь задаются в `.env`).
Используется только `rclone copy`: ничего не удаляется.

## Окружение

| Что | Значение |
|---|---|
| Хост | Raspberry Pi (Linux); rclone, скрипт и systemd работают под `RUN_USER`, не под root |
| Источник | `SRC_REMOTE` (например `gdrive:Media`; обычный аккаунт Google, OAuth client типа **Desktop app**, приложение In production) |
| Приёмник | `DST_DIR` на диске, смонтированном в `MOUNT_POINT` |
| Конфиг rclone | `~/.config/rclone/rclone.conf` пользователя `RUN_USER` (`chmod 600`) |
| Установка rclone | скриптом с rclone.org |

Получение OAuth client ID и токена, настройка remote `gdrive`: [gdrive/CONNECTION_README.md](gdrive/CONNECTION_README.md). Сделать это нужно до `deploy.sh`.

## Структура

```
gdrive/
├── .env.example                 # шаблон персональных настроек
├── CONNECTION_README.md         # получение Google-кредов и настройка rclone
├── deploy.sh                    # установка скрипта и юнитов
├── scripts/
│   ├── gdrive-pull.sh           # основной скрипт
│   └── watch-log.sh             # tail -f последнего лога
└── system/
    ├── gdrive-pull.service.in   # шаблон юнита: oneshot, Nice=10, IOSchedulingClass=idle
    └── gdrive-pull.timer        # OnCalendar=*:0/15, Persistent=true, RandomizedDelaySec=30
```

Расположение на Pi (`APP_DIR` из `.env`):

| Файл | Путь |
|---|---|
| Скрипт | `$APP_DIR/gdrive-pull.sh` |
| Логи | `$APP_DIR/log/ГГГГ-ММ-ДД_ЧЧ-ММ-СС.log` (по файлу на прогон, старше 14 дней удаляются) |
| Lock | `$APP_DIR/.lock` |
| Настройки | `$APP_DIR/.env` (копия, chmod 600) |
| Юниты | `/etc/systemd/system/gdrive-pull.{service,timer}` |

## Установка

```bash
git clone https://github.com/AstEfTech/rclone-sync.git
cd rclone-sync/gdrive
cp .env.example .env
$EDITOR .env       # заполнить RUN_USER, SRC_REMOTE, DST_DIR (внутри MOUNT_POINT), MOUNT_POINT, APP_DIR
./deploy.sh        # от RUN_USER, не через sudo
```

`.env` обязателен: без него `deploy.sh` не запустится. Скрипт проверяет, что rclone установлен (если нет, спросит подтверждение и поставит его скриптом с rclone.org) и что remote из `SRC_REMOTE` настроен у `RUN_USER`; затем копирует файлы в `APP_DIR`, подставляет значения в шаблон юнита, делает `daemon-reload` и включает таймер. `.env` в git не попадает.

Переводы строк: при установке `deploy.sh` убирает CR из `.env`, скриптов и юнитов, так что CRLF из Windows им не страшен. Исключение — сам `deploy.sh`: bash не запустит файл с CRLF. Если он приехал с CRLF, один раз выполните `sed -i 's/\r$//' deploy.sh`.

## Логика скрипта

1. `flock -n` на `.lock`: если прошлый прогон ещё идёт, выход с кодом 0.
2. Проверка `mountpoint $MOUNT_POINT` и минимум 5 ГБ свободного места.
3. `rclone copy $SRC_REMOTE $DST_DIR` с параметрами:
   `--transfers 4 --checkers 8 --drive-skip-gdocs --exclude ".Trash-*/**" --stats 30s --stats-file-name-length 0`,
   лог пишется в `--log-file` в `log/`.
4. `LOG_LEVEL=INFO` по умолчанию, переопределяется переменной окружения (`LOG_LEVEL=DEBUG` для отладки).
5. Ненулевой код rclone логируется и возвращается наружу (юнит помечается как failed).

## Управление

```bash
# включить таймер
sudo systemctl enable --now gdrive-pull.timer

# ручной прогон (не блокирует терминал)
sudo systemctl start --no-block gdrive-pull.service

# статус и журнал
systemctl list-timers | grep gdrive
journalctl -u gdrive-pull -f

# лог последнего прогона
tail -f "$(ls -t $APP_DIR/log/*.log | head -1)"   # или $APP_DIR/watch-log.sh

# после правки unit-файлов (лучше править шаблон и перезапустить deploy.sh)
sudo systemctl daemon-reload
```

## Поведение

- **Наложение прогонов.** systemd не запускает второй экземпляр oneshot-юнита, а `flock` страхует от ручных запусков. Пропущенные срабатывания в очередь не копятся.
- **Обрыв.** Прерванный файл качается заново (rclone пишет во временный `.partial`), готовые файлы пропускаются.

## Решённые проблемы

| Симптом | Причина / решение |
|---|---|
| `redirect_uri_mismatch` | OAuth client должен быть типа Desktop app |
| Не публикуется в Production | Нужно заполнить Branding: имя, email, homepage, privacy policy |
| `permission denied` на `mkdir` | Владелец `DST_DIR` должен быть `RUN_USER`; для NTFS/exFAT задать `uid`/`gid` в fstab |
| `permission denied` на `/tmp/gdrive-pull.lock` | Lock перенесён в папку скрипта; запускать всегда от `RUN_USER`, не через `sudo` |
| `systemctl start` блокирует терминал (oneshot) | Использовать `--no-block` или положиться на таймер |

## Возможные доработки

- Уведомления о сбоях.
- `--fast-list` при большом дереве.
- `--update` или `--ignore-existing`, чтобы не перезаписывать локальные файлы.
