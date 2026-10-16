# Установка

## Требования

- Windows Server 2016+ / Windows 10+
- IIS 10+
- .NET Framework 4.7.2+

### Установка ролей IIS

```powershell
Install-WindowsFeature Web-Server, Web-Asp-Net45, Web-Static-Content, `
                       Web-Filtering, Web-IP-Security, Web-Dyn-Compression
```

## Шаги

### 1. Скопировать файлы

Разместите содержимое репозитория в каталог сайта:

```
C:\inetpub\wwwroot\passwordApi\
```

### 2. Создать папку для секретов

```cmd
mkdir "C:\inetpub\wwwroot\passwordApi\App_Data\secrets"
```

Создайте `App_Data\secrets\web.config` — запрет доступа по HTTP:

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.webServer>
    <authorization>
      <deny users="*"/>
    </authorization>
  </system.webServer>
</configuration>
```

### 3. Сгенерировать ключи

Нужны **два разных** ключа:

```powershell
# EncryptionKey — ровно 32 байта в base64 (шифрование файлов)
[Convert]::ToBase64String((1..32 | %{Get-Random -Max 256}))

# ApiKey — 48 байт в base64 (пароль для внешних клиентов)
[Convert]::ToBase64String((1..48 | %{Get-Random -Max 256}))
```

Скопируйте оба значения — они понадобятся на следующем шаге.

### 4. Заполнить Web.config

Скопируйте `Web.config.example` → `Web.config` и заполните:

```xml
<appSettings>
  <add key="EncryptionKey" value="ПЕРВЫЙ_КЛЮЧ"/>
  <add key="DefaultTtlMinutes" value="1440"/>
  <add key="MaxTtlMinutes" value="10080"/>
  <add key="MaxSecretSize" value="65536"/>
  <add key="BaseUrl" value="https://your-domain.example"/>
  <add key="ApiKey" value="ВТОРОЙ_КЛЮЧ"/>
  <add key="ApiAllowedIps" value="127.0.0.1,::1"/>
</appSettings>
```

Все параметры описаны в [CONFIGURATION.md](CONFIGURATION.md).

### 5. Создать сайт в IIS

- **Application Pool**: `.NET CLR v4.0`, **Integrated**, Identity = `ApplicationPoolIdentity`
- **Physical path**: `C:\inetpub\wwwroot\passwordApi`
- **Binding**: HTTPS 443 (обязательно)

### 6. Права на файловую систему

Замените `passwordApi` на имя вашего пула:

```cmd
:: Read на весь сайт
icacls "C:\inetpub\wwwroot\passwordApi" /grant "IIS AppPool\passwordApi:(OI)(CI)R"

:: Modify на папку секретов
icacls "C:\inetpub\wwwroot\passwordApi\App_Data\secrets" /grant "IIS AppPool\passwordApi:(OI)(CI)M"
```

### 7. Зашифровать секцию appSettings

Защита ключей от чтения из файла:

```cmd
aspnet_regiis -pe "appSettings" -app "/passwordApi" -prov "DataProtectionConfigurationProvider"
```

Расшифровать обратно (для отладки):

```cmd
aspnet_regiis -pd "appSettings" -app "/passwordApi"
```

### 8. Проверка

```cmd
curl.exe -X POST https://your-domain.example/Api.ashx ^
  -H "X-Api-Key: ВАШ_API_КЛЮЧ" ^
  -H "Content-Type: application/json" ^
  -d "{\"secret\":\"test\",\"ttl\":5}"
```

Ожидаемый ответ:

```json
{
  "url": "https://your-domain.example/View.ashx?id=0fdca0c656044f0291a673ebcfad8821",
  "id": "0fdca0c656044f0291a673ebcfad8821",
  "expiresMinutes": 5,
  "expiresAtUtc": "2026-10-16T12:34:56.789Z"
}
```

1. Откройте `url` в браузере → увидите пароль.
2. Обновите страницу → «Ссылка недействительна».

## Smoke test

```bash
# 1. Без ключа → 401
curl -i -X POST https://your-domain.example/Api.ashx \
  -H "Content-Type: application/json" -d '{"secret":"x"}'

# 2. С ключом → 200 и url
curl -sS -X POST https://your-domain.example/Api.ashx \
  -H "X-Api-Key: $PW_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"secret":"smoke","ttl":5}'

# 3. Открыть url → увидеть пароль
# 4. Открыть повторно → 404
```

## Диагностика

| Симптом | Причина | Решение |
|---|---|---|
| `500.19` «не удалось добавить копию ввода» | `App_Data` уже в `hiddenSegments` | Убрать `<add segment="App_Data"/>` из `Web.config` |
| `500.19` «пропущенное объявление раздела customErrors» | Элемент вне `<system.web>` | Перенести внутрь `<system.web>` |
| `500` «Отказано в доступе по пути ...secret.tmp» | Нет прав на `App_Data\secrets` | `icacls ... /grant "IIS AppPool\<пул>:(OI)(CI)M"` |
| `401` «ApiKey не задан в Web.config» | `ApiKey` пуст | Заполнить в `Web.config` |
| `401` «Неверный API-ключ» | Ключ не совпадает | Сверить значение в заголовке и в `Web.config` |
| `401` «IP не разрешён» | IP клиента не в списке | Добавить в `ApiAllowedIps` |
| Кракозябры в браузере | Кодировка ответа | `Response.Charset = "utf-8"` в обработчике |
| `url` содержит `localhost` | `BaseUrl` пуст, запрос с localhost | Задать `BaseUrl` в `Web.config` |
