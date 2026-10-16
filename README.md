# PasswordApi

Сервис одноразовых паролей на IIS + ASP.NET (WebHandler / `.ashx`).
Внешняя программа создаёт ссылку через API → получатель открывает её в браузере
и видит пароль **ровно один раз**. После первого просмотра или истечения TTL
файл секрета физически удаляется с сервера.

## Возможности

- 🔐 Шифрование секретов на диске (AES-256-CBC, случайный IV)
- 🔗 Одноразовые ссылки с GUID
- ⏱ TTL ссылки (по умолчанию 1440 мин, максимум 10080)
- 🗑 Автоматическое удаление после первого просмотра (атомарный `File.Move`)
- 🧹 Ленивая очистка просроченных файлов
- 🔑 Авторизация по API-ключу + фильтр по IP
- 🎨 Страница просмотра в фирменном стиле
- 📱 Адаптивная вёрстка
- 🌐 UTF-8 по всему стеку

## Документация

| Документ | Описание |
|---|---|
| [Установка](docs/INSTALL.md) | Развёртывание на IIS, права, ключи, проверка |
| [API](docs/API.md) | Эндпоинты, параметры, коды ответов |
| [Примеры вызова](docs/EXAMPLES.md) | C#, PowerShell, curl, Python |
| [Конфигурация](docs/CONFIGURATION.md) | Все параметры `Web.config` |
| [Безопасность](docs/SECURITY.md) | Угрозы, меры защиты, чек-лист |

## Структура проекта

```
passwordApi/
├── App_Code/
│   ├── SecretStore.cs        # Шифрование, хранение, атомарное извлечение
│   └── ApiAuth.cs            # Проверка X-Api-Key и IP
├── App_Data/
│   └── secrets/              # Зашифрованные файлы (не в git)
│       └── web.config        # deny all
├── Api.ashx                  # POST /Api.ashx — создать ссылку
├── View.ashx                 # GET  /View.ashx?id=... — просмотр пароля
└── Web.config
```

## Требования

- Windows Server 2016+ / Windows 10+
- IIS 10+ с ролями ASP.NET 4.8, Static Content, Request Filtering
- .NET Framework 4.7.2+

## Быстрый старт

```powershell
# 1. Сгенерировать два разных ключа
[Convert]::ToBase64String((1..32 | %{Get-Random -Max 256}))   # EncryptionKey
[Convert]::ToBase64String((1..48 | %{Get-Random -Max 256}))   # ApiKey

# 2. Заполнить Web.config (см. docs/CONFIGURATION.md)

# 3. Дать права пулу приложений
icacls "C:\inetpub\wwwroot\passwordApi\App_Data\secrets" `
  /grant "IIS AppPool\passwordApi:(OI)(CI)M"

# 4. Проверить
curl.exe -X POST https://your-domain.example/Api.ashx `
  -H "X-Api-Key: ВАШ_КЛЮЧ" `
  -H "Content-Type: application/json" `
  -d "{\"secret\":\"test\",\"ttl\":5}"
```

Подробнее — в [docs/INSTALL.md](docs/INSTALL.md).

## Как это работает

1. Клиент POST-ит `secret` на `Api.ashx`.
2. `SecretStore.Create` шифрует и атомарно пишет `App_Data\secrets\{guid}.secret`.
3. API возвращает `View.ashx?id={guid}`.
4. Получатель открывает URL.
5. `SecretStore.Take` атомарно захватывает файл, расшифровывает, удаляет.
6. Повторный заход → 404.

## Лицензия

MIT (или укажите свою).
