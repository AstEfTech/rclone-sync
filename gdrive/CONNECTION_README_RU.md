# Получение Google-кредов и токена для rclone (Google Drive)

[English version](CONNECTION_README.md)

Инструкция для headless-машины (Raspberry Pi без браузера). Используется собственный OAuth client ID, а не общий ключ rclone: так нет жёстких лимитов, а токен не протухает через 7 дней.

## Требования

- Аккаунт Google (обычный Gmail или Workspace).
- rclone на Pi **и** на компьютере с браузером. Версии одинаковые или новее на компьютере. Ставить скриптом с rclone.org, не из `apt`:
  ```bash
  curl https://rclone.org/install.sh | sudo bash
  rclone version
  ```
  На Windows/macOS: скачать с https://rclone.org/downloads/

## Часть 1. Создание OAuth client ID в Google Cloud

### 1.1 Проект и API
1. Открыть https://console.cloud.google.com/ и создать проект (например `rclone-pi`).
2. **APIs & Services → Library** → найти **Google Drive API** → **Enable**.

### 1.2 Google Auth Platform (consent screen)
1. **APIs & Services → OAuth consent screen** (раздел Google Auth Platform) → **Get started**.
2. **Branding:**
   - App name: `rclone-pi`
   - User support email: свой Gmail
   - App home page и Privacy policy link: любые реальные https-ссылки (например страница на GitHub Pages или публичный gist с одной строкой «Personal rclone backup tool, no user data is collected»). Содержимое Google не проверяет, только формат.
   - Developer contact information: свой email
   - Логотип не загружать (потянет доп. проверку). В Authorized domains ничего не добавлять.
3. **Audience:** `External` для Gmail, `Internal` для Workspace.
4. **Data Access → Add or remove scopes:** добавить `https://www.googleapis.com/auth/drive`.
5. **Audience → Test users:** добавить свой Gmail (нужно, пока статус Testing).
6. **Audience → Publish app → Confirm.** Статус должен стать **In production**.

> Важно: если оставить статус **Testing**, refresh-токен умирает через 7 дней (`invalid_grant`), и синк молча ломается. Верификация приложения не нужна. При логине Google покажет предупреждение «Google hasn't verified this app»: Advanced → Go to rclone-pi (unsafe).

### 1.3 Создание клиента
1. **Google Auth Platform → Clients → Create client** (или Credentials → Create credentials → OAuth client ID).
2. Application type: **Desktop app** (не Web application!). Имя: `rclone-pi`.
3. Скопировать **Client ID** и **Client secret** (secret может показываться только при создании).

## Часть 2. Настройка rclone на Pi

```bash
rclone config
```

Ответы:

| Вопрос | Ответ |
|---|---|
| `n` New remote | `n` |
| name | `gdrive` |
| Storage | `drive` |
| client_id | вставить свой |
| client_secret | вставить свой |
| scope | `1` (Full access) |
| service_account_file | пусто |
| Edit advanced config | `n` |
| Use web browser to automatically authenticate | **`n`** (на Pi нет браузера) |

rclone выведет команду вида:

```
rclone authorize "drive" "eyJ....длинная строка...."
```

## Часть 3. Получение токена на компьютере с браузером

1. Скопировать команду **целиком**, вместе с длинной строкой в кавычках (в ней зашит твой client_id и secret).
2. Выполнить её на компьютере с браузером и rclone.
3. Откроется браузер: войти в Google, разрешить доступ (Advanced → Go to rclone-pi (unsafe) → Continue).
4. В терминале появится блок:
   ```
   Paste the following into your remote machine --->
   {"access_token":"...","token_type":"Bearer","refresh_token":"...","expiry":"..."}
   <---End paste
   ```
5. Скопировать JSON между стрелками и вставить на Pi в приглашение `config_token>`.
6. На вопрос про Shared Drive: `n` (для обычного «Мой диск»).
7. Подтвердить сохранение: `y`, затем `q`.

> Если запустить просто `rclone authorize "drive"` без длинной строки, авторизация пойдёт через общий клиент rclone, и токен не подойдёт к твоему конфигу.

## Часть 4. Проверка

Выполнять под тем же пользователем, под которым будет работать синк (не под root):

```bash
rclone lsd gdrive:
rclone about gdrive:
```

Конфиг с токеном: `~/.config/rclone/rclone.conf`. Он даёт полный доступ к Drive:

```bash
chmod 600 ~/.config/rclone/rclone.conf
```

## Переавторизация (токен протух или сменили client ID)

```bash
rclone config update gdrive client_id=НОВЫЙ_ID client_secret=НОВЫЙ_SECRET
rclone config reconnect gdrive:
```

На вопрос про браузер ответить `n`, дальше как в части 3.

## Частые ошибки

| Симптом | Причина и решение |
|---|---|
| `redirect_uri_mismatch` | Клиент создан как Web application. Создать новый типа **Desktop app**. Либо добавить `http://127.0.0.1:53682/` в Authorized redirect URIs. Либо старый rclone (OOB-редирект): обновить на обеих машинах. |
| `invalid_grant` через ~неделю | Приложение осталось в Testing. Перевести в In production и переавторизоваться. |
| `access_denied` при логине | Аккаунта нет в Test users (если статус Testing). |
| `accessNotConfigured` | Не включён Drive API в проекте. |
| `rateLimitExceeded` | Используется общий client_id rclone вместо своего. |
| «valid app name, support email, homepage url, privacy policy url are required» при публикации | Заполнить все поля на странице Branding, затем снова Publish app. |
| После перевода в Production токен всё равно живёт 7 дней | Токен выдан до смены статуса. Выполнить `rclone config reconnect gdrive:`. |