<%@ WebHandler Language="C#" Class="ViewHandler" %>
using System;
using System.Text;
using System.Web;

public class ViewHandler : IHttpHandler
{
    public void ProcessRequest(HttpContext ctx)
{
    ctx.Response.Cache.SetCacheability(HttpCacheability.NoCache);
    ctx.Response.Cache.SetNoStore();

    // Ключевая строка: не даём IIS подменять наш 404 своей страницей
    ctx.Response.TrySkipIisCustomErrors = true;

    string id   = ctx.Request.QueryString["id"];
    string user = ctx.Request.QueryString["u"];
    string date = ctx.Request.QueryString["d"];

    string secret = SecretStore.Take(id);

    string html = secret == null
        ? RenderInvalid()
        : RenderSecret(secret, user, date);

    if (secret == null) ctx.Response.StatusCode = 404;

    ctx.Response.Clear();
    ctx.Response.Charset = "utf-8";
    ctx.Response.ContentEncoding = Encoding.UTF8;
    ctx.Response.ContentType = "text/html; charset=utf-8";
    byte[] bytes = Encoding.UTF8.GetBytes(html);
    ctx.Response.OutputStream.Write(bytes, 0, bytes.Length);
    ctx.Response.Flush();
}

    private static string RenderSecret(string secret, string user, string date)
    {
        string enc = HttpUtility.HtmlEncode(secret);

        string greeting = string.IsNullOrWhiteSpace(user)
            ? "Здравствуйте!"
            : "Здравствуйте, " + HttpUtility.HtmlEncode(user).ToUpperInvariant() + "!";

        string lead = string.IsNullOrWhiteSpace(user)
            ? "Для вашей учётной записи установлен новый пароль. Скопируйте его сейчас — после закрытия страницы доступ исчезнет."
            : "Для вашей учётной записи <b>" + HttpUtility.HtmlEncode(user) + "</b> установлен новый пароль. Скопируйте его сейчас — после закрытия страницы доступ исчезнет.";

        // Блок метаданных — показываем только если есть хотя бы один параметр
        string meta = "";
        if (!string.IsNullOrWhiteSpace(user) || !string.IsNullOrWhiteSpace(date))
        {
            string uBox = string.IsNullOrWhiteSpace(user) ? "" :
                "<td width=\"48%\" valign=\"top\" class=\"meta-box\">" +
                "  <div class=\"meta-label\">Логин</div>" +
                "  <div class=\"meta-value\">" + HttpUtility.HtmlEncode(user) + "</div>" +
                "</td>";
            string dBBox = string.IsNullOrWhiteSpace(date) ? "" :
                "<td width=\"48%\" valign=\"top\" class=\"meta-box\">" +
                "  <div class=\"meta-label\">Дата смены</div>" +
                "  <div class=\"meta-value\">" + HttpUtility.HtmlEncode(date) + "</div>" +
                "</td>";
            string gap = (!string.IsNullOrWhiteSpace(user) && !string.IsNullOrWhiteSpace(date))
                ? "<td width=\"4%\"></td>" : "";

            meta =
                "<div class=\"meta-row\">" +
                "  <table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr>" +
                     uBox + gap + dBBox +
                "  </tr></table>" +
                "</div>";
        }

        string body =
            // Жёлтый hero
            "<div class=\"hero\">" +
            "  <div class=\"badge\">Новый пароль</div>" +
            "  <h1>" + greeting + "</h1>" +
            "  <p class=\"lead\">" + lead + "</p>" +
            "</div>" +

            meta +

            // Тёмная карточка с паролем
            "<div class=\"dark-card\">" +
            "  <div class=\"dark-label\">Одноразовый пароль</div>" +
            "  <div class=\"dark-desc\">Пароль доступен один раз. После первого просмотра он будет уничтожен.</div>" +
            "  <pre id=\"secret\">" + enc + "</pre>" +
            "  <button type=\"button\" id=\"copy\" class=\"btn-yellow\">Скопировать пароль</button>" +
            "  <div id=\"copied\" class=\"copied\" hidden>Скопировано в буфер обмена</div>" +
            "</div>" +

            // Предупреждение
            "<div class=\"warning\">" +
            "  <b>Важно.</b> Не передавайте пароль другим людям и не оставляйте его на этом экране. " +
            "  Обновите страницу — доступ исчезнет." +
            "</div>" +

            "<script>(function(){" +
            "var b=document.getElementById('copy');" +
            "var t=document.getElementById('secret');" +
            "var ok=document.getElementById('copied');" +
            "b.addEventListener('click',function(){" +
            "  var text=t.textContent;" +
            "  function done(){b.textContent='Скопировано';ok.hidden=false;" +
            "    setTimeout(function(){ok.hidden=true;b.textContent='Скопировать пароль';},2500);}" +
            "  if(navigator.clipboard&&navigator.clipboard.writeText){" +
            "    navigator.clipboard.writeText(text).then(done).catch(function(){fallback(text);done();});" +
            "  } else { fallback(text); done(); }" +
            "});" +
            "function fallback(text){" +
            "  var ta=document.createElement('textarea');ta.value=text;" +
            "  ta.style.position='fixed';ta.style.opacity='0';" +
            "  document.body.appendChild(ta);ta.select();" +
            "  try{document.execCommand('copy');}catch(e){}" +
            "  document.body.removeChild(ta);" +
            "}" +
            "})();</script>";

        return Layout("Ваш новый пароль", body, false);
    }

