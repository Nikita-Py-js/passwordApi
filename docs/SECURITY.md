# Безопасность

## Модель угроз

| Угроза | Защита |
|---|---|
| Перехват пароля в сети | HTTPS, `Referrer-Policy: no-referrer` |
| Перехват API-ключа | HTTPS, шифрование `appSettings` |
| Подбор API-ключа | Длинный ключ, Dynamic IP Restrictions, rate limit |
| Чтение файлов секретов с диска | AES-256-CBC, ключ в зашифрованном `appSettings` |
| Утечка ссылки до первого просмотра | TTL, PIN-код второй ступени (опционально) |
| Повторный просмотр по той же ссылке | Атомарное удаление через `File.Move` |
| Перебор GUID | 128-битный GUID, rate limit, алерты |
| XSS на странице просмотра | `HttpUtility.HtmlEncode`, CSP |
| Clickjacking | `X-Frame-Options: DENY`, CSP `frame-ancestors 'none'` |
| MIME-sniffing | `X-Content-Type-Options: nosniff` |

## Обязательные меры

- ✅ **Только HTTPS.** HTTP → 301 redirect.
- ✅ **`EncryptionKey` ≠ `ApiKey`.** Оба длинные и случайные.
- ✅ **`appSettings` зашифрован** через `aspnet_regiis -pe`.
- ✅ **ACL на `App_Data\secrets`** — только пул приложений, только `Modify`.
- ✅ **`customErrors mode="On"`** (или `RemoteOnly`) в продакшене.
- ✅ **`debug="false"`** в `<compilation>`.

### Force HTTPS

```xml
<system.webServer>
  <rewrite>
    <rules>
      <rule name="Force HTTPS" stopProcessing="true">
        <match url="(.*)" />
        <conditions>
          <add input="{HTTPS}" pattern="^OFF$" />
        </conditions>
        <action type="Redirect" url="https://{HTTP_HOST}/{R:1}"
                redirectType="Permanent" />
      </rule>
    </rules>
  </rewrite>
</system.webServer>
```

## Рекомендуемые меры

### Dynamic IP Restrictions

10 одновременных запросов, 100 за 10 секунд:

```powershell
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' `
  -Filter 'system.webServer/security/dynamicIpSecurity/denyByConcurrentRequests' `
  -Name 'enabled' -Value 'True'
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' `
  -Filter 'system.webServer/security/dynamicIpSecurity/denyByConcurrentRequests' `
  -Name 'maxConcurrentRequests' -Value 10

Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' `
  -Filter 'system.webServer/security/dynamicIpSecurity/denyByRequestRate' `
  -Name 'enabled' -Value 'True'
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' `
  -Filter 'system.webServer/security/dynamicIpSecurity/denyByRequestRate' `
  -Name 'maxRequests' -Value 100
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' `
  -Filter 'system.webServer/security/dynamicIpSecurity/denyByRequestRate' `
  -Name 'requestIntervalInMilliseconds' -Value 10000
```

### Content Security Policy

Заголовок для `View.ashx`:

```
Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src 'none'; connect-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'
```

### Скрытие заголовков сервера

```xml
<httpProtocol>
  <customHeaders>
    <remove name="X-Powered-By"/>
    <remove name="X-AspNet-Version"/>
    <remove name="Server"/>
  </customHeaders>
</httpProtocol>
```

### Ограничение методов

```xml
<requestFiltering>
  <verbs allowUnlisted="false">
    <add verb="GET" allowed="true"/>
    <add verb="POST" allowed="true"/>
  </verbs>
  <requestLimits maxAllowedContentLength="102400"/>
</requestFiltering>
```

### Ротация API-ключа

Поддерживайте два ключа одновременно:

```xml
<add key="ApiKey" value="новый-ключ"/>
<add key="ApiKeyOld" value="старый-ключ"/>
```

```csharp
bool ok = FixedTimeEquals(provided, current)
       || (!string.IsNullOrEmpty(old) && FixedTimeEquals(provided, old));
```

Мигрируйте клиентов, затем удалите `ApiKeyOld`.

### Логирование

Пишите в Event Log:

```csharp
System.Diagnostics.EventLog.WriteEntry("PasswordApi",
    $"Create: ip={ctx.Request.UserHostAddress}, ttl={ttl}, key={apiKey.Substring(0, 8)}...",
    System.Diagnostics.EventLogEntryType.Information);
```

