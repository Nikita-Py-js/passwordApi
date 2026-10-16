<%@ WebHandler Language="C#" Class="ApiHandler" %>
using System;
using System.Configuration;
using System.IO;
using System.Text;
using System.Web;
using System.Web.Script.Serialization;

public class ApiHandler : IHttpHandler
{
    public void ProcessRequest(HttpContext ctx)
    {
        ctx.Response.Cache.SetCacheability(HttpCacheability.NoCache);
        ctx.Response.Cache.SetNoStore();

        if (!string.Equals(ctx.Request.HttpMethod, "POST", StringComparison.OrdinalIgnoreCase))
        {
            Fail(ctx, 405, "Только POST");
            return;
        }

        string err;
        if (!ApiAuth.IsAuthorized(ctx, out err))
        {
            Fail(ctx, 401, err);
            return;
        }

        string secret = null;
        int? ttlFromBody = null;

        string contentType = (ctx.Request.ContentType ?? "").ToLowerInvariant();
        if (contentType.Contains("application/json"))
        {
            using (var reader = new StreamReader(ctx.Request.InputStream, Encoding.UTF8))
            {
                string body = reader.ReadToEnd();
                try
                {
                    var dict = new JavaScriptSerializer()
                        .Deserialize<System.Collections.Generic.Dictionary<string, object>>(body);
                    if (dict != null)
                    {
                        if (dict.ContainsKey("secret")) secret = Convert.ToString(dict["secret"]);
                        if (dict.ContainsKey("ttl"))
                        {
                            int v;
                            if (int.TryParse(Convert.ToString(dict["ttl"]), out v)) ttlFromBody = v;
                        }
                    }
                }
                catch
                {
                    Fail(ctx, 400, "Некорректный JSON");
                    return;
                }
            }
        }
        else
        {
            secret = ctx.Request.Form["secret"];
            int v;
            if (int.TryParse(ctx.Request.Form["ttl"], out v)) ttlFromBody = v;
        }

        if (string.IsNullOrEmpty(secret))
        {
            Fail(ctx, 400, "Поле secret обязательно");
            return;
        }

        int maxSize = int.Parse(ConfigurationManager.AppSettings["MaxSecretSize"] ?? "65536");
        if (secret.Length > maxSize)
        {
            Fail(ctx, 400, "Слишком большой секрет");
            return;
        }

        int defaultTtl = int.Parse(ConfigurationManager.AppSettings["DefaultTtlMinutes"] ?? "1440");
        int maxTtl = int.Parse(ConfigurationManager.AppSettings["MaxTtlMinutes"] ?? "10080");
        int ttl = ttlFromBody ?? defaultTtl;
        if (ttl <= 0) ttl = defaultTtl;
        if (ttl > maxTtl) ttl = maxTtl;

        SecretStore.CleanupExpired();

        string id = SecretStore.Create(secret, TimeSpan.FromMinutes(ttl));

        string baseUrl = ConfigurationManager.AppSettings["BaseUrl"];
        if (string.IsNullOrEmpty(baseUrl))
        {
            var u = ctx.Request.Url;
            baseUrl = u.Scheme + "://" + u.Authority + ctx.Request.ApplicationPath.TrimEnd('/');
        }
        baseUrl = baseUrl.TrimEnd('/');

        var result = new
        {
            url = baseUrl + "/View.ashx?id=" + id,
            id = id,
            expiresMinutes = ttl,
            expiresAtUtc = DateTime.UtcNow.AddMinutes(ttl).ToString("o")
        };
        WriteJson(ctx, new JavaScriptSerializer().Serialize(result));
    }

    private static void Fail(HttpContext ctx, int code, string message)
    {
        ctx.Response.StatusCode = code;
        WriteJson(ctx, new JavaScriptSerializer().Serialize(new { error = message }));
    }

    private static void WriteJson(HttpContext ctx, string json)
    {
        ctx.Response.Clear();
        ctx.Response.Charset = "utf-8";
        ctx.Response.ContentEncoding = Encoding.UTF8;
        ctx.Response.ContentType = "application/json; charset=utf-8";
        byte[] bytes = Encoding.UTF8.GetBytes(json);
        ctx.Response.OutputStream.Write(bytes, 0, bytes.Length);
        ctx.Response.Flush();
    }

    public bool IsReusable { get { return false; } }
}