    private static string RenderInvalid()
    {
        string body =
            "<div class=\"hero hero-muted\">" +
            "  <div class=\"badge\">Ссылка недоступна</div>" +
            "  <h1>Ссылка недействительна</h1>" +
            "  <p class=\"lead\">Этот пароль уже был просмотрен, истёк по времени или никогда " +
            "    не существовал. Запросите новую ссылку у отправителя.</p>" +
            "</div>" +

            "<div class=\"warning\">" +
            "  <b>Что можно сделать.</b> Одноразовые ссылки уничтожаются после первого открытия. " +
            "  Запросите новую ссылку — обычно она приходит тем же каналом, что и первая." +
            "</div>";

        return Layout("Ссылка недействительна", body, true);
    }

    private static string Layout(string title, string inner, bool isError)
    {
        return
            "<!DOCTYPE html><html lang=\"ru\"><head>" +
            "<meta charset=\"utf-8\">" +
            "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">" +
            "<meta name=\"robots\" content=\"noindex,nofollow\">" +
            "<title>" + HttpUtility.HtmlEncode(title) + "</title>" +
            "<style>" +
            "*,*::before,*::after{box-sizing:border-box}" +
            "body{margin:0;padding:0;background:#eaeaea;" +
            "  font-family:'Inter','Segoe UI',Arial,Helvetica,sans-serif;color:#2f3640;" +
            "  -webkit-font-smoothing:antialiased}" +
            ".wrap{padding:24px 12px;display:flex;justify-content:center}" +
            ".card{max-width:620px;width:100%;background:#ffffff}" +

            // Шапка
            ".card-header{background:#ffffff;padding:22px 36px;border-bottom:1px solid #eeeeee;" +
            "  display:flex;justify-content:space-between;align-items:center;gap:16px}" +
            ".brand{font-size:26px;font-weight:900;letter-spacing:1px;line-height:1;" +
            "  color:#0a0a0a;text-transform:uppercase}" +
            ".brand-muted{color:#a8a8a8}" +
            ".tag{font-size:10px;color:#8a8a8a;letter-spacing:2px;text-transform:uppercase;" +
            "  text-align:right;line-height:1.5;font-weight:600}" +

            // Жёлтый hero
            ".hero{background:#ffc400;padding:34px 36px 32px}" +
            ".hero-muted{background:#f5f5f5}" +
            ".badge{display:inline-block;background:#2f3640;padding:6px 12px;font-size:11px;" +
            "  font-weight:800;letter-spacing:2px;color:#fff;text-transform:uppercase}" +
            ".hero h1{margin:22px 0 0;font-size:32px;line-height:1.1;font-weight:900;" +
            "  letter-spacing:-.5px;color:#2f3640;text-transform:uppercase}" +
            ".hero .lead{margin:16px 0 0;font-size:15px;line-height:1.55;color:#3a3f47}" +
            ".hero .lead b{color:#2f3640}" +

            // Метаданные
            ".meta-row{padding:24px 36px 0}" +
            ".meta-box{background:#f5f5f5;padding:18px 20px;vertical-align:top}" +
            ".meta-label{font-size:10px;text-transform:uppercase;letter-spacing:2px;" +
            "  color:#8a8a8a;font-weight:700}" +
            ".meta-value{margin-top:8px;font-size:17px;font-weight:800;color:#2f3640;" +
            "  word-break:break-all}" +

            // Тёмная карточка
            ".dark-card{margin:16px 36px 0;background:#2f3640;padding:26px 28px}" +
            ".dark-label{font-size:10px;text-transform:uppercase;letter-spacing:2px;" +
            "  color:#ffc400;font-weight:800}" +
            ".dark-desc{margin-top:12px;font-size:13px;line-height:1.6;color:#bfbfbf}" +
            "pre#secret{margin:18px 0 0;padding:16px 20px;background:#262b33;" +
            "  border-left:4px solid #ffc400;font-family:Consolas,'SF Mono',Menlo,monospace;" +
            "  font-size:17px;line-height:1.5;color:#ffffff;white-space:pre-wrap;" +
            "  word-break:break-all;font-weight:600;letter-spacing:.3px}" +
            ".btn-yellow{margin-top:20px;display:inline-block;background:#ffc400;color:#2f3640;" +
            "  border:0;padding:14px 26px;font-size:14px;font-weight:800;cursor:pointer;" +
            "  font-family:inherit;letter-spacing:.3px}" +
            ".btn-yellow:hover{background:#e5b000}" +
            ".btn-yellow:active{background:#cc9d00}" +
            ".copied{margin-top:12px;font-size:12px;color:#bfbfbf}" +

            // Предупреждение
            ".warning{margin:20px 36px 32px;background:#fff5cc;border-left:4px solid #ffc400;" +
            "  padding:16px 20px;font-size:13px;line-height:1.55;color:#2f3640}" +
            ".warning b{color:#2f3640}" +

            // Подвал
            ".card-footer{background:#ffc400;padding:24px 36px}" +
            ".footer-brand{font-size:15px;font-weight:900;letter-spacing:1px;line-height:1;" +
            "  color:#0a0a0a;text-transform:uppercase}" +
            ".footer-line{font-size:12px;color:#2f3640;margin-top:12px;line-height:1.7}" +
            ".footer-line a{color:#2f3640;text-decoration:none;font-weight:700}" +
            ".footer-line .sep{color:#5a6068;padding:0 4px}" +
            ".footer-note{font-size:11px;color:#5a6068;margin-top:14px;line-height:1.6}" +
            ".footer-note a{color:#2f3640;text-decoration:none;font-weight:700}" +

            "@media (max-width:480px){" +
            "  .card-header{padding:18px 22px}" +
            "  .hero{padding:26px 22px 24px}" +
            "  .hero h1{font-size:24px}" +
            "  .meta-row{padding:20px 22px 0}" +
            "  .meta-box{padding:14px 16px}" +
            "  .meta-value{font-size:15px}" +
            "  .dark-card{margin:14px 22px 0;padding:22px 22px 26px}" +
            "  pre#secret{font-size:15px;padding:14px 16px}" +
            "  .warning{margin:18px 22px 26px}" +
            "  .card-footer{padding:20px 22px}" +
            "  .tag{font-size:9px;letter-spacing:1.5px}" +
            "}" +
            "</style></head><body>" +
            "<div class=\"wrap\"><div class=\"card\">" +

            // Header
            "<div class=\"card-header\">" +
            "  <div class=\"brand" + (isError ? " brand-muted" : "") + "\">EFSOL</div>" +
            "  <div class=\"tag\">Информационная<br>безопасность</div>" +
            "</div>" +

            inner +

            // Footer
            "<div class=\"card-footer\">" +
            "  <div class=\"footer-brand\">EFSOL</div>" +
            "  <div class=\"footer-line\">" +
            "    <a href=\"https://efsol.ru\">https://efsol.ru</a>" +
            "    <span class=\"sep\">·</span>" +
            "    <a href=\"mailto:info@efsol.ru\">info@efsol.ru</a>" +
            "    <span class=\"sep\">·</span>" +
            "    <span>8 (495) 230-03-03 доб. 333</span>" +
            "  </div>" +
            "</div>" +

            "</div></div></body></html>";
    }

    public bool IsReusable { get { return false; } }
}