**Никогда** не логируйте `secret` и полный `X-Api-Key`.

### Алерты

- Всплеск `401` от `Api.ashx` → подбор ключа.
- Всплеск `404` от `View.ashx` → перебор GUID.
- Один IP > 100 ссылок за час → злоупотребление.

## Что не делать

- ❌ Не коммитить `Web.config` с реальными ключами.
- ❌ Не бэкапить `App_Data\secrets` — бэкап оживит «мёртвые» ссылки.
- ❌ Не логировать `secret` и полный `X-Api-Key`.
- ❌ Не передавать `secret` в URL-параметрах.
- ❌ Не использовать один ключ на всех клиентов.
- ❌ Не запускать пул под `LocalSystem` / `NetworkService`.

## Права на файловую систему

| Папка | Права пула |
|---|---|
| `wwwroot\passwordApi` (корень) | Read |
| `App_Data\secrets` | Modify |
| `App_Code` | Read |
| Весь остальной диск | Нет доступа |

Проверка:

```cmd
icacls "C:\inetpub\wwwroot\passwordApi\App_Data\secrets"
```

Ожидаемый результат — только `IIS AppPool\passwordApi:(OI)(CI)(M)`. Уберите `Users`, `Authenticated Users`, `Everyone`, если они там есть.

## Проверки раз в квартал

- [ ] `EncryptionKey` ≠ `ApiKey`, оба длинные и случайные.
- [ ] `App_Data\secrets` содержит только `.secret`, нет `.tmp` и `.claimed_*` старше суток.
- [ ] ACL на папках — только пул приложений.
- [ ] `ApiAllowedIps` актуален.
- [ ] `customErrors mode` = `On` или `RemoteOnly`.
- [ ] `debug="false"`.
- [ ] Нет тестовых `.ashx` и `index.html` в корне.
- [ ] Логи не содержат `secret` и полных `X-Api-Key`.

## Проверки раз в год

- [ ] Ротация `ApiKey`.
- [ ] Обновление .NET Framework и IIS до последних патчей.
- [ ] Проверка сертификата TLS (срок, cipher suites).

## Быстрый чек-лист

| # | Действие | Приоритет |
|---|---|---|
| 1 | `EncryptionKey` ≠ `ApiKey` | 🔴 Критично |
| 2 | HTTPS + редирект с HTTP | 🔴 Критично |
| 3 | Зашифровать `appSettings` через `aspnet_regiis -pe` | 🔴 Критично |
| 4 | Dynamic IP Restrictions | 🟠 Высокий |
| 5 | CSP-заголовок на `View.ashx` | 🟠 Высокий |
| 6 | Убрать `X-Powered-By`, `Server`, `X-AspNet-Version` | 🟡 Средний |
| 7 | ACL только для пула на `App_Data\secrets` | 🟡 Средний |
| 8 | Логирование в Event Log | 🟡 Средний |
| 9 | Отключить Anonymous Authentication для `Api.ashx` | 🟢 Опционально |
| 10 | Scheduled task для `CleanupExpired` | 🟢 Опционально |

## Ограничения

Даже после всех мер:

- **Утечка ссылки до первого просмотра** — получит тот, кто откроет первым. Для критичных паролей добавьте PIN-код второй ступени (отправляется другим каналом).
- **Компрометация сервера** — администратор может читать память процесса.
- **Человеческий фактор** — получатель может переслать пароль дальше.

## Как это работает

1. Клиент POST-ит `secret` на `Api.ashx`.
2. `SecretStore.Create`:
   - Генерирует GUID.
   - Шифрует `secret` (AES-256-CBC, случайный IV).
   - Пишет `.secret.tmp`, затем атомарно `File.Move` в `.secret`.
3. API возвращает URL вида `View.ashx?id={guid}`.
4. Получатель открывает URL.
5. `View.ashx` → `SecretStore.Take`:
   - `File.Move` из `.secret` в `.claimed_<random>` — атомарный захват.
   - Если не удалось — секрет уже забран, возвращаем `null` → 404.
   - Иначе читает, расшифровывает, удаляет `.claimed_*`, возвращает пароль.
6. `View.ashx` рендерит HTML с паролем.
7. Повторный заход → файла нет → 404.

TTL проверяется внутри `Take`. Просроченные файлы подчищаются при каждом `Create`.

## Отчёт об уязвимости

Сообщайте на `security@your-domain.example`, не открывайте публичный issue. Ответ в течение 48 часов.
