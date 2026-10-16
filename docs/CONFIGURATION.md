# Конфигурация

Все параметры — в `<appSettings>` в `Web.config`.

## Параметры

| Ключ | Тип | По умолчанию | Описание |
|---|---|---|---|
| `EncryptionKey` | base64 | — | 32 байта. AES-256 для шифрования файлов секретов. **Обязателен.** |
| `ApiKey` | string | — | Ключ для авторизации API. Пусто → API всегда 401 |
| `ApiAllowedIps` | csv | — | Список разрешённых IP через запятую. Пусто → без ограничений |
| `BaseUrl` | url | — | Внешний URL сайта для генерации ссылок. Пусто → берётся из запроса |
| `DefaultTtlMinutes` | int | 1440 | TTL ссылки по умолчанию |
| `MaxTtlMinutes` | int | 10080 | Верхняя граница TTL (7 дней) |
| `MaxSecretSize` | int | 65536 | Макс. длина секрета в символах |

## Пример

```xml
<configuration>
  <appSettings>
    <add key="EncryptionKey" value="bPaN6LyzJ2GJpD0IqyD2oBXAnnWXXwCIp+l0lGLhzTY="/>
    <add key="DefaultTtlMinutes" value="1440"/>
    <add key="MaxTtlMinutes" value="10080"/>
    <add key="MaxSecretSize" value="65536"/>
    <add key="BaseUrl" value="https://your-domain.example"/>
    <add key="ApiKey" value="ZtYqT7V2kLp8..."/>
    <add key="ApiAllowedIps" value="127.0.0.1,::1,10.0.0.5"/>
  </appSettings>

  <system.web>
    <compilation debug="false" targetFramework="4.7.2"/>
    <httpRuntime targetFramework="4.7.2" maxRequestLength="1024"
                 requestValidationMode="4.5"/>
    <customErrors mode="On"/>
    <globalization requestEncoding="utf-8"
                   responseEncoding="utf-8"
                   fileEncoding="utf-8"/>
  </system.web>

  <system.webServer>
    <defaultDocument>
      <files>
        <clear/>
      </files>
    </defaultDocument>
    <httpProtocol>
      <customHeaders>
        <remove name="X-Powered-By"/>
        <remove name="X-AspNet-Version"/>
        <add name="X-Content-Type-Options" value="nosniff"/>
        <add name="X-Frame-Options" value="DENY"/>
        <add name="Referrer-Policy" value="no-referrer"/>
      </customHeaders>
    </httpProtocol>
    <security>
      <requestFiltering>
        <verbs allowUnlisted="false">
          <add verb="GET" allowed="true"/>
          <add verb="POST" allowed="true"/>
        </verbs>
        <requestLimits maxAllowedContentLength="102400"/>
      </requestFiltering>
    </security>
  </system.webServer>
</configuration>
```

## Генерация ключей

### EncryptionKey — ровно 32 байта

```powershell
[Convert]::ToBase64String((1..32 | %{Get-Random -Max 256}))
```

Результат: 44 символа, заканчивается на `=`.

### ApiKey — 48 байт

```powershell
[Convert]::ToBase64String((1..48 | %{Get-Random -Max 256}))
```

Можно использовать hex вместо base64:

```powershell
-join ((1..48) | %{ '{0:x2}' -f (Get-Random -Max 256) })
```

## Шифрование секции appSettings

Защита ключей от чтения из файла:

```cmd
aspnet_regiis -pe "appSettings" -app "/passwordApi" -prov "DataProtectionConfigurationProvider"
```

Расшифровать:

```cmd
aspnet_regiis -pd "appSettings" -app "/passwordApi"
```

## Настройки IIS

Рекомендуется включить:

### Dynamic IP Restrictions

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

### IP Address and Domain Restrictions

```powershell
Set-WebConfigurationProperty -PSPath "IIS:\Sites\passwordApi" `
  -Filter "system.webServer/security/ipSecurity" `
  -Name "allowUnlisted" -Value $false
```

Подробнее — в [SECURITY.md](SECURITY.md).

## Смена ключа EncryptionKey

При смене `EncryptionKey` все ранее сохранённые секреты станут нечитаемыми.

- Если активных ссылок нет — очистите `App_Data\secrets` и работайте с новым ключом.
- Если есть — дождитесь истечения TTL (макс. `MaxTtlMinutes`), затем смените.
