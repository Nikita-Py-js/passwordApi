# PasswordApi

Сервис одноразовых паролей на IIS + ASP.NET (WebHandler / `.ashx`).
Внешняя программа создаёт ссылку через API → получатель открывает её в браузере
и видит пароль **ровно один раз**. После первого просмотра или истечения TTL
файл секрета физически удаляется с сервера.

---

## Возможности

- 🔐 Шифрование секретов на диске (AES-256-CBC, случайный IV)
- 🔗 Одноразовые ссылки с GUID
- ⏱ TTL ссылки (по умолчанию 1440 мин, максимум 10080)
- 🗑 Автоматическое удаление после первого просмотра (атомарный `File.Move`)
- 🧹 Ленивая очистка просроченных файлов
- 🔑 Авторизация по API-ключу + фильтр по IP
- 🎨 Страница просмотра в фирменном стиле (жёлто-чёрный, EFSOL)
- 📱 Адаптивная вёрстка
- 🌐 UTF-8 по всему стеку

---

## Структура проекта
passwordApi/
├── App_Code/
│ ├── SecretStore.cs # Шифрование, хранение, атомарное извлечение
│ └── ApiAuth.cs # Проверка X-Api-Key и IP
├── App_Data/
│ └── secrets/ # Сюда пишутся зашифрованные файлы (не в git)
│ └── web.config # deny all
├── Api.ashx # POST /Api.ashx — создать ссылку
├── View.ashx # GET /View.ashx?id=... — просмотр пароля
└── Web.config



---

## Требования

- Windows Server 2016+ / Windows 10+
- IIS 10+ с ролями:
  - ASP.NET 4.8
  - Static Content
  - Request Filtering
  - (опционально) IP and Domain Restrictions
  - (опционально) Dynamic IP Restrictions
- .NET Framework 4.7.2+

Установка ролей:

```powershell
Install-WindowsFeature Web-Server, Web-Asp-Net45, Web-Static-Content, `
                       Web-Filtering, Web-IP-Security, Web-Dyn-Compression
