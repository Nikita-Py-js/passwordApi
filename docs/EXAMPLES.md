# Примеры вызова

## C#

```csharp
using System;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

class Program
{
    static async Task Main()
    {
        using var http = new HttpClient();
        http.DefaultRequestHeaders.Add("X-Api-Key",
            Environment.GetEnvironmentVariable("PW_API_KEY"));

        var json = JsonSerializer.Serialize(new
        {
            secret = "P@ssw0rd!",
            ttl = 60,
            u = "test",
            d = DateTime.Now.ToString("dd.MM.yyyy HH:mm")
        });

        using var content = new StringContent(json, Encoding.UTF8, "application/json");
        using var resp = await http.PostAsync(
            "https://your-domain.example/Api.ashx", content);

        resp.EnsureSuccessStatusCode();

        using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync());
        Console.WriteLine(doc.RootElement.GetProperty("url").GetString());
    }
}
```

### Готовый клиент

```csharp
public sealed class OneTimePasswordClient : IDisposable
{
    private readonly HttpClient _http;

    public OneTimePasswordClient(string baseUrl, string apiKey)
    {
        _http = new HttpClient
        {
            BaseAddress = new Uri(baseUrl.TrimEnd('/') + "/"),
            Timeout = TimeSpan.FromSeconds(15)
        };
        _http.DefaultRequestHeaders.Add("X-Api-Key", apiKey);
    }

    public async Task<CreateResult> CreateLinkAsync(
        string secret, int ttlMinutes = 60,
        string user = null, string date = null,
        CancellationToken ct = default)
    {
        var payload = JsonSerializer.Serialize(new
        {
            secret, ttl = ttlMinutes, u = user, d = date
        });
        using var content = new StringContent(payload, Encoding.UTF8, "application/json");
        using var resp = await _http.PostAsync("Api.ashx", content, ct);
        var body = await resp.Content.ReadAsStringAsync(ct);

        if (!resp.IsSuccessStatusCode)
            throw new Exception($"API {(int)resp.StatusCode}: {body}");

        return JsonSerializer.Deserialize<CreateResult>(body,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
    }

    public void Dispose() => _http.Dispose();

    public sealed class CreateResult
    {
        public string Url { get; set; }
        public string Id { get; set; }
        public int ExpiresMinutes { get; set; }
        public string ExpiresAtUtc { get; set; }
    }
}
```

Использование:

```csharp
using var client = new OneTimePasswordClient(
    "https://your-domain.example",
    Environment.GetEnvironmentVariable("PW_API_KEY"));

var result = await client.CreateLinkAsync(
    secret: "P@ssw0rd!",
    ttlMinutes: 30,
    user: "test",
    date: DateTime.Now.ToString("dd.MM.yyyy HH:mm"));

Console.WriteLine(result.Url);
```

## PowerShell

```powershell
$body = @{
    secret = "P@ssw0rd!"
    ttl    = 60
    u      = "test"
    d      = (Get-Date).ToString("dd.MM.yyyy HH:mm")
} | ConvertTo-Json

$r = Invoke-RestMethod -Method Post `
    -Uri "https://your-domain.example/Api.ashx" `
    -Headers @{ "X-Api-Key" = $env:PW_API_KEY } `
    -ContentType "application/json" `
    -Body $body

$r.url
```

### Функция-обёртка

```powershell
function New-OneTimePassword {
    param(
        [Parameter(Mandatory)][string]$Secret,
        [int]$TtlMinutes = 60,
        [string]$User,
        [string]$Date,
        [string]$ApiUrl = "https://your-domain.example/Api.ashx",
        [string]$ApiKey = $env:PW_API_KEY
    )

    $body = @{
        secret = $Secret
        ttl    = $TtlMinutes
        u      = $User
        d      = $Date
    } | ConvertTo-Json

    $r = Invoke-RestMethod -Method Post -Uri $ApiUrl `
        -Headers @{ "X-Api-Key" = $ApiKey } `
        -ContentType "application/json" `
        -Body $body

    $r.url
}

$url = New-OneTimePassword -Secret "P@ssw0rd!" -TtlMinutes 30 -User "test"
Write-Host $url
```

## curl

```bash
curl -sS -X POST https://your-domain.example/Api.ashx \
  -H "X-Api-Key: $PW_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"secret":"P@ssw0rd!","ttl":60,"u":"test"}' \
  | jq -r .url
```

Без `jq`:

```bash
curl -sS -X POST https://your-domain.example/Api.ashx \
  -H "X-Api-Key: $PW_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"secret":"P@ssw0rd!","ttl":60}'
```

## Python

```python
import os
import requests

r = requests.post(
    "https://your-domain.example/Api.ashx",
    headers={"X-Api-Key": os.environ["PW_API_KEY"]},
    json={
        "secret": "P@ssw0rd!",
        "ttl": 60,
        "u": "test",
        "d": "16.10.2026 09:59",
    },
    timeout=10,
)
r.raise_for_status()
print(r.json()["url"])
```

## Bash для CI/CD

```bash
URL=$(curl -sS -X POST "https://your-domain.example/Api.ashx" \
  -H "X-Api-Key: $PW_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"secret\":\"$NEW_DB_PASSWORD\",\"ttl\":15}" \
  | jq -r .url)

echo "Пароль доступен 15 минут: $URL"
```

## Сценарии

### Отправить пароль коллеге

1. Сгенерируйте ссылку через API.
2. Отправьте URL по защищённому каналу (Slack DM, Signal, email).
3. Получатель открывает — видит пароль, копирует.
4. Ссылка умирает.

### Автоматическая ротация

Скрипт при смене пароля создаёт ссылку с TTL = 10 минут и пишет её в защищённый лог или чатOps-канал.

```bash
#!/bin/bash
NEW_PASS=$(openssl rand -base64 24)
URL=$(curl -sS -X POST "https://your-domain.example/Api.ashx" \
  -H "X-Api-Key: $PW_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"secret\":\"$NEW_PASS\",\"ttl\":10}" | jq -r .url)

echo "Пароль: $URL" | mail -s "Новый пароль БД" dba@your-domain.example
```